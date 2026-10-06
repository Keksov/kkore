#!/bin/bash
# kk.unit / kk.uses / kk.defined — the unit loader (kklass/USES_PLAN.md, phase U1a).
# Every scenario runs in a FRESH bash (the registry is per shell) against a
# throw-away kbool tree built by unit_fixture.sh: a copy of kbool.sh + kkore and
# fixture units with the two header lines of §7.4.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "UnitsAndUses" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
uf_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
FX="$UF_FX"

# ---------------------------------------------------------------------------
# Header, bootstrap, once-only (U19', U27, C4)
uf_run 'source "$FX/kcl/a/a.sh"; r1=$?; source "$FX/kcl/a/a.sh"; echo "r=$r1/$? L=$A_LOADS fn=$(type -t a.hello) klib=$(type -t kk.isInt) home=$KBOOL_HOME"'
[[ $UF_RC == 0 && "$UF_OUT" == "r=0/0 L=1 fn=function klib=function home=$FX" ]]
uf_check "direct source in a bare shell bootstraps kbool.sh and loads the unit once [U27]" $?

uf_run 'cd "$FX/kcl/a" && source a.sh; r1=$?; source a.sh; echo "r=$r1/$? L=$A_LOADS dir=$A_DIR home=$KBOOL_HOME"'
[[ "$UF_OUT" == "r=0/0 L=1 dir=$FX/kcl/a home=$FX" ]]
uf_check "no-slash source from the unit's own folder: once, KK_UNIT_DIR and KBOOL_HOME absolute [C4]" $?

uf_run 'PATH="$FX/kcl/a:$PATH"; cd /; source a.sh; r1=$?; source a.sh; echo "r=$r1/$? L=$A_LOADS"'
[[ "$UF_OUT" == "r=0/0 L=1" ]]
uf_check "a unit found through PATH (sourcepath) loads once [U3]" $?

uf_run 'set -eu; source "$FX/kcl/a/a.sh"; source "$FX/kcl/a/a.sh"; kk.uses a; echo "ok $A_LOADS"'
[[ $UF_RC == 0 && "$UF_OUT" == "ok 1" ]]
uf_check "set -eu: direct source twice + kk.uses, silent, once [C3]" $?

uf_run 'source "$FX/kcl/a/a.sh"; x=$(source "$FX/kcl/a/a.sh"; echo "$A_LOADS"); echo "sub=$x"'
[[ "$UF_OUT" == "sub=1" ]]
uf_check "a \$( ) subshell inherits the registry: re-source there is a no-op" $?

uf_run 'source "$FX/kcl/a/a.sh"; export -f kk.unit kk.uses; env __KK_UNITS=scalar "$BASH" -c "source \"\$FX/kcl/a/a.sh\"; echo child r=\$? L=\$A_LOADS klib=\$(type -t kk.isInt)"'
[[ "$UF_OUT" == "child r=0 L=1 klib=function" ]]
uf_check "child bash with exported functions and an exported scalar __KK_UNITS re-bootstraps, loads once [U28, C3]" $?

uf_run 'source "$FX/kcl/fnu/fnu.sh"; fnu.reuse; echo "r=$? L=$FNU_LOADS"'
[[ "$UF_OUT" == "r=0 L=1" ]]
uf_check "a function defined in the unit re-sources it at the first load's depth: no false cycle (only source frames count) [C12]" $?

# ---------------------------------------------------------------------------
# kk.uses: names, paths, the lazy index (U12-U16, U13', P5)
uf_run 'source "$FX/kbool.sh"; kk.uses a; r1=$?; kk.uses a; echo "r=$r1/$? L=$A_LOADS"'
[[ "$UF_OUT" == "r=0/0 L=1" ]]
uf_check "kk.uses NAME loads once, a repeat is a silent rc-0 no-op" $?

uf_run 'source "$FX/kbool.sh"; kk.uses a b; echo "r=$? ${A_LOADS}${B_LOADS}"'
[[ "$UF_OUT" == "r=0 11" ]]
uf_check "kk.uses A B loads both" $?

