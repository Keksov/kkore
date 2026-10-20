#!/usr/bin/env bash
# UnitExtdebug — kk.unit under `shopt -s extdebug` and the K7 frame shifts (kklass round 5 / P14,
# finding K7, critic r5a C8).
#
# kk.unit is split: the wrapper keeps the no-op re-source fast path, the body
# moved one frame deeper into kk._unit, so every stack index of the body
# shifted by one. Under extdebug bash also pushes every FUNCTION's arguments on
# BASH_ARGV / BASH_ARGC, so the P8 "units take no arguments" check must skip
# BOTH kk._unit's and kk.unit's own entries: the source frame's count is
# BASH_ARGC[2] and its first argument BASH_ARGV[BASH_ARGC[0] + BASH_ARGC[1]].
# No other test runs extdebug — the un-shifted variant (BASH_ARGC[1],
# BASH_ARGV[BASH_ARGC[0]]) passed the whole kkore suite and warned "called
# with arguments" on every plain `source unit.sh` under extdebug.
# The registration (__KK_UNIT_BOT, the unit's source frame counted from the
# bottom of the stack) must not depend on extdebug either, and a structural
# error still taints the enclosing unit and never the erroring file's own
# registration (kk._unit_taint MIN 4; X6/X7, critic p14 F7).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "UnitExtdebug" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
FX="$_KT_TMPDIR/fx"
uf_build "$FX" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
UF_FX="$FX"
uf_unit "$FX" xdu 'XDU_LOADS=$(( ${XDU_LOADS:-0} + 1 ))' 'xdu.hi() { echo hi; }'
uf_unit "$FX" xdv 'XDV_LOADS=$(( ${XDV_LOADS:-0} + 1 ))'
# xdo plain-sources xdu (no arguments), then a unit with a header error when XD_BAD=1
uf_unit "$FX" xdo 'source "$FX/kcl/xdu/xdu.sh"; XDO_U=$?' 'if (( ${XD_BAD:-0} )); then source "$FX/kcl/xdbad/xdbad.sh"; fi' 'XDO_LOADS=$(( ${XDO_LOADS:-0} + 1 ))'
mkdir -p "$FX/kcl/xdbad"
printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || return 2' 'kk.unit wrongname || return $__kk_unit_rc' > "$FX/kcl/xdbad/xdbad.sh"
# zfoo: its header takes an argument when ZXTRA is set (a usage error -> kk._unit_taint)
mkdir -p "$FX/kcl/zfoo"
printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || return 2' 'kk.unit zfoo ${ZXTRA-} || return $__kk_unit_rc' 'ZFOO_LOADS=$(( ${ZFOO_LOADS:-0} + 1 ))' > "$FX/kcl/zfoo/zfoo.sh"

# ---------------------------------------------------------------------------
uf_run 'source "$FX/kbool.sh" || exit 9; shopt -s extdebug
f() { source "$FX/kcl/xdu/xdu.sh"; echo "rc=$? L=$XDU_LOADS"; }; f
shopt -u extdebug; echo "bot=${__KK_UNIT_BOT[xdu]} done=$(xdu.hi)"'
[[ "$UF_OUT" == $'rc=0 L=1\nbot=1 done=hi' ]]
uf_check "X1 extdebug: a plain 'source unit.sh' (no arguments) from a function loads it with NO 'called with arguments' warning; __KK_UNIT_BOT as without extdebug" $?

uf_run 'source "$FX/kbool.sh" || exit 9
f() { source "$FX/kcl/xdu/xdu.sh"; echo "rc=$? L=$XDU_LOADS"; }; f
echo "bot=${__KK_UNIT_BOT[xdu]}"'
[[ "$UF_OUT" == $'rc=0 L=1\nbot=1' ]]
uf_check "X1b the same without extdebug (the reference: bot=1)" $?

uf_run 'source "$FX/kbool.sh" || exit 9; shopt -s extdebug
g() { source "$FX/kcl/xdu/xdu.sh"; echo "rc=$?"; }; g one two three
source "$FX/kcl/xdv/xdv.sh"; echo "top rc=$? L=$XDV_LOADS"'
[[ "$UF_OUT" == $'rc=0\ntop rc=0 L=1' ]]
uf_check "X2 extdebug: no warning either from a function called WITH arguments, nor at the top level" $?

uf_run 'source "$FX/kbool.sh" || exit 9; shopt -s extdebug
f() { source "$FX/kcl/xdv/xdv.sh" a b; echo "rc=$? L=$XDV_LOADS"; }; f'
[[ "$UF_OUT" == *"WARNING: unit 'xdv' called with arguments; units take none"* && "$UF_OUT" == *"rc=0 L=1" ]]
uf_check "X3 extdebug: 'source unit.sh a b' still WARNS 'called with arguments' (and loads)" $?

uf_run 'source "$FX/kbool.sh" || exit 9; shopt -s extdebug
f() { source "$FX/kcl/xdo/xdo.sh"; echo "rc=$? O=$XDO_LOADS U=$XDO_U/$XDU_LOADS"; }; f
echo "bot=${__KK_UNIT_BOT[xdo]}/${__KK_UNIT_BOT[xdu]} src=${__KK_UNIT_SRC[xdu]##*/}"'
[[ "$UF_OUT" == $'rc=0 O=1 U=0/1\nbot=1/2 src=xdu.sh' ]]
uf_check "X4 extdebug: a unit plain-sourcing another (no arguments): no warning, nested registration (bot 1/2)" $?

uf_run 'source "$FX/kbool.sh" || exit 9; shopt -s extdebug
XD_BAD=1; source "$FX/kcl/xdo/xdo.sh" 2>/dev/null; XD_BAD=0
source "$FX/kcl/xdo/xdo.sh"; echo "rc=$? O=$XDO_LOADS"'
[[ "$UF_OUT" == "rc=0 O=2" ]]
uf_check "X5 extdebug: a header error in a nested unit taints the enclosing one (kk._unit_taint): its next source runs it again" $?

# critic p14 F7: the error taints the ENCLOSING unit only, never the erroring
# file's own (complete) registration at the same depth (kk._unit_taint MIN 4;
# the un-shifted MIN 3 tainted it and the next kk.uses loaded it again)
uf_run 'source "$FX/kbool.sh" || exit 9
source "$FX/kcl/zfoo/zfoo.sh"; ZXTRA=x; source "$FX/kcl/zfoo/zfoo.sh" 2>/dev/null; unset ZXTRA
kk.uses zfoo; echo "loads=$ZFOO_LOADS"'
[[ "$UF_OUT" == "loads=1" ]]
uf_check "X6 a header error on a re-source of a complete unit at the top level does not taint that unit (kk.uses does not load it again)" $?

uf_run 'source "$FX/kbool.sh" || exit 9
f() { source "$FX/kcl/zfoo/zfoo.sh"; }; f; ZXTRA=x; f 2>/dev/null; unset ZXTRA
kk.uses zfoo; echo "loads=$ZFOO_LOADS"'
[[ "$UF_OUT" == "loads=1" ]]
uf_check "X7 the same from a function" $?

kt_test_log "016_UnitExtdebug.sh completed"
