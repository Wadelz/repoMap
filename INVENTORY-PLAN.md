# Repo Inventory & Sync — Plan

## Goal
Get a clear, current picture of all of the account's git repositories — especially the ones that live only on local machines (some reachable via remote control / SSH) — and keep them synced: know which have remotes vs. which are local-only (backup risk), which carry unpushed/stranded work, which are dirty, and which are behind their upstreams; then pull updates where safe.

## Environment constraint (why this is two-track)
This Claude session runs in an isolated **cloud container** with only a fresh clone of `Wadelz/repoMap`. It has **no access to the local machines' filesystems** and cannot see local-only repos directly. So the plan has two complementary tracks.

## Track A — Portable local inventory tool (in this repo)
`tools/repo-inventory.sh` — a portable bash tool run on each machine. For each git repo under the given directories it reports:
- current branch (or detached HEAD)
- remotes — flags **LOCAL-ONLY** repos (no remote = single-disk backup risk)
- ahead/behind vs upstream
- dirty working tree + untracked count
- stash count
- **unpushed work across all local branches** (stranded-work risk)

Options: `--fetch` (get updates from remotes before computing status), `--pull` (fast-forward only, never on a dirty tree), `--tsv` (machine-readable rows that can feed this inventory).

Risk summary groups: local-only, unpushed, dirty, behind.

## Track B — Drive the machines live (current priority)
Run the inventory *on* each local / remote-controlled box and collect results centrally. Ways to reach the machines from this cloud session:

1. **Claude Code + Remote Control (recommended, two-way).** Run `claude` on each box, sign in to the same account, enable Remote Control so the session connects to this one. It then appears in this session's agent list and can be messaged a task ("inventory repos under X, run repo-inventory.sh --fetch --tsv, report back"). The box executes with full local filesystem access and reports the inventory back here. Cleanest path; each machine's permissions stay local.
2. **SSH from this container (pending feasibility).** Viable only if this container's network policy allows outbound SSH, each machine is reachable (public IP or a tunnel such as Tailscale / Cloudflare Tunnel / ngrok), and auth is available. Feasibility must be verified before relying on it.
3. **Push-based (fallback).** Each machine runs the tool on a schedule and pushes its `--tsv` output to a git remote or shared location this session can read.

## Data model / output
One row per repo: path, branch, remotes, ahead, behind, dirty, untracked, stashes, unpushed_branches. Aggregated per machine, then rolled up in repoMap.

## Next steps
1. Land `tools/repo-inventory.sh` + docs on `claude/slack-session-50m16v`.
2. Set up reach (Remote Control preferred) for each machine.
3. Run the tool on each machine, collect TSV, roll up a cross-machine inventory here.
4. Prioritize fixes: back up local-only repos, push stranded work, reconcile behind/ahead.
