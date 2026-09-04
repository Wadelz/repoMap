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

---

## Review: 2026-08-27 — AgenticUniverse (Team Bridge relay + agent-team tooling)

First deep-dive pass on this repo; the initial cross-repo review only ruled it
out of the comms lineage (see `README.md`) without examining its own workflow.
Chosen this run as the most recently active repo (`614d7e4`, 2026-08-25) with
no findings on record yet. Source: `.claude/skills/team*/`,
`docs/relay-and-egress-field-notes.md`, `docs/agent-teams-test.md`,
`.claude/hooks/session-start.sh`, `.github/workflows/deploy-relay.yml`, and
`relay/cloudflare/`. No raw transcripts were directly readable; these docs are
themselves post-session write-ups (dated 2026-08-21 and undated field notes),
the closest durable substitute available, same as the methodology note above.

### 11. No pre-deploy verification for the relay Worker
- **What / who:** `relay/cloudflare/worker.ts` carries the logic that gates
  every command reaching the agent team from a phone (route ordering, token
  checks, Durable Object dispatch) — exactly the kind of logic that already
  shipped one real bug (`HEAD /health` falling through the `GET`-only
  exemption into the token check, documented in
  `docs/relay-and-egress-field-notes.md` §5). `package.json`'s `test` script
  is a stub (`echo "Error: no test specified" && exit 1`), and
  `.github/workflows/deploy-relay.yml` runs `npm ci`/`install` then
  `wrangler deploy` directly — no typecheck, no unit test.
- **Where it lives:** `relay/cloudflare/package.json`,
  `.github/workflows/deploy-relay.yml`.
