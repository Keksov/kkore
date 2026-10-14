#!/bin/bash
# Declared namespaces — kk.unit NAME and kk.namespace X declare function
# namespaces (kklass/USES_PLAN.md U22 as amended by U40, phase U2b): kbool.sh
# declares the kkore ones, the table __KK_NAMESPACES names their owner unit and
# file, kklass is told through its hook kk._namespace_add, and kk.unit /
# kk.namespace refuse a name kklass's hook kk._name_in_use says is a class or a
# live instance. Every scenario runs in a FRESH bash against a throw-away tree
# (unit_fixture.sh); the kklass hooks are stand-ins defined by the snippet.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "DeclaredNamespaces" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
uf_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
FX="$UF_FX"
uf_unit "$FX" nsu 'kk.namespace nsx nsy; NSU_RC=$?' 'nsx.f() { :; }'
uf_unit "$FX" busy 'BUSY_LOADS=1'
printf '%s\n' 'kk.namespace plainns; echo "plain rc=$?"' > "$FX/plain.sh"

# ---------------------------------------------------------------------------
uf_run 'source "$FX/kbool.sh"; for n in kk kl ke kv kc; do printf "%s=%s " "$n" "${__KK_NAMESPACES[$n]%%$__KK_SEP*}"; done; echo'
[[ $UF_RC == 0 && "$UF_OUT" == "kk=kuse kl=klib ke=kerr kv=kvar kc=kcfg " ]]
uf_check "kbool.sh declares the kkore namespaces kk kl ke kv kc with their owner units" $?

uf_run 'source "$FX/kbool.sh"; kk.uses nsu; echo "rc=$? nsu=$NSU_RC"
        for n in nsu nsx nsy; do v=${__KK_NAMESPACES[$n]-}; printf "%s=%s:%s " "$n" "${v%%$__KK_SEP*}" "${v##*/}"; done; echo
        source "$FX/plain.sh"; v=${__KK_NAMESPACES[plainns]-}; echo "plain owner=[${v%%$__KK_SEP*}] file=${v##*/}"'
[[ "$UF_OUT" == $'rc=0 nsu=0\nnsu=nsu:nsu.sh nsx=nsu:nsu.sh nsy=nsu:nsu.sh \nplain rc=0\nplain owner=[] file=plain.sh' ]]
uf_check "kk.unit NAME declares NAME; kk.namespace from a unit is owned by that unit, from a plain file by no unit (its file)" $?

uf_run 'source "$FX/kbool.sh"; kk.namespace; echo "none=$?"; kk.namespace "a b" ok; echo "bad=$? ok=${__KK_NAMESPACES[ok]+set}"
        kk.namespace "x[\$(touch PWN)]"; echo "inj=$?"; kk.namespace again again; echo "repeat=$?"; ls PWN 2>/dev/null'
[[ "$UF_OUT" == *"none=2"* && "$UF_OUT" == *"bad=2 ok="$'\n'* && "$UF_OUT" == *"inj=2"* && "$UF_OUT" == *"repeat=0" && "$UF_OUT" != *$'\nPWN'* ]]
uf_check "kk.namespace: no name / a non-identifier -> rc 2 (nothing declared), a repeat is a no-op" $?

uf_run 'kk_hook=""; source "$FX/kbool.sh"
        kk._namespace_add() { kk_hook+=" $1:$2"; }
        kk._name_in_use() { [[ $1 == busy || $1 == taken ]] || return 1; RESULT="an instance of TX"; return 0; }
        kk.namespace fresh; echo "fresh=$? hook=[$kk_hook]"
        kk.namespace taken; echo "taken=$? declared=${__KK_NAMESPACES[taken]+yes}"
        source "$FX/kcl/busy/busy.sh"; echo "unit busy=$? loaded=${BUSY_LOADS:-0} reg=${__KK_UNITS[busy]+yes}"'
[[ "$UF_OUT" == *"fresh=0 hook=[ fresh:]"* && "$UF_OUT" == *"'taken' is already an instance of TX"* && "$UF_OUT" == *"taken=2 declared="$'\n'* \
   && "$UF_OUT" == *"'busy' is already an instance of TX"* && "$UF_OUT" == *"unit busy=2 loaded=0 reg="* ]]
