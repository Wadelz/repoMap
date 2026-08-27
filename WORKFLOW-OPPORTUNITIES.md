# Workflow & automation opportunities

Findings from a review of session-transcript-equivalent artifacts (`CLAUDE.md`
/ `AGENTS.md`, `HANDOFF.md`, runbooks, `.github/workflows/`) and repository
structure across all 14 in-scope repos, prioritized by impact and repetition
frequency. See `README.md` for how the repos relate.

## High priority

### 1. PowerShell 5.1 compatibility + BOM + parse-check gate
- **What / who:** Before trusting any `.ps1`/`.psm1` edit, three separate
  checks must be run — a `PSScriptAnalyzer` compatibility sweep (syntax +
  commands + types), a UTF-8-BOM presence check, and a full parse check —
  because the target host runs Windows PowerShell 5.1 while all editing and
  testing happens under pwsh 7 on Linux, which silently tolerates things 5.1
  rejects outright.
- **Where it lives:** `rat-hunt/CLAUDE.md` and `Claude-Remote-recover/CLAUDE.md`,
  as copy-pasted shell one-liners a human/agent must remember to run "after
  any edit." No CI wiring.
- **Opportunity:** This already caused a real incident-time failure — on
  2026-08-18, all 13 scripts and 4 test suites in `Claude-Remote-recover`
  turned out to be missing the BOM, which is invisible to the three
  compatibility rules and only surfaced on an actual Windows host as ten
  cascading, misleading parse errors (`FIRST-CONTACT-FINDINGS-2026-08-18.md`).
  Converting the three checks into a single pre-commit hook or CI job would
  catch this class of bug before it ever reaches an isolated host mid-incident,
  which is the worst possible place to discover it.

### 2. Test-suite gate with no CI wiring
- **What / who:** 179 assertions across 4 suites (`tests/Test-Helpers.ps1`,
  `Test-Ancestry.ps1`, `Test-EvidenceModel.ps1`, `Test-Rescue.ps1`) are
  documented as required "before and after" any edit, and are explicitly
  platform-independent (run fine under pwsh 7 on Linux).
- **Where it lives:** Manual instruction in both DFIR repos' `CLAUDE.md`;
  the suites exist as runnable scripts but no `.github/workflows/` invokes
  them.
- **Opportunity:** Trivial CI candidate — a workflow that runs all four
  suites on every push/PR would remove reliance on a human remembering to
  run them, with no cross-platform excuse available since the repo's own
  documentation proves they run outside Windows.

### 3. Skill-propagation drift check (relay-kit plugin)
- **What / who:** Editing `repo-comms` or `session-message` requires copying
  the skill into `plugins/relay-kit/skills/<name>/`, regenerating the inline
  installer (`scripts/relay-kit-installer/generate.sh`), and re-pasting the
  regenerated script into each environment's Setup script field — three
  places that must stay in sync by hand.
- **Where it lives:** `ClaudeWebPlayground/.claude/skills/README.md` and
  `agent-comms/CLAUDE.md`. `generate.sh` checks internal consistency of the
  generated installer but nothing checks that the plugin copy still matches
  its source skill.
- **Opportunity:** Three-way drift already happened once — it's the stated
  reason the account-level synced-skill copy was removed on 2026-08-16. A
  cheap CI check (re-run the `cp` + `generate.sh` and `git diff --exit-code`)
  would catch this class of drift for free.

### 4. Shared-bearer-token guard on `/fire`
- **What / who:** `agent-comms` documents an explicit ordering rule —
  per-peer tokens must ship before the `/fire` capability is enabled,
  because with a single shared `RELAY_TOKEN` any holder can spawn sessions
  on the receiving account.
- **Where it lives:** Pure documentation (`docs/cross-project-comms/CREDENTIALS.md`,
  `cross-project-relay/TODO-per-peer-tokens.md`). No code enforces the
  ordering; the Worker will honor `/fire` today regardless of token scoping.
- **Opportunity:** Security-critical and currently has zero guardrail beyond
  a human remembering to read the doc. A one-line startup check in the
  Worker (refuse to honor `/fire` while `RELAY_TOKEN` is a bare shared
  secret) would convert a documentation convention into an enforced
  invariant.

