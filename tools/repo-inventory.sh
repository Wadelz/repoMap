#!/usr/bin/env bash
#
# repo-inventory.sh — inventory (and optionally sync) every git repository
# under one or more directories.
#
# Walks each DIR recursively, finds every git repo (pruning once a repo is
# found so we don't descend into its internals), and reports per repo:
#   branch, remotes, ahead/behind vs upstream, dirty state, untracked file
#   count, stash count, and how many local branches carry unpushed work.
#
# The point is backup / stranded-work risk detection across a machine full of
# local clones: which repos have no remote at all (nothing backing them up),
# which hold commits that live on no remote, which are dirty, and which are
# behind their upstream. Optionally it can --fetch updates and --pull
# (fast-forward-only, never on a dirty tree) to bring repos up to date.
#
# Portable: works on both Linux and macOS. Avoids GNU-only find flags and
# handles paths containing spaces via -print0 / read -d ''.

set -euo pipefail

# ----------------------------------------------------------------------------
# Options / usage
# ----------------------------------------------------------------------------

DO_FETCH=0
DO_PULL=0
DO_TSV=0

usage() {
	cat <<'EOF'
Usage: repo-inventory.sh [options] [DIR ...]

Recursively discover every git repository under each DIR (default: .) and
report its status. Highlights local-only repos (no remote = backup risk) and
repos carrying unpushed / stranded work.

Options:
  --fetch     Run 'git fetch --all --prune --quiet' in each repo before
              computing status. Never fetches by default.
  --pull      Fast-forward the current branch when it is safe to do so:
              only if the tree is clean, an upstream is configured, the repo
              is behind, and the merge is a true fast-forward. Implies --fetch.
  --tsv       Emit tab-separated output (one row per repo) instead of the
              human-readable table. Columns:
                path  branch  remotes  ahead  behind  dirty  untracked
                stashes  unpushed_branches
  -h, --help  Show this help.

Environment:
  NO_COLOR    If set, disables ANSI color even on a TTY.
EOF
}

DIRS=()
while [ $# -gt 0 ]; do
	case "$1" in
		--fetch) DO_FETCH=1 ;;
		--pull)  DO_PULL=1; DO_FETCH=1 ;;
		--tsv)   DO_TSV=1 ;;
		-h|--help) usage; exit 0 ;;
		--) shift; while [ $# -gt 0 ]; do DIRS+=("$1"); shift; done; break ;;
		-*) echo "repo-inventory.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
		*)  DIRS+=("$1") ;;
	esac
	shift
done

# Default search root is the current directory.
if [ "${#DIRS[@]}" -eq 0 ]; then
	DIRS=(".")
fi

# ----------------------------------------------------------------------------
# Color setup — only when writing to a TTY and NO_COLOR is unset, and never in
# --tsv mode (machine-readable output must stay plain).
# ----------------------------------------------------------------------------

