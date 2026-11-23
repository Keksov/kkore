#!/usr/bin/env bash
# KBOOL_VERSION (kklass/docs/dev/IMAGE_PLAN.md §7.6, IMG-D1): kbool.sh declares
# the release it belongs to, and it must equal the newest release heading of
# the kbool root CHANGELOG.md — so a release that forgets the bump fails here
# (CONTRIBUTING.md "Releasing"). The comparison is also run against fixture
# changelogs it must refuse, so a broken comparison cannot pass silently.
#
# The release heading: the first `## ` heading that is not `## Unreleased` must
# be `## X.Y.Z`, optionally followed by ` — DATE` (or any text after a dash);
# any other shape (`## [X.Y.Z]`, `## vX.Y.Z`, `## X.Y.Z-rc.1`, `## X.Y.Z:`) fails
# as an unrecognised release heading rather than being skipped.
#
# One narrow skip (I0 critic M4): kkore's own CI runs this file inside kbool
# MAIN (its workflow calls kbool's ci.yml, which checks out kbool main and puts
# the kkore commit under test in place). While kbool main's kbool.sh does not
# define KBOOL_VERSION yet — the window between a kkore push and the kbool push
# that brings KBOOL_VERSION — the first two cases SKIP there, naming the reason.
# "kkore's own CI" = KKORE_CI_STANDALONE=1, or GITHUB_REPOSITORY=Keksov/kkore
# (what GitHub sets in a reusable workflow called from Keksov/kkore). Everywhere
# else, and in kkore's CI once kbool.sh has KBOOL_VERSION, a mismatch fails.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "KboolVersion" "$SCRIPT_DIR" "$@"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"     # the kbool root
TMPD="$_KT_TMPDIR/kv"
mkdir -p "$TMPD/home" "$TMPD/cwd"

