#!/usr/bin/env bash
# kk.settings / kk.localeDefault / __KK_UNIT_ORDER — the settings hooks and the
# load-order list of kklass/docs/dev/IMAGE_PLAN.md (stage I0: §5.2, §7.7).
# Every scenario runs in a FRESH bash against a throw-away kbool tree built by
# unit_fixture.sh, plus the fixture units below (kcl/<name>/<name>.sh).
#
#   sa    a hook sa._s (counts its runs, sets SA_W, appends to SEQ) with VARs
#         SA_W SHARED; SA_AFTER = the run count right after kk.settings, SA_LAST
#         = the last __KK_UNIT_ORDER entry during its load
#   sb    `kk.settings :` with VARs SHARED SB_X SB_X (a repeat)
#   sn    a nested load: hook sn._pre, `kk.uses sa`, hook sn._post (VAR SN_V)
#   src   the hook's rc passes through (UF_SRC_RC; no `|| return`); rc != 0 taints
#   srr   a failing hook under `|| return` (UF_SRR_RC, default 4): the load fails
#   hra   a hook calling kk.settings; hrb a hook loading units (hrb2), M1
#   hsub  kk.settings inside $( ) during the load (L8); hcomp kk._unit_complete
#         during its own load (L2); ca / CA (folder cb) names differing in case (L3)
#   sbad  bad calls, chosen by UF_SB; SBAD_RC, SBAD_N (records), SBAD_RAN
#   sfk   kk.settings under `set -x` with PS4 = $BASHPID (the fork count)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Settings" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
uf_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
FX="$UF_FX"

uf_unit "$FX" sa \
    'SA_LOADS=$(( ${SA_LOADS:-0} + 1 ))' \
    'SA_LAST=${__KK_UNIT_ORDER[-1]//$'"'"'\x1f'"'"'/:}' \
    'sa._s() { SA_RUNS=$(( ${SA_RUNS:-0} + 1 )); : "${SA_W:=80}"; SEQ+="sa._s "; }' \
    'kk.settings sa._s SA_W SHARED || return' \
    'SA_AFTER=${SA_RUNS-unset}' \
    'sa.later() { kk.settings :; }'
uf_unit "$FX" sb \
    'kk.settings : SHARED SB_X SB_X || return' \
    'SB_RC=$?'
uf_unit "$FX" sn \
    'sn._pre() { SEQ+="sn._pre "; }' \
    'sn._post() { SEQ+="sn._post "; }' \
    'kk.settings sn._pre || return' \
    'kk.uses sa || return' \
    'kk.settings sn._post SN_V || return'
uf_unit "$FX" src \
    'SRC_LOADS=$(( ${SRC_LOADS:-0} + 1 ))' \
    'src._f() { SRC_RAN=1; return "${UF_SRC_RC:-0}"; }' \
    'kk.settings src._f SRC_V; SRC_RC=$?'
uf_unit "$FX" srr \
    'SRR_LOADS=$(( ${SRR_LOADS:-0} + 1 ))' \
    'srr._f() { return "${UF_SRR_RC:-4}"; }' \
    'kk.settings srr._f SRR_V || return' \
    'SRR_PAST=1'
uf_unit "$FX" sbad \
    'sbad._f() { SBAD_RAN=1; }' \
    'case ${UF_SB:-} in' \
    '    1) kk.settings; SBAD_RC=$? ;;' \
    '    2) kk.settings sbad._nofn SBAD_V; SBAD_RC=$? ;;' \
    '    3) kk.settings sbad._f SBAD_V a-b; SBAD_RC=$? ;;' \
    "    4) kk.settings ''; SBAD_RC=\$? ;;" \
    '    5) kk.settings sbad._late; SBAD_RC=$?; sbad._late() { :; } ;;' \
    '    6) kk.settings echo; SBAD_RC=$? ;;' \
    "    7) kk.settings sbad._f 'x[1]'; SBAD_RC=\$? ;;" \
    'esac' \
    'SBAD_N=${#__KK_UNIT_SETTINGS[@]}'
