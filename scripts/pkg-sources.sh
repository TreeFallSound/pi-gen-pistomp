# shellcheck shell=sh
# Canonical source-of-truth for the git-backed debpkgs and their upstream refs.
# Sourced by check-dirty-pkgs.sh and check-upstream-staleness.sh so the two
# checks can never drift apart and never need a hand-maintained package list.
#
# POSIX sh — no bashisms — so it can be sourced/inspected from bash, zsh, or dash.
# Defines one function, pkg_sources, which prints one line per git-backed package:
#
#     <pkg>|<repo>|<ref>|<kind>
#
# The package set is DISCOVERED, not hardcoded: every debpkgs/<pkg>/ that clones
# an upstream git repo references exactly one config.sh *_REPO var and one
# *_REF / *_BRANCH / *_TAG var in its build files. We scrape those names, then
# read their values out of the environment.
#
#   kind = branch  ref is a branch; can move upstream — checked by both scripts.
#          commit  ref is a pinned 40-char SHA; only moves when config.sh
#                  changes, so it is meaningless to the build-staleness (dirty)
#                  check but still worth listing in the release-staleness check.
#          tag     ref is a release tag (*_TAG var); pinned, excluded from both
#                  checks — it only changes via an explicit config.sh tag bump.
#
# Requirements (both already satisfied by the two consumer scripts):
#   - config.sh has been sourced (supplies the *_REPO / *_REF / ... values).
#   - $ROOT_DIR points at the repo root.
#
# Packages with no *_REPO reference (ffmpeg-pistomp, fluidsynth-headless,
# lcd-splash, libfluidsynth2-compat) build from a tarball/local source and are
# skipped automatically.

pkg_sources() {
    : "${ROOT_DIR:?pkg-sources.sh requires ROOT_DIR to be set}"
    for _pkg_dir in "${ROOT_DIR}"/debpkgs/*/; do
        [ -d "$_pkg_dir" ] || continue
        _pkg=$(basename "$_pkg_dir")

        # The config.sh var names this package's build references.
        # (|| true: head closing the pipe early gives grep a harmless SIGPIPE,
        #  which would otherwise trip the caller's `set -o pipefail`.)
        _repo_var=$(grep -rhoE '[A-Z0-9_]+_REPO' "$_pkg_dir" 2>/dev/null | sort -u | head -1 || true)
        [ -n "$_repo_var" ] || continue   # tarball/local package — no upstream git repo
        _ref_var=$(grep -rhoE '[A-Z0-9_]+_(REF|BRANCH|TAG)' "$_pkg_dir" 2>/dev/null | sort -u | head -1 || true)
        [ -n "$_ref_var" ] || continue

        _repo=''; eval "_repo=\$$_repo_var"
        _ref='';  eval "_ref=\$$_ref_var"

        case "$_ref_var" in
            *_TAG) _kind=tag ;;
            *)
                case "$_ref" in
                    *[!0-9a-f]*) _kind=branch ;;                              # has a non-hex char
                    *) [ ${#_ref} -eq 40 ] && _kind=commit || _kind=branch ;; # 40 hex chars = SHA
                esac
                ;;
        esac

        printf '%s|%s|%s|%s\n' "$_pkg" "$_repo" "$_ref" "$_kind"
    done | sort
}
