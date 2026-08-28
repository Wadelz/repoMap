# repoMap

A standing overview of the repositories on this account: what each one is,
how they relate to one another, and where shared lineage or dependencies
exist. Generated 2026-08-27 by an automated review of repository structure,
CI/CD configuration, and the durable project-instruction files (`CLAUDE.md`
/ `AGENTS.md`, `HANDOFF.md`, runbooks) that each repo carries — see
`WORKFLOW-OPPORTUNITIES.md` for the repeatable-workflow findings the same
review produced.

**Methodology note:** raw session transcripts were not directly readable
from this session. What stood in for them: each repo's `CLAUDE.md`/`AGENTS.md`
(persistent project instructions, several of which explicitly narrate prior
incidents — e.g. a missing-BOM bug that took down every script on first
contact with a real host), `HANDOFF.md`/`BRIEFING-ANALYSIS-*.md` files
(point-in-time handoffs written *during* past sessions), runbooks, and
CI workflow definitions. These are the closest thing to transcripts that
persist in the repos themselves, and several clusters below are explicit,
dated migrations (e.g. "split out of X on 2026-08-16 at commit `217cfb8`")
rather than inferred relationships.

## Clusters

### DFIR incident response — NetSupport RAT implant

- **rat-hunt** — Windows DFIR tooling (collection, persistence-hunting,
  guided removal, gated evidence transfer) for a NetSupport Manager RAT
  implant (`rumyhealth.exe`) on a compromised workstation. Split out of
  `ClaudeWebPlayground` so the incident has its own home. Assumes the host
  gets reimaged regardless of findings.
- **Claude-Remote-recover** — a direct successor/superset of `rat-hunt`:
  identical core scripts and evidence model, plus a new containment layer
  (two "get work off an infected host" routes — Option A: default-deny
  egress lockdown with a single pinhole; Option B: fully air-gapped
  USB-only rescue — and a collector-relay pattern for pushing work to a
  clean intermediary over SSH). Real-world Windows rehearsal findings live
  in `FIRST-CONTACT-FINDINGS-2026-08-18.md`.

### Cross-project agent comms

- **ClaudeWebPlayground** — the original personal playground repo; this is
  where the cross-session/cross-account messaging system (Tier 1: GitHub PR
  comment protocol, Tier 2: Cloudflare Worker relay) was designed and
  prototyped. Kept as the historical/provenance record post-split.
- **agent-comms** — split out of `ClaudeWebPlayground` at `main = 217cfb8`
  (2026-08-16) to give the comms infrastructure its own home, mirroring the
  same move that produced `rat-hunt`. As of this writing the split is not
  yet finalized: the deployed Worker, its GitHub PAT, and a cross-account
  test peer (`crosstalk-cc`) still point at `ClaudeWebPlayground`, and both
  repos currently carry identical copies of `cross-project-relay/`,
  `docs/cross-project-comms/`, and `plugins/relay-kit/`.
- **AgenticUniverse** — **not** part of this lineage despite a similarly
  named `relay/` directory. Its relay is "Team Bridge," a phone-to-agent-team
  push relay for a local `team.sh` setup. It shares only the general
  "Cloudflare Worker + Durable Object" architecture, not the claude-msg/
  GitHub-PR protocol or any code.

### aircoenverwarmen SEO content pipeline

- **aircoenverwarmen-seo-pipeline** — a frozen snapshot: its tip
  (`fb36aa2`, "Initial commit: aircoenverwarmen SEO content pipeline") is
  also the root of `airco2`'s history.
- **airco2** — the live continuation of the same repo, two commits ahead
  (`bfbafb8`, `84320d9` — "e24 Gemini route" checkpoints). This is where
  actual production experiment runs (`rnd/experiments/e1`…`e24`) happened;
  `aircoenverwarmen-seo-pipeline` never diverged from the shared starting
  point. Treat `airco2` as canonical and `aircoenverwarmen-seo-pipeline` as
  a baseline snapshot, not an independent fork.
- **SEO** — empty (git-initialized, zero commits). Placeholder only.
- **startup-script-test** — misnamed relative to its content, and more
  entangled with the pipeline above than the initial pass found (see
  `WORKFLOW-OPPORTUNITIES.md`, 2026-08-28 review, #14/#16): has no `main` or
  `master` branch, only four disconnected, unmerged branches. Three hold a
  blocked Google-Drive-inventory handoff (`SEO-folder-review-handoff.md`,
  stopped by a download-size cap and missing OAuth) and Hetzner
  rescue/backup tooling. The fourth, `incident-evidence-20260822`, is *not*
  tangential — it holds the confirmed-root-cause recovery plan for a second,
  separate compromise of the same `aircoenverwarmen.nl` site that `airco2`
  publishes to, six days undocumented anywhere in the pipeline repo's own
  incident trail as of this review.

### Security tooling

- **legba** — standalone Rust multi-protocol credential bruteforcer /
  password sprayer. Unrelated to the other clusters. Has by far the most
  mature, explicitly documented release process of any repo reviewed (see
  `WORKFLOW-OPPORTUNITIES.md`).

### Infra / misc

- **AZURE** — a single reusable environment-bootstrap script
  (`scripts/setup-azure.sh`) that provisions Azure CLI/`azd`/extensions and
  logs in via service principal on every ephemeral Claude Code container
  start. Explicitly designed to be copy-pasted into *other* repos'
  environment setup fields, not just used here.
- **security** — empty (10-byte README only). Placeholder.
- **Coolify-** — completely empty: no commits at all on any branch.
  Placeholder for a future Coolify-related project.

## Lineage / dependency graph (textual)

```
ClaudeWebPlayground ──(split, 2026-08-16 @ 217cfb8)──> agent-comms
ClaudeWebPlayground ──(split)──────────────────────────> rat-hunt
rat-hunt ──(extended: egress lockdown + collector relay)──> Claude-Remote-recover
aircoenverwarmen-seo-pipeline ──(same root commit fb36aa2, frozen)──> airco2 (active, diverged)
startup-script-test ──(branch incident-evidence-20260822: 2nd compromise of the site airco2 publishes to)──> airco2
AgenticUniverse/relay ┄┄ architecturally similar to, but NOT derived from ┄┄ agent-comms/cross-project-relay
```

## Repos with nothing to report

`SEO`, `security`, and `Coolify-` are empty placeholders. Three of
`startup-script-test`'s four branches hold an unrelated, stalled handoff doc
and Hetzner rescue tooling — its fourth branch does not belong in this list,
see the aircoenverwarmen cluster above and `WORKFLOW-OPPORTUNITIES.md`. None
of the three unrelated branches currently warrant workflow
formalization — noted here so a future review doesn't re-scan them expecting
new content without cause.