uf_unit "$FX" sfk \
    'sfk._s() { : "${SFK_V:=1}"; kk.localeDefault; }' \
    'exec 9>"$SFK_TRACE"; BASH_XTRACEFD=9; PS4='"'"'+${BASHPID}|'"'"'' \
    'printf "MAIN=%s\n" "$BASHPID" >&9' \
    'set -x' \
    'kk.settings sfk._s SFK_V LC_CTYPE || { set +x; return 1; }' \
    'kk.settings : SFK_W' \
    'set +x; unset BASH_XTRACEFD'
printf '%s\n' 'kk.settings : PLAIN_V; PLAIN_RC=$?' > "$FX/plain.sh"
# M1 (critic r1 A/B): a hook that calls kk.settings; a hook that loads units
uf_unit "$FX" hra \
    'hra._t() { HRA_T=$(( ${HRA_T:-0} + 1 )); }' \
    'hra._s() { kk.settings hra._t HRA_TV; HRA_INNER=$?; return 0; }' \
    'kk.settings hra._s HRA_V; HRA_RC=$?; HRA_RUN=${__KK_SETTINGS_RUN-}'
uf_unit "$FX" hrb2 \
    'hrb2._s() { HRB2_RAN=1; }' \
    'kk.settings hrb2._s HRB2_V || return'
uf_unit "$FX" hrb \
    'hrb._s() { kk.uses hrb2; HRB_USES=$?; source "$FX/kcl/hrb2/hrb2.sh"; HRB_SRC=$?; kk.uses sa; HRB_LOADED=$?; return 0; }' \
    'kk.settings hrb._s HRB_V; HRB_RC=$?'
# L8: kk.settings in a subshell of the load
uf_unit "$FX" hsub \
    'hsub._s() { echo ran; }' \
    'HSUB_OUT=$(kk.settings hsub._s HSUB_V 2>&1); HSUB_RC=$?'
# L2: kk._unit_complete on the unit loading now
uf_unit "$FX" hcomp \
    'kk._unit_complete hcomp; HC_SELF=$?; kk._unit_complete klib; HC_SYS=$?'
# L3: two units whose names differ only in case (a unit `CA` in folder kcl/cb)
uf_unit "$FX" ca 'kk.settings : CA_V || return'
mkdir -p "$FX/kcl/cb"
printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%CA.sh}../../kbool.sh" || return' \
    'kk.unit CA || return $__kk_unit_rc' 'kk.settings : CA_V || return' > "$FX/kcl/cb/CA.sh"

# helpers every snippet sources: ord (the order list as KIND:NAME), sets (the
# hooks as UNIT/FN), v VAR (the units listing VAR, comma-joined; NONE)
cat > "$FX/h.sh" <<'EOF'
ord() { local e o=""; for e in "${__KK_UNIT_ORDER[@]}"; do o+="${e//$'\x1f'/:} "; done; echo "ord=${o% }"; }
sets() { local e o=""; for e in "${__KK_UNIT_SETTINGS[@]}"; do o+="${e//$'\x1f'//} "; done; echo "sets=${o% }"; }
v() { local l; for l; do if [[ -n ${__KK_SETTINGS_VARS[$l]+x} ]]; then l="$l=${__KK_SETTINGS_VARS[$l]//$'\x1f'/,}"; else l="$l=NONE"; fi; printf '%s ' "$l"; done; echo; }
EOF
H='source "$FX/kbool.sh" || exit 9; source "$FX/h.sh"'
SYS='s:kuse s:klib s:kerr s:kvar s:kcfg'

# ---------------------------------------------------------------------------
kt_test_section "019: the kk.settings contract"

uf_run "$H"'; kk.uses sa; echo "r=$? runs=$SA_RUNS after=$SA_AFTER w=$SA_W"; sets; v SA_W SHARED'
[[ $UF_RC == 0 && "$UF_OUT" == "r=0 runs=1 after=1 w=80"$'\n'"sets=sa/sa._s"$'\n'"SA_W=sa, SHARED=sa, " ]]
uf_check "kk.settings runs FN at once (once), records UNIT<US>FN and each VAR under the unit" $?

