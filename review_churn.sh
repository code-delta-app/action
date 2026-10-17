#!/usr/bin/env bash
# review_churn.sh — PR post-review churn for the CodeDelta Action (Lance, 15-17 Oct 2026: the one Waydev measure
# CodeDelta lacked). How much the pull request changed AFTER review started, and over how many reviewed revisions.
#
#   "the code when review started" = the commit the FIRST submitted review was made on (GitHub records it per review)
#   "now"                          = the PR's head commit
#   churn                          = CodeDelta's own logical-statement churn between the two (the engine's TOTAL row),
#                                    over the files the PR itself changes (merges of the base branch are not counted)
#   reviewed revisions             = how many different commits reviews were submitted on
#
# Appends one line to the PR comment file. Reporting only: never fails the job (every error path writes a plain line or
# nothing and exits 0).
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_EVENT_PATH, CD_DIR (engine folder), CD_PATH (scanned path, default "."),
#      CD_COMMENT (the *_pr_comment.md to append to). Test hooks: CD_ENGINE overrides "$CD_DIR/codedelta".
set -uo pipefail

CMT="${CD_COMMENT:-}"
[ -n "$CMT" ] && [ -f "$CMT" ] || exit 0
say() { printf '\n%s\n' "$1" >> "$CMT"; echo "post-review churn: $1"; }   # also into the run log

PR=$(jq -r '.pull_request.number // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2>/dev/null)
HEAD_SHA=$(jq -r '.pull_request.head.sha // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2>/dev/null)
BASE_SHA=$(jq -r '.pull_request.base.sha // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2>/dev/null)
[ -n "$PR" ] && [ -n "$HEAD_SHA" ] || exit 0

REVIEWS=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR/reviews" --paginate 2>/dev/null) || exit 0
# submitted reviews only (PENDING = an unsent draft), oldest first
FIRST=$(printf '%s' "$REVIEWS" | jq -rs 'add // [] | map(select(.state != "PENDING" and .commit_id != null and .submitted_at != null))
        | sort_by(.submitted_at) | .[0].commit_id // empty' 2>/dev/null)
ROUNDS=$(printf '%s' "$REVIEWS" | jq -rs 'add // [] | map(select(.state != "PENDING" and .commit_id != null)) | map(.commit_id) | unique | length' 2>/dev/null)
[ -n "$FIRST" ] || exit 0                                   # no review yet: no line

rev() { [ "$1" = 1 ] && echo "1 reviewed revision" || echo "$1 reviewed revisions"; }

if [ "$FIRST" = "$HEAD_SHA" ]; then
  say "**Post-review churn:** no changes yet ($(rev "${ROUNDS:-1}"))"
  exit 0
fi

# The reviewed commit and the head must both be present; a rebase or force-push can make the reviewed one unreachable.
git fetch --no-tags --quiet origin "pull/$PR/head" 2>/dev/null || true
git fetch --no-tags --quiet origin "$FIRST" 2>/dev/null || true
if ! git cat-file -e "$FIRST^{commit}" 2>/dev/null || ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
  say "**Post-review churn:** not measured — the reviewed commit ${FIRST:0:7} is no longer in the branch (rebased or force-pushed)"
  exit 0
fi

W=$(mktemp -d)
cleanup() { git worktree remove --force "$W/reviewed" >/dev/null 2>&1; git worktree remove --force "$W/now" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT
git worktree add --detach --quiet "$W/reviewed" "$FIRST" >/dev/null 2>&1 && git worktree add --detach --quiet "$W/now" "$HEAD_SHA" >/dev/null 2>&1 || exit 0

ENGINE="${CD_ENGINE:-$CD_DIR/codedelta}"
P="${CD_PATH:-.}"
# Only the files THIS pull request changes (vs the base branch): merging main into the PR branch after review brings in
# other people's work, which is not post-review churn (17 Oct 2026, demo PR #4: 1,788 counted for a 70-statement PR).
FILES=""
if [ -n "$BASE_SHA" ]; then
  git fetch --no-tags --quiet origin "$BASE_SHA" 2>/dev/null || true
  MB=$(git merge-base "$BASE_SHA" "$HEAD_SHA" 2>/dev/null || true)
  # the PR's files now AND at review time, so a file renamed after review appears under both names (the engine then
  # sees moved statements as moved, not as new code)
  MB1=$(git merge-base "$BASE_SHA" "$FIRST" 2>/dev/null || true)   # where the PR stood against main at review time
  [ -n "$MB" ] && FILES=$( { git diff --name-only "$MB" "$HEAD_SHA" -- "$P"; [ -n "$MB1" ] && git diff --name-only "$MB1" "$FIRST" -- "$P"; } 2>/dev/null | sort -u)
fi
if [ -n "$FILES" ]; then
  mkdir -p "$W/a" "$W/b"
  # files renamed since review: compare the reviewed content under the NEW name (the engine pairs files by path)
  git diff -M --name-status "$FIRST" "$HEAD_SHA" -- "$P" 2>/dev/null | awk -F'\t' '$1 ~ /^R/ {print $2 "\t" $3}' > "$W/renames"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    src=$(awk -F'\t' -v n="$f" '$2==n {print $1; exit}' "$W/renames")       # renamed since review: content from old name
    gone=$(awk -F'\t' -v o="$f" '$1==o {print 1; exit}' "$W/renames")       # the old name itself: compared under the new
    [ -z "$src" ] && src="$f"
    [ -z "$gone" ] && [ -f "$W/reviewed/$src" ] && { mkdir -p "$W/a/$(dirname "$f")"; cp "$W/reviewed/$src" "$W/a/$f"; }
    [ -f "$W/now/$f" ] && { mkdir -p "$W/b/$(dirname "$f")"; cp "$W/now/$f" "$W/b/$f"; }
  done <<< "$FILES"
  OLD="$W/a"; NEW="$W/b"
else
  OLD="$W/reviewed/$P"; NEW="$W/now/$P"
fi
"$ENGINE" "$OLD" "$NEW" -o "$W/r.html" --csv "$W/m.csv" -q >/dev/null 2>&1 || true
[ -f "$W/m.csv" ] || exit 0

# TOTAL row, by header name (the CSV is header-aligned)
read -r CRN ADD DEL CHG < <(awk -F, 'NR==1{for(i=1;i<=NF;i++)h[$i]=i; next}
  $1=="TOTAL"{print $(h["CRN_LLOC"]), $(h["ADD_LLOC"]), $(h["DEL_LLOC"]), $(h["CHG_LLOC"]); exit}' "$W/m.csv")
[ -n "${CRN:-}" ] || exit 0
say "**Post-review churn:** ${CRN} logical statements changed (+${ADD} / −${DEL} / Δ${CHG}) across $(rev "${ROUNDS:-1}") — first review on ${FIRST:0:7}"
exit 0
