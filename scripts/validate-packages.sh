#!/usr/bin/env bash
# PR-time validation of the debpkg/CI contract.
#
# Catches the four landmines that today only surface at image build time,
# long after a PR has merged:
#
#   1. A package listed in stage2/05-pistomp/02-run.sh's `apt-get install`
#      block has no .github/workflows/build-<pkg>.yml — the image's
#      `apt-get install` will hard-fail because the .deb was never built
#      (the rpi-preseed landmine).
#   2. A PR touches debpkgs/<pkg>/** without bumping debian/changelog —
#      the post-merge duplicate-version gate would silently skip the
#      publish (build-deb.yml:80-94). Failing at PR time is faster.
#   3. A PR adds a new debpkgs/<pkg>/ directory but doesn't ship the
#      corresponding build-<pkg>.yml workflow in the same diff — belt-
#      and-suspenders to (1) for packages not yet wired into 02-run.sh.
#   4. A .github/workflows/build-<name>.yml has paths: debpkgs/<pkg>/**
#      but no debpkgs/<pkg>/ directory exists — typo, or a stale
#      workflow left after a package was removed.
#
# Exits non-zero if any check failed; all failures are reported together
# so a PR shows every problem in one pass, not just the first.
#
# Local usage: ./scripts/validate-packages.sh   (defaults base ref to main)
# CI usage:    invoked by .github/workflows/validate-packages.yml
#              ($GITHUB_BASE_REF drives the base comparison for PR events).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

INSTALL_LIST="${ROOT_DIR}/stage2/05-pistomp/02-run.sh"
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"
DEBPKGS_DIR="${ROOT_DIR}/debpkgs"

# Packages in stage2/05-pistomp/02-run.sh's apt install lines that should
# NOT have a .github/workflows/build-<pkg>.yml because they aren't built
# by this repo:
#   jack2-pistomp / lg / lg-pistomp — installed earlier in
#     stage2/00-dummy-packages/01-run.sh via apt-get install, present in
#     02-run.sh only in a *comment*; harmless if a maintainer ever moves
#     them into the install block.
#   jack-example-tools — Trixie-apt, not a custom deb (02-run.sh:42-43).
ALLOWLIST="jack2-pistomp lg lg-pistomp jack-example-tools"

# Resolve the base ref for the diff comparison. GITHUB_BASE_REF is set in
# pull_request events (e.g. "main"); falling back to origin/main covers
# local invocation and workflow_dispatch.
BASE_REF="${GITHUB_BASE_REF:-main}"
if ! git rev-parse --verify "refs/remotes/origin/${BASE_REF}" >/dev/null 2>&1 \
   && git rev-parse --verify "refs/heads/${BASE_REF}" >/dev/null 2>&1; then
    # Allow local invocation where only the local branch exists.
    BASE_REF_FOR_DIFF="${BASE_REF}"
else
    BASE_REF_FOR_DIFF="origin/${BASE_REF}"
fi

# dch-style changelog parse: prefer dpkg-parsechangelog (dpkg-dev) when
# available, fall back to a sed parser of the first line. The first line
# of a Debian changelog is `package (version) suite; urgency=...`, so the
# sed parser is unambiguous and works on macOS where dpkg-dev isn't
# installed by default.
get_changelog_version() {
    local changelog="$1"
    if command -v dpkg-parsechangelog >/dev/null 2>&1; then
        dpkg-parsechangelog --show-field Version --file "${changelog}" 2>/dev/null
    else
        sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "${changelog}" 2>/dev/null
    fi
}

# Binary-only packages (no Source: stanza in debian/control) have their
# authoritative version in debian/control's Version: field per build-deb.yml:60-63.
# Falls back to changelog if control has no Version (sanity).
get_pkg_version() {
    local pkg_dir="$1"
    local control="${pkg_dir}/debian/control"
    local changelog="${pkg_dir}/debian/changelog"

    if [ -f "${control}" ] && ! grep -q '^Source:' "${control}" 2>/dev/null \
       && grep -q '^Version:' "${control}" 2>/dev/null; then
        awk '/^Version:/ {print $2; exit}' "${control}"
    elif [ -f "${changelog}" ]; then
        get_changelog_version "${changelog}"
    else
        return 0   # empty — caller treats as "no version found"
    fi
}