uf_run "$H"'; SA_W=5; kk.uses sa; echo "w=$SA_W"'
[[ "$UF_OUT" == "w=5" ]]
uf_check "the hook sees the caller's preset (a self-default keeps it)" $?

uf_run "$H"'; kk.uses sb; echo "r=$? rc=$SB_RC"; sets; v SHARED SB_X'
[[ $UF_RC == 0 && "$UF_OUT" == "r=0 rc=0"$'\n'"sets=sb/:"$'\n'"SHARED=sb, SB_X=sb, " ]]
uf_check "FN ':' is accepted (rc 0, recorded); a VAR listed twice in one call is recorded once" $?

uf_run "$H"'; kk.uses sa sb; v SHARED SA_W SB_X; sets'
[[ "$UF_OUT" == "SHARED=sa,sb, SA_W=sa, SB_X=sb, "$'\n'"sets=sa/sa._s sb/:" ]]
uf_check "one VAR claimed by two units: both listed, first lister first; hooks in load order" $?

uf_run "$H"'; kk.uses src; echo "r=$? rc=$SRC_RC ran=${SRC_RAN-}"; sets; v SRC_V'
[[ $UF_RC == 0 && "$UF_OUT" == "r=0 rc=0 ran=1"$'\n'"sets=src/src._f"$'\n'"SRC_V=src, " ]]
uf_check "rc = FN's rc (0): recorded" $?

for rc in 1 3 7; do
    uf_run "$H"'; UF_SRC_RC='"$rc"' kk.uses src; echo "r=$? rc=$SRC_RC ran=${SRC_RAN-}"; sets; v SRC_V; ord'
    [[ $UF_RC == 0 && "$UF_OUT" == "kbool: error: kk.uses: unit 'src' is not completely loaded"*$'\n'"r=2 rc=$rc ran=1"$'\n'"sets="$'\n'"SRC_V=NONE "$'\n'"ord=$SYS" ]]
    uf_check "rc = FN's rc ($rc), and a failed hook taints the unit even when the load ignores the rc: kk.uses reports it incomplete and drops it [M2]" $?
done

uf_run "$H"'; UF_SRC_RC=3 source "$FX/kcl/src/src.sh"; echo "src=$? fail=${__KK_UNIT_FAIL[src]-no} rc=$SRC_RC"; UF_SRC_RC=0 kk.uses src; echo "uses=$? loads=$SRC_LOADS"; sets'
[[ "$UF_OUT" == "src=0 fail=1 rc=3"$'\n'"uses=0 loads=2"$'\n'"sets=src/src._f" ]]
uf_check "a plain-sourced unit whose hook failed (rc ignored) is tainted: the next kk.uses loads it again [M2]" $?

uf_run "$H"'; source "$FX/kcl/srr/srr.sh"; echo "src=$? past=${SRR_PAST-none}"; UF_SRR_RC=0 kk.uses srr; echo "uses=$? loads=$SRR_LOADS past=${SRR_PAST-none}"; sets'
[[ "$UF_OUT" == "src=4 past=none"$'\n'"uses=0 loads=2 past=1"$'\n'"sets=srr/srr._f" ]]
uf_check "a plain-sourced unit whose hook failed under '|| return' is tainted too: kk.uses loads it again (critic r2 case 1) [M2]" $?

uf_run "$H"'; kk.uses srr; echo "r=$? past=${SRR_PAST-none}"; sets; v SRR_V; ord'
[[ $UF_RC == 0 && "$UF_OUT" == *"kk.uses: loading unit 'srr' failed (rc=4)"*$'\n'"r=4 past=none"$'\n'"sets="$'\n'"SRR_V=NONE "$'\n'"ord=$SYS" ]]
uf_check "a failing hook under '|| return' fails the load: kk.uses forgets the unit and its records" $?