- **Opportunity:** The workflow's only verification is a live `GET`+`HEAD
  /health` probe against production *after* deploying — which is exactly how
  the HEAD bug above was actually caught, meaning today's safety net is "ship
  it and see." Adding `tsc --noEmit` plus a small route-order/gating unit test
  (or at minimum a `wrangler dev` + local curl smoke test covering the token
  and DO-dispatch paths, not just `/health`) as a required step before deploy
  would catch this class of bug pre-production instead of in the field.
  Impact if left alone: the relay is the transport for destructive commands
  (`kill` tears down the running agent team); a bad deploy is currently
  discovered only by the two paths the post-deploy check happens to cover.

### 12. Destructive relay commands gated by prose convention, not code
- **What / who:** `kill` and `logout`, queued from the phone control-panel
  artifact or typed into the relay thread, are documented in three places
  (`.claude/skills/team/SKILL.md`, `relay/SETUP.md`'s security checklist) as
  requiring a human confirmation step in the thread before the listening
  Claude session executes them — "the relay does not validate command
  content — it is a transport." Nothing in `worker.ts` or `team.sh` itself
  distinguishes a destructive command from a routine one or requires a
  second signal; the guard exists only in the instructions given to whichever
  session happens to have loaded the `team` skill.
- **Where it lives:** `.claude/skills/team/SKILL.md` ("Two judgement calls
  stay yours…"), `relay/SETUP.md` security checklist. No code enforcement.
- **Opportunity:** Same shape as finding #4 above (`agent-comms`'
  documentation-only ordering rule for `/fire` and shared bearer tokens) —
  convention where enforcement would be cheap. `team.sh kill`/`logout` could
  require an explicit second argument (e.g. `--confirm`) or a queued
  follow-up item, so the destructive action can't fire from a single tap
  regardless of which session, or how carefully briefed, is draining the
  queue. Low cost; closes a documented-but-unenforced gap the account has
  already hit once in a different repo.

### Correctly left manual — not a gap
- **Long-lived `CLAUDE_CODE_OAUTH_TOKEN` vs. per-session login.** The
  `team-setup` skill requires stating the real tradeoff out loud (a
  long-lived bearer credential injected into every container vs. repeated
  8-hour login friction) before the user commits, and explicitly refuses to
  source such a token any other way (no harvesting one out of a running
  process). This is exactly the kind of judgment call that should stay
  human-gated, matching the same posture `legba`'s docs-audit/changelog steps
  take (see "Low priority" above) — recorded here so a future pass doesn't
  mistake deliberate friction for an automation gap.

### Worth noting — a template for an existing open finding
- `.claude/hooks/session-start.sh` here is a working instance of exactly the
  pattern finding #1 above (PowerShell 5.1/BOM/parse-check gate for
  `rat-hunt` / `Claude-Remote-recover`) is asking for: a `SessionStart` hook
  that *reports* on startup rather than *blocking* it — stale `wrangler`
  deps, an 8-hour login token close to expiry, an orphaned team config that
  "reads exactly like a live team." Its own header comment states the
  principle directly: "a hook that blocks startup over a stale token would be
  worse than the problem." Worth pointing to as a concrete template when
  finding #1 is eventually implemented, rather than designing that gate from
  scratch.

---

## Review: 2026-08-27 — DFIR cluster deep dive (branches and open PRs, not just `main`)

Second deep-dive this account has had (after AgenticUniverse above). Chosen
per the "check branches, not just the checkout" step: findings #1, #2, #7, #8
above were drawn entirely from `CLAUDE.md` prose as read on `main`, and
neither DFIR repo's non-default branches or PR queue had been examined yet.
Source: `git branch -a` / `git log` / `git merge-base` against `origin/main`
for every branch in `Wadelz/rat-hunt` and `Wadelz/Claude-Remote-recover`, plus
`mcp__github__list_pull_requests` / `pull_request_read` for both repos. No
raw transcripts were read; branch commit messages are the only record, and
one of them is itself an explicit, dated design note (quoted below).

**Findings #1 and #2 re-confirmed, unchanged:** `ls .github/workflows` finds
nothing in either repo — the CI-wiring gap both findings describe is still
live.

### 13. Incident work — including a stranded security hardening improvement — sits unmerged on both DFIR repos, one PR open and unreviewed for 9 days
- **What / who:** In `rat-hunt`, `main` carries only the thin lineage
  (collection scripts, `Rescue-Files.ps1`, relay/skills setup). The actual
  incident *analysis* — nine registry-hive parsers, a ranked rotation
  worklist generator, an offline VM-boot scanning kit
  (`kit/rathunt_offline/`), IOC hash recovery/re-bucketing, and four new test
  suites (`Test-BrowserStores`/`Test-ShortcutTier`/`Test-SignatureScan`/
  `Test-SysmonRead`) — lives entirely on branches that never merged:
  `Moving-forward` → `claude/branch-isolation-note-k905zy` →
  `archive/ledger-fold-20260818` → `incident-state-20260817` (last commit
  2026-08-22) is one unreconciled lineage; `claude/new-session-pg9x7i` (last
  commit 2026-08-24) is a second, independent one — open as **PR #2**
  ("Record the fourth staging directory...") since 2026-08-18, mergeable
  ("clean"), 91 commits, +21,242/-24 across 91 files, and as of this review
  zero comments, zero reviews, zero review requests in 9 days. The first
  three branches in that lineage don't even have a PR open — nobody has
  pointed a merge decision at them at all.
  In `Claude-Remote-recover` — the successor repo, so *not* a case of "the
  lesson was already learned by splitting repos" as this review first
  assumed before checking — `claude/new-session-pg9x7i` (same generated name,
  different repo, unrelated branch) sits 19 commits ahead of `main` with no
  PR at all, and `main` hasn't moved since the branch point
  (2026-08-19). Those 19 commits are not cosmetic: `Set-EgressLockdown.ps1`
  grows from 468 to 815 lines, adding `-ClaudeRunAsUser` (closes a
  same-user-process-injection bypass of the egress pinhole — running
  `claude.exe` as a separate local account moves that bypass from "free" to
  "needs elevation") and `-CollectorOnly` (removes the model API from the
  allowlist entirely, described in the branch's own comments as "the
  TIGHTEST configuration here" for a structural reason, not a cosmetic one).
  A `-NoDns` mode is also there but explicitly flagged not ready as of
  2026-08-20 (a 25-minute hang reproduced and survived a reboot). The same
  branch also carries several commits with no visible connection to this
  repo's incident at all (an Azure jump-host build, a Coolify API
  experiment) — content that belongs in `AZURE`/`Coolify-` if it belongs
  anywhere, suggesting the branch name was reused across an unrelated
  session's work rather than kept scoped to this repo's incident.
- **Where it lives:** git branch/PR state only. Nothing in either repo's
  `CLAUDE.md`, `README.md`, or any tracked file lists which branches hold
  live incident work versus which are safe to delete. The only record of
  *why* reconciliation was deferred at all is a single commit message on
  `rat-hunt`'s `claude/branch-isolation-note-k905zy` (`e91cf9a`): it correctly
  spotted that a plain merge of that branch into `main` would *silently*
  duplicate work rather than conflict (a concurrent session's plugin-install
  hook and this branch's vendored-skills approach solve the same problem by
  touching disjoint files), and deferred the decision "in one place" —
  a place that, five more branches and nine days later, still hasn't
  happened.
- **Opportunity:** Both of these repos exist because of, and describe
  themselves as covering, **an incident that is still open**
  (`CLAUDE.md`: "The incident is also still open" / "this host should be
  reimaged"). Hive-parser findings, IOC corrections, closed/filed OI-tracker
  items, and a specific process-injection hardening fix for the live
  containment tool are sitting in a form — dangling branches, one stale PR —
  that a routine branch cleanup or a `git gc` window could quietly lose, and
  no future session reading `main` alone would know to look for them. This
  is *not* "just auto-merge everything" — `branch-isolation-note-k905zy`'s
  own reasoning shows real reconciliations here need a human to pick a
  winner between two divergent fixes, so that judgment call should stay
  manual (see below). What's missing is cheap and mechanical instead: (a) a
  tracked index — even a one-file `BRANCHES.md` per repo, or just a
  filled-in PR description — naming every branch that holds unmerged
  incident content and why, so "nobody pointed a merge decision at it" stops
  being the silent default; (b) closing the loop on PR #2 and the
  `Set-EgressLockdown.ps1` hardening specifically, since both are
  security-relevant and have sat actionable-but-untouched for over a week on
  an account with no reviewer assigned and no reminder mechanism — the same
  "convention with no enforcement" shape as findings #4 and #12 above, just
  with a stopwatch this time instead of a policy statement.

### Correctly left manual — not a gap
- **Which divergent branch's fix wins**, per `branch-isolation-note-k905zy`
  above: a real semantically-duplicating merge (two different fixes to the
  same problem, touching disjoint files, so git reports no conflict) needs a
  human to choose. The commit that spotted this and stopped a silent merge
  is a good template for the *reasoning* — it's the follow-through that's
  missing (#13), not the judgment call itself.

---

## Review: 2026-08-28 — aircoenverwarmen/SEO cluster deep dive (branches, PRs, and a second incident)

Third deep-dive this account has had. Chosen per the prioritization rule: this
cluster (`aircoenverwarmen-seo-pipeline`, `airco2`, `SEO`, `startup-script-test`)
had only ever received the shallow, `main`-only initial pass — no branch/PR
sweep — while both other clusters already got one. `git branch -a` /
`git log` against each repo's actual default branch, plus
`mcp__github__list_pull_requests` / `pull_request_read`, turned up far more
than the initial pass saw: none of it in `CLAUDE.md`/`AGENTS.md` (this cluster
has neither), all of it in commit messages and in-repo markdown written
during past sessions — the same "closest durable substitute" sourcing as the
other two deep dives.

### 14. A second, confirmed-root-cause WordPress compromise (2026-08-22) is undiscoverable from where anyone would look
- **What / who:** `aircoenverwarmen-seo-pipeline`'s own incident trail
  (`rnd/INCIDENT-REMEDIATION-STATUS.md`, dated 2026-08-18/19, and
  `rnd/INCIDENT-CHECKLIST.md`, last touched 2026-08-25) describes one breach —
  the 2026-08-10 compromise, remediated by an 2026-08-18 Hetzner-snapshot
  rebuild — and nothing else. Neither file mentions that on **2026-08-22** a
  *second* intrusion was found, root-caused, and documented in
  99% more detail than the first: `RECOVERY-PLAN.md`, 299 lines, added by
  commit `d06e888` — but in **`startup-script-test`**, on branch
  `incident-evidence-20260822`, which branches from nothing (`git ls-remote`
  shows this repo has no `main`/`master` at all — see #16) and has never had
  a pull request. That plan names the confirmed root cause as **wp2shell**,
  an unauthenticated WordPress-core RCE chain (CVE-2026-63030 + CVE-2026-60137,
  disclosed 2026-07-17, exploited here from ~Aug 1), left unpatched because a
  leftover `automation-by-installatron.php` mu-plugin from the site's previous
  shared host silently disabled minor core auto-updates since January 2026 —
  so the fix (WP 6.9.5) was released and available and never installed. It
  lists 4 removed backdoors (including a 150 KB shell at `wp-conffq.php`), a
  timestomped file, a hijacked `.htaccess`, and states the site was **stopped
  and "not yet safe to restart"** pending 7 Tier-0 blockers: patch core to
  ≥6.9.5, block anonymous `POST /wp-json/batch/v1` at the edge, revoke every
  WooCommerce REST key (bearer credentials exposing 100+ customers' PII),
  purge application passwords/session tokens (survive password *and* salt
  rotation), audit 9 stray `.htaccess` files for `auto_prepend_file`, rotate
  WP salts, and rotate every credential — **from a device other than the
  still-un-reimaged NetSupport-RAT workstation**, which held the SSH key,
  WooCommerce keys, GitHub PAT and Coolify/Hetzner logins.
- **Where it lives:** One markdown file, one orphan branch, one repo that
  nothing else in the cluster references or was ever taught to check.
  `INCIDENT-REMEDIATION-STATUS.md` in the pipeline repo — the file anyone
  would actually open when picking up this incident — was never updated to
  point at it, so reading only the "official" incident doc leaves someone
  believing the story ends at the 2026-08-18 rebuild.
- **Impact if left alone:** Meanwhile, ordinary pipeline work (menu
  restructuring, a new drop pass, a productivity-plugin customization)
  continued in `aircoenverwarmen-seo-pipeline` right through and after
  2026-08-22 — encouragingly, the one live-write-capable piece of that work
  (the P10 menu apply) is correctly gated behind `--yes` +
  `MENU_APPLY_APPROVED=yes` and was never actually run (`da3b85b`: "No live
  writes"), so this did not turn into a second incident on top of the first.
  But nothing in this account's tooling would have caught it if it had. This
  review cannot confirm from repo content alone whether the 7 Tier-0 blockers
  were ever completed — the 2026-08-18 remediation was itself done by hand
  "via Coolify terminal (mobile)" and only recorded after the fact, so silent
  completion is possible. That ambiguity is itself the finding: **a second
  confirmed unauthenticated-RCE incident against the same production site,
  six days old as of this review, has no status that any future reviewer —
  human or agent — would find without independently discovering this branch.**
- **Opportunity:** Not "automate the remediation" — rotating credentials and
  patching a live site from a clean device is exactly the kind of step that
  should stay a deliberate, hand-verified human action (see below). What's
  missing is purely mechanical: (a) this plan belongs in
  `aircoenverwarmen-seo-pipeline` next to the other incident docs, or at
  minimum cross-linked from `INCIDENT-REMEDIATION-STATUS.md`, not on an
  unrelated repo's disconnected branch; (b) a one-line "is this resolved?"
  status — even just checked boxes against the 7 Tier-0 items — belongs
  somewhere a human will actually see it on the next login, the same gap
  finding #13 already named for the DFIR cluster and now confirmed a second
  time in a second cluster, which suggests this is an account-wide pattern
  (incident follow-through tracked nowhere durable) rather than a one-off.

### 15. Three near-identical incident-remediation-review branches, redundant work, still no index
- **What / who:** `claude/incident-remediation-review-4pjd2a`,
  `-uub79h`, and `-y3w9qq` in `aircoenverwarmen-seo-pipeline` share the
  entire P1–P9 replay history (93,794 ledgered writes: 6,280 publishes, 145
  rewrites, 84,988 draft categorizations, 1,606 retitles, 469 terms, ~300
  menu/slug ops — all rolled back by the Aug 18 rebuild and replayed from
  repo finals with checkpoint/epoch tooling) and the same incident checklist
  commits, then diverge into different tail commits (menu-variant drafting on
  two of the three; a "verify replay against live" correction on the third).
  None has a pull request; nothing records that three sessions independently
  picked up the same incident-review starting point.
- **Where it lives:** Git branch state only, same as DFIR finding #13.
- **Opportunity:** This is the same shape as #13, now observed in a second
  cluster, which upgrades it from "a DFIR-specific lapse" to a recurring
  cross-account pattern worth a general fix rather than a per-repo one: a
  lightweight convention (a per-repo `BRANCHES.md`, or just requiring a PR —
  even a draft one — for any branch meant to survive past its own session)
  would surface "someone already started this" before a second or third
  session duplicates 90+ commits of replay work. The replay tooling itself
  (checkpointing, ground-truth validation, epoch markers distinguishing dead
  vs. live term ids) is well-built and not the gap — the coordination layer
  around it is.

### 16. `startup-script-test` has no trunk, no PRs, and is holding the account's most safety-critical undiscovered document
- **What / who:** The repo has no `main` or `master` branch at all —
  `git remote show origin` reports its own `HEAD branch` as
  `claude/seo-folder-review-yvp28s`, a generated session branch, because that
  is the only ref anyone happened to push first. Four branches exist
  (`claude/seo-folder-review-yvp28s`, `claude/google-drive-mcp-download-wrlolq`,
  `claude/hertzner-snapshot-backup-local-mgij3v`, `incident-evidence-20260822`),
  none merged into any other, zero pull requests ever opened.
- **Where it lives:** Repo structure. The prior cross-repo review (see
  `README.md`, since corrected) described this repo as holding one stalled,
  tangential Google-Drive-inventory handoff — true of three of its four
  branches, but the fourth is finding #14 above.
- **Opportunity:** Give the repo an actual default branch (even an empty one
  with a README pointing at the others) so `HEAD` stops pointing at an
  arbitrary session branch, and open a PR — draft is fine — for
  `incident-evidence-20260822` specifically, given #14. This repo is a small,
  mechanical fix; it is flagged here mainly because its current state is *why*
  #14 was findable only by deep-diving branches instead of reading `main`.

### 17. PR #3 in `aircoenverwarmen-seo-pipeline`: high-quality, mergeable, unreviewed, and self-flags a pre-publish hardening TODO
- **What / who:** "Deterministic derived-claim drop" (opened 2026-08-27,
  `mergeable_state: clean`, base `master`) is a well-documented, benchmarked
  change (72.0%→93.2% gate rate on one corpus, zero regressions measured
  against two corpora with opposite failure profiles) — the kind of PR the
  other two deep-dived clusters' stale PRs (#2 in `rat-hunt`, 9 days
  unreviewed) show a pattern of accumulating. This one is only a day old, so
  the urgency is lower, but the shape (opened, clean, zero comments/reviews)
  is identical.
- **Where it lives:** GitHub PR state.
- **Opportunity:** Lower priority than #13/#14 given its age, but worth the
  same fix in kind: a reviewer nudge after N days with no activity on a
  green, mergeable PR. Separately, the PR body itself already names a real
  gap — the workflow scripts it adds hardcode the production IP and an SSH
  key filename (9 mentions each), flagged by its own author as "worth
  parameterising via env var before adding a collaborator or making it
  public." That's a correct, self-identified TODO, not yet tracked anywhere
  it will survive the PR being merged and forgotten — worth a follow-up issue
  rather than trusting the PR description to be re-read later.

### Worth noting — a resolved instance of the pattern #4 and #12 are still open gaps for
- **The credential-materialization anti-pattern here fixed itself, without
  code enforcement, because the safer fix was also the fix for an unrelated
  bug.** Two branches independently added a `SessionStart` hook that wrote
  WooCommerce credentials to a plaintext file on every cloud-session start
  (`c99914b`/`65c4ffa`); both were reverted within the hour, then replaced in
  the same session with the actually-correct fix — credential *loaders*
  falling back to reading `WC_URL`/`WC_KEY`/`WC_SECRET` env vars directly when
  no file exists, so no file, hook, or setup script is needed at all
  (`9254a11`). The stated reason for reverting was that the hook broke
  container resumption, not a security review — but the replacement happens
  to be strictly safer too (no credential-bearing file touches disk). Unlike
  findings #4 (`agent-comms` shared-bearer-token ordering) and #12
  (AgenticUniverse `kill`/`logout` gating), which remain conventions with no
  enforcement, this is a case where the incentives lined up on their own.
  Worth keeping as the template to point to when #4/#12 are eventually
  fixed: prefer "make the safe path also the only path that works" over
  "document the unsafe path and hope."

### Correctly left manual — not a gap
- **Whether/when to restart the aircoenverwarmen.nl site and how to notify
  the client.** `RECOVERY-PLAN.md`'s Tier-2 items include a 72-hour
  Autoriteit Persoonsgegevens (Dutch DPA) notification clock contingent on a
  GDPR/AVG assessment, and rotating credentials "from a phone or a different
  verified-clean device" — both genuinely need a human decision and a human
  hand on the keyboard, not automation. The gap this review flags (#14) is
  purely that the plan is undiscoverable, not that any of its steps should
  have been scripted.

---

## Review: 2026-08-29 — Cross-project comms cluster deep dive (branches and open PRs)

Fourth deep-dive. The DFIR, AgenticUniverse, and aircoenverwarmen/SEO clusters
each already got a branch/PR sweep (two on 2026-08-27, one on 2026-08-28); the
cross-project-comms cluster (`ClaudeWebPlayground` + `agent-comms`) had only
the shallow, `main`-only initial pass. Also checked `legba` as the other
candidate with no deep dive yet: `git branch -a` shows only `main` plus the
assigned working branch, last commit 2026-08-15, no divergent branches, no
open PRs beyond ordinary upstream contributor flow — an external OSS repo with
nothing account-specific to find. Finding #6 stands unchanged.

`git fetch origin` on `ClaudeWebPlayground` surfaced nine remote branches
never examined: `CommsChannelB`, `claude-comms`, `claude-comms-private-demo`,
`claude/agent-fleet-management-hnho02`, `claude/new-session-x66b86`,
`claude/second-branch-creation-6sqjsp`, `claude/session-check`,
`claude/untitled-session-h242e9`, `comms-channel`. `agent-comms` itself has
only `main` and its working branch — expected, since it's a clean 2026-08-16
export with no history of its own yet.

Cross-checked against `mcp__github__list_pull_requests`: PRs #1, #4, #6 are
the three open, draft, "do not merge" claude-comms channel PRs — these exactly
match what `agent-comms/CLAUDE.md` already documents (channel PRs #1/#4/#6
still living in `ClaudeWebPlayground`), so not a new finding. `agent-comms`
has zero PRs.

Two of the nine branches (`claude/untitled-session-h242e9`: plugin-install-method
experiments; `claude/session-check`: a one-off tool/skill boot-inventory
report) are scratch exploration superseded by what's now on `main` (the
relay-kit plugin install path) — reviewed, no new findings.

### 18. A stranded branch holds the real incident-planning history behind `rat-hunt`'s transfer design, and an unimplemented multi-agent build architecture for it — neither is linked from anywhere
- **What / who:** `claude/agent-fleet-management-hnho02` (5 commits, last
  2026-08-16) forked from a point 13 commits behind the lineage that produced
  today's `main` and was never rebased or merged; no PR was ever opened for
  it. It carries two files, `docs/agent-fleet/DESIGN.md` (570 lines) and
  `docs/agent-fleet/OPERATION-PLAN.md` (505 lines):
  - `OPERATION-PLAN.md` is a full incident runbook — seven hard ordering
    constraints, a two-person keyboard/off-box-reader protocol, and the exact
    reasoning behind a three-tier evidence-transfer scheme (stage JSON always
    crosses; collected artefacts cross only as a second copy after USB;
    archives/executables/rescued files never cross) built around an
    Android-hotspot-in-airplane-mode courier. This is visibly the design
    ancestor of `rat-hunt/TRANSFER-SETUP.md` and `Send-Evidence.ps1`'s three
    transfer tiers (USB always, phone hotspot + FTP for stage JSON, artefacts
    gated) — the same shape, down to the phone-hotspot detail — but neither
    `rat-hunt` nor `Claude-Remote-recover`'s `CLAUDE.md` Provenance section
    (which names only `tools/rat-hunt/` and `.claude/skills/rat-hunt*`)
    mentions this branch or these files as where that reasoning came from.
    The plan's one item marked "UNALLOCATED" (`data.notCovered` on
    `Get-Persistence.ps1`'s envelope) turns out to already be fixed in both
    current DFIR repos — verified directly: `notCovered`/`notCoveredSweptBy`/
    `notCoveredFields` exist in `RatHunt.psm1` in both `rat-hunt` and
    `Claude-Remote-recover`, with matching assertions in
    `tests/Test-EvidenceModel.ps1` in both — but nothing marks this stale plan
    as resolved, so a future reader could easily re-open a closed question.
  - `DESIGN.md` Part 3 is a substantial, sourced multi-agent "fleet"
    architecture for *building* rat-hunt itself (not for running it): a
    20-paper arXiv prior-art pass via isolated single-abstract subagents,
    landing on Prosecutor–Judge role separation (evidence-gathering split from
    verdict-issuing) because rat-hunt's own `claimType`/verdict data model
    already encodes that separation and its *build process* doesn't — plus a
    schema-first-then-fan-out topology keyed to `RatHunt.psm1` being the
    repo's only shared-write surface. There is no evidence this fleet was ever
    actually run against the repo; the toolkit's subsequent development
    (visible in the DFIR cluster's own branch sprawl, finding #13) looks like
    ordinary single-session iteration, not the coordinated fan-out this
    document proposes.
- **Where it lives:** One orphan git branch in `ClaudeWebPlayground`, 13
  commits stale relative to other lineage on the same repo, no PR, not
  referenced by any `README.md` or `CLAUDE.md` in any of the three repos it
  concerns.
- **Opportunity:** (a) Cheap and purely mechanical — link this branch (or
  cherry-pick the two docs into a `docs/history/` or similar) from `rat-hunt`'s
  and `Claude-Remote-recover`'s Provenance sections, since it's real design
  history that explains a concrete implementation choice (the transfer-tier
  shape) that would otherwise look unmotivated to a future reader; mark the
  "UNALLOCATED" item resolved so it can't be mistaken for still-open. (b)
  Lower urgency, worth a note rather than a task: this account's `Workflow`
  tool (pipeline/parallel/agent primitives) postdates this 2026-08-16 design
  and provides exactly the machinery Part 3 assumed didn't exist yet — if a
  future session revisits building out rat-hunt's remaining gaps
  (`Get-PreBreachTimeline.ps1`'s unrun sections, `Find-Dropper.ps1`'s Sysmon/WMI
  paths, per `HANDOFF.md`), this document is a ready-made schema-first fan-out
  plan rather than something to redesign from scratch.
- Same shape as #13/#15/#16: a real, useful artifact stranded on an unlinked
  branch. Adds a fourth cluster to that pattern, reinforcing it as
  account-wide rather than DFIR-specific.

### Correctly left manual — not a gap
- **Whether to actually adopt the Part 3 fleet design**, and which of two
  divergent branches' fixes wins in any future reconciliation of the DFIR
  branch sprawl (finding #13) — both are human calls, not something a link-up
  of stale docs should decide by default.

## Review: 2026-08-30 — AZURE deep dive (infra/misc cluster)

Fifth deep-dive. `AZURE` was the only non-empty repo left with no branch/PR
sweep: the initial pass gave it one line (README.md, "worth noting"); `legba`
already got its deep dive on 2026-08-29 (confirmed nothing new, stands); `SEO`,
`security`, `Coolify-` remain confirmed-empty placeholders. `git branch -a`
shows only `main` plus the assigned working branch (identical, one commit,
`5ecef64`); `git diff main` against the working branch is empty;
`mcp__github__list_pull_requests` (state=all) returns zero — no open, closed,
or merged PRs, ever. Reviewed in full: `scripts/setup-azure.sh` (the only
logic in the repo), `.claude/hooks/session-start.sh`, `.claude/settings.json`,
`README.md`. No transcripts or handoff docs exist for this repo; the README
and the scripts' own header comments are the only durable source, and they are
unusually thorough — this repo already documents its own tradeoffs better
than most.

### 19. No parse/lint gate on the two scripts that bootstrap every remote session's Azure tooling
- **What / who:** `scripts/setup-azure.sh` and `.claude/hooks/session-start.sh`
  are the entire repo. The hook is wired into `.claude/settings.json` as a
  `SessionStart` hook (runs for everyone once merged to `main`), and the
  script's contents are *also* meant to be pasted verbatim into the
  setup-script field of unrelated environments — both entry points documented
  explicitly in `README.md`. There is no `.github/workflows/` directory, no
  shellcheck config, no test of any kind; `bash -n` (checked this run) passes
  on both files today, but nothing re-runs that check on a future edit.
- **Where it lives:** repo root — absence, not a file.
- **Opportunity:** This is the same hazard class `rat-hunt/CLAUDE.md` already
  treats as a first-order concern for its PowerShell scripts — "PowerShell
  parses a whole file before executing any of it, so a syntax error means
  nothing runs" — except here the blast radius is wider, not narrower: a
  syntax error in `setup-azure.sh` doesn't strand one incident host, it breaks
  Azure-tooling bootstrap for every session that either merges this repo's
  hook or has pasted the script into an environment config. A two-line CI job
  (`bash -n` on both files, plus `shellcheck` — both cheap, no live Azure
  credentials needed) would catch exactly the class of error the account has
  already been burned by once (rat-hunt's BOM/parse incident) before it ships,
  for the cost of adding the one workflow file this repo has never had.
  Medium-high priority given the account-wide blast radius, despite the repo
  itself being tiny.

### 20. Copy-paste propagation into environment setup-script fields has no drift detection — second confirmed instance
- **What / who:** `README.md` §"Two ways to run it" documents, as *intended
  design*, that getting this tooling into a session on any other repo means a
  human pastes the current contents of `scripts/setup-azure.sh` into that
  environment's setup-script field by hand. There is no install command, no
  version marker written into the pasted copy, and nothing that reads back
  what a given environment's field currently holds — so once `setup-azure.sh`
  changes (a new default extension, a security-relevant fix to the login
  flow), every environment that already has an older paste silently keeps
  running it, indefinitely, with no signal to anyone that it's stale.
- **Where it lives:** `AZURE/README.md` (the paste-by-hand instructions);
  the actual pasted copies live outside any repo, in each environment's own
  config, invisible to this review.
- **Opportunity:** This is the identical shape of finding #3 (the `relay-kit`
  plugin's `SKILL.md` → `plugins/relay-kit/skills/` → regenerated-installer →
  re-pasted-into-setup-script chain, `ClaudeWebPlayground`/`agent-comms`), now
  confirmed in a second, unrelated repo — which raises this from "one repo's
  quirk" to "the account has no general mechanism for noticing when a
  copy-pasted setup script has drifted from its source." A full fix needs
  either an environments API/CLI this session doesn't have visibility into, or
  a low-tech convention (an embedded version string the script logs on every
  run, cross-checked by hand against the repo) — worth solving once, generally,
  rather than per-repo. Recorded here rather than re-argued in full; see
  finding #3 for the mechanism-level detail.

### Correctly left manual — not a gap
- **The `az login --service-principal` secret-on-argv trade-off** is already
  named explicitly in `README.md` ("visible in the process list to anything
  else running in the container… acceptable trade in a single-tenant ephemeral
  container; prefer `AZURE_CLIENT_CERTIFICATE_PATH`") with the safer
  alternative given equal billing. Nothing to automate here — the tradeoff is
  already surfaced, not hidden, and the decision of which auth mode to
  configure per-environment is a per-tenant judgment call.
- **`curl | bash` installs for `az` and `azd` via Microsoft's own
  `aka.ms` install scripts**, unpinned to a specific version. This is the
  vendor-documented install method (not a shortcut this repo invented), every
  step is already idempotent and re-run-safe, and pinning would trade "always
  current" for a staleness problem of its own. Not a gap worth designing
  around absent a concrete incident.

### Nothing else new
No other findings from this pass. The repo's small size cuts both ways here:
there was very little surface to review, but what exists (idempotency,
explicit env-var tuning, degrade-not-abort error handling, the dual-entry-point
design, the documented auth tradeoff) was already in good shape going in —
this run's two findings are about the process *around* the repo (CI gate,
propagation tracking), not defects in the script itself.

## Review: 2026-08-31 — legba (security tooling cluster)

Sixth deep-dive, and legba's first at content level. The only two prior
touches were the initial pass (finding #6, plus the low-priority notes on
docs-audit and the version/tag double-check) and the 2026-08-29
cross-project-comms review's branch/PR sweep, which checked `git branch -a`
and open PRs only ("last commit 2026-08-15, no divergent branches, no open
PRs beyond ordinary upstream contributor flow... nothing account-specific to
find") without reading the commit content itself. No new commits exist since
that check — `main` and the assigned working branch are both still at
`dab974b` (2026-08-15), confirmed via `git fetch origin` and `git log`;
`mcp__github__list_pull_requests` (state=open) returns zero. So this pass
isn't chasing new activity, it's the first time anyone has actually read the
history rather than just its shape — same posture as the AZURE deep-dive on
2026-08-30.

### 21. Recurring reactive fixes for one bug class across five plugins, with no shared guard and no fuzzing — and at least one instance still unaudited
- **What / who:** PRs #98–#102 (merged 2026-07-05/06, all from the same
  external contributor, `gigioneggiando`) fixed five independent instances
  of the same underlying defect across five different protocol plugins: a
  remote server's response drives either an unbounded allocation from a
  server-controlled size field (AMQP `connection.start` frame, Kerberos TCP
  response length) or a panic on malformed input (non-ASCII HTTP headers,
  out-of-range IPv4 octets, a multi-byte UTF-8 SMTP reply), or a missing
  read/write timeout that lets a stalling server hang the operator's thread
  indefinitely (RDP, Kerberos TCP). Each was fixed with hand-written,
  plugin-local bounds/timeouts (`amqp/mod.rs`'s `MAX_CONN_START_FRAME`,
  `kerberos/transport.rs`'s `MAX_KRB_RESPONSE`, IRC's `IRC_MAX_RESPONSE`)
  rather than a shared bounded-read helper, and none of it is backed by a
  fuzz target — `find . -iname "*fuzz*"` returns nothing in the repo, and
  `ci.yml` runs only `cargo clippy`/`cargo test`, neither of which exercises
  adversarial/malformed input, which is what all five bugs needed to
  surface.
  Confirmed this defect class is not fully closed out: Kerberos's UDP
  transport (`transport.rs::UDP::request`, untouched by #101, which fixed
  only the TCP path in the same file) still does `sd.peek(&mut resp)` into a
  buffer that doubles in a loop with no upper bound, and the function's own
  `timeout` parameter is discarded (`fn request(&self, _: Duration, raw:
  &[u8])`) — so a Kerberos KDC reachable over UDP can still drive unbounded
  growth and can still hang the caller forever, the exact two failure modes
  #101 fixed on its sibling TCP path.
- **Where it lives:** Scattered across `src/plugins/{amqp,kerberos,http,irc,
  smtp,rdp}/` as five independent, ad-hoc patches; no shared utility, no
  test, no CI gate, no tracking issue tying the five together as one class.
- **Opportunity:** legba's whole purpose is speaking many protocols to
  servers it does not control or trust — any response-parsing path
  untouched by this cluster of fixes is a plausible unaudited DoS/panic
  surface, and the fact that five turned up in one contributor's single pass
  through the plugin list is itself evidence there was no systematic sweep,
  only an opportunistic one. Two concrete, boundable actions: (a) fix the
  Kerberos UDP transport the same way its TCP sibling was fixed — cap the
  peek-loop growth and honor the `timeout` parameter instead of discarding
  it; (b) add `cargo-fuzz` targets for the response-parsing entry point of
  each plugin that reads a server-controlled length/size field before
  allocating (AMQP and Kerberos are the two confirmed instances; MSSQL,
  Oracle, MQTT, STOMP, and ScyllaDB were not audited this pass and should be
  treated as unreviewed, not cleared), wired into CI as a time-boxed job
  (`cargo fuzz run <target> -- -max_total_time=60`) — the direct, mechanical
  answer to "no CI gate would have caught any of these five." High priority:
  this is a live security gap in a security tool, already proven to produce
  real bugs, not a hypothetical one.

### 22. No documented vulnerability-disclosure channel for a tool that parses adversarial network input by design
- **What / who:** There is no `SECURITY.md`, no security-contact section,
  and no responsible-disclosure process anywhere in the repo, despite
  finding #21 above being a live demonstration that this codebase's core
  function — parsing responses from untrusted servers across roughly two
  dozen protocol plugins — produces real, exploitable-by-a-malicious-server
  bugs.
- **Where it lives:** Absence — no file, no README section.
- **Opportunity:** Low-effort, standard-practice fix: a `SECURITY.md` naming
  a contact or process for reporting a plugin-parsing bug privately before
  it's filed as a public GitHub issue (the current implicit path, since
  nothing else is documented). Not urgent standalone, but cheap enough to
  ride along with whatever addresses #21.

### Nothing else reviewed this pass
The release process (`AGENTS.md`/`CLAUDE.md` steps 0–11) and the two
already-recorded low-priority notes (docs-audit/changelog human-gating,
the duplicated version/tag consistency check) were re-read and still stand
unchanged from the initial pass — not re-litigated here. A full
plugin-by-plugin audit beyond the response-parsing pattern in #21 (e.g.
credential-handling paths, CLI option parsing) was out of scope this run.

## Review: 2026-09-01 — AgenticUniverse re-deep-dive (branches, a hook, and a stale PR)

Seventh deep-dive, second pass on this repo (first: 2026-08-27, content-level
on the relay/cloudflare deploy pipeline — findings #11, #12). Picked per the
"commit activity since last review" tiebreaker: a background activity scan
across all 13 in-scope repos found AgenticUniverse to be the *only* one with
default-branch commits (`e5f7b949`, merged 2026-08-31) and an open-PR update
newer than its own last review date; every other repo was either unchanged
since its last pass or already confirmed empty. Source: `git branch -a` /
`git log` / `git merge-base --is-ancestor` against `origin/main` for all 10
branches, `mcp__github__pull_request_read` for PR #1, and direct reads of
`.claude/hooks/scope-guard.py`, `.claude/settings.json`, `docs/team-assembly.md`.
No raw transcripts read; `scope-guard.py`'s own docstring is itself an
unusually detailed, dated post-hoc incident writeup, used here the same way
other repos' `CLAUDE.md` narration has been used throughout this review.

### 23. A live access-control hook failed open for its entire operating life, silently, with zero regression test guarding the fix
- **What/who:** `.claude/hooks/scope-guard.py`, wired as a PreToolUse hook in
  `.claude/settings.json`, is meant to deny a generated teammate's
  Edit/Write/MultiEdit/NotebookEdit call outside its declared `## Scope` glob
  set — the only mechanism turning that generated prose into something a
  tool call can actually be refused for. Its two-commit history (`6ae9dcb`
  introduced it; `103cd56`, same day, fixed it) shows it matched every
  teammate's PreToolUse payload against a manifest keyed by *archetype*
  (`ui-verifier`), but the payload field it read (`agent_type`) carries the
  *roster name* a human gave that teammate (`"zed"`) — the opposite of what
  the equivalent subagent payload reports, and not obvious from the static
  hook schema (verified only by capturing real payloads off a live team's
  stdin). Every direct-key lookup for a teammate therefore missed, and
  because the hook's only failure mode is "print nothing, which Claude Code
  treats as allow" — denial is not the default anywhere in its control flow
  — the guard denied nothing, ever, for any teammate, while the generated
  agent files, the on-disk manifest, and the settings.json wiring all looked
  correctly configured. It was caught only by a live test against a real
  running team: a teammate typed `ui-verifier` was asked to edit a file
  outside its scope, and the fact that the edit went through — not the
  teammate's own account of what happened — was the evidence.
