#!/usr/bin/env bash
# SystemUnitHeaders — the kkore modules are units (kklass/USES_PLAN.md phase U3:
# §7.4 header shapes, C10, P3, P8, U1, U40; found_in_U1a lint).
#
# klib, kerr, kvar and kcfg start with the two §7.4 header lines (relative form,
# `../kbool.sh`): a direct `source kkore/X.sh` bootstraps kbool.sh, which loads
# every system unit once and registers it, and the outer source is then a
# no-op. kuse.sh cannot carry a header (kbool.sh sources it plainly and
# registers it). kerr.sh takes no argument any more (units never do, P8): the
# ERR trap is `ke.setTrap`, called explicitly. The unit-name namespaces of all
# system units are declared (U40). A unit runs inside a function (kbool.sh's
# boot, kk._uses), so its file scope may not use `local` / `declare` without
# -g — linted here with the reusable unit_lint.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SystemUnitHeaders" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/unit_lint.sh"
GOOD="$_KT_TMPDIR/fx"
uf_build "$GOOD" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
UF_FX="$GOOD"
SYS_UNITS=(klib kerr kvar kcfg)

# A copy whose system modules count their COMPLETE body runs (a line appended
# at the end of each file): __T13_N_<unit>.
CNT="$_KT_TMPDIR/cnt"
rm -rf "$CNT"; cp -r "$GOOD" "$CNT"
for u in "${SYS_UNITS[@]}" kuse; do
    printf '\n__T13_N_%s=$(( ${__T13_N_%s:-0} + 1 ))\n' "$u" "$u" >> "$CNT/kkore/$u.sh"
done
COUNTS='for u in kuse klib kerr kvar kcfg; do n=__T13_N_$u; printf "%s=%s " $u "${!n:-0}"; done'

# ---------------------------------------------------------------------------
# 1. The header itself
kt_test_start "klib, kerr, kvar, kcfg carry the §7.4 relative header (line 1 + 'kk.unit NAME || return \$__kk_unit_rc') after the shebang [U3, §7.4]"
bad=""
for u in "${SYS_UNITS[@]}"; do
    f="$SCRIPT_DIR/../$u.sh"
    mapfile -t -n 3 head3 < "$f"
    want1='[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%'"$u"'.sh}../kbool.sh" || return'
    want2="kk.unit $u || return \$__kk_unit_rc"
    [[ "${head3[0]}" == '#!/usr/bin/env bash' && "${head3[1]}" == "$want1" && "${head3[2]}" == "$want2" ]] || bad+=" $u"
done
if [[ -z "$bad" ]]; then kt_test_pass "4 headers"; else kt_test_fail "wrong or missing header:$bad"; fi

kt_test_start "the unit index finds every system unit by name now (kk._unit_find klib/kerr/kvar/kcfg -> kkore/NAME.sh); kuse.sh has no header [U3, U13']"
uf_run 'source "$FX/kbool.sh"; for u in klib kerr kvar kcfg kuse; do if kk._unit_find $u "$PWD"; then printf "%s=%s " $u "${__kk_found#$FX/}"; else printf "%s=- " $u; fi; done'
if [[ "$UF_OUT" == "klib=kkore/klib.sh kerr=kkore/kerr.sh kvar=kkore/kvar.sh kcfg=kkore/kcfg.sh kuse=- " ]]; then
    kt_test_pass "$UF_OUT"
else
    kt_test_fail "rc=$UF_RC out='$UF_OUT'"
fi

kt_test_start "no system unit sources another file or forks for its folder (no 'source', no \$(cd ...) / dirname): kbool.sh loads them all [U3, U1]"
bad=""
for u in "${SYS_UNITS[@]}"; do
    f="$SCRIPT_DIR/../$u.sh"
    n=$(grep -n -E '(^|[;&|[:space:]])(source|\.)[[:space:]]|\$\(cd |dirname' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | cut -d: -f1 | tr '\n' ' ')
    [[ "$n" == "2 " ]] || bad+=" $u:[$n]"     # the one allowed: header line 1 (file line 2)