# bad calls inside a load: rc 2, printed, nothing recorded, FN not run, the unit tainted
declare -A BAD=(
    [1]="kk.settings: usage 'kk.settings FN [VAR...] || return' (in unit 'sbad')"
    [2]="kk.settings: 'sbad._nofn' is not a function (define it before kk.settings; in unit 'sbad')"
    [3]="kk.settings sbad._f: 'a-b' is not a variable name (letters, digits, _; in unit 'sbad')"
    [4]="kk.settings: usage 'kk.settings FN [VAR...] || return' (in unit 'sbad')"
    [5]="kk.settings: 'sbad._late' is not a function (define it before kk.settings; in unit 'sbad')"
    [6]="kk.settings: 'echo' is not a function (define it before kk.settings; in unit 'sbad')"
    [7]="kk.settings sbad._f: 'x[1]' is not a variable name (letters, digits, _; in unit 'sbad')"
)
for k in 1 2 3 4 5 6 7; do
    uf_run "$H"'; UF_SB='"$k"' kk.uses sbad; echo "r=$? rc=$SBAD_RC n=$SBAD_N ran=${SBAD_RAN-no}"; v SBAD_V; UF_SB= kk.uses sbad; echo "again=$? ran=${SBAD_RAN-no}"'
    [[ "$UF_OUT" == "kbool: error: ${BAD[$k]}"$'\n'"kbool: error: kk.uses: unit 'sbad' is not completely loaded"*$'\n'"r=2 rc=2 n=0 ran=no"$'\n'"SBAD_V=NONE "$'\n'"again=0 ran=no" ]]
    uf_check "bad call $k: rc 2, kkore's message, nothing recorded, FN not run, the unit tainted (kk.uses reports it; the next load runs it again)" $?
done

uf_run "$H"'; VERBOSE_KKLASS=quiet; UF_SB=3 kk.uses sbad; echo "r=$? rc=$SBAD_RC"'
[[ "$UF_OUT" == "r=2 rc=2" ]]
uf_check "VERBOSE_KKLASS=quiet silences the message (rc 2 stays)" $?

# ---------------------------------------------------------------------------
kt_test_section "019: outside a unit's load"

uf_run "$H"'; kk.settings :; echo "top=$?"; kk.uses sa; sa.later; echo "later=$?"; kk.uses "$FX/plain.sh"; echo "plain=$PLAIN_RC"; f() { kk.settings sa._s X; }; f; echo "fn=$?"; sets; v X PLAIN_V; echo "runs=$SA_RUNS"'
[[ $UF_RC == 0 && "$UF_OUT" == "kbool: error: kk.settings :: not inside a unit's load (call it in the unit file, after the function is defined)"$'\n'"top=2"$'\n'"kbool: error: kk.settings :: not inside a unit's load"*$'\n'"later=2"$'\n'"kbool: error: kk.settings :: not inside"*$'\n'"plain=2"$'\n'"kbool: error: kk.settings sa._s: not inside"*$'\n'"fn=2"$'\n'"sets=sa/sa._s"$'\n'"X=NONE PLAIN_V=NONE "$'\n'"runs=1" ]]
uf_check "rc 2 at the top level, in a unit's function after its load, in a header-less file kk.uses loads, in a script function; nothing run or recorded" $?

uf_run "$H"'; ( unset __KK_LOADED; kk.settings : X; echo "rc=$?" )'
[[ "$UF_OUT" == "kbool: error: kk.settings : X: kbool.sh is not loaded"$'\n'"rc=2" ]]
uf_check "a shell without kbool's registry: rc 2, 'kbool.sh is not loaded'" $?

uf_run "$H"'; set -eu; kk.uses sn sb; kk.settings : 2>/dev/null || echo "top rc=$?"; echo "ok ${#__KK_UNIT_SETTINGS[@]}"'
[[ $UF_RC == 0 && "$UF_OUT" == "top rc=2"$'\n'"ok 4" ]]
uf_check "set -eu: loads with kk.settings work; a refused call is an ordinary rc 2" $?

