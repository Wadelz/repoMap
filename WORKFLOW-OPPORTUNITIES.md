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