uf_check "kklass's hooks: a new namespace is pushed to kk._namespace_add; kk.namespace and a unit header refuse a name kk._name_in_use reports (rc 2; the unit not loaded, not registered) [U22, U40]" $?

uf_unit "$FX" nsbad 'kk.namespace held || return' 'NSBAD_LOADS=$(( ${NSBAD_LOADS:-0} + 1 ))'
uf_unit "$FX" nsuse 'kk.namespace "a b" || return' 'NSUSE_LOADS=$(( ${NSUSE_LOADS:-0} + 1 ))'
uf_run 'source "$FX/kbool.sh"
        kk._name_in_use() { [[ $1 == held ]] || return 1; RESULT="an instance of TX"; return 0; }
        source "$FX/kcl/nsbad/nsbad.sh" 2>/dev/null; a=$?
        kk.uses nsbad 2>/dev/null; b=$?
        source "$FX/kcl/nsbad/nsbad.sh" 2>/dev/null; c=$?
        kk._name_in_use() { return 1; }
        kk.uses nsbad; d=$?
        source "$FX/kcl/nsuse/nsuse.sh" 2>/dev/null; e=$?
        kk.uses nsuse 2>/dev/null; f=$?
        echo "plain=$a uses=$b again=$c freed=$d loads=${NSBAD_LOADS:-0} usage=$e,$f loads=${NSUSE_LOADS:-0}"'
[[ "$UF_OUT" == "plain=2 uses=2 again=2 freed=0 loads=1 usage=2,2 loads=0" ]]
uf_check "a refused or malformed kk.namespace in a PLAIN-sourced unit taints it (U34/U42): the next kk.uses and the next source run it again and fail again (rc 2), never an empty 'complete' unit [U4-G1 R1]" $?

uf_run 'source "$FX/kbool.sh"; set -a; :; set +a; export -f kk.namespace kk._ns_declare kk._ns_free
        hz="z[\$(touch PWN)]" "$BASH" -c "kk.namespace hz; echo ns=\$?; kk._ns_declare hz u f; echo decl=\$?"; ls PWN 2>/dev/null'
[[ "$UF_OUT" == $'kbool: error: kk.namespace hz: kbool.sh is not loaded\nns=2\ndecl=2' ]]
uf_check "R14: in a child without the registry kk.namespace and kk._ns_declare refuse (rc 2) before any table is touched — nothing evaluated" $?

# ---------------------------------------------------------------------------
# U44 (owner 2026-10-14, critic_u4 C5): an ALREADY declared namespace may be
# shared only by a file in the SAME FOLDER as its owner (a package: the
# thttpserver files share ths); a file elsewhere is refused (rc 2, the loading
# unit tainted — U42 — so its next load runs and fails again); a namespace
# that is a class declared in another file is never shared.
uf_pkg() {   # uf_pkg FILE NAME BODY... — a relative-header unit at FILE (any folder of the tree)
    local file=$1 name=$2; shift 2
    mkdir -p "${file%/*}"
    { printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%'"$name"'.sh}../../kbool.sh" || return' \
          "kk.unit $name || return \$__kk_unit_rc"; printf '%s\n' "$@"; } > "$file"
}
uf_pkg "$FX/kcl/pkg/pkga.sh" pkga 'kk.namespace shr clsns || return' 'shr.a() { :; }'
uf_pkg "$FX/kcl/pkg/pkgb.sh" pkgb 'kk.uses pkga || return' 'kk.namespace shr || return' 'shr.b() { :; }'
uf_pkg "$FX/kcl/pkg/pkgc.sh" pkgc 'PKGC_LOADS=$(( ${PKGC_LOADS:-0} + 1 ))' 'kk.uses pkga || return' 'kk.namespace clsns || return'
for n in shr kk pkga TSetX; do
    uf_user "$FX/proj/forn/f_$n.sh" "f_$n" "F_${n}_LOADS=\$(( \${F_${n}_LOADS:-0} + 1 ))" "kk.namespace $n || return" "$n.hijack() { echo HIJACK; }"