# ---------------------------------------------------------------------------
kt_test_section "019: nested loads, --forget, reload"

uf_run "$H"'; kk.uses sn; echo "seq=$SEQ"; sets; v SA_W SHARED SN_V; ord'
[[ "$UF_OUT" == "seq=sn._pre sa._s sn._post "$'\n'"sets=sn/sn._pre sa/sa._s sn/sn._post"$'\n'"SA_W=sa, SHARED=sa, SN_V=sn, "$'\n'"ord=$SYS u:sn u:sa" ]]
uf_check "nested load: the inner unit's hook is filed under it, between the outer unit's hooks, in call order" $?

uf_run "$H"'; kk.uses sa sb; kk.unit --forget sa; echo "f=$?"; sets; v SHARED SA_W SB_X; kk.uses sa; echo "re=$? runs=$SA_RUNS"; sets; v SHARED SA_W; kk.unit --forget sb; sets; v SHARED SB_X'
[[ "$UF_OUT" == "f=0"$'\n'"sets=sb/:"$'\n'"SHARED=sb, SA_W=NONE SB_X=sb, "$'\n'"re=0 runs=2"$'\n'"sets=sb/: sa/sa._s"$'\n'"SHARED=sb,sa, SA_W=sa, "$'\n'"sets=sa/sa._s"$'\n'"SHARED=sa, SB_X=NONE " ]]
uf_check "--forget drops the unit's hooks and VAR claims (a shared VAR keeps the other unit); a reload records again at the end" $?

uf_run "$H"'; kk.uses sn; kk.unit --forget sn; sets; v SN_V SA_W; kk.uses sn; echo "runs=$SA_RUNS seq=$SEQ"; sets'
[[ "$UF_OUT" == "sets=sa/sa._s"$'\n'"SN_V=NONE SA_W=sa, "$'\n'"runs=1 seq=sn._pre sa._s sn._post sn._pre sn._post "$'\n'"sets=sa/sa._s sn/sn._pre sn/sn._post" ]]
uf_check "--forget of the outer unit keeps the inner unit's records; its reload does not run the loaded inner hook again" $?

uf_run "$H"'; kk.uses a sa; kk.unit --forget a; sets; source "$FX/kcl/sa/sa.sh"; source "$FX/kcl/sa/sa.sh"; echo "runs=$SA_RUNS"; sets'
[[ "$UF_OUT" == "sets=sa/sa._s"$'\n'"runs=1"$'\n'"sets=sa/sa._s" ]]
uf_check "--forget of a unit without hooks changes nothing; a no-op re-source records nothing" $?

uf_run "$H"'; source "$FX/kcl/sa/sa.sh"; echo "runs=$SA_RUNS after=$SA_AFTER"; sets'
[[ "$UF_OUT" == "runs=1 after=1"$'\n'"sets=sa/sa._s" ]]
uf_check "a plain-sourced unit records its hook like a kk.uses-loaded one" $?

# ---------------------------------------------------------------------------
kt_test_section "019: __KK_UNIT_ORDER"

uf_run "$H"'; ord; declare -p __KK_UNIT_ORDER | { read -r d f _; echo "$d $f"; }'
[[ "$UF_OUT" == "ord=$SYS"$'\n'"declare -a" ]]
uf_check "after kbool.sh: the five system units, in boot order, marked s (an indexed array)" $?

uf_run "$H"'; kk.uses sn; kk.uses b; source "$FX/kcl/a/a.sh"; echo "last=$SA_LAST"; ord'
[[ "$UF_OUT" == "last=u:sa"$'\n'"ord=$SYS u:sn u:sa u:b u:a" ]]
uf_check "units are appended at registration (marked u): a nested unit after its parent, a plain source too; a loading unit is already last" $?