uf_run 'source "$FX/kbool.sh"; echo "before=$__KK_UNIT_IDX_OK"; kk.uses a; echo "after=$__KK_UNIT_IDX_OK a=${__KK_UNIT_IDX[a]-} bench=${__KK_UNIT_IDX[bench]-none} helper=${__KK_UNIT_IDX[helper]-none}"'
[[ "$UF_OUT" == "before=0"$'\n'"after=1 a=$FX/kcl/a/a.sh bench=none helper=none" ]]
uf_check "the name index is lazy (built at the first name lookup), headered files only, first match wins [P5, U13', U15]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses nosuch; echo "r=$?"'
[[ "$UF_OUT" == *"r=2" && "$UF_OUT" == *"'nosuch'"* ]]
uf_check "kk.uses of an unknown name: rc 2 with a message naming it" $?

uf_run 'source "$FX/kbool.sh"; kk.uses bench; echo "r=$? L=${BENCH_LOADS:-0}"'
[[ "$UF_OUT" == *"r=2 L=0" && "$UF_OUT" == *"'bench'"* ]]
uf_check "kk.uses bench: a header-less file is not a unit, not found by name [U13', C18]" $?

uf_run 'source "$FX/kbool.sh"; cd "$FX/kcl/a"; kk.uses helper; echo "r=$? L=${HELPER_LOADS:-0}"'
[[ "$UF_OUT" == *"r=2 L=0" ]]
uf_check "a header-less file in the caller's folder is not found by name either [U13']" $?

uf_run 'source "$FX/kbool.sh"; kk.uses "$FX/kcl/a/bench.sh"; r1=$?; kk.uses "$FX/kcl/b/../a//bench.sh"; echo "r=$r1/$? L=$BENCH_LOADS"'
[[ "$UF_OUT" == "r=0/0 L=1" ]]
uf_check "a header-less file by path loads, and kk.uses does not load it again (any lexical spelling)" $?

uf_run '"$BASH" "$FX/proj/main.sh"'
[[ "$UF_OUT" == "proj=1 kcl=0" ]]
uf_check "a name resolves in the calling file's folder first, before the system paths [U14]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses "x\\y"; echo "r=$?"'
[[ "$UF_OUT" == *"r=2" && "$UF_OUT" == *"file"* ]]
uf_check "a backslash makes the argument a path, not a unit name [C18]" $?