# kv_newest FILE -> NEWEST: the version of the release heading (above); rc 1
# with WHY when there is none or it is not recognised
kv_newest() {
    local line
    NEWEST="" WHY=""
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ $line == '## '* ]] || continue
        [[ $line =~ ^##[[:space:]]+\[?[Uu]nreleased\]?([[:space:]]|$) ]] && continue
        if [[ $line =~ ^##[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)([[:space:]]+(—|–|-)([[:space:]].*)?)?[[:space:]]*$ ]]; then
            NEWEST=${BASH_REMATCH[1]}
            return 0
        fi
        WHY="unrecognised release heading '$line' in $1 (want '## X.Y.Z' or '## X.Y.Z — DATE')"
        return 1
    done < "$1"
    WHY="no '## X.Y.Z' release heading in $1"
    return 1
}

# kv_compare VERSION CHANGELOG -> rc 0 when VERSION is the release heading; WHY
kv_compare() {
    kv_newest "$2" || return 1
    if [[ $1 != "$NEWEST" ]]; then
        WHY="KBOOL_VERSION=$1 but the newest CHANGELOG heading is $NEWEST"
        return 1
    fi
    return 0
}

# kv_decl [PRESET] — DECL = `declare -p KBOOL_VERSION` after PRESET and a source
# of kbool.sh in a fresh, hermetic bash; VER = its value when it is a plain string
kv_decl() {
    DECL="$(cd "$TMPD/cwd" && env -u KBOOL_VERSION -u KBOOL_HOME -u KBOOL_CONFIG -u USERPROFILE -u ProgramData \
        HOME="$TMPD/home" __KK_CFG_ETC="$TMPD/etc" "$BASH" -c \
        "${1:-:}"'; source "$1/kbool.sh" >/dev/null 2>&1 || exit 9; declare -p KBOOL_VERSION' _ "$ROOT" 2>&1)"
    VER=""
    if [[ $DECL =~ ^declare\ --\ KBOOL_VERSION=\"([^\"]*)\"$ ]]; then VER=${BASH_REMATCH[1]}; fi
}
kv_decl

# the M4 skip: kkore's standalone CI and a kbool.sh without KBOOL_VERSION
kv_skip_cond() {   # DECL — rc 0: kkore's own CI and no KBOOL_VERSION in DECL
    [[ ${KKORE_CI_STANDALONE-} == 1 || ${GITHUB_REPOSITORY-} == Keksov/kkore ]] && [[ $1 != *KBOOL_VERSION=* ]]
}
SKIP=""
if kv_skip_cond "$DECL"; then
    SKIP="SKIP: kkore's own CI runs kbool main, whose kbool.sh has no KBOOL_VERSION yet (it arrives with the kbool push of IMAGE_PLAN stage I0); strict everywhere else"
fi

kt_test_start "kbool.sh sets KBOOL_VERSION to X.Y.Z, a plain variable (not exported, no other attribute)"
if [[ -n $SKIP ]]; then
    kt_test_pass "$SKIP"
elif [[ $VER =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    kt_test_pass "KBOOL_VERSION=$VER"
else
    kt_test_fail "declare -p: [$DECL]"
fi

kt_test_start "KBOOL_VERSION equals the newest release heading of the root CHANGELOG.md (bump both together: CONTRIBUTING.md, Releasing)"
if [[ -n $SKIP ]]; then
    kt_test_pass "$SKIP"
elif [[ -n $VER ]] && kv_compare "$VER" "$ROOT/CHANGELOG.md"; then
    kt_test_pass "both $VER"
else
    kt_test_fail "${WHY:-no KBOOL_VERSION}"
fi

kt_test_start "a preset KBOOL_VERSION (exported, integer, both) or set -a: kbool.sh leaves a plain, unexported string"
got="" want=""
if [[ -z $SKIP ]]; then
    for p in 'export KBOOL_VERSION=9.9.9' 'declare -i KBOOL_VERSION=7' 'declare -ix KBOOL_VERSION=3' 'set -a'; do
        kv_decl "$p"
        got+="[$p] $DECL"$'\n'
        want+="[$p] declare -- KBOOL_VERSION=\"$VER\""$'\n'
    done
fi
if [[ -n $SKIP ]]; then
    kt_test_pass "$SKIP"
elif [[ $got == "$want" && $want != *'=""'* ]]; then
    kt_test_pass "plain"
else
    kt_test_fail "${got//$'\n'/ | }"
fi

kt_test_start "the comparison refuses what it must: an older version, a newer heading on top, no heading, other heading shapes; skips '## Unreleased' and CRLF"
printf '%s\n' '# Changelog' '' '## 9.9.9 — 2099-01-01' '' '## 1.2.3 — 2026-01-01' > "$TMPD/newer.md"
printf '%s\n' '# Changelog' '' 'No releases.' '### 1.2.3 is not a level-2 heading' > "$TMPD/none.md"
printf '%s\r\n' '# Changelog' '## Unreleased' '* x' '## 1.2.3 — 2026-01-01' '## 1.2.2' > "$TMPD/unrel.md"
printf '%s\n' '## 1.2.30 — x' > "$TMPD/longer.md"
printf '%s\n' '# Changelog' '## 1.2.3' '## 1.2.2' > "$TMPD/plain.md"
got=""
kv_compare 1.2.2 "$TMPD/unrel.md"; got+="older=$? "
kv_compare 1.2.3 "$TMPD/newer.md"; got+="newer=$? "
kv_compare 1.2.3 "$TMPD/none.md"; got+="none=$? "
kv_compare 1.2.3 "$TMPD/unrel.md"; got+="unrel=$? "
kv_compare 1.2.3 "$TMPD/plain.md"; got+="plain=$? "
kv_compare 1.2.3 "$TMPD/longer.md"; got+="prefix=$?"
for h in '## [0.2.0] — 2026-12-01' '## v0.2.0 — 2026-12-01' '## 0.2.0-rc.1 — 2026-12-01' '## 0.2.0: 2026-12-01'; do
    printf '%s\n' '# Changelog' "$h" '## 0.1.1 — 2026-11-08' > "$TMPD/shape.md"
    kv_compare 0.1.1 "$TMPD/shape.md"
    got+=" [${h%% —*}]=$?:${WHY:0:28}"
done
if [[ $got == "older=1 newer=1 none=1 unrel=0 plain=0 prefix=1 [## [0.2.0]]=1:unrecognised release heading [## v0.2.0]=1:unrecognised release heading [## 0.2.0-rc.1]=1:unrecognised release heading [## 0.2.0: 2026-12-01]=1:unrecognised release heading" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "$got"
fi

kt_test_start "the M4 skip is narrow: only for kkore's own CI with a kbool.sh lacking KBOOL_VERSION"
kv_skip() {   # DECL [ENV=VAL...] — kv_skip_cond DECL with only these CI variables set
    local d=$1; shift
    ( unset KKORE_CI_STANDALONE GITHUB_REPOSITORY; if (( $# )); then export "$@"; fi; kv_skip_cond "$d" )
}
none='bash: line 1: declare: KBOOL_VERSION: not found'
got=""
kv_skip "$none" KKORE_CI_STANDALONE=1; got+="standalone=$? "
kv_skip "$none" GITHUB_REPOSITORY=Keksov/kkore; got+="kkore-repo=$? "
kv_skip "$none" GITHUB_REPOSITORY=Keksov/kbool; got+="kbool-repo=$? "
kv_skip "$none"; got+="local=$? "
kv_skip 'declare -- KBOOL_VERSION="0.1.0"' KKORE_CI_STANDALONE=1; got+="has-version=$?"
if [[ $got == "standalone=0 kkore-repo=0 kbool-repo=1 local=1 has-version=1" ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi

kt_test_log "020_KboolVersion.sh completed"