allowlisted() {
    local pkg="$1"
    case " ${ALLOWLIST} " in
        *" ${pkg} "*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Check 1 — every package in 02-run.sh's apt install lines has a workflow
# ---------------------------------------------------------------------------

echo "==> Check 1: every apt-installed package has a .github/workflows/build-<pkg>.yml"

check1_fail=0

# Extract package names from every `apt-get install -y...` invocation in
# 02-run.sh. Handles flag tokens (-y, -qq), version constraints (=, >=,
# <<), trailing backslash continuation, and the single-line standalone
# case (`apt-get install -y jack-example-tools`). Only matches valid
# Debian package name characters (lowercase, digits, +, -, .).
installed_pkgs="$(
    awk '
        /^[[:space:]]*apt-get[[:space:]]+install/ {
            sub(/^[[:space:]]*apt-get[[:space:]]+install[[:space:]]*/, "")
            in_block = 1
        }
        in_block {
            line = $0
            cont = (line ~ /\\[[:space:]]*$/)
            sub(/\\[[:space:]]*$/, "", line)
            n = split(line, toks, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                t = toks[i]
                if (t == "") continue
                if (substr(t, 1, 1) == "-") continue
                sub(/[=<>!~].*/, "", t)
                if (t ~ /^[a-z][a-z0-9.+_-]+$/) print t
            }
            if (!cont) in_block = 0
        }
    ' "${INSTALL_LIST}" | sort -u
)"

if [ -z "${installed_pkgs}" ]; then
    echo "  FAIL  could not parse any package names from ${INSTALL_LIST}"
    check1_fail=1
fi

while IFS= read -r pkg; do
    [ -z "${pkg}" ] && continue
    if allowlisted "${pkg}"; then
        echo "  SKIP  ${pkg} (allowlisted: not a custom deb)"
        continue
    fi
    workflow="${WORKFLOW_DIR}/build-${pkg}.yml"
    if [ ! -f "${workflow}" ]; then
        echo "  FAIL  ${pkg} is in ${INSTALL_LIST#${ROOT_DIR}/} install list but has no .github/workflows/build-${pkg}.yml"
        check1_fail=1
    else
        echo "  OK    ${pkg} has build-${pkg}.yml"
    fi
done <<< "${installed_pkgs}"

# ---------------------------------------------------------------------------
# Check 2 — every debpkgs/<pkg>/** touched in the PR had its changelog bumped
# ---------------------------------------------------------------------------

echo ""
echo "==> Check 2: every modified debpkgs/<pkg>/ has a bumped debian/changelog (vs ${BASE_REF_FOR_DIFF})"

check2_fail=0

if ! git rev-parse --verify "${BASE_REF_FOR_DIFF}" >/dev/null 2>&1; then
    echo "  SKIP  base ref ${BASE_REF_FOR_DIFF} not resolvable (shallow clone; run with fetch-depth: 0 in CI)"
else
    changed_pkg_dirs="$(
        git diff --name-only "${BASE_REF_FOR_DIFF}...HEAD" -- 'debpkgs/' \
            | sed -n 's|^debpkgs/\([^/]*\)/.*|\1|p' \
            | sort -u
    )"
    if [ -z "${changed_pkg_dirs}" ]; then
        echo "  OK    no debpkgs/<pkg>/ directories modified in PR"
    fi
    while IFS= read -r pkg; do
        [ -z "${pkg}" ] && continue
        pkg_dir="${DEBPKGS_DIR}/${pkg}"
        if [ ! -d "${pkg_dir}" ]; then
            # Was deleted in the PR; nothing to bump.
            echo "  SKIP  debpkgs/${pkg}/ removed in PR (no version to bump)"
            continue
        fi

        head_ver="$(get_pkg_version "${pkg_dir}")"
        if [ -z "${head_ver}" ]; then
            echo "  FAIL  debpkgs/${pkg}/ could not read version from HEAD (no debian/changelog and no Version: in debian/control)"
            check2_fail=1
            continue
        fi

        base_ver="$(
            git show "${BASE_REF_FOR_DIFF}:debpkgs/${pkg}/debian/changelog" 2>/dev/null \
                | ( command -v dpkg-parsechangelog >/dev/null 2>&1 \
                      && dpkg-parsechangelog --show-field Version - 2>/dev/null \
                      || sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' ) \
                | head -1
        )"
        if [ -z "${base_ver}" ]; then
            base_control_ver="$(git show "${BASE_REF_FOR_DIFF}:debpkgs/${pkg}/debian/control" 2>/dev/null | awk '/^Version:/ {print $2; exit}')"
            base_ver="${base_control_ver}"
        fi

        if [ -z "${base_ver}" ]; then
            # New package in this PR — there's no prior version to compare against.
            # Check 3 will verify the workflow is added; here we just confirm a
            # version exists on HEAD (already checked above).
            echo "  OK    debpkgs/${pkg}/ is new in this PR (HEAD version ${head_ver})"
            continue
        fi

        if [ "${head_ver}" = "${base_ver}" ]; then
            echo "  FAIL  debpkgs/${pkg}/ modified in PR but version unchanged (${head_ver}); run: ./scripts/bump-version.sh ${pkg} \"...\""
            check2_fail=1
        else
            echo "  OK    debpkgs/${pkg}/ bumped ${base_ver} → ${head_ver}"
        fi
    done <<< "${changed_pkg_dirs}"