C_RESET=""; C_BOLD=""; C_RED=""; C_YELLOW=""; C_CYAN=""
if [ "$DO_TSV" -eq 0 ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_RED=$'\033[31m'
	C_YELLOW=$'\033[33m'
	C_CYAN=$'\033[36m'
fi

# ----------------------------------------------------------------------------
# Per-repo inspection
# ----------------------------------------------------------------------------
#
# Every git invocation is guarded (subshell + '|| true' / '|| echo ...') so a
# single corrupt or unusual repo cannot abort the whole scan under 'set -e'.

# Run git in a given repo, swallowing failure. Prints nothing on error.
git_in() {
	local dir="$1"; shift
	git -C "$dir" "$@" 2>/dev/null || true
}

# Collected results, one line per repo, tab-separated (internal buffer used by
# both the table and TSV renderers).
RESULTS=()
REPO_COUNT=0

inspect_repo() {
	local dir="$1"

	# --- optional fetch / pull -------------------------------------------
	if [ "$DO_FETCH" -eq 1 ]; then
		git -C "$dir" fetch --all --prune --quiet 2>/dev/null || \
			echo "repo-inventory.sh: fetch failed in $dir" >&2
	fi

	# --- current branch --------------------------------------------------
	local branch
	branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
	if [ -z "$branch" ]; then
		local short_sha
		short_sha=$(git_in "$dir" rev-parse --short HEAD)
		[ -z "$short_sha" ] && short_sha="unknown"
		branch="(detached: $short_sha)"
	fi

	# --- remotes ---------------------------------------------------------
	local remotes_raw remotes
	remotes_raw=$(git_in "$dir" remote)
	if [ -z "$remotes_raw" ]; then
		remotes="-"
	else
		# Join remote names with commas.
		remotes=$(printf '%s' "$remotes_raw" | paste -sd, -)
	fi

	# --- ahead / behind vs upstream --------------------------------------
	# left = behind, right = ahead when using @{upstream}...HEAD.
	local ahead="-" behind="-"
	local lr
	lr=$(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || true)
	if [ -n "$lr" ]; then
		behind=$(printf '%s' "$lr" | awk '{print $1}')
		ahead=$(printf '%s' "$lr" | awk '{print $2}')
	fi

	# --- optional pull (fast-forward only, safe) -------------------------
	if [ "$DO_PULL" -eq 1 ]; then
		maybe_pull "$dir" "$branch" "$ahead" "$behind"
		# Recompute ahead/behind after a successful fast-forward.
		lr=$(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || true)
		if [ -n "$lr" ]; then
			behind=$(printf '%s' "$lr" | awk '{print $1}')
			ahead=$(printf '%s' "$lr" | awk '{print $2}')
		fi
	fi

	# --- dirty / untracked ----------------------------------------------
	# Tracked changes count as "dirty". Untracked files are counted
	# separately so they don't mask (or inflate) the dirty signal.
	local status dirty untracked
	status=$(git_in "$dir" status --porcelain)
	dirty="no"
	untracked=0
	if [ -n "$status" ]; then
		# Lines starting with '??' are untracked; everything else is a
		# tracked modification/staged change.
		local tracked_changes
		tracked_changes=$(printf '%s\n' "$status" | grep -cv '^??' || true)
		untracked=$(printf '%s\n' "$status" | grep -c '^??' || true)
		[ "$tracked_changes" -gt 0 ] && dirty="yes"
	fi

	# --- stashes ---------------------------------------------------------
	local stashes
	stashes=$(git_in "$dir" stash list | grep -c '' || true)
	[ -z "$stashes" ] && stashes=0

	# --- unpushed work across all local branches -------------------------
	# A branch carries unpushed work if it has no upstream at all, or if its
	# upstream track info shows it is ahead. Both mean commits that exist on
	# no remote ("stranded work").
	local unpushed
	unpushed=$(git -C "$dir" for-each-ref \
		--format='%(refname:short)|%(upstream:short)|%(upstream:track)' \
		refs/heads 2>/dev/null | awk -F'|' '
			{
				up = $2
				track = $3
				if (up == "") { n++ }               # no upstream configured
				else if (track ~ /ahead/) { n++ }   # ahead of its upstream
			}
			END { print n + 0 }
		' || true)
	[ -z "$unpushed" ] && unpushed=0

	# Buffer a tab-separated result row.
	RESULTS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
		"$dir" "$branch" "$remotes" "$ahead" "$behind" \
		"$dirty" "$untracked" "$stashes" "$unpushed")")
	REPO_COUNT=$((REPO_COUNT + 1))
}

# Attempt a safe fast-forward pull. Prints a clear note about what it did or
# why it skipped. Never touches a dirty tree or does a non-ff merge.
maybe_pull() {
	local dir="$1" branch="$2" ahead="$3" behind="$4"

	# Detached HEAD: nothing to pull onto.
	case "$branch" in
		"(detached:"*) echo "  pull: skip $dir (detached HEAD)" >&2; return ;;
	esac

	# No upstream configured.
	if [ "$behind" = "-" ]; then
		echo "  pull: skip $dir (no upstream)" >&2
		return
	fi

	# Dirty tree — never pull.
	if [ -n "$(git_in "$dir" status --porcelain --untracked-files=no)" ]; then
		echo "  pull: skip $dir (working tree dirty)" >&2
		return
	fi

	# Not behind — nothing to do.
	if [ "$behind" = "0" ]; then
		return
	fi

	# Only fast-forward. git merge --ff-only refuses non-ff automatically.
	if git -C "$dir" merge --ff-only --quiet '@{upstream}' 2>/dev/null; then
		echo "  pull: fast-forwarded $dir ($behind commit(s))" >&2
	else
		echo "  pull: skip $dir (not a fast-forward)" >&2
	fi
}

# ----------------------------------------------------------------------------
# Repo discovery
# ----------------------------------------------------------------------------
#
# Find every '.git' entry (directories for normal repos, files for submodules
# / linked worktrees) under each DIR. '-prune' stops find from descending INTO
# a matched '.git', which is what keeps us out of a repo's own internals
# (e.g. '.git/modules/*/.git', '.git/worktrees/...') — the "don't descend into
# a repo's contents looking for more" behavior. Because a repo's git metadata
# lives inside '.git', pruning it does not stop us from finding a genuinely
# independent repo nested elsewhere in the working tree, so a normal layout of
# nested independent repos is still fully discovered.
#
# -print0 / read -d '' keep this correct for paths containing spaces, and
# -name .git -prune is portable across GNU (Linux) and BSD (macOS) find.

discover_and_inspect() {
	local root="$1"

	if [ ! -e "$root" ]; then
		echo "repo-inventory.sh: no such path: $root" >&2
		return
	fi

	while IFS= read -r -d '' gitpath; do
		# The repo root is the parent directory of the .git entry.
		local repo_dir
		repo_dir=$(dirname "$gitpath")

		# Confirm it really is a work tree / repo we can inspect.
		if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			inspect_repo "$repo_dir"
		fi
	done < <(find "$root" -name .git -prune -print0 2>/dev/null)
}

# ----------------------------------------------------------------------------
# Rendering
# ----------------------------------------------------------------------------

render_tsv() {
	local row
	for row in "${RESULTS[@]}"; do
		printf '%s\n' "$row"
	done
}