done
if [[ -z "$bad" ]]; then kt_test_pass "header line only"; else kt_test_fail "source/cd/dirname lines besides the header:$bad"; fi

# ---------------------------------------------------------------------------
# 2. A direct source of a system unit bootstraps kbool.sh, once
for u in "${SYS_UNITS[@]}"; do
    UF_FX="$CNT"
    uf_run "source \"\$FX/kkore/$u.sh\"; r=\$?; [[ \${__KK_UNITS[@]@a} == A* ]] && g=on || g=off
            [[ \${__KK_UNITS[$u]-} -ef \$FX/kkore/$u.sh ]] && f=same || f=other
            echo \"r=\$r guard=\$g file=\$f done=\${__KK_UNIT_DONE[$u]-} sys=\${__KK_UNIT_SYS[$u]-} n=\${#__KK_UNITS[@]} home=\${KBOOL_HOME#\$FX}\"; $COUNTS"
    UF_FX="$GOOD"
    [[ "$UF_OUT" == "r=0 guard=on file=same done=1 sys=1 n=6 home="$'\n'"kuse=1 klib=1 kerr=1 kvar=1 kcfg=1 " ]]
    uf_check "a bare shell: source kkore/$u.sh -> kbool.sh bootstrapped, $u registered as a loaded system unit, every system module body ran exactly once [U3, U27]" $?
done

UF_FX="$CNT"
uf_run "cd \"\$FX/kkore\" && source kvar.sh; echo \"r=\$? home=\${KBOOL_HOME#\$FX}\"; source ./kvar.sh; source \"\$FX/kkore/../kkore/kvar.sh\"; kk.uses kvar klib; echo \"u=\$?\"; $COUNTS"
UF_FX="$GOOD"
[[ "$UF_OUT" == "r=0 home="$'\n'"u=0"$'\n'"kuse=1 klib=1 kerr=1 kvar=1 kcfg=1 " ]]
uf_check "a no-slash 'source kvar.sh' from kkore/ bootstraps kbool.sh; later sources by other spellings and kk.uses kvar klib are silent no-ops [C4, U3]" $?

UF_FX="$CNT"
uf_run "source \"\$FX/kkore/klib.sh\"; source \"\$FX/kbool.sh\"; source \"\$FX/kkore/kerr.sh\"; kk.uses klib kerr kvar kcfg kuse kbool; echo \"u=\$?\"; $COUNTS"
UF_FX="$GOOD"
[[ "$UF_OUT" == "u=0"$'\n'"kuse=1 klib=1 kerr=1 kvar=1 kcfg=1 " ]]
uf_check "klib sourced directly FIRST, then kbool.sh, kerr.sh again and kk.uses of every system unit: each module loaded once, silent (the P7 shape for kkore) [P7, U3]" $?

UF_FX="$CNT"
uf_run "set -eu; source \"\$FX/kkore/kcfg.sh\"; source \"\$FX/kkore/kcfg.sh\"; source \"\$FX/kkore/klib.sh\"; echo ok; $COUNTS"
UF_FX="$GOOD"
[[ $UF_RC == 0 && "$UF_OUT" == "ok"$'\n'"kuse=1 klib=1 kerr=1 kvar=1 kcfg=1 " ]]
uf_check "set -eu: kcfg.sh twice, then klib.sh -> silent, each module once [D7, U3]" $?

uf_run 'source "$FX/kbool.sh"; kk.unit --forget klib; echo "f=$?"'
[[ "$UF_OUT" == *"cannot be forgotten"*"f=2" ]]
uf_check "a system unit registered through its header still cannot be forgotten (rc 2) [R7, U3]" $?

uf_run 'source "$FX/kbool.sh"; for u in kuse klib kerr kvar kcfg; do printf "%s=%s " $u "${__KK_NAMESPACES[$u]%%$__KK_SEP*}"; done; echo'
[[ "$UF_OUT" == "kuse=kuse klib=klib kerr=kerr kvar=kvar kcfg=kcfg " ]]
uf_check "every system unit's own name is a declared namespace owned by that unit (kuse and klib too, whose kk.unit cannot declare it) [U40, U3]" $?