### 5. SEO publish approval gate
- **What / who:** Publishing generated SEO content (~10k pages/week) is
  gated behind a runbook (`airco2/rnd/publish/GOLF1-RUNBOOK.md`) with
  numbered preconditions, a named/dated client-approval ledger
  (`rnd/publish/approvals.json`), snapshot/canary/batch-publish/rollback
  phases, and abort conditions. It is the single highest-risk, least
  reversible step in the whole pipeline.
- **Where it lives:** Markdown runbook + JSON ledger, executed by hand
  against a checklist.
- **Opportunity:** Highest-value formalization target in the SEO cluster —
  turning the runbook's preconditions and ledger into a small CLI/state
  machine would remove the risk of a hand-checked step being skipped under
  time pressure, without changing who gets to approve anything.

### 6. legba post-release brew-formula automation
- **What / who:** After a GitHub Release publishes, someone must manually
  `curl` each asset, `sha256sum` it, hand-edit `pkg/brew/legba.rb`, paste the
  changelog into the release notes, and commit — step 11 of an otherwise
  very well-specified 11-step release process.
- **Where it lives:** `legba/AGENTS.md` (steps 11.1–11.4), fully manual.
- **Opportunity:** `.github/workflows/release.yml` already computes and
  uploads `*.sha256` files for every asset as part of the same run — a
  `release: published` (not tag-push, since releases are created `--draft`)
  triggered job could download those, patch the formula, and paste the
  changelog automatically, eliminating the only fully mechanical step left
  in the process. Note in passing: nothing in the documented flow currently
  un-drafts the release, which is worth confirming isn't an existing gap.

## Medium priority

### 7. Evidence-transfer verification gate, generalized
`Confirm-Transfer.ps1` (re-hash, content-sniffing beyond extension,
credential-path detection, quarantine-not-delete on reject) is a solid,
already-implemented pattern that's specific to one incident's transfer path.
Worth extracting as a standalone reusable "transfer gate" tool/skill so the
next incident doesn't rebuild it from scratch.

### 8. Two-route containment decision, as a template
Option A (egress lockdown) vs Option B (air-gapped rescue) in
`Claude-Remote-recover` is a well-reasoned, human-executed decision runbook.
Not code-automatable (it involves physical/network steps), but worth turning
into a reusable incident-response template/skill rather than one-off prose
tied to this incident.

### 9. SEO experiment-script consolidation
`airco2/rnd/experiments/e1`…`e24` each carry their own `run_eNN.py`-style
driver script with substantial duplication. Promoting these into one
reusable CLI/module would cut duplication across roughly 15 experiment
folders — medium impact, not urgent.

### 10. Migration checklist tracking
`agent-comms/CLAUDE.md`'s "Migration state (2026-08-16)" section is a plain
prose to-do list (Worker still pointed at `ClaudeWebPlayground`, PAT scope,
test peer location) with no tracking issue or CI gate. Converting it to
GitHub issues/checkboxes is low-effort; low urgency since the system isn't
yet widely consumed.

## Low priority / intentionally not automatable

These showed up as candidates but should stay judgment-driven rather than be
converted into scripts or CI:

- **legba's docs-audit and changelog-drafting steps** (deciding which prose
  in `docs/*.md` needs updating from a commit diff, and writing the
  changelog copy) are explicitly gated behind human approval via
  `AskUserQuestion` already, and correctly so — grep can surface candidate
  files but can't judge whether the prose is still accurate.
- **Handoff documents** (`HANDOFF.md`, `BRIEFING-ANALYSIS-*.md`,
  `SEO-folder-review-handoff.md`) are well-structured by convention
  (status table, ranked open questions, time-sensitive items) but are
  fundamentally point-in-time human/agent judgment calls. Worth keeping as a
  repo template or skill prompt, not converting into automation.
- **legba's version/tag consistency check** is already duplicated
  deliberately (agent pre-check + CI re-check) — a "belt and suspenders"
  pattern worth reusing in other repos' release docs as-is, not a gap.

## Also worth noting

- `AZURE/scripts/setup-azure.sh` is itself a reusable-infrastructure-bootstrap
  pattern (idempotent, env-var configured, explicitly documented as
  copy-paste-portable to other repos' environment setup fields). Not a gap —
  flagging it as a pattern other repos facing similar cloud-tooling bootstrap
  needs could reuse directly.
- `SEO`, `security`, and `Coolify-` are empty; `startup-script-test` holds one
  unrelated, stalled Google-Drive-inventory handoff. None of these produced
  workflow findings — see `README.md`.
