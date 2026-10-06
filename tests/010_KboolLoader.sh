#!/bin/bash
# kbool.sh — the startup file (kklass/USES_PLAN.md U1, U2, U4, P1, P3; phase U1a).
# Fresh bash per scenario against a throw-away kbool tree (unit_fixture.sh); the
# P3 scenarios damage copies of that tree and require rc != 0 on every failure
# path, with the loader guard left OFF so a later good load still works.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "KboolLoader" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
GOOD="$_KT_TMPDIR/fx"
uf_build "$GOOD" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
UF_FX="$GOOD"
FX="$GOOD"

# ---------------------------------------------------------------------------
# A good tree
uf_run 'source "$FX/kbool.sh"; echo "r=$? home=$KBOOL_HOME env=$("$BASH" -c "echo \$KBOOL_HOME")"'
[[ "$UF_OUT" == "r=0 home=$FX env=$FX" ]]
uf_check "source kbool.sh: rc 0, KBOOL_HOME = its folder, exported [P1, U4]" $?

uf_run 'source "$FX/kbool.sh"; for u in kbool kuse klib kerr kvar kcfg; do printf "%s=%s " $u "${__KK_UNIT_DONE[$u]-}"; done; kk.uses klib kerr kvar kcfg kuse kbool; echo "r=$? klib=${__KK_UNITS[klib]}"'
[[ "$UF_OUT" == "kbool=1 kuse=1 klib=1 kerr=1 kvar=1 kcfg=1 r=0 klib=$FX/kkore/klib.sh" ]]
uf_check "the system units (kbool, kuse, klib, kerr, kvar, kcfg) are registered as loaded; kk.uses of them is a no-op [U1]" $?

uf_run 'source "$FX/kbool.sh"; echo "${__KK_UNIT_SYSPATH[*]}"'
[[ "$UF_OUT" == "$FX/kkore $FX/kklass $FX/kcl/*" ]]
uf_check "the built-in system search path: kkore, kklass, kcl/* under KBOOL_HOME [U4]" $?

uf_run 'source "$FX/kbool.sh"; __KK_UNIT_SYSPATH=(x); source "$FX/kbool.sh"; echo "r=$? ${__KK_UNIT_SYSPATH[*]}"'
[[ "$UF_OUT" == "r=0 x" ]]
uf_check "a second source of kbool.sh is a no-op (the loader guard) [C3]" $?

uf_run 'source "$FX/kcl/a/../../kbool.sh"; echo "$KBOOL_HOME"'
[[ "$UF_OUT" == "$FX" ]]
uf_check "kbool.sh through a ../.. spelling: KBOOL_HOME normalised" $?

uf_run 'cd "$FX" && source kbool.sh; echo "r=$? $KBOOL_HOME"'
[[ "$UF_OUT" == "r=0 $FX" ]]
uf_check "source kbool.sh from its own folder (no slash): KBOOL_HOME absolute [C4]" $?

uf_run 'PATH="$FX:$PATH"; cd /; source kbool.sh; echo "r=$? $KBOOL_HOME"'
[[ "$UF_OUT" == "r=0 $FX" ]]
uf_check "source kbool.sh through PATH (sourcepath) [U3]" $?

uf_run 'set -eu; source "$FX/kbool.sh"; source "$FX/kbool.sh"; echo ok'
[[ $UF_RC == 0 && "$UF_OUT" == "ok" ]]
uf_check "set -eu: kbool.sh twice, silent" $?

uf_run 'set -- set_trap p2; source "$FX/kbool.sh"; echo "$#:$1:[$(trap -p ERR)]"'
[[ "$UF_OUT" == "2:set_trap:[]" ]]
uf_check "the caller's positional args survive and do not reach the system units (no kerr set_trap) [C10]" $?

uf_run '"$BASH" "$FX/kbool.sh"; echo "r=$?"'
[[ "$UF_OUT" == *"r=2" && "$UF_OUT" == *"sourced"* ]]
uf_check "kbool.sh executed instead of sourced: rc 2 with a message" $?

uf_run 'source "$FX/kbool.sh"; export -f kk.unit kk.uses; "$BASH" -c "source \"\$FX/kcl/a/a.sh\"; echo r=\$? L=\$A_LOADS n=\${#__KK_UNITS[@]}"'
[[ "$UF_OUT" == "r=0 L=1 n=7" ]]
uf_check "a child bash with exported functions starts with an empty registry and re-bootstraps [U28]" $?