uf_run 'KK_UNIT_DIR=/keep; source "$FX/kbool.sh"; echo "a=$KK_UNIT_DIR"; "$BASH" -c '\''source "$FX/kkore/klib.sh"; echo "b=${KK_UNIT_DIR-unset}"'\'
[[ "$UF_OUT" == "a=/keep"$'\n'"b=unset" ]]
uf_check "loading the system units through their headers leaves the caller's KK_UNIT_DIR as it was (set or unset) [C19, U3]" $?

# ---------------------------------------------------------------------------
# 3. kerr.sh takes no argument: ke.setTrap is explicit (C10, P8)
uf_run 'source "$FX/kkore/kerr.sh" set_trap; echo "r=$? trap=[$(trap -p ERR)]"; ke.setTrap; echo "trap=[$(trap -p ERR)]"'
[[ "$UF_OUT" == *"unit 'kerr' called with arguments; units take none"*$'\n'"r=0 trap=[]"$'\n'"trap=[trap -- 'ke.onError \${LINENO} \${BASH_LINENO}' ERR]" ]]
uf_check "a stale 'source kerr.sh set_trap' (bare shell): one WARNING, no ERR trap; ke.setTrap sets it [C10, P8]" $?

uf_run 'source "$FX/kbool.sh"; source "$FX/kkore/kerr.sh" set_trap; echo "r=$? trap=[$(trap -p ERR)]"'
[[ "$UF_OUT" == *"units take none"*$'\n'"r=0 trap=[]" ]]
uf_check "the same with kbool loaded (a re-source): one WARNING, no ERR trap [C10, P8]" $?

kt_test_start "kerr.sh has no argument-driven code left (no \$1 / \$@ at file scope) [C10]"
n=$(awk '/^[a-zA-Z_][a-zA-Z0-9_.]*\(\)/{f=1} f&&/^}/{f=0;next} !f' "$SCRIPT_DIR/../kerr.sh" | grep -v '^[[:space:]]*#' | grep -c -E '\$\{?[1@*#]')
if [[ "$n" == 0 ]]; then kt_test_pass "none"; else kt_test_fail "$n file-scope lines read the positional parameters"; fi

# ---------------------------------------------------------------------------
# 4. P3 with headers: a system unit whose header fails makes kbool.sh fail
H="$_KT_TMPDIR/hdr"
rm -rf "$H"; cp -r "$GOOD" "$H"
sed 's/^kk\.unit kcfg || return \$__kk_unit_rc$/kk.unit kcfgx || return $__kk_unit_rc/' "$H/kkore/kcfg.sh" > "$H/kkore/kcfg.sh.kt" && mv "$H/kkore/kcfg.sh.kt" "$H/kkore/kcfg.sh"
UF_FX="$H"
uf_run 'source "$FX/kbool.sh"; r=$?; [[ ${__KK_UNITS[@]@a} == A* ]] && g=on || g=off; echo "r=$r guard=$g home=${KBOOL_HOME-unset}"'
UF_FX="$GOOD"
[[ "$UF_OUT" == *"does not match the file name"*"system unit kcfg failed (rc=2"*"r=2 guard=off home=unset" ]]
uf_check "P3: kcfg.sh's header names another unit -> kbool.sh rc 2 naming kcfg, guard off, KBOOL_HOME unset [P3, U33]" $?

H2="$_KT_TMPDIR/hdr2"
rm -rf "$H2"; cp -r "$GOOD" "$H2"
head -3 "$GOOD/kkore/klib.sh" > "$H2/kkore/klib.sh"
UF_FX="$H2"
uf_run 'source "$FX/kkore/kvar.sh"; r=$?; [[ ${__KK_UNITS[@]@a} == A* ]] && g=on || g=off; echo "r=$r guard=$g"'
UF_FX="$GOOD"
[[ "$UF_OUT" == *"system unit klib did not define kk.isInt"*"r=2 guard=off" ]]
uf_check "P3: a klib.sh that is only its header (defines nothing) -> the sentinel check fails the boot, and the direct source of kvar.sh returns kbool.sh's rc 2 [P3]" $?