fi

# ---------------------------------------------------------------------------
# Check 3 — any new debpkgs/<pkg>/ directory in the PR ships its workflow
# ---------------------------------------------------------------------------

echo ""
echo "==> Check 3: new debpkgs/<pkg>/ directories ship a build-<pkg>.yml"

check3_fail=0

if ! git rev-parse --verify "${BASE_REF_FOR_DIFF}" >/dev/null 2>&1; then
    echo "  SKIP  base ref ${BASE_REF_FOR_DIFF} not resolvable"
else
    # Bash globbing with trailing slash guarantees only directories; the
    # `for d in <dir>/*/` form is portable across bash/dash/zsh, unlike
    # `find -printf` (GNU-only) which silently fails on BSD/macOS and
    # produces an empty set whose pipe downstream still succeeds.
    head_pkgs=""
    for d in "${DEBPKGS_DIR}"/*/; do
        [ -d "$d" ] || continue
        head_pkgs+="${head_pkgs:+$'\n'}$(basename "$d")"
    done
    head_pkgs="$(printf '%s\n' "${head_pkgs}" | sort -u)"
    base_pkgs="$(
        git ls-tree --name-only "${BASE_REF_FOR_DIFF}" debpkgs/ \
            | sed -n 's|^debpkgs/\([^/]*\)$|\1|p' \
            | sort -u
    )"
    new_pkgs="$(comm -23 <(echo "${head_pkgs}") <(echo "${base_pkgs}"))"

    if [ -z "${new_pkgs}" ]; then
        echo "  OK    no new debpkgs/<pkg>/ directories in PR"
    fi
    while IFS= read -r pkg; do
        [ -z "${pkg}" ] && continue
        workflow="${WORKFLOW_DIR}/build-${pkg}.yml"
        if [ ! -f "${workflow}" ]; then
            echo "  FAIL  new package debpkgs/${pkg}/ has no .github/workflows/build-${pkg}.yml"
            check3_fail=1
        else
            echo "  OK    debpkgs/${pkg}/ ships build-${pkg}.yml in the same PR"
        fi
    done <<< "${new_pkgs}"
fi

# ---------------------------------------------------------------------------
# Check 4 — every build-<name>.yml workflow's paths: filter points at a real
# debpkgs/<pkg>/ directory (catches typos and stale workflows after deletion)
# ---------------------------------------------------------------------------

echo ""
echo "==> Check 4: every build-*.yml paths: filter names an existing debpkgs/<pkg>/"

check4_fail=0

for wf in "${WORKFLOW_DIR}"/build-*.yml; do
    [ -e "${wf}" ] || continue
    wf_name="$(basename "${wf}" .yml)"
    # The reusable build-deb.yml has no `paths:` filter — skip it (it's
    # called via workflow_call, never triggered directly).
    [ "${wf_name}" = "build-deb" ] && continue
    # build-image.yml has no debpkgs paths — skip it too.
    [ "${wf_name}" = "build-image" ] && continue

    # First `paths:` filter block: extract package dir from the first
    # `debpkgs/<pkg>/**` token. We require exactly one package per
    # workflow; the existing template enforces this.
    pkg=$(awk '
        /^[[:space:]]*paths:/ { in_paths = 1; next }
        in_paths && /^[[:space:]]*-[[:space:]]*'\''debpkgs\// {
            match($0, /debpkgs\/[^\/'\'')]+/)
            if (RSTART > 0) {
                print substr($0, RSTART + length("debpkgs/"), RLENGTH - length("debpkgs/"))
                exit
            }
        }
        in_paths && /^[[:space:]]*[a-zA-Z]/ { in_paths = 0 }
    ' "${wf}" | head -1)

    if [ -z "${pkg}" ]; then
        echo "  FAIL  ${wf_name}: could not parse a debpkgs/<pkg>/** entry from its paths: filter"
        check4_fail=1
        continue
    fi

    if [ ! -d "${DEBPKGS_DIR}/${pkg}" ]; then
        echo "  FAIL  ${wf_name}: paths: debpkgs/${pkg}/** but no debpkgs/${pkg}/ directory exists"
        check4_fail=1
    else
        echo "  OK    ${wf_name} → debpkgs/${pkg}/"
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
total_fail=$(( check1_fail + check2_fail + check3_fail + check4_fail ))
if [ "${total_fail}" -eq 0 ]; then
    echo "==> All checks passed."
    exit 0
fi

echo "==> ${total_fail} check(s) failed. Resolve each above before merging."
exit 1