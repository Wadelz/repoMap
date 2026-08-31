# tools

Portable helpers for operating on the repositories this account carries.

## repo-inventory.sh

A single-file bash tool that walks one or more directories, discovers every
git repository underneath them, and reports the state that matters when you
keep many local clones on a machine: current branch, configured remotes,
ahead/behind vs upstream, whether the working tree is dirty, how many
untracked files and stashes are present, and how many local branches hold
commits that live on no remote.

Its reason for existing is the risk the account-wide review keeps flagging
(see the root `README.md` and `WORKFLOW-OPPORTUNITIES.md`): work that is only
ever local. Two failure modes in particular —

- **backup risk** — a repo with *no remote at all*, so nothing is backing it
  up; and
- **stranded work** — commits or whole branches that exist locally but have
  never been pushed anywhere —

are surfaced explicitly in a **Risk summary** at the end of every run. Dirty
trees and repos that have fallen behind their upstream are grouped there too.

It runs on both Linux and macOS (stock bash 3.2 included), handles paths with
spaces, and guards every git call so one broken repo cannot abort the scan.
Discovery prunes at each `.git`, so it will not descend into a repo's internal
git metadata, but it still finds genuinely independent repos nested inside
another project's working tree.

### Usage

```
repo-inventory.sh [options] [DIR ...]
```

Default `DIR` is the current directory. Nothing touches the network or your
working trees unless you ask for it with `--fetch` / `--pull`.

```sh
# Inventory everything under ~/code and ~/projects (read-only):
./tools/repo-inventory.sh ~/code ~/projects

# Same, but fetch updates from every remote first (prune stale branches):
./tools/repo-inventory.sh --fetch ~/code ~/projects

# Fetch, then fast-forward each repo where it is safe to do so. Never pulls a
# dirty tree, never does a non-fast-forward merge; skips are reported:
./tools/repo-inventory.sh --pull ~/code

# Machine-readable, one tab-separated row per repo (no colors), for feeding a
# spreadsheet or the account inventory:
./tools/repo-inventory.sh --tsv ~/code > inventory.tsv
```

### Options

| Option        | Effect                                                              |
| ------------- | ------------------------------------------------------------------- |
| `--fetch`     | `git fetch --all --prune --quiet` in each repo before status. Never runs by default. |
| `--pull`      | Fast-forward the current branch only when clean, tracked, behind, and a true fast-forward. Implies `--fetch`. |
| `--tsv`       | Tab-separated output instead of the human table. Columns: `path`, `branch`, `remotes`, `ahead`, `behind`, `dirty`, `untracked`, `stashes`, `unpushed_branches`. |
| `-h`, `--help`| Usage text.                                                         |

Color is used only when stdout is a TTY and `NO_COLOR` is unset.
