#!/usr/bin/env bash
# FailedDepsAndLookup — owner decisions 2026-10-09 (uses U3 review):
#
# U42 (amends U1a R1, U34): a `kk.uses X` that fails inside a unit's load (X not
#   found, a bad name, X's own rc, a structural error) marks the loading unit as
#   not completely loaded, and its next load — a plain source or kk.uses — runs
#   it again (before: a retry returned rc 0 with nothing loaded, or kk.uses said
#   "not completely loaded" until kk.unit --forget). `kk.uses --optional X...`:
#   a failure neither taints nor prints the loader's message; rc still reports it.
# U43 (amends U14): the caller-folder step of a NAME lookup cannot be hijacked by
#   the cwd — a loaded kkore / kklass unit is never resolved again; without a
#   calling file the cwd is searched only at an interactive prompt (not bash -c,
#   bash -s, a pipe); a RELATIVE calling file is resolved against the PWD it was
#   loaded from, not the current one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "FailedDepsAndLookup" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
GOOD="$_KT_TMPDIR/fx"
uf_build "$GOOD" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
UF_FX="$GOOD"
FX="$GOOD"

# hostile stand-ins in a folder used as the cwd: same names as units, one line of
# evidence each (HIJ_<name>=1 and a HIJACK line on stderr)
mkdir -p "$FX/hostile" "$FX/app"
for n in a klib kerr pa; do
    printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || return 2' "kk.unit $n || return \$__kk_unit_rc" \
        "HIJ_$n=1; echo \"HIJACK_$n\" >&2" > "$FX/hostile/$n.sh"
done
# a script in app/ with its own unit pa next to it; it cd's before kk.uses
uf_user "$FX/app/pa.sh" pa 'PA_LOADS=$(( ${PA_LOADS:-0} + 1 ))'
printf '%s\n' 'source "$FX/kbool.sh" || exit 9' 'cd "$FX/hostile"' 'kk.uses pa; r1=$?' 'kk.uses a; r2=$?' \
    'echo "app r=$r1/$r2 pa=${PA_LOADS:-0} hij=${HIJ_pa:-0}${HIJ_a:-0} A=${A_LOADS:-0}"' > "$FX/app/app.sh"

# ---------------------------------------------------------------------------
# U42: a failed dependency taints the loading unit; --optional
uf_run 'UF_FAIL=1; source "$FX/kcl/needs/needs.sh"; echo "r=$? L=$NEEDS_LOADS fb=${NEEDS_FB:-0}"; UF_FAIL=0; kk.uses needs; echo "uses r=$? L=$NEEDS_LOADS"'
[[ "$UF_OUT" == "r=0 L=1 fb=1"$'\n'"uses r=0 L=2" ]]
uf_check "U42: a plain-sourced unit whose non-optional kk.uses failed (handled, rc 0) is incomplete: the next kk.uses runs it again" $?

uf_run 'UF_FAIL=1; source "$FX/kcl/needs/needs.sh"; UF_FAIL=0; source "$FX/kcl/needs/needs.sh"; echo "r=$? L=$NEEDS_LOADS"; source "$FX/kcl/needs/needs.sh"; echo "again r=$? L=$NEEDS_LOADS"'
[[ "$UF_OUT" == "r=0 L=2"$'\n'"again r=0 L=2" ]]
uf_check "U42: the same through a plain re-source: it runs again once, then (complete) is a no-op" $?

uf_run 'UF_FAIL=1; source "$FX/kbool.sh"; kk.uses needs; echo "r=$? L=$NEEDS_LOADS reg=${__KK_UNITS[needs]+yes}"; UF_FAIL=0; kk.uses needs; echo "r=$? L=$NEEDS_LOADS done=${__KK_UNIT_DONE[needs]-}"'
[[ "$UF_OUT" == *"unit 'needs' is not completely loaded"*$'\n'"r=2 L=1 reg="$'\n'"r=0 L=2 done=1" ]]
uf_check "U42: through kk.uses the unit's rc 0 does not hide the failed dependency: rc 2 (printed), forgotten; the retry loads it" $?

uf_run 'UF_FAIL=1; source "$FX/kcl/dep/dep.sh"; r1=$?; UF_FAIL=0; source "$FX/kcl/dep/dep.sh"; echo "r=$r1/$? D=$DEP_LOADS"'
[[ "$UF_OUT" == *"r=2/0 D=2" && "$UF_OUT" != *"not completely loaded"* ]]
uf_check "U42: a plain-sourced unit left incomplete by a structural error: a plain re-source runs it again (was: rc 2 'not completely loaded')" $?

