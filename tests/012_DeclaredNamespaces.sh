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

uf_run 'source "$FX/kbool.sh"; set -a; :; set +a; export -f kk.namespace kk._ns_declare kk._ns_free
        hz="z[\$(touch PWN)]" "$BASH" -c "kk.namespace hz; echo ns=\$?; kk._ns_declare hz u f; echo decl=\$?"; ls PWN 2>/dev/null'
[[ "$UF_OUT" == $'kbool: error: kk.namespace hz: kbool.sh is not loaded\nns=2\ndecl=2' ]]
uf_check "R14: in a child without the registry kk.namespace and kk._ns_declare refuse (rc 2) before any table is touched — nothing evaluated" $?

kt_test_log "012_DeclaredNamespaces.sh completed"