render_table() {
	if [ "${#RESULTS[@]}" -eq 0 ]; then
		echo "No git repositories found."
		return
	fi

	# Header plus rows, formatted through column-width computation.
	# (Namerefs / associative arrays are avoided deliberately so this runs on
	# macOS's stock bash 3.2 as well as modern Linux bash.)
	local header=$'PATH\tBRANCH\tREMOTES\tAHEAD\tBEHIND\tDIRTY\tUNTRACKED\tSTASH\tUNPUSHED'

	# Compute column widths across header + all rows into the global WIDTHS.
	WIDTHS=()
	local i
	local -a hcols
	IFS=$'\t' read -r -a hcols <<<"$header"
	for i in "${!hcols[@]}"; do
		WIDTHS[i]=${#hcols[i]}
	done

	local row
	local -a cols
	for row in "${RESULTS[@]}"; do
		IFS=$'\t' read -r -a cols <<<"$row"
		for i in "${!cols[@]}"; do
			local len=${#cols[i]}
			if [ "${WIDTHS[i]:-0}" -lt "$len" ]; then
				WIDTHS[i]=$len
			fi
		done
	done

	# Print the header (bold/cyan), uncolored per-cell.
	local out=""
	for i in "${!hcols[@]}"; do
		out+=$(printf '%-*s' "${WIDTHS[i]}" "${hcols[i]}")
		out+="  "
	done
	printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$out" "$C_RESET"

	# Print each data row, coloring risk flags.
	for row in "${RESULTS[@]}"; do
		IFS=$'\t' read -r -a cols <<<"$row"
		print_data_row
	done
}

# Print the current 'cols' array as a padded data row, coloring risky values.
# Reads the global 'cols' and 'WIDTHS' arrays.
print_data_row() {
	local i out=""
	for i in "${!cols[@]}"; do
		local val="${cols[i]}"
		local color=""
		case "$i" in
			2) [ "$val" = "-" ] && color="$C_RED" ;;      # remotes: local-only
			3) [ "$val" != "-" ] && [ "$val" != "0" ] && color="$C_YELLOW" ;; # ahead
			4) [ "$val" != "-" ] && [ "$val" != "0" ] && color="$C_YELLOW" ;; # behind
			5) [ "$val" = "yes" ] && color="$C_RED" ;;    # dirty
			8) [ "$val" != "0" ] && color="$C_YELLOW" ;;  # unpushed branches
		esac
		local padded
		padded=$(printf '%-*s' "${WIDTHS[i]}" "$val")
		if [ -n "$color" ]; then
			out+="${color}${padded}${C_RESET}"
		else
			out+="$padded"
		fi
		out+="  "
	done
	printf '%s\n' "$out"
}

render_risk_summary() {
	LOCAL_ONLY=(); UNPUSHED_REPOS=(); DIRTY_REPOS=(); BEHIND_REPOS=()
	local row
	local -a c
	for row in "${RESULTS[@]}"; do
		IFS=$'\t' read -r -a c <<<"$row"
		local path="${c[0]}" remotes="${c[2]}" behind="${c[4]}"
		local dirty="${c[5]}" unpushed="${c[8]}"
		[ "$remotes" = "-" ] && LOCAL_ONLY+=("$path")
		if [ "$unpushed" != "0" ]; then
			UNPUSHED_REPOS+=("$path ($unpushed branch(es))")
		fi
		[ "$dirty" = "yes" ] && DIRTY_REPOS+=("$path")
		if [ "$behind" != "-" ] && [ "$behind" != "0" ]; then
			BEHIND_REPOS+=("$path ($behind behind)")
		fi
	done

	printf '\n%s%sRisk summary%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

	print_risk_group "Local-only repos (no remote — backup risk)" "$C_RED" "${LOCAL_ONLY[@]+"${LOCAL_ONLY[@]}"}"
	print_risk_group "Repos with unpushed commits/branches (stranded work)" "$C_YELLOW" "${UNPUSHED_REPOS[@]+"${UNPUSHED_REPOS[@]}"}"
	print_risk_group "Dirty repos (uncommitted tracked changes)" "$C_RED" "${DIRTY_REPOS[@]+"${DIRTY_REPOS[@]}"}"
	print_risk_group "Repos behind upstream" "$C_YELLOW" "${BEHIND_REPOS[@]+"${BEHIND_REPOS[@]}"}"
}

# print_risk_group TITLE COLOR [ITEM ...]
print_risk_group() {
	local title="$1" color="$2"
	shift 2
	printf '  %s%s%s\n' "$color" "$title" "$C_RESET"
	if [ "$#" -eq 0 ]; then
		printf '    none\n'
	else
		local item
		for item in "$@"; do
			printf '    - %s\n' "$item"
		done
	fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
	local d
	for d in "${DIRS[@]}"; do
		discover_and_inspect "$d"
	done

	if [ "$DO_TSV" -eq 1 ]; then
		render_tsv
		return
	fi

	render_table
	render_risk_summary
	printf '\n%s%d repos scanned.%s\n' "$C_BOLD" "$REPO_COUNT" "$C_RESET"
}

main