# ---------------------------------------------------------------------------
# A user unit outside the tree: the KBOOL_HOME header shape (P1, §7.4)
uf_run 'source "$FX/kbool.sh"; source "$FX/proj/lib/user.sh"; r1=$?; kk.uses "$FX/proj/lib/user.sh"; echo "r=$r1/$? L=$USER_LOADS"'
[[ "$UF_OUT" == "r=0/0 L=1" ]]
uf_check "user unit with kbool loaded: loads once [P1]" $?

uf_run 'export KBOOL_HOME="$FX"; source "$FX/proj/lib/user.sh"; echo "r=$? L=$USER_LOADS klib=$(type -t kk.isInt)"'
[[ "$UF_OUT" == "r=0 L=1 klib=function" ]]
uf_check "user unit in a bare shell with KBOOL_HOME exported: bootstraps kbool.sh [P1]" $?

uf_run 'unset KBOOL_HOME; source "$FX/proj/lib/user.sh"; echo "r=$? L=${USER_LOADS:-0}"; echo still-here'
[[ $UF_RC == 0 && "$UF_OUT" == *"/kbool.sh: No such file"* && "$UF_OUT" == *"r=2 L=0"$'\n'"still-here" ]]
uf_check "user unit with neither kbool nor KBOOL_HOME: rc 2, the body never runs, the CALLER's shell continues [P1, R5]" $?

# ---------------------------------------------------------------------------
# P3: rc != 0 on every failure path; the guard stays off; KBOOL_HOME restored
uf_broken() {   # NAME DAMAGE-SNIPPET (run with D = the copy) -> UF_FX = the copy
    local d="$_KT_TMPDIR/brk_$1"
    rm -rf "$d"; cp -r "$GOOD" "$d"
    D="$d" eval "$2"
    UF_FX="$d"
}
P3_PROBE='source "$FX/kbool.sh"; r=$?; [[ ${__KK_UNITS[@]@a} == A* ]] && g=on || g=off; echo "r=$r guard=$g home=${KBOOL_HOME-unset}"'

uf_broken nokuse 'rm -f "$D/kkore/kuse.sh"'
uf_run "$P3_PROBE"
[[ "$UF_OUT" == *"r=2 guard=off home=unset" ]]
uf_check "P3: kkore/kuse.sh missing -> rc 2, guard off, KBOOL_HOME unset" $?

uf_broken kuserc 'printf "return 3\n" > "$D/kkore/kuse.sh"'
uf_run "$P3_PROBE"
[[ "$UF_OUT" == *"r=3 guard=off home=unset" ]]
uf_check "P3: kuse.sh returns 3 -> rc 3, guard off" $?

uf_broken kuseempty ': > "$D/kkore/kuse.sh"'
uf_run "$P3_PROBE"
[[ "$UF_OUT" == *"r=2 guard=off home=unset" ]]
uf_check "P3: kuse.sh empty (defines no loader) -> rc 2, guard off" $?

uf_broken nokerr 'rm -f "$D/kkore/kerr.sh"'
uf_run "$P3_PROBE"
[[ "$UF_OUT" == *"r=2 guard=off home=unset" && "$UF_OUT" == *"kerr"* ]]
uf_check "P3: kkore/kerr.sh missing -> rc 2 naming kerr, guard off, KBOOL_HOME unset" $?

uf_broken klibrc '{ printf "return 1\n"; cat "$GOOD/kkore/klib.sh"; } > "$D/kkore/klib.sh.new"; mv "$D/kkore/klib.sh.new" "$D/kkore/klib.sh"'
uf_run "$P3_PROBE"
[[ "$UF_OUT" == *"r=1 guard=off home=unset" && "$UF_OUT" == *"system unit klib"* ]]
uf_check "P3: klib.sh returns 1 -> rc 1 naming klib, guard off" $?

uf_broken kvardir 'rm -f "$D/kkore/kvar.sh"; mkdir "$D/kkore/kvar.sh"'
uf_run "$P3_PROBE"
[[ "$UF_OUT" == *"r=2 guard=off home=unset" ]]
uf_check "P3: kvar.sh is a directory -> rc 2, guard off" $?