# ---------------------------------------------------------------------------
# 5. Lint (found_in_U1a, critic C11): no file-scope local / declare without -g
kt_test_start "lint: no file-scope 'local' and no 'declare'/'typeset' without -g in kbool.sh, kuse.sh and the system units (they run inside a function) [U3, C11]"
LFILES=("$SCRIPT_DIR/../../kbool.sh" "$SCRIPT_DIR/../kuse.sh")
for u in "${SYS_UNITS[@]}"; do LFILES+=("$SCRIPT_DIR/../$u.sh"); done
lint="$(kk_unit_lint "${LFILES[@]}" 2>&1)"; lrc=$?
if (( lrc == 0 )) && [[ -z "$lint" ]]; then kt_test_pass "clean"; else kt_test_fail "rc=$lrc: ${lint//$'\n'/ | }"; fi

kt_test_start "the lint itself: flags a file-scope local, a declare without -g (also after then/;/||), skips bodies, one-liners, here-documents, -g / -f / -F / -p [U3]"
LF="$_KT_TMPDIR/lint_sample.sh"
printf '%s\n' 'f() {' '  local a' '}' 'local b' 'declare c' 'declare -g d' 'declare -gA e' 'g() { local z; }' \
    'if x; then declare -a q; fi' 'cat <<EOF' 'declare inheredoc' 'EOF' '  h()' '  {' '    declare inbody' '  }' \
    'declare -F foo >/dev/null' 'x || typeset -i t' 'declareClass T' '# local commented' > "$LF"
got="$(kk_unit_lint "$LF")"; lrc=$?
got="${got//"$LF":/}"
want=$'4: local b\n5: declare c\n9: if x; then declare -a q; fi\n18: x || typeset -i t'
if (( lrc == 1 )) && [[ "$got" == "$want" ]]; then kt_test_pass "4 findings"; else kt_test_fail "rc=$lrc got='${got//$'\n'/|}'"; fi

kt_test_start "the lint (review R8, critic lint/sample.sh): ! / time / builtin / command / NAME=VALUE prefixes, a body closed by 'echo x; }', '(( z<<y ))' is no here-document, multi-line quoted strings and 'f() ( ... )' bodies are skipped [U3, R8]"
LF2="$_KT_TMPDIR/lint_sample2.sh"
printf '%s\n' '#!/bin/bash' 'local a1' 'declare b1=1' 'typeset c1' 'declare -A d1' 'readonly e1=1' 'declare -r f1=1' \
    'export g1=1' 'declare -gA h1' 'declare -Ag h2' '[[ -n x ]] && declare -i i1=1' 'if true; then declare j1; fi' \
    'for k in 1; do declare k1; done' '! declare l1' 'time declare m1' "eval 'declare n1'" 'builtin declare o1' \
    'command declare p1' 'x=1 declare q1' 'declare -- r1=1' 'declare -a -g s1' 'f() {' '    local inside_ok' '}' \
    'g() { local one_liner_ok; }' 'h() {' '    echo x; }' 'declare t1' 'cat <<EOF2' 'local in_heredoc_ok' 'EOF2' \
    'echo "' 'local in_dq_string' '"' "echo '" 'declare in_sq_string' "'" '(( z = 1 << 2 ))' '(( z = z<<y ))' \
    'declare u1' 'y' 'declare v1' 'sub() (' '    local in_subshell_fn' ')' 'echo "a; declare inline_string"' > "$LF2"
got="$(kk_unit_lint "$LF2")"; lrc=$?
got="$(printf '%s\n' "$got" | sed -e "s#^$LF2:##" -e 's/:.*//' | tr '\n' ' ')"
want="2 3 4 5 7 11 12 13 14 15 17 18 19 20 28 40 42 "
if (( lrc == 1 )) && [[ "$got" == "$want" ]]; then kt_test_pass "17 findings"; else kt_test_fail "rc=$lrc lines='$got' want='$want'"; fi

kt_test_log "013_SystemUnitHeaders.sh completed"