- **Where it lives:** `.claude/hooks/scope-guard.py` (now carries the long
  docstring narrating this). No test file anywhere in the repo references
  it — `.github/workflows/` contains exactly one file, `deploy-relay.yml`,
  and it only ever touches `relay/cloudflare/`; it does not run this hook,
  or anything else in `.claude/hooks/`, in CI.
- **Opportunity:** same shape as findings #4 and #12 (a mechanism that looks
  like enforcement with no automated check behind it), except here the
  mechanism already shipped, already had exactly the silent failure the
  class predicts, and the fix that landed still has no regression test — a
  future change to the manifest format or the payload schema could
  reintroduce the identical bug with nothing to catch it before the next
  live incident does. Cheap to close: a fixture PreToolUse payload shaped
  like a real teammate call (`agent_type` set to a roster name, a manifest
  keyed by archetype, a target path outside the resolved scope) asserted to
  produce a deny decision, run in CI. High priority — this is a live,
  currently-deployed access control for a system that already runs
  unattended agent teams with edit access to the repo.

### 24. PR #1 is fully superseded but still open, and its "dirty" state is a stale-base artifact, not a real conflict
- **What/who:** PR #1, "Support HEAD requests on unauthenticated relay
  routes" (opened 2026-08-24, `mergeable_state: dirty`), targets
  `claude/test-agent-teams-wrntvt` as its base — not `main`. Verified via
  `git merge-base --is-ancestor`: the PR's head branch,
  `claude/team-relay-deployment-arhzow`, is **already a full ancestor of
  `main`** — every one of its commits shipped already, through the ordinary
  sequence of merges visible in `main`'s own log (the roster/CLAUDE.md merge
  on 2026-08-31 is its tip). The base branch it's still diffed against is
  117 commits behind `main` and shares none of that later history, which is
  what produces the "dirty" state GitHub reports — not a genuine content
  conflict with anything current.