uf_broken kcfgunit 'rm -f "$D/kkore/kcfg.sh"'
uf_run 'source "$FX/kcl/a/a.sh"; echo "r=$? L=${A_LOADS:-0}"'
[[ "$UF_OUT" == *"r=2 L=0" ]]
uf_check "P3: a unit sourced directly in a broken tree -> its header line 1 returns kbool.sh's rc, body not run" $?

uf_run 'set -e; source "$FX/kbool.sh" || echo caught; echo after'
[[ "$UF_OUT" == *"caught"$'\n'"after" && "$UF_OUT" == *"system unit kcfg"* ]]
uf_check "P3: set -e caller: 'source kbool.sh || ...' catches the failure" $?

uf_run 'export KBOOL_HOME=/pre; source "$FX/kbool.sh"; echo "r=$? home=$KBOOL_HOME"'
[[ "$UF_OUT" == *"r=2 home=/pre" ]]
uf_check "P3: a failed load restores a preset KBOOL_HOME" $?

uf_run "source \"\$FX/kbool.sh\" 2>/dev/null; r1=\$?; source \"$GOOD/kbool.sh\"; echo \"r=\$r1/\$? home=\$KBOOL_HOME n=\${#__KK_UNITS[@]}\""
[[ "$UF_OUT" == "r=2/0 home=$GOOD n=6" ]]
uf_check "P3: after a failed load a good kbool.sh loads in the same shell" $?

# ---------------------------------------------------------------------------
# U1a review round: registry robustness (R2), executed detection (R10), a second copy (R12)
UF_FX="$GOOD"

uf_run 'export FX; set -a; source "$FX/kbool.sh"; set +a; "$BASH" -c "source \"\$FX/kcl/a/a.sh\"; echo child r=\$? L=\$A_LOADS; source \"\$FX/kcl/a/a.sh\"; kk.uses b; echo rb=\$? L=\$A_LOADS B=\$B_LOADS k=\${__KK_UNITS[kbool]+set}"'
[[ "$UF_OUT" == "child r=0 L=1"$'\n'"rb=0 L=1 B=1 k=set" ]]
uf_check "a child of a 'set -a' parent (every loader scalar exported): bootstraps, loads once, kk.uses works [R2, C2]" $?

uf_run 'export FX; source "$FX/kbool.sh"; export __KLIB_USE_SOURCED=1; export -f $(compgen -A function); "$BASH" -c "source \"\$FX/kcl/a/a.sh\"; echo child r=\$? L=\$A_LOADS; source \"\$FX/kcl/a/a.sh\"; kk.uses b; echo rb=\$? L=\$A_LOADS B=\$B_LOADS"'
[[ "$UF_OUT" == "child r=0 L=1"$'\n'"rb=0 L=1 B=1" ]]
uf_check "a child with an exported __KLIB_USE_SOURCED and every function exported: tables rebuilt, loads once [R2, C2]" $?

uf_run '__KLIB_SOURCED=1; source "$FX/kbool.sh"; r=$?; [[ ${__KK_UNITS[@]@a} == A* ]] && g=on || g=off; echo "r=$r guard=$g isInt=$(type -t kk.isInt)"'
[[ "$UF_OUT" == *"r=2 guard=off isInt=" && "$UF_OUT" == *"klib did not define kk.isInt"* ]]
uf_check "a preset klib guard (__KLIB_SOURCED=1): klib defines nothing -> kbool.sh rc 2, guard off [R2]" $?

uf_run 'source "$FX/kbool.sh"; unset __KK_UNITS; source "$FX/kcl/a/a.sh"; echo "r=$? L=$A_LOADS"; source "$FX/kcl/a/a.sh"; kk.uses b; echo "rb=$? L=$A_LOADS B=$B_LOADS"'
[[ "$UF_OUT" == "r=0 L=1"$'\n'"rb=0 L=1 B=1" ]]
uf_check "an unset __KK_UNITS: the next unit re-bootstraps kbool.sh with fresh tables [R2]" $?

