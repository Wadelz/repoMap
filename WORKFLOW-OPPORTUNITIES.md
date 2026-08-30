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