- **Where it lives:** GitHub PR state only.
- **Opportunity:** functionally a no-op that *looks* like a stuck,
  conflicted, unreviewed PR — someone opening it expecting to review a small
  HEAD-request change would instead see 112 commits and +16,461/-92 across
  82 files against a dead base, and reasonably conclude it needs work, when
  the actual fix has been live on `main` since before this review started.
  Close it as superseded (reference the commits already on `main`), and
  delete or retarget `claude/test-agent-teams-wrntvt` so nothing else gets
  based on a 117-commit-stale branch by accident. Cheap, mechanical, and
  removes a false signal from the PR queue — same "PR hygiene" shape as
  `rat-hunt` PR #2 and `aircoenverwarmen-seo-pipeline` PR #3, but the
  opposite failure direction: those are real work waiting on review, this
  one is already done and just needs closing.

### 25. Two more branches carry finished, unlinked work; a third looks like unwitting duplicate effort
- **What/who:** `claude/relay-share-target` (7 commits, last 2026-08-25) is
  a complete, device-tested feature — a share-target PWA capture flow with a
  signed Android APK built without the Android SDK and a BrowserStack App
  Automate device-testing harness, including a real bug found and fixed on
  real hardware (a restart leaving a second capture listener alive). No PR,
  110 commits behind `main`. `claude/frozen-session-recovery-d9m4dl` (1
  commit, 2026-08-25) is a diagnosis/recovery writeup for exactly the class
  of problem this account's `CLAUDE.md` files already treat as first-order
  (frozen/orphaned sessions, watcher staleness) — also no PR, 116 behind.
  Separately, `claude/new-session-absdvb` (3 commits, 2026-08-30) reworks
  `registry.py` to distinguish env vars, feature gates, and CLI flags — the
  exact same distinction `main`'s `edb26dd` (2026-08-30, merged same day)
  credits to a *different* branch, `claude/probe-surfaces-team-wiring`. The
  two branches are not ancestors of each other; whether `new-session-absdvb`
  is redundant with what already shipped or a genuinely different pass at
  the same problem was not resolved this review and needs a side-by-side
  read of both diffs before either is touched further.