uf_run '"$BASH" -c '\''source "$0"; echo "r=$? home=$KBOOL_HOME"'\'' "$FX/kbool.sh"'
[[ "$UF_OUT" == "r=0 home=$FX" ]]
uf_check "bash -c 'source \"\$0\"' kbool.sh is a SOURCE, not an execution [R10, C9]" $?

uf_broken nokerr2 'rm -f "$D/kkore/kerr.sh"'
uf_run 'source "$FX/kbool.sh" 2>/dev/null; echo "r=$? boot=[$(type -t kk._kbool_boot)]"'
[[ "$UF_OUT" == "r=2 boot=[]" ]]
uf_check "a failed load leaves no kk._kbool_boot behind [R10]" $?
UF_FX="$GOOD"

COPY2="$_KT_TMPDIR/copy2"
rm -rf "$COPY2"; cp -r "$GOOD" "$COPY2"
uf_run "source \"\$FX/kbool.sh\"; source \"$COPY2/kbool.sh\"; echo \"r=\$? home=\$KBOOL_HOME\"; source \"\$FX/kbool.sh\"; source \"\$FX/kcl/../kbool.sh\""
[[ "$UF_OUT" == "kbool: WARNING: $COPY2/kbool.sh is ignored: kbool is already loaded from $FX/kbool.sh"$'\n'"r=0 home=$FX" ]]
uf_check "a second kbool.sh from ANOTHER copy: a no-op with exactly one WARNING; the same file again (any spelling) silent [R12]" $?

# ---------------------------------------------------------------------------
# R14: a child that inherited the loader FUNCTIONS (set -a exports them too, and
# `bash -c` may exec the child in the parent's PID) but none of the assoc tables
uf_run 'export FX; set -a; source "$FX/kbool.sh"; set +a; "$BASH" -c "kk.uses a; echo child rc=\$? L=\$A_LOADS; kk.uses a b; echo rc2=\$? L=\$A_LOADS B=\$B_LOADS"'
[[ "$UF_OUT" == "child rc=0 L=1"$'\n'"rc2=0 L=1 B=1" ]]
uf_check "set -a parent -> a child calls kk.uses NAME directly: bootstraps, loads, rc 0, no bash diagnostic [R14]" $?

# (b) every function exported, no set -a: the registry-less child calls kk.defined /
#     kk.unit --forget with injection-shaped names BEFORE anything bootstraps
rm -f "$GOOD/cwd/PWN"
uf_run 'export FX; cd "$FX/cwd"; source "$FX/kbool.sh"; export -f $(compgen -A function); "$BASH" -c '\''kk.defined "x[\$(touch PWN)]"; echo def=$?; kk.unit --forget "y[\$(touch PWN)]"; echo fg=$?; kk.uses a; echo rc=$? L=$A_LOADS'\'''
[[ "$UF_OUT" == *"def=2"*"fg=2"*"rc=0 L=1" && "$UF_OUT" != *"syntax error"* && ! -e "$GOOD/cwd/PWN" ]]
uf_check "every function exported (no set -a): a registry-less child's kk.defined / kk.unit --forget refuse (rc 2) without evaluating the name, kk.uses bootstraps [R14]" $?

# (c) a calling file in a folder named d[$(touch PWN)]
rm -f "$GOOD/cwd/PWN"
uf_run 'cd "$FX/cwd"; source "$FX/kbool.sh"; source "$FX/inj/d[\$(touch PWN)]/caller.sh"'
[[ "$UF_OUT" == "inj rc=0 A=1 B=1"$'\n'"inj again rc=0" && ! -e "$GOOD/cwd/PWN" ]]
uf_check "a calling file in a folder named 'd[\$(touch PWN)]' (normal shell): correct result, nothing executed [R14]" $?

rm -f "$GOOD/cwd/PWN"
uf_run 'export FX; cd "$FX/cwd"; set -a; source "$FX/kbool.sh"; set +a; "$BASH" -c '\''source "$FX/inj/d[\$(touch PWN)]/caller.sh"'\'''
[[ "$UF_OUT" == "inj rc=0 A=1 B=1"$'\n'"inj again rc=0" && ! -e "$GOOD/cwd/PWN" ]]
uf_check "the same caller in a set -a child (exec'd in the parent's PID): correct result, nothing executed [R14]" $?
rm -f "$GOOD/cwd/PWN"

kt_test_log "010_KboolLoader.sh completed"