uf_run "$H"'; kk.uses sn b; kk.unit --forget sa; ord; kk.uses sa; ord; kk.unit --forget sn; kk.uses sn; ord'
[[ "$UF_OUT" == "ord=$SYS u:sn u:b"$'\n'"ord=$SYS u:sn u:b u:sa"$'\n'"ord=$SYS u:b u:sa u:sn" ]]
uf_check "--forget removes the entry; a reload goes to the end" $?

uf_run "$H"'; UF_FAIL=1 kk.uses fail 2>/dev/null; echo "r=$?"; ord; UF_FAIL=1; source "$FX/kcl/dep/dep.sh" 2>/dev/null; kk.uses a; ord; UF_FAIL=0; kk.uses dep; echo "r=$?"; ord'
[[ "$UF_OUT" == "r=3"$'\n'"ord=$SYS"$'\n'"ord=$SYS u:dep u:a"$'\n'"r=0"$'\n'"ord=$SYS u:a u:dep" ]]
uf_check "a failed kk.uses load leaves no entry; a tainted plain-sourced load stays until its reload, which goes to the end" $?

uf_run "$H"'; kk.uses klib kerr; kk.unit --forget klib 2>/dev/null; echo "r=$?"; ord; source "$FX/kbool.sh"; ord'
[[ "$UF_OUT" == "r=2"$'\n'"ord=$SYS"$'\n'"ord=$SYS" ]]
uf_check "system units: kk.uses of one, a refused --forget and a kbool.sh re-source change nothing" $?

uf_run 'source "$FX/kcl/sa/sa.sh"; source "$FX/h.sh"; ord'
[[ "$UF_OUT" == "ord=$SYS u:sa" ]]
uf_check "a unit whose header bootstraps kbool.sh: the system units first, then the unit" $?

uf_run 'source "$FX/kbool.sh"; __KK_UNIT_ORDER=x; unset __KK_UNIT_SETTINGS __KK_SETTINGS_VARS; __KK_UNIT_SETTINGS=y; __KK_SETTINGS_VARS=z; source "$FX/kkore/kuse.sh"; declare -p __KK_UNIT_SETTINGS __KK_SETTINGS_VARS | while read -r d f n; do echo "$d $f ${n%%=*}"; done; echo "${__KK_UNIT_ORDER[0]//$'"'"'\x1f'"'"'/:}"'
[[ "$UF_OUT" == "declare -a __KK_UNIT_SETTINGS"$'\n'"declare -A __KK_SETTINGS_VARS"$'\n'"x" ]]
uf_check "a re-source of kuse.sh repairs a scalar settings table into its array kind (an existing indexed one is kept)" $?

# ---------------------------------------------------------------------------
kt_test_section "019: kk.localeDefault"

uf_run "$H"'; unset LC_ALL LC_CTYPE LANG; kk.localeDefault; echo "rc=$?"; declare -p LC_CTYPE; "$BASH" -c '"'"'echo "child=$LC_CTYPE"'"'"''
[[ "$UF_OUT" == "rc=0"$'\n''declare -x LC_CTYPE="C.UTF-8"'$'\n'"child=C.UTF-8" ]]
uf_check "no locale variable: LC_CTYPE=C.UTF-8, exported" $?

uf_run "$H"'; unset LC_ALL LC_CTYPE; export LANG=; kk.localeDefault; echo "rc=$? ${LC_CTYPE-unset}"'
[[ "$UF_OUT" == "rc=0 C.UTF-8" ]]
uf_check "an empty LANG counts as unset" $?

uf_run "$H"'; unset LC_ALL LC_CTYPE; export LANG=en_US.UTF-8; kk.localeDefault; echo "rc=$? ${LC_CTYPE-unset} $LANG"; unset LANG; LC_ALL=C; kk.localeDefault; echo "${LC_CTYPE-unset}"; unset LC_ALL; LC_CTYPE=POSIX; kk.localeDefault; declare -p LC_CTYPE'
[[ "$UF_OUT" == "rc=0 unset en_US.UTF-8"$'\n'"unset"$'\n''declare -- LC_CTYPE="POSIX"' ]]
uf_check "LANG, LC_ALL or LC_CTYPE set: nothing touched (not even exported)" $?