- **Where it lives:** git branch state only; none referenced from `main`,
  `README.md`, or any `docs/` file.
- **Opportunity:** the same account-wide pattern already named four times
  (`rat-hunt`/`Claude-Remote-recover` finding #13,
  `aircoenverwarmen-seo-pipeline` finding #15, `startup-script-test` finding
  #16, `ClaudeWebPlayground` finding #18) — real, sometimes device-verified
  work stranded on unindexed branches — now confirmed in a fifth repo. Worth
  escalating from "recurring observation" to "worth a general fix" the next
  time any session has bandwidth for account-wide hygiene rather than a
  per-repo one: a lightweight branch index, or a norm of opening even a
  draft PR for any branch meant to survive past its own session, would have
  caught both the stranded feature work and the possible duplicate-effort
  case above before a sixth instance shows up in a sixth repo.

### Correctly left manual — not a gap
- **Which of `new-session-absdvb` or `probe-surfaces-team-wiring`'s
  `registry.py` approach is correct, if they actually differ** — a real
  diff-reading judgment call, not something to resolve by assuming either
  branch wins by default.

### Also corrected this run
- **`security`'s "empty placeholder" label (README.md).** `main` is
  genuinely a 10-byte README, but two branches off that root carry real
  content — one of them, `claude/chat-history-review-r1aofy`, is the exact
  incident record both `rat-hunt/CLAUDE.md` and
  `Claude-Remote-recover/CLAUDE.md` cite under "Provenance." The prior
  "empty placeholder" label in `README.md` meant this cross-repo reference
  was never verified against the repo it points to. Fixed in `README.md`
  this run; not a workflow-opportunity finding on its own, but worth noting
  since the label being wrong is what let it go unverified for five prior
  reviews.

## Review: 2026-09-02 — DFIR cluster re-check (no new findings)

Eighth review overall. Picked per the prioritization rule as the least
recently reviewed cluster: DFIR (`rat-hunt`, `Claude-Remote-recover`) last got
a deep dive on 2026-08-27, older than every other cluster's most recent pass
(AgenticUniverse 2026-09-01, legba 2026-08-31, AZURE 2026-08-30,
cross-project-comms 2026-08-29, aircoenverwarmen/SEO 2026-08-28). Before
committing to that pick, spot-checked every other cluster for commit activity
since its own last review (`git branch -a` / latest commits on
`aircoenverwarmen-seo-pipeline`, `airco2`, `startup-script-test`,
`ClaudeWebPlayground`, `legba`, `AZURE`, `AgenticUniverse`, `agent-comms`,
plus `list_pull_requests` on `aircoenverwarmen-seo-pipeline` and `rat-hunt`):
**nothing account-wide has a new commit since its cluster's last review.**
The one exception is age, not content — see below.

Re-examined `rat-hunt` and `Claude-Remote-recover` branch/PR state in full
(`git branch -a`, `list_commits` on every branch, `list_pull_requests`
state=all on both repos) against finding #13's 2026-08-27 description.

**Nothing new.** Specifically:
- `Claude-Remote-recover` is byte-for-byte unchanged: still only `main`
  (tip `3be35353`, 2026-08-19) and `claude/new-session-pg9x7i` (tip
  `32fb2e13`, 2026-08-21), still no PR. The 19-commit gap, the
  `-ClaudeRunAsUser`/`-CollectorOnly` hardening, and the unrelated
  Azure-jump-host/Coolify commits finding #13 already named are all still
  exactly where they were.
- `rat-hunt` gained two branches since the last review — `add-file-rescue`
  (tip `d0e254b8`) and `claude/install-matt-pocock-plugin-vez29j` (tip
  `fe9f509c`) — but both are checked and are **not** new stray work: the
  first points at a commit that's already an ancestor of `main`, the second
  points at the exact same commit `main` is currently at. Both are stale
  local working branches from sessions that already merged, safe to delete,
  not a repeat of the finding #13 pattern.
- PR #2 in `rat-hunt` ("Record the fourth staging directory...") is still
  open, still zero comments/reviews/review-requests — `updated_at` is
  unchanged at `2026-08-24T15:03:30Z`. It was 9 days stale when finding #13
  flagged it; it is now **15 days** stale with no action taken. Noted here
  as an update to #13's status, not a new finding — the fix finding #13
  already proposed (a tracked index of live incident branches, and closing
  the loop on this PR specifically) still stands unimplemented.

No new "worth automating" or "correctly left manual" items surfaced this
pass. Recorded so a future review doesn't re-spend a full deep-dive re-
confirming a cluster that hasn't moved — the next DFIR check should wait for
either commit/PR activity or a longer idle interval than nine days.

## Review: 2026-09-03 — aircoenverwarmen/SEO cluster re-check (branches only)

Ninth review overall. Picked over the cross-project-comms cluster (its last
deep dive, 2026-08-29, is one day newer than this cluster's, 2026-08-28) after
a routine default-branch check on `airco2` turned up something the
prioritization step should not skip past: `git remote show origin` reports
its `HEAD branch` as `e24-production-run`, not `main`/`master` as the
existing `README.md` entry's phrasing implies. That was reason enough to
re-verify this cluster's branch/PR state properly rather than assume the
2026-08-28 sweep was complete. `startup-script-test` was re-checked in full
(`git branch -a`, tip commits, `list_pull_requests` state=all) and confirmed
byte-for-byte unchanged since 2026-08-28 — same four branches, same tips, zero
PRs — no new findings there.

### 26. Two independently built daily-ops-automation systems for this same pipeline, built the same day, neither merged, neither cross-linked — and the stopgap scheduler both of them name has already lapsed
- **What/who:** On 2026-08-25, two different sessions each diagnosed the exact
  same problem — this pipeline's operators re-deriving state by hand at the
  start of every session — and each built a standing daily-check design to
  fix it, on two different repos in the same cluster, with no reference to
  the other:
  - `airco2` branch `ops/tier-a-daily-routine` (`a8c1e1d`, no PR): a spec
    (`docs/ops/tier-a-daily-routine.md`) plus a seeded `SESSIONS.md`, covering
    a cross-repo blocker check against `Claude-Remote-recover` (this pipeline
    is explicitly paused pre-publish on that incident's resolution — see
    commit `84320d9`), a branch sweep, session-log append, and an
    `OPEN-TASKS.md` reconciliation *proposal* file (never a direct edit, by
    design — closing an item is called out as a judgment call).
  - `aircoenverwarmen-seo-pipeline` branch `claude/pensive-keller-ikmxb8`
    (`b80a79a`, no PR): a working, dependency-free 286-line
    `scripts/daily_pipeline_digest.py` plus design notes
    (`docs/daily-digest/README.md`), covering branch-hygiene/stale-branch
    detection, checkpoint-ledger delta/stall detection, a WooCommerce
    credential-resolution check (including a specific regression guard: has
    the credential-writing `SessionStart` hook — added and reverted twice
    already — reappeared in `.claude/settings.json`), a live published-count
    sentinel check, and tracked-doc-staleness reporting. Prints `OK`/`ESCALATE`
    with exit code 0/1 and is explicitly designed to notify only on the
    latter.
  Neither branch's commit history is descended from the other, and neither
  design doc, `README.md`, or `CLAUDE.md` anywhere in the cluster mentions
  the other exists. Both design docs independently name the same limitation
  and reach the same conclusion about it: the in-session `CronCreate` tool is
  session-scoped and **auto-expires after 7 days regardless of session
  lifetime**, so it is "a pilot convenience, not the production schedule" —
  `airco2`'s doc says a fresh session must "re-arm the schedule";
  `aircoenverwarmen-seo-pipeline`'s doc names the actual fix (a Claude Code on
  the web *scheduled task*, the exact mechanism this review itself runs
  under) and gives the prompt to configure one. Both were written 2026-08-25;
  today is 2026-09-03, nine days later — whatever pilot `CronCreate` job either
  session armed has certainly lapsed by now, and because neither branch
  merged, no later session had a `main`-visible reason to notice or re-arm
  anything.
- **Where it lives:** Two unmerged git branches, no PRs, no cross-reference.
  Findable only by walking every branch's own commits, not by reading either
  repo's `main`/`master`, `README.md`, or (this cluster has neither)
  `CLAUDE.md`.
- **Opportunity / impact if left alone:** This is not "build the automation"
  — it's already built, twice, by people who'd each correctly diagnosed the
  need. The work left is purely integrative: (a) pick one design or merge the
  best of both (the `pensive-keller` script is the more complete
  implementation; the `tier-a` spec's cross-repo incident-blocker check is the
  one capability it lacks and is arguably the highest-value single check in
  the cluster, since it's this pipeline's actual publish gate) — a real
  reconciliation decision, correctly left to a human/session judgment call,
  not something to auto-merge; (b) once merged, stand up the real scheduled
  task both design docs already point at, rather than another `CronCreate`
  pilot that will silently lapse the same way. Left alone, this is the same
  stranded-branch pattern already named five times in this account
  (findings #13/#15/#16/#18/#25) — except here the stranded artifact is
  automation *for the very kind of workflow this whole review exists to
  find*, sitting fully built and inert.
  **One concrete correctness risk if either script is merged and run
  as-is without review:** `daily_pipeline_digest.py`'s live published-count
  sentinel is hardcoded to `2631` (`DEFAULT_SENTINEL_EXPECTED`). This
  repo's own `rnd/OPEN-TASKS.md` item 7.7 (unrelated code, same underlying
  quantity) already documents that a hardcoded dashboard sentinel of "2,632"
  is stale against a live count of "4,632" and calls it "a permanent false
  alarm on the only unauthorised-publish tripwire." Whether the digest
  script's `2631` baseline has drifted the same way was not verified this
  pass (no WooCommerce credentials in this session to call the live API) —
  flagged here so whoever merges this script checks the current live count
  first, rather than inheriting a false-alarm baseline the same repo has
  already been burned by once.

### 27. Two more stale, unreviewed PRs on `aircoenverwarmen-seo-pipeline` that finding #17 didn't cover
- **What/who:** Finding #17 (2026-08-28) flagged PR #3 as "a day old... the
  urgency is lower" than the DFIR cluster's stale PRs. Re-listing all PRs
  (state=all) this pass shows #3 is not the only one open: **PR #1**
  ("e24 run: in-flight Gemini checkpoint," opened 2026-08-14, `e24-production-run`
  → `master`) and **PR #2** ("codex vs minimax-v2 route comparison," opened
  2026-08-16, `e24-production-run-16ykwd` → `e24-production-run`) are both
  still open, both with zero comments/reviews as of this review — 20 and 18
  days stale respectively, older than `rat-hunt` PR #2 was when finding #13
  first flagged it (9 days) and older than it is now (15 days, per the
  2026-09-02 re-check). Finding #17 missed both because it only listed PRs
  opened at review time; neither predates that review by much, but both
  predate PR #3.