done
uf_user "$FX/proj/forn/shr.sh" shr 'FSHR_LOADS=$(( ${FSHR_LOADS:-0} + 1 ))' 'shr.hijack() { echo HIJACK; }'
printf '%s\n' 'kk.namespace shr; echo "plain rc=$?"' > "$FX/proj/forn/plainshr.sh"

uf_run 'source "$FX/kbool.sh"; kk.namespace TSetX || exit 7
        kk.uses "$FX/kcl/pkg/pkgb.sh"; r=$?; v=${__KK_NAMESPACES[shr]-}
        echo "pkgb=$r owner=${v%%$__KK_SEP*} b=$(declare -F shr.b)"
        for n in shr kk pkga TSetX; do
            f="$FX/proj/forn/f_$n.sh"; l="F_${n}_LOADS"
            source "$f" 2>/dev/null; a=$?; kk.uses "$f" 2>/dev/null; b=$?; source "$f" 2>"$FX/err.$n"; c=$?
            v=${__KK_NAMESPACES[$n]-}
            echo "$n=$a$b$c runs=${!l:-0} owner=${v%%$__KK_SEP*} hijack=$(declare -F $n.hijack || echo none)"
        done
        source "$FX/proj/forn/shr.sh" 2>"$FX/err.unit"; echo "unit shr=$? runs=${FSHR_LOADS:-0} reg=${__KK_UNITS[shr]+yes}"
        source "$FX/proj/forn/plainshr.sh" 2>/dev/null
        kk.namespace shr 2>/dev/null; echo "nofile=$?"
        kk.unit --forget pkga; source "$FX/kcl/pkg/pkga.sh"; echo "owner-again=$?"
        cat "$FX/err.shr" "$FX/err.unit"'
W=$'pkgb=0 owner=pkga b=shr.b\nshr=222 runs=3 owner=pkga hijack=none\nkk=222 runs=3 owner=kuse hijack=none\npkga=222 runs=3 owner=pkga hijack=none\nTSetX=222 runs=3 owner= hijack=none\nunit shr=2 runs=0 reg=\nplain rc=2\nnofile=2\nowner-again=0'
[[ "$UF_OUT" == "$W"$'\n'* && "$UF_OUT" == *"kk.namespace shr: 'shr' is already the function namespace of unit pkga ("*"/kcl/pkg/pkga.sh); only a file in that folder may share it (U44)"* \
   && "$UF_OUT" == *"unit header 'kk.unit shr' in '$FX/proj/forn/shr.sh': 'shr' is already the function namespace of unit pkga ("* ]]
uf_check "U44: a second file in the owner's folder shares a declared namespace (rc 0, the owner stays); a unit or plain file in another folder, a file-less caller, or a unit NAMED like it is refused (rc 2, the unit tainted: every next load runs and fails again, nothing defined) — also for kk (kkore) and a unit's own name; the owner re-loads fine [U44, U42, critic_u4 C5]" $?

uf_run 'source "$FX/kbool.sh"
        kk._name_in_use() { [[ $1 == clsns ]] || return 1; [[ $2 -ef $FX/kcl/pkg/pkga.sh ]] && return 1; RESULT="a class declared at $FX/kcl/pkg/pkga.sh:9"; return 0; }
        kk.uses "$FX/kcl/pkg/pkga.sh"; echo "pkga=$?"
        source "$FX/kcl/pkg/pkgc.sh" 2>"$FX/err.c"; a=$?; source "$FX/kcl/pkg/pkgc.sh" 2>/dev/null; b=$?
        echo "pkgc=$a$b runs=${PKGC_LOADS:-0}"; cat "$FX/err.c"'
[[ "$UF_OUT" == $'pkga=0\npkgc=22 runs=2\n'*"kk.namespace clsns: 'clsns' is already a class declared at $FX/kcl/pkg/pkga.sh:9"* ]]
uf_check "U44: a namespace that is a class declared in another file is never shared, not even within the owner's folder (rc 2, tainted) [U44]" $?

kt_test_log "012_DeclaredNamespaces.sh completed"