uf_run 'source "$FX/kbool.sh"; kk.uses --optional nosuchunit; r1=$?; kk.uses --optional "$FX/nofile.sh"; r2=$?; kk.uses --optional a nosuchunit; r3=$?; echo "r=$r1/$r2/$r3 A=$A_LOADS"'
[[ "$UF_OUT" == "r=2/2/2 A=1" ]]
uf_check "U42: kk.uses --optional: a missing NAME / PATH -> rc 2, nothing printed; the units before it load" $?

uf_run 'UF_FAIL=1; source "$FX/kbool.sh"; kk.uses --optional fail; echo "r=$?"; kk.uses nosuchunit 2>/dev/null; echo "r=$?"; kk.uses nosuchunit 2>&1 | grep -c "not found"'
[[ "$UF_OUT" == "r=3"$'\n'"r=2"$'\n'"1" ]]
uf_check "U42: --optional reports a failing unit's own rc silently; without it the loader prints its error" $?

uf_run 'UF_FAIL=1; source "$FX/kcl/opt/opt.sh"; echo "r=$? fb=$OPT_FALLBACK$OPT_FALLBACK2"; UF_FAIL=0; kk.uses opt; echo "uses r=$? L=$OPT_LOADS"'
[[ "$UF_OUT" == "r=0 fb=11"$'\n'"uses r=0 L=1" ]]
uf_check "U42: dependencies loaded with --optional never taint the unit (complete, not run again)" $?

# ---------------------------------------------------------------------------
# U43: lookups the cwd cannot hijack
uf_run 'cd "$FX/hostile"; source "$FX/kbool.sh"; kk.uses klib kerr; echo "r=$? hij=${HIJ_klib:-0}${HIJ_kerr:-0}"'
[[ "$UF_OUT" == "r=0 hij=00" ]]
uf_check "U43: bash -c in a folder holding klib.sh / kerr.sh: kk.uses klib kerr = the loaded system units, silently" $?

uf_run 'cd "$FX/hostile"; source "$FX/kbool.sh"; kk.uses a; echo "r=$? A=${A_LOADS:-0} hij=${HIJ_a:-0}"'
[[ "$UF_OUT" == "r=0 A=1 hij=0" ]]
uf_check "U43: bash -c (no calling file, not interactive) in a folder holding a.sh: kk.uses a loads kcl/a, not the cwd's" $?

uf_run 'cd "$FX/hostile" && printf "%s\n" "source \"\$FX/kbool.sh\"" "kk.uses a; echo \"r=\$? A=\${A_LOADS:-0} hij=\${HIJ_a:-0}\"" | "$BASH" -s'
[[ "$UF_OUT" == "r=0 A=1 hij=0" ]]
uf_check "U43: the same from bash -s (a script on stdin)" $?

uf_run 'cd "$FX/hostile" && printf "%s\n" "source \"\$FX/kbool.sh\"" "kk.uses a; echo \"r=\$? A=\${A_LOADS:-0} hij=\${HIJ_a:-0}\"" | "$BASH"'
[[ "$UF_OUT" == "r=0 A=1 hij=0" ]]
uf_check "U43: the same from a pipe" $?

# (bash -i's stderr goes to a FILE, not a pipe: without a terminal bash -i takes
# fd 2 as its terminal, and on FreeBSD tcgetpgrp() on a pipe answers 0 instead of
# failing, so bash -i sends itself SIGTTIN and stays stopped — launch L3.5)
uf_run 'cd "$FX/hostile"; o=$("$BASH" -i -c '\''source "$FX/kbool.sh"; kk.uses a; echo "r=$? A=${A_LOADS:-0} hij=${HIJ_a:-0}"'\'' 2>"$FX/ierr.txt"); grep -v -i -E "job control|terminal process group|^bash: " "$FX/ierr.txt"; printf "%s\n" "$o"'
[[ "$UF_OUT" == *"r=0 A=0 hij=1" ]]
uf_check "U43: at an interactive prompt (\$- has i) the cwd IS the first lookup place (U14 unchanged there)" $?

uf_run 'cd "$FX/app" && "$BASH" app.sh'
[[ "$UF_OUT" == "app r=0/0 pa=1 hij=00 A=1" ]]
uf_check "U43: 'bash app.sh' (a relative script) that cd's after loading kbool: kk.uses pa resolves against the script's folder, a against the search path — not the new cwd" $?

uf_run 'cd "$FX/app" && source ./app.sh'
[[ "$UF_OUT" == "app r=0/0 pa=1 hij=00 A=1" ]]
uf_check "U43: the same script sourced by a relative path from bash -c" $?

kt_test_log "014_FailedDepsAndLookup.sh completed"