- **Where it lives:** GitHub PR state only.
- **Opportunity:** Same fix as #17 already proposed — a reviewer nudge after
  N days of no activity on a green/mergeable PR — now with three qualifying
  PRs in this one repo instead of one. Not re-litigating priority: this is a
  correction to #17's scope, not a new class of finding.

### Correctly left manual — not a gap
- **Which of the two daily-digest designs to keep, or how to merge them** —
  a real design decision (one has a cross-repo blocker check the other
  lacks; the other has a working implementation the first doesn't), not
  something to resolve by picking whichever merged first.

### Nothing else new
`airco2`'s and `aircoenverwarmen-seo-pipeline`'s other previously-uncatalogued
branches (`claude/coolify-api-menu-dump-db965s`, `claude/customize-product-management-plugin-lypbi6`,
`claude/datadog-plugin-customize-8cd0dq`, `claude/productivity-plugin-customize-v43iri`,
`claude/remove-startup-hook-commit-sa7foz`, `claude/woocommerce-non-admin-api-key-unhg8u`,
`e24-production-run-16ykwd-part2`) were checked and are either already-reverted
one-offs, a stale ref pointing at a commit already covered above, or ordinary
feature work with no workflow-formalization angle beyond what's already
recorded — not itemized individually.

## Review: 2026-09-04 — Cross-project comms cluster re-check (content level, not just branches)

Tenth review overall. Picked per the prioritization rule as the least recently
reviewed cluster: cross-project-comms (`ClaudeWebPlayground`, `agent-comms`)
last touched 2026-08-29, older than every other cluster's most recent pass
(legba 2026-08-31, AZURE 2026-08-30, AgenticUniverse 2026-09-01, DFIR
2026-09-02, aircoenverwarmen/SEO 2026-09-03). Before committing to it, spot-
checked every repo in scope for commit/branch/PR drift since its own last
review (`git fetch` + `git log` against each repo's actual default branch,
`list_pull_requests` state=all on `ClaudeWebPlayground` and `agent-comms`):
**nothing account-wide has moved.** Every repo's tip commit matches what the
prior reviews already recorded, `ClaudeWebPlayground`'s branch list is
byte-for-byte the same nine remote branches the 2026-08-29 review enumerated,
and its PR list is unchanged (#1/#4/#6 still open-draft, everything else still
closed, no new PRs anywhere in either repo).

Given that, re-running the 2026-08-29 branch/PR sweep would be exactly the
"re-review an unchanged cluster just to produce output" case the brief warns
against. What that sweep never did, though, was read the cluster at content
level — `agent-comms/cross-project-relay/src/` (the actual Cloudflare Worker
code), its test suite, and its build/deploy tooling had only been described
secondhand via `CLAUDE.md`/`HANDOVER.md`/`CREDENTIALS.md`, the same gap
findings #11 and #23 closed for `AgenticUniverse`'s relay. This pass reads and
**runs** that code instead of the docs describing it — source: direct
execution of `npx tsc --noEmit`, `node test/*.mjs` for all four suites, and a
manual `dist/` build, plus reads of `package.json`, `wrangler.jsonc`,
`tsconfig.json`, `README.md`, `fire.ts`, `channel.ts`.

### 28. `npm run test:all` is broken today, not hypothetically — two of four suites refuse to run, and nothing in the repo can fix that by design
- **What/who:** `cross-project-relay/package.json`'s `test:all` script chains
  `alarm-retry.mjs && fire-notifier.mjs && github-bridge.mjs && unicast.mjs`.
  Ran as documented (`npm install && npm run test:all`) on a clean checkout:
  `alarm-retry.mjs` (26 assertions) and `fire-notifier.mjs` (48 assertions)
  pass — both fall back to importing the `.ts` source directly when no build
  exists, a pattern their own header comments describe as "no build step
  needed." `github-bridge.mjs` and `unicast.mjs` do not have that fallback:
  each exits 2 immediately with `build first: npx tsc --outDir dist
  --module es2022 --target es2022 src/<file>.ts` and runs zero assertions.
  `test:all` therefore halts at the third script — silently, from a caller's
  perspective, since a chained `&&` failure looks like "the tests failed,"
  not "half the suite never ran." `package.json` has no `build` script at
  all, and `tsconfig.json` hardcodes `"noEmit": true` project-wide, so the
  fix these two files print in their own error text is not reachable through
  any existing npm command — `npm run typecheck` (the only compile step
  wired up) is `tsc --noEmit` by definition and can never produce the `dist/`
  either file is waiting for.
  Verified this is a packaging gap, not a code defect: manually running the
  exact command the error message names (`npx tsc --outDir dist --module
  es2022 --target es2022 src/github.ts src/unicast.ts`) and re-running both
  files afterward passes all 55 + 18 assertions clean. Full suite, correctly
  built: **147/147 assertions, zero network calls, sub-second.** `npx tsc
  --noEmit` (the real project-wide typecheck) was already clean before any of
  this — the source is fine; only the two test files' loading convention is
  inconsistent with the other two and with what `package.json` actually
  offers.
- **Where it lives:** `cross-project-relay/package.json` (`test:all`, and the
  absent `build` script), `test/github-bridge.mjs` and `test/unicast.mjs`
  (the `dist/`-only import, no `.ts` fallback), `tsconfig.json` (`noEmit`).
  No CI wiring exists anywhere in `agent-comms` to have caught this —
  confirmed by `find . -iname "*.yml" -o -iname "*.yaml"` returning nothing
  in the whole repo, so `test:all` has apparently never been run start-to-
  finish by anything other than a human who happened to build `dist/` by
  hand first and never noticed the script's own advertised path doesn't work
  standalone.
- **Opportunity:** This is the same shape as findings #1/#2 (DFIR),
  #11 (AgenticUniverse relay), and #19 (AZURE) — tests exist, are fast, need
  no live credentials, and have no CI gate — now confirmed in a fourth
  cluster, and worse in one specific way: those three were "nobody runs this
  automatically," this one is "the documented way to run it locally doesn't
  even work as shipped." Two independent, cheap fixes, either sufficient
  alone: (a) give `fire-notifier.mjs`'s `.ts`-source fallback to
  `github-bridge.mjs` and `unicast.mjs` too, so `test:all` needs no build
  step at all, matching the other two files' own stated design goal; (b) add
  a real `build` script (`tsc --outDir dist ...`, separate from the
  `noEmit` typecheck config) and have `test:all` depend on it. Either would
  then be a one-line CI job (`npm ci && npm run typecheck && npm run
  test:all`) with zero live-credential exposure — the exact same "trivial CI
  candidate" character finding #2 already named for the DFIR suites. High
  priority for the same reason #23 was: this is verification infrastructure
  for a Worker that gates cross-account message delivery and a `/fire` path
  capable of spawning sessions on another account, and it currently cannot
  even prove its own correctness to a human who follows its own
  instructions, let alone to CI.

### Correctly left manual — not a gap
- **Whether to add per-peer tokens before enabling `/fire`** (finding #4) and
  **whether to widen the GitHub PAT for cross-repo channel routing**
  (`HANDOVER.md` §4) are unchanged, real judgment/credential-scoping calls
  re-read this pass and still correctly gated on a human — not re-litigated
  here.

### Nothing else new
`ClaudeWebPlayground`'s nine remote branches and PRs #1/#4/#6 were re-checked
against the 2026-08-29 review's inventory and are byte-for-byte unchanged — no
new branches, no new PRs, no state transitions. Not re-itemized; see that
review's entry (finding #18) for what they hold.