# ---------------------------------------------------------------------------
kt_test_section "019: hooks re-entering, subshells, kk._unit_complete, nocasematch (I0 critic)"

uf_run "$H"'; kk.uses hra; echo "r=$? rc=$HRA_RC inner=$HRA_INNER T=${HRA_T-0} run=[$HRA_RUN] now=[$__KK_SETTINGS_RUN]"; sets; v HRA_V HRA_TV'
[[ "$UF_OUT" == "kbool: error: kk.settings hra._t: called inside the settings hook hra._s of unit 'hra'; a hook may not call kk.settings (in unit 'hra')"$'\n'"kbool: error: kk.uses: unit 'hra' is not completely loaded"*$'\n'"r=2 rc=0 inner=2 T=0 run=[] now=[]"$'\n'"sets="$'\n'"HRA_V=NONE HRA_TV=NONE " ]]
uf_check "a hook calling kk.settings: refused (rc 2, printed, the inner FN not run, the unit tainted); the running-hook mark is cleared after FN [M1, critic r1 A]" $?

uf_run "$H"'; kk.uses sa; kk.uses hrb; echo "r=$? rc=$HRB_RC uses=$HRB_USES src=$HRB_SRC loaded=$HRB_LOADED ran=${HRB2_RAN-no}"; ord; kk.uses hrb2; echo "later=$? ran=$HRB2_RAN"; sets'
[[ "$UF_OUT" == "kbool: error: kk.uses hrb2: a settings hook may not load units (inside the hook hrb._s of unit 'hrb')"$'\n'"kbool: error: kk.unit hrb2: a settings hook may not load units (inside the hook hrb._s of unit 'hrb'; in "*$'\n'"kbool: error: kk.uses: unit 'hrb' is not completely loaded"*$'\n'"r=2 rc=0 uses=2 src=2 loaded=0 ran=no"$'\n'"ord=$SYS u:sa"$'\n'"later=0 ran=1"$'\n'"sets=sa/sa._s hrb2/hrb2._s" ]]
uf_check "a hook loading a unit: kk.uses and a plain source of a new unit are refused (rc 2, printed, the hook's unit tainted); kk.uses of a loaded unit stays a no-op (rc 0); outside the hook the unit loads [M1, critic r1 B]" $?

uf_run "$H"'; cd "$FX/cwd"; printf -v u "\037"; p="a[\$(touch PWN)]"; for m in "0${u}zz${u}f" "99999${u}zz${u}f" "$p${u}zz${u}f"; do __KK_SETTINGS_RUN=$m; kk.unit --forget sa; kk.uses sa; printf "%s " "r=$?"; done; echo "runs=$SA_RUNS pwn=$([[ -e PWN ]] && echo yes || echo no)"; sets'
[[ "$UF_OUT" == "r=0 r=0 r=0 runs=3 pwn=no"$'\n'"sets=sa/sa._s" ]]
uf_check "a running-hook mark left behind (no such kk.settings frame on the stack, or not a number) is inert: units load, nothing evaluated [M1]" $?

uf_run "$H"'; kk.uses hsub;echo "r=$? rc=$HSUB_RC"; echo "out=$HSUB_OUT"; sets; v HSUB_V'
[[ "$UF_OUT" == "r=0 rc=2"$'\n'"out=kbool: error: kk.settings hsub._s: called in a subshell of the load of unit 'hsub' (\$( ), a pipe, ( )): nothing would be recorded"$'\n'"sets="$'\n'"HSUB_V=NONE " ]]
uf_check "kk.settings in a subshell of the load (\$( )): rc 2, printed, the hook not run, nothing recorded [L8, critic r1 G]" $?