if [[ $FX == /[a-zA-Z]/* && ( $OSTYPE == msys* || $OSTYPE == cygwin* ) ]]; then
    uf_run 'W="${FX:1:1}:${FX:2}"; WB="${W//\//\\}"
source "$FX/kcl/a/a.sh"; source "$W/kcl/a/a.sh"; r1=$?; kk.uses "$WB\\kcl\\a\\a.sh"; echo "r=$r1/$? L=$A_LOADS"'
    [[ "$UF_OUT" == "r=0/0 L=1" ]]
    uf_check "Windows spellings C:/... and C:\\... of a loaded unit are the same unit (-ef) [U18']" $?
else
    kt_test_start "Windows spellings C:/... and C:\\... of a loaded unit are the same unit (-ef) [U18']"
    kt_test_pass "SKIP: not an MSYS/Cygwin shell ($OSTYPE) — no drive-letter spellings"
fi

uf_run 'source "$FX/kcl/a/a.sh"; source "$FX/kcl/b/../a//a.sh"; r1=$?; kk.uses "$FX/kcl/b/../a/a.sh"; echo "r=$r1/$? L=$A_LOADS"'
[[ "$UF_OUT" == "r=0/0 L=1" ]]
uf_check "the same unit through .. and // spellings is loaded once, silently [U18']" $?

uf_run 'source "$FX/kbool.sh"; kk.uses; r1=$?; kk.uses "a*"; r2=$?; kk.uses ""; echo "r=$r1/$r2/$?"'
[[ "$UF_OUT" == *"r=2/2/2" ]]
uf_check "kk.uses with no argument, a glob-like or an empty name: rc 2" $?

# ---------------------------------------------------------------------------
# Errors: U33, same name from another file (U18'), cycles (U25), U34
uf_run 'source "$FX/kcl/bad/bad.sh"; echo "r=$? L=${BAD_LOADS:-0}"'
[[ "$UF_OUT" == *"r=2 L=0" && "$UF_OUT" == *"wrongname"* ]]
uf_check "U33: 'kk.unit wrongname' in bad.sh, plain source -> rc 2, body not run" $?

uf_run 'source "$FX/kbool.sh"; kk.uses "$FX/kcl/bad/bad.sh"; echo "r=$? L=${BAD_LOADS:-0}"'
[[ "$UF_OUT" == *"r=2 L=0" && "$UF_OUT" == *"loading unit 'bad' failed (rc=2)"* ]]
uf_check "U33 through kk.uses PATH -> rc 2, body not run, the failure names the unit by its stem" $?

uf_run 'source "$FX/kbool.sh"; kk.uses a; kk.uses "$FX/kcl/zdup/a.sh"; r1=$?; source "$FX/kcl/zdup/a.sh"; echo "r=$r1/$? D=${DUP_LOADS:-0} A=$A_LOADS"'
[[ "$UF_OUT" == *"r=2/2 D=0 A=1" && "$UF_OUT" == *"already loaded"* ]]
uf_check "the same unit name from a different file: rc 2 by kk.uses and by plain source [U18']" $?

uf_run 'UF_CYC=1; source "$FX/kbool.sh"; kk.uses a; echo "r=$? A=$A_LOADS B=$B_LOADS"'
[[ "$UF_OUT" == *"r=2 A=1 B=1" && "$UF_OUT" == *"circular unit reference: a -> b -> a"* ]]
uf_check "cycle a -> b -> a through kk.uses: error naming the chain [U25, C12]" $?

uf_run 'UF_CYC=2; source "$FX/kcl/a/a.sh"; echo "r=$? A=$A_LOADS B=$B_LOADS"'
[[ "$UF_OUT" == *"r=2 A=1 B=1" && "$UF_OUT" == *"circular unit reference: a -> b -> a"* ]]
uf_check "cycle with a plain source (b sources a while a loads) [U25, C12]" $?

uf_run 'UF_CYC=1; source "$FX/kcl/a/a.sh"; echo "r=$? A=$A_LOADS B=$B_LOADS"'
[[ "$UF_OUT" == *"r=2 A=1 B=1" && "$UF_OUT" == *"circular unit reference: a -> b -> a"* ]]
uf_check "cycle mixed: a plain-sourced, a -> b by kk.uses, b -> a by kk.uses [U25, C12]" $?

uf_run 'UF_CYC=1; source "$FX/kbool.sh"; kk.uses a 2>/dev/null; UF_CYC=0; kk.uses a; echo "r=$? A=$A_LOADS"'
[[ "$UF_OUT" == "r=0 A=2" ]]
uf_check "after a failed (cyclic) kk.uses the unit is forgotten: a retry reloads it [C12]" $?

uf_run 'UF_FAIL=1; source "$FX/kbool.sh"; kk.uses fail; r1=$?; UF_FAIL=0; kk.uses fail; echo "r=$r1/$? L=$FAIL_LOADS fn=$(type -t fail.hello)"'
[[ "$UF_OUT" == *"r=3/0 L=2 fn=function" ]]
uf_check "a unit that fails mid-load returns its rc; a retry reloads it [C12]" $?

uf_run 'set -e; UF_FAIL=1; source "$FX/kbool.sh"; kk.uses fail || echo caught; echo after'
[[ "$UF_OUT" == *"caught"$'\n'"after" ]]
uf_check "set -e: 'kk.uses x || ...' survives a failing unit (plain source, no builtin source) [C11]" $?

uf_run 'UF_FAIL=1; source "$FX/kcl/dep/dep.sh"; r1=$?; UF_FAIL=0; kk.uses dep; r2=$?; kk.unit --forget dep; r3=$?; kk.uses dep; echo "r=$r1/$r2/$r3/$? D=$DEP_LOADS"'
[[ "$UF_OUT" == *"r=2/2/0/0 D=2" && "$UF_OUT" == *"not completely loaded"* ]]
uf_check "a plain-sourced unit with a STRUCTURAL error inside its load (a header error): kk.uses says 'not completely loaded' (rc 2); --forget then reloads [U34, R1]" $?

uf_run 'source "$FX/kcl/a/a.sh"; kk.uses a; echo "r=$? L=$A_LOADS"'
[[ "$UF_OUT" == "r=0 L=1" ]]
uf_check "a unit loaded by plain source counts as loaded for kk.uses (no reload, no error)" $?

uf_run 'source "$FX/kbool.sh"; kk.unit x; echo "r=$?"'
[[ "$UF_OUT" == *"r=2" ]]
uf_check "kk.unit outside a unit file's header: rc 2" $?

uf_run 'source "$FX/kkore/kuse.sh"; source "$FX/kcl/a/a.sh"; echo "r=$? L=$A_LOADS klib=$(type -t kk.isInt)"'
[[ "$UF_OUT" == "r=0 L=1 klib=function" ]]
uf_check "kuse.sh sourced alone first (its empty registry is not 'loaded'): a unit's line 1 still bootstraps kbool.sh" $?

uf_run 'source "$FX/kkore/kuse.sh"; kk.uses a; echo "r=$?"'
[[ "$UF_OUT" == *"r=2" && "$UF_OUT" == *"not loaded"* ]]
uf_check "kuse.sh sourced alone (no kbool.sh): kk.uses refuses with rc 2" $?

# ---------------------------------------------------------------------------
# Positional arguments (C10, P8) and KK_UNIT_DIR (U17, C19)
uf_run 'set -- p1 p2; source "$FX/kbool.sh"; kk.uses args; echo "n=$ARGS_N outer=$#:$1"'
[[ "$UF_OUT" == "n=0 outer=2:p1" ]]
uf_check "kk.uses: the caller's positional args do not leak into the unit [C10]" $?

uf_run 'source "$FX/kcl/args/args.sh" set_trap; echo "r=$? n=$ARGS_N"'
[[ "$UF_OUT" == *"r=0 n=1" && "$UF_OUT" == *"called with arguments"* ]]
uf_check "a unit sourced WITH arguments loads and prints the P8 WARNING [P8]" $?

uf_run 'source "$FX/kcl/args/args.sh"; source "$FX/kcl/args/args.sh" x; echo "r=$? L=$ARGS_LOADS"'
[[ "$UF_OUT" == *"r=0 L=1" && "$UF_OUT" == *"called with arguments"* ]]
uf_check "the P8 WARNING also on a skipped re-source with arguments (stale 'source kerr.sh set_trap' shape) [P8]" $?

uf_run 'set -- p1; source "$FX/kcl/args/args.sh"; echo "r=$? n=$ARGS_N"'
[[ "$UF_OUT" == "r=0 n=1" ]]
uf_check "no WARNING for a plain source without arguments (inherited positionals are not 'arguments') [P8]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses kdir; echo "top=$KDIR_TOP after=$KDIR_AFTER now=${KK_UNIT_DIR-unset}"'
[[ "$UF_OUT" == "top=$FX/kcl/kdir after=$FX/kcl/kdir now=unset" ]]
uf_check "KK_UNIT_DIR is the unit's folder, restored after a nested kk.uses and after the outer one [U17, C19]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses a; kk._unit_current; echo "in=$A_CUR out=[$RESULT] rc=$?"'
[[ "$UF_OUT" == "in=a out=[] rc=1" ]]
uf_check "kk._unit_current names the unit being loaded (empty outside a load) — the U2 class-site hook" $?

# ---------------------------------------------------------------------------
# kk.unit --forget, the unit -> classes registry (U24', P4), kk.defined (U31)
uf_run 'source "$FX/kbool.sh"; kk.uses a; kk.unit --forget a; r1=$?; kk.uses a; echo "r=$r1/$? L=$A_LOADS"'
[[ "$UF_OUT" == "r=0/0 L=2" ]]
uf_check "kk.unit --forget NAME: the next kk.uses loads the unit again [U24']" $?

uf_run 'source "$FX/kbool.sh"; kk.unit --forget nosuch; r1=$?; kk.unit --forget kbool 2>/dev/null; r2=$?; kk.unit --forget 2>/dev/null; echo "r=$r1/$r2/$?"'
[[ "$UF_OUT" == "r=1/2/2" ]]
uf_check "kk.unit --forget: unknown -> rc 1, kbool or no name -> rc 2" $?

uf_run 'source "$FX/kbool.sh"; kk.uses a; kk._unit_add_class a TFoo; kk._unit_add_class a TBar; kk._unit_add_class a TFoo; kk._unit_classes a; c1=$RESULT
kk._unit_forget_class() { echo "forgot $1"; }
kk.unit --forget a; kk._unit_classes a; echo "c1=$c1 c2=[$RESULT]"'
[[ "$UF_OUT" == "forgot TFoo"$'\n'"forgot TBar"$'\n'"c1=TFoo TBar c2=[]" ]]
uf_check "unit -> classes registry: add (deduplicated), list, --forget calls the class hook per class and clears it [P4]" $?

uf_run 'source "$FX/kbool.sh"; kk.defined FOO; r1=$?; kk.defined; r2=$?; __KK_DEFINES[FOO]=1; kk.defined FOO; echo "r=$r1/$r2/$?"'
[[ "$UF_OUT" == "r=1/2/0" ]]
uf_check "kk.defined NAME: rc 1 undefined, rc 0 defined, rc 2 without a name [U31]" $?

# ---------------------------------------------------------------------------
# U1a review round (R1, R3, R4, R7, R8, R11)
uf_run 'UF_FAIL=1; source "$FX/kcl/opt/opt.sh"; echo "r=$? L=$OPT_LOADS fb=$OPT_FALLBACK$OPT_FALLBACK2"; kk.uses opt; echo "uses r=$? L=$OPT_LOADS"'
[[ "$UF_OUT" == "r=0 L=1 fb=11"$'\n'"uses r=0 L=1" ]]
uf_check "an optional dependency the unit handles (not found; failing rc 3), PLAIN source: the unit is complete, kk.uses of it rc 0 [R1]" $?

uf_run 'UF_FAIL=1; source "$FX/kbool.sh"; kk.uses opt; echo "r=$? L=$OPT_LOADS fb=$OPT_FALLBACK$OPT_FALLBACK2"; kk.uses opt; echo "uses r=$? L=$OPT_LOADS"'
[[ "$UF_OUT" == "r=0 L=1 fb=11"$'\n'"uses r=0 L=1" ]]
uf_check "the same optional dependency through kk.uses: rc 0, loaded once [R1]" $?

uf_run 'export FX; "$BASH" "$FX/proj/main1.sh"'
[[ "$UF_OUT" == *"rc=2 proj=1 kcl=0 needa=0" && "$UF_OUT" == *"unit 'a' is already loaded from '$FX/proj/a.sh'; here it resolves to '$FX/kcl/a/a.sh'"* ]]
uf_check "kk.uses NAME is resolved and compared: the project's a loaded, a kcl unit's 'kk.uses a' resolves to kcl/a -> rc 2 [R3]" $?

uf_run 'export FX; "$BASH" "$FX/proj/main2.sh"'
[[ "$UF_OUT" == *"rc=2 proj=0 kcl=1 needa=1" && "$UF_OUT" == *"unit 'a' is already loaded from '$FX/kcl/a/a.sh'; here it resolves to '$FX/proj/a.sh'"* ]]
uf_check "the reverse: kcl/a loaded first, the project's 'kk.uses a' resolves to proj/a.sh -> rc 2 [R3]" $?

uf_run 'export FX; "$BASH" "$FX/proj3/main.sh"'
[[ "$UF_OUT" == *"rc=2 userklib=0" && "$UF_OUT" == *"unit 'klib' is already loaded from '$FX/kkore/klib.sh'"* ]]
uf_check "a user klib.sh in the caller's folder vs the loaded system klib -> rc 2, not loaded [R3]" $?

uf_run 'source "$FX/kbool.sh"; cd "$FX/kcl/a"; kk.uses a b; kk.uses a b; r1=$?; cd /; kk.uses a; echo "r=$r1/$? A=$A_LOADS"'
[[ "$UF_OUT" == "r=0/0 A=1" ]]
uf_check "repeated kk.uses of loaded names (fast path / cached resolution) stays a silent rc-0 no-op [R3, R9]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses shb cmt crlf; echo "r=$? $SHB_LOADS$CMT_LOADS${CRLF_LOADS%$'"'"'\r'"'"'}"; kk.uses late; echo "late r=$?"'
[[ "$UF_OUT" == "r=0 111"* && "$UF_OUT" == *"late r=2" ]]
uf_check "header detection skips a shebang, blank and # lines (incl. a comment block) and a CR; a header after two code lines is none [R4]" $?

uf_run 'source "$FX/kbool.sh"; for u in kuse klib kerr kvar kcfg kbool; do kk.unit --forget $u 2>/dev/null; printf "%s=%s " $u $?; done; echo "isInt=$(type -t kk.isInt)"'
[[ "$UF_OUT" == "kuse=2 klib=2 kerr=2 kvar=2 kcfg=2 kbool=2 isInt=function" ]]
uf_check "kk.unit --forget refuses every unit kbool.sh loaded (rc 2) [R7]" $?

uf_run 'export FX; source "$FX/kbool.sh"; export -f kk.uses; "$BASH" -c "kk.uses a; echo child r=\$? L=\$A_LOADS klib=\$(type -t kk.isInt)"'
[[ "$UF_OUT" == "child r=0 L=1 klib=function" ]]
uf_check "a child bash that inherited only kk.uses (no registry) loads kbool.sh from KBOOL_HOME first [R8]" $?

uf_run 'GLOBIGNORE="*"; source "$FX/kbool.sh"; kk.uses a; echo "r=$? L=$A_LOADS gi=[$GLOBIGNORE]"'
[[ "$UF_OUT" == "r=0 L=1 gi=[*]" ]]
uf_check "a caller's GLOBIGNORE='*' does not empty the name index, and is the caller's again afterwards [R11]" $?

# ---------------------------------------------------------------------------
# The ktests runner sees a header error as a failing file (U19', C2)
KTD="$_KT_TMPDIR/ktmini"
mkdir -p "$KTD"
printf '%s\n' '#!/bin/bash' "source \"$KTESTS_LIB_DIR/ktest.sh\"" 'kt_test_init "Last" "$(dirname "$0")" "$@"' \
    'kt_test_start "t"' 'kt_test_pass "t"' "source \"$FX/kcl/bad/bad.sh\"" > "$KTD/001_Last.sh"
kt_test_start "ktests verdict: a U33 header error as the file's last command fails the file ('source returned rc=2') [U19', C2]"
UF_OUT="$("$BASH" "$KTESTS_LIB_DIR/ktests.sh" "$KTD" "mini" --mode single 2>&1)"; UF_RC=$?
if [[ "$UF_OUT" == *"source returned rc=2"* ]]; then
    kt_test_pass "verdict"
else
    kt_test_fail "no rc=2 verdict: ${UF_OUT//$'\n'/ | }"
fi
rm -rf "$KTD"

kt_test_log "009_UnitsAndUses.sh completed"
