# CodeDelta GitHub Action

Measure code churn and flag AI-generated / AI-agent code on every pull request —
then comment the summary on the PR, surface findings in the code-scanning (Security)
tab, and optionally block the merge. Runs entirely on your own runner; no source
leaves the machine and nothing phones home.

![The CodeDelta report comment on a pull request — churn summary, AI audit and agent-scan findings, all checks passed](https://codedelta.app/shots/pr-flow.png)

```yaml
# .github/workflows/codedelta.yml
name: CodeDelta
on: [pull_request]

permissions:
  contents: read
  pull-requests: write     # post the summary comment
  security-events: write   # upload SARIF to the code-scanning tab

jobs:
  codedelta:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # full history so churn (base..head) works
      - uses: code-delta-app/action@v1
```

That's the whole setup. **Free and fully unlocked during the beta (to 31 July 2026)
— no license, no secrets, no signup.** The engine downloads itself. See
[example-workflow.yml](example-workflow.yml) for a fully configured workflow with
gating and an AI Bill of Materials.

## Setup (one minute)

1. **Add the workflow** above to `.github/workflows/codedelta.yml`. Done.

To run past the beta — or to use your own license sooner — add one secret:
`CODEDELTA_LICENSE` = base64 of your `codedelta.lic`
(`base64 -i codedelta.lic | pbcopy`), then pass it as the `license` input. It
overrides the built-in beta license automatically. Get a license at
[codedelta.app](https://codedelta.app/download.html#register).

No install on anyone's machine; it all runs on the GitHub runner.

## Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `license` | built-in beta license | Optional. base64 of `codedelta.lic`, or a path to it (use a repo secret). Overrides the free beta license (valid to 31 July 2026). |
| `engine-url` | latest release | URL of the CodeDelta Linux bundle (`.tar.gz`). Defaults to the latest published release; override to pin a version or self-host. |
| `path` | `.` | Directory to scan. |
| `mode` | `churn` | `churn` (churn only — the default) / `both` (churn + AI audit + agent) / `ai_audit` (AI + agent, no churn) / `ai` / `agent`. |
| `threshold` | `50` | AI sensitivity 0–100 (affects rating cut-offs only). |
| `baseline` | — | Path to a committed `codedelta-baseline.json`. |
| `fail-on-new` | `false` | Fail the job if there are new findings vs the baseline. |
| `comment` | `true` | Post the summary as a PR comment (updates in place). |
| `sarif` | `true` | Upload findings as SARIF to the code-scanning tab. |
| `gate` | `false` | Fail the job on the default AI-governance policy: egress to a non-allied jurisdiction (CN/RU/KP/IR) or the rogue exec-on-model pattern. Needs an agent scan (`mode: agent`/`both`/`ai_audit`). |
| `gate-policy` | — | Path to a custom gate policy JSON (`deny_jurisdictions` / `allow_providers` / `deny_flags` / `max_risk`). Implies `gate`. |
| `bom` | — | Write an AI Bill of Materials to this path. |
| `bom-format` | `native` | `native` or `cyclonedx` (CycloneDX 1.6). |

## How findings reach the PR

- **Comment** — a concise churn + AI summary, re-used (edited) on each push.
- **Annotations / Security tab** — SARIF results appear inline on the diff and in
  code scanning, keyed to the flagged files. *(Public repos, or private repos with
  GitHub Advanced Security.)*
- **Merge gate** — with `baseline` + `fail-on-new`, only files that got *worse* than
  the accepted baseline fail the check (exit code 3).

## Notes

- The license is verified locally on the runner; nothing leaves the machine. AI
  signals are pointers for review, not verdicts.
- Generate a baseline once and commit it:
  `codedelta-gui scan . --mode both --write-baseline codedelta-baseline.json -q`
- Default `mode: churn` is the ~90% case — fast, pure measurement, no ML. Switch to
  `both` to add the AI audit and agent scan.