uf_run "$H"'; kk.uses hcomp; echo "self=$HC_SELF sys=$HC_SYS"; kk._unit_complete hcomp; echo "after=$?"; source "$FX/kcl/a/a.sh"; kk._unit_complete a; echo "plain=$? done=${__KK_UNIT_DONE[a]-unset}"; UF_FAIL=1 source "$FX/kcl/dep/dep.sh" 2>/dev/null; kk._unit_complete dep; echo "tainted=$?"; kk._unit_complete nosuch; echo "none=$?"; kk._unit_complete; echo "empty=$?"; ( unset __KK_LOADED; kk._unit_complete a; echo "noreg=$?" )'
[[ "$UF_OUT" == "self=1 sys=0"$'\n'"after=0"$'\n'"plain=0 done=unset"$'\n'"tainted=1"$'\n'"none=1"$'\n'"empty=1"$'\n'"noreg=2" ]]
uf_check "kk._unit_complete: 1 while loading, 0 when done or plain-sourced and ended (not marking it done), 1 tainted / unknown / empty, 2 without a registry; silent [L2, critic r2 case 9]" $?

uf_run "$H"'; RESULT=x; kk._unit_current; echo "top=$? [$RESULT]"; kk.uses a; echo "cur=$A_CUR"; ( unset __KK_LOADED; RESULT=y; kk._unit_current; echo "noreg=$? [$RESULT]" )'
[[ "$UF_OUT" == "top=1 []"$'\n'"cur=a"$'\n'"noreg=1 []" ]]
uf_check "kk._unit_current on the shared stack walk: RESULT '' + rc 1 outside a load and without a registry, the unit's name inside its load [L9]" $?

uf_run "$H"'; kk.uses ca; shopt -s nocasematch; source "$FX/kcl/cb/CA.sh"; echo "src=$?"; v CA_V; ord; kk.unit --forget ca; ord; v CA_V; sets; shopt -q nocasematch && echo nc=on'
[[ "$UF_OUT" == "src=0"$'\n'"CA_V=ca,CA, "$'\n'"ord=$SYS u:ca u:CA"$'\n'"ord=$SYS u:CA"$'\n'"CA_V=CA, "$'\n'"sets=CA/:"$'\n'"nc=on" ]]
uf_check "nocasematch: units ca and CA are told apart when recording a VAR and on --forget (order, hooks, VARs); the option is restored [L3, critic r2 case 5]" $?

# ---------------------------------------------------------------------------
kt_test_section "019: fork-free"

# the trace of the kk.settings calls (in a load and refused outside one) under
# set -x with PS4 = $BASHPID: a line of another pid is a subshell
uf_run "$H"'; export SFK_TRACE="$FX/sfk.trace"; unset LC_ALL LC_CTYPE LANG; kk.uses sfk; echo "r=$? v=$SFK_V lc=$LC_CTYPE"
exec 8>>"$SFK_TRACE"; BASH_XTRACEFD=8; PS4='"'"'+${BASHPID}|'"'"'; set -x; kk.settings : 2>/dev/null; set +x; unset BASH_XTRACEFD'
forks=0 lines=0 seen="" main=""
while IFS= read -r line; do
    case $line in MAIN=*) main=${line#MAIN=}; continue ;; +*) ;; *) continue ;; esac
    p=${line%%|*}; p=${p##*+}
    [[ -n $p && $p != *[!0-9]* ]] || continue
    (( lines++ ))
    [[ $line == *"kk.localeDefault"* ]] && seen+=L
    [[ $line == *"not inside a unit"* ]] && seen+=E
    [[ -n $main && $p != "$main" ]] && (( forks++ ))
done < "$FX/sfk.trace"
[[ "$UF_OUT" == "r=0 v=1 lc=C.UTF-8" && -n $main && $forks == 0 && $lines -gt 20 && $seen == *L* && $seen == *E* ]]
uf_check "kk.settings (a hook with kk.localeDefault, ':', the refusal outside a load) forks nothing [forks=$forks lines=$lines seen=$seen]" $?

kt_test_log "019_Settings.sh completed"
