#!/usr/bin/env bash
# ImageBackground — `kk.image --background` (kklass/docs/dev/IMAGE_PLAN.md,
# owner decision IMG-D10, stage I5; kkore/kimgbg.sh): a miss is a plain load
# at once and a detached writer writes the image (the next start hits); the
# caller's `$!` and job table untouched; `$(…)` returns without waiting for
# the writer (its descriptors: 0-2 /dev/null, no pipe); one writer per image
# (the marker NAME.bg: a second call while it runs starts none and does not
# wait); a writer killed (a stale marker: a hold of 10 minutes, no new
# writer), stopped by its limit (TERM: a hold of 10 minutes), its watchdog
# mode (no timeout tool); a refusal holds as the foreground writer does; its
# own key or unit table not the caller's: no image, a hold; KBOOL_IMAGE=off;
# a prior set (no background writer); option clashes; --forget and pruning
# take the marker. Every writer is waited for; the EXIT trap kills a leftover
# writer group AND fails the file (a leftover is a bug). Fixture:
# image_fixture.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImageBackground" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
IMGD=$FX/img
UF_ENV=(KBOOL_IMAGE_DIR="$IMGD" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9; VERBOSE_KKLASS=debug'
FL='fl() { local l; while IFS= read -r l; do [[ $l == *"$1"* ]] && { echo "$l"; return 0; }; done < "$FX/e.txt"; return 0; }'

# ---- the writers: found by their markers, waited for, never left behind ----
BG_SEEN=()          # "PID PGID" of every writer this file saw
BG_LEFT=""          # leftovers found by bg_guard
# bg_read MARKER -> BG_T BG_O BG_P BG_G BG_Q (time token pid tag pgid); rc 1 when absent
bg_read() {
    BG_T="" BG_O="" BG_P="" BG_G="" BG_Q=""
    [[ -f $1 ]] || return 1
    { IFS=' ' read -r BG_T BG_O BG_P BG_G BG_Q < "$1"; } 2>/dev/null || :
    return 0
}
# bg_marker -> BG_M = the one marker in the image folder ('' none)
bg_marker() {
    local f
    BG_M=""
    for f in "$IMGD"/*.bg; do [[ -e $f ]] && BG_M=$f; done
}
# bg_started MARKER [S] — wait (<= S s, default 20) until the writer wrote its
# pid into MARKER; records it. rc 1 on a timeout.
bg_started() {
    local n=$(( ${2:-20} * 10 ))
    while (( n-- > 0 )); do
        if bg_read "$1" && [[ -n $BG_P && $BG_P != *[!0-9]* ]]; then BG_SEEN+=("$BG_P ${BG_Q:--}"); return 0; fi
        [[ -f $1 ]] || return 1
        sleep 0.1
    done
    return 1
}
# bg_wait MARKER [S] — wait (<= S s, default 60) until the marker is gone and
# its writer's pid answers no more. rc 1 on a timeout.
bg_wait() {
    local n=$(( ${2:-60} * 10 )) p=""
    if bg_read "$1"; then p=$BG_P; fi
    while (( n-- > 0 )); do
        if [[ ! -e $1 ]] && { [[ -z $p || $p == *[!0-9]* ]] || ! kill -0 "$p" 2>/dev/null; }; then return 0; fi
        if [[ -z $p || $p == - ]] && bg_read "$1"; then p=$BG_P; fi
        sleep 0.1
    done
    return 1
}
# bg_kill PID PGID SIG — the writer's process group (and the pid itself)
bg_kill() {
    if [[ -n $2 && $2 != *[!0-9]* && $2 != 0 ]]; then kill "-$3" -- "-$2" 2>/dev/null; fi
    kill "-$3" "$1" 2>/dev/null
}
# bg_guard — every writer seen, and every marker's, still alive: killed
# (group TERM, then KILL) and named in BG_LEFT
bg_guard() {
    local e p q f n
    local -a all=("${BG_SEEN[@]}")
    for f in "$IMGD"/*.bg; do
        [[ -e $f ]] || continue
        bg_read "$f" && [[ -n $BG_P && $BG_P != *[!0-9]* ]] && all+=("$BG_P ${BG_Q:--}")
    done
    for e in "${all[@]}"; do
        p=${e%% *} q=${e#* }
        kill -0 "$p" 2>/dev/null || continue
        BG_LEFT+=" $p"
        bg_kill "$p" "$q" TERM
        for (( n = 0; n < 30; n++ )); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done
        bg_kill "$p" "$q" KILL
    done
}
bg_exitcheck() {
    bg_guard
    if [[ -n $BG_LEFT ]]; then
        kt_test_start "no background writer outlives the test file"
        kt_test_fail "leftover writer(s):$BG_LEFT"
    fi
}
t=$(trap -p EXIT)
eval "set -- $t"
trap "bg_exitcheck; ${3-}" EXIT
# us -> T_US: the wall time of the last uf_run (microseconds)
timed_run() {
    local t0=$EPOCHREALTIME t1
    uf_run "$1"
    t1=$EPOCHREALTIME
    T_US=$(( 10#${t1/./} - 10#${t0/./} ))
}

# ---------------------------------------------------------------------------
kt_test_section "029: a miss: the plain load now, the writer, then a hit"

uf_run "$H; $FL"'; __KK_IMG_BGSYNC=1 __KK_IMG_BGERR=$FX/w.err; kk.image --background ia 2>"$FX/e.txt"; echo "rc=$? ${__KK_UNIT_PID[ia]+normal} $(declare -F ia.f) jobs=[$(jobs -p)] bang=[$!]"; fl "background writer"'
for f in "$IMGD"/ia-*.img; do IMG=$f; done
[[ $UF_OUT == "rc=0 normal ia.f jobs=[] bang=[]"$'\n'"kbool: image: no image $IMGD/ia-"*".img yet: a normal load (kk.uses ia), then a background writer ($IMGD/ia-"*".bg)" \
   && -f ${IMG-} ]]
uf_check "a miss with --background: the plain load (rc, units), \$! and the job table untouched, the writer started; the image written" $?
W=$(cat "$FX/w.err")
[[ $W == *"kbool: image: background writer: no image $IMG yet: a normal load, then an image"* && $W == *"kbool: image: wrote $IMG"* ]]
uf_check "the writer keyed the request as the caller did and wrote THE caller's image (its debug lines)" $?
bg_marker
[[ -z $BG_M ]]
uf_check "the writer removed its marker at its end" $?
uf_run "$H"'; kk.image --path ia >/dev/null; echo "path=$?"'
[[ $UF_OUT == "path=0" ]]
uf_check "kk.image --path from the same caller: the image is valid" $?
uf_run "$H; $FL"'; kk.image --background ia 2>"$FX/e.txt"; echo "rc=$? ${__KK_UNIT_PID[ia]+normal}"; fl "loaded from"'
bg_marker
[[ $UF_OUT == "rc=0 "$'\n'"kbool: image: loaded from $IMG" && -z $BG_M ]]
uf_check "the next start is a hit (the background writer's image is the one a start uses), no writer" $?
# a calling FILE (bin/fvdlg's case): the writer's image, then a hit whose
# state equals a normal load's
cat > "$FX/bs.sh" <<'EOF'
# bs.sh MODE FILE — MODE bg: kk.image --background ia (the writer waited
# for); hit: kk.image --background ia, then the state dump; plain: the same
# with KBOOL_IMAGE=off
source "$FX/kbool.sh" || exit 9
case $1 in
    bg)    __KK_IMG_BGSYNC=1 kk.image --background ia; echo "bg rc=$?" ;;
    hit)   kk.image --background ia; echo "hit rc=$? ${__KK_UNIT_PID[ia]+normal}" ;;
    plain) KBOOL_IMAGE=off kk.image --background ia; echo "plain rc=$? ${__KK_UNIT_PID[ia]+normal}" ;;
esac
[[ $1 == bg ]] && exit 0
kk._image_lib || exit 9
kk._img_state "$2" canon
EOF
rm -f "$IMGD"/*
uf_run 'bash "$FX/bs.sh" bg; bash "$FX/bs.sh" hit "$FX/i.d"; bash "$FX/bs.sh" plain "$FX/n.d"; bash "$FX/cmp.sh" "$FX/n.d" "$FX/i.d"'
[[ $UF_OUT == "bg rc=0"$'\n'"hit rc=0 "$'\n'"plain rc=0 normal"$'\n'"cmp rc=0 "* ]]
uf_check "a calling file: the writer's image is hit by the next start, its state equal to a normal load's (the documented allow-list)" $?

# ---------------------------------------------------------------------------
kt_test_section "029: detached: \$(…) returns at once, one writer, its descriptors"

rm -f "$IMGD"/*
timed_run "$H"'; export __KK_IMG_BGPAUSE=6; exec 7>&1; kk.image --background ia 2>/dev/null; echo "rc=$? jobs=[$(jobs -p)]"'
bg_marker; M=$BG_M
(( T_US < 4000000 )) && [[ $UF_OUT == "rc=0 jobs=[]" && -n $M ]]
uf_check "the caller's \$(…) returned in $(( T_US / 1000 )) ms while the writer waits 6 s (it holds no descriptor of the caller's: fd 7 = the substitution's pipe)" $?
bg_started "$M"
uf_check "the writer wrote its pid into the marker NAME.bg" $?
P=$BG_P O=$BG_O
if [[ -d /proc/$P/fd ]]; then
    ok=0 bad=""
    for n in 0 1 2; do l=$(readlink "/proc/$P/fd/$n" 2>/dev/null); [[ $l == /dev/null ]] || { ok=1; bad+=" $n=$l"; }; done
    for f in /proc/"$P"/fd/*; do l=$(readlink "$f" 2>/dev/null); [[ $l != pipe:* && $l != *"[pipe]"* ]] || { ok=1; bad+=" ${f##*/}=$l"; }; done
    kt_test_start "the writer's descriptors: 0, 1, 2 are /dev/null, none is a pipe (no tty, no caller's stdin or pipes) [R5]"
    if (( ok == 0 )); then kt_test_pass ok; else kt_test_fail "$bad"; fi
else
    kt_test_start "the writer's descriptors [R5]"; kt_test_pass "N/A: no /proc/PID/fd here"
fi
timed_run "$H; $FL"'; kk.image --background ia 2>"$FX/e.txt"; echo "rc=$?"; fl "no background writer"'
bg_read "$M"
(( T_US < 4000000 )) && [[ $UF_OUT == "rc=0"$'\n'"kbool: image: no image "*": a normal load (kk.uses ia); no background writer: a background writer is running (pid $P, marked "*" s ago)" \
   && $BG_O == "$O" && $BG_P == "$P" ]]
uf_check "a second call while the writer runs: a plain load, no second writer (the marker unchanged), no wait" $?
bg_wait "$M" 60
uf_check "the writer ended by itself" $?
uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl "loaded from"'
[[ $UF_OUT == "kbool: image: loaded from $IMGD/ia-"*".img" ]]
uf_check "then a hit" $?

# ---------------------------------------------------------------------------
kt_test_section "029: a killed writer, a stopped one, the watchdog mode"

rm -f "$IMGD"/*
uf_run "$H"'; export __KK_IMG_BGPAUSE=30; kk.image --background ia 2>/dev/null'
bg_marker; M=$BG_M
bg_started "$M"
P=$BG_P Q=$BG_Q
bg_kill "$P" "$Q" KILL
n=0; while kill -0 "$P" 2>/dev/null && (( n++ < 50 )); do sleep 0.1; done
! kill -0 "$P" 2>/dev/null && [[ -f $M ]]
uf_check "a writer killed (SIGKILL to its group): gone, its marker left behind" $?
uf_run "$H; $FL"'; kk.image --background ia 2>"$FX/e.txt"; echo "rc=$?"; fl "no background writer"'
HOLD=${M%.bg}.hold
R=$(cat "$HOLD" 2>/dev/null)
[[ $UF_OUT == "rc=0"$'\n'*"no background writer: the last background writer did not finish (marked "*" s ago): a hold for 10 minutes" \
   && $R == *" a background writer did not finish" ]] && (( EPOCHSECONDS - ${R%% *} >= 2990 ))
uf_check "the next call: a plain load, no new writer, a hold of 10 minutes (dated 50 minutes back)" $?
uf_run "$H; $FL"'; kk.image --background ia 2>"$FX/e.txt"; fl "held"'
[[ $UF_OUT == *"held (a background writer did not finish, "*"; a normal load (kk.uses ia)" ]] && ! ls "$IMGD"/ia-*.img >/dev/null 2>&1
uf_check "while held: plain loads, no image, no writer" $?
rm -f "$IMGD"/*

uf_run "$H"'; export __KK_IMG_BGPAUSE=0; kk.image --background ia 2>/dev/null'
bg_marker; M=$BG_M
bg_started "$M"
P=$BG_P Q=$BG_Q
seen=""
for (( n = 0; n < 300; n++ )); do
    for f in "$IMGD"/*.tmp.*; do [[ -e $f ]] && { seen=$f; break 2; }; done
    kill -0 "$P" 2>/dev/null || break
    sleep 0.02
done
if [[ -n $seen ]]; then
    bg_kill "$P" "$Q" KILL
    n=0; while kill -0 "$P" 2>/dev/null && (( n++ < 50 )); do sleep 0.1; done
    ok=0
    for f in "$IMGD"/ia-*.img; do
        [[ -e $f ]] || continue
        uf_run "$H"'; kk.image --path ia >/dev/null; echo "path=$?"'
        [[ $UF_OUT == path=0 ]] || ok=1
    done
    kt_test_start "a writer killed while it writes (its temp files seen): no image, or a valid one — never a damaged one"
    if (( ok == 0 )); then kt_test_pass ok; else kt_test_fail "an image that is not valid: $UF_OUT"; fi
else
    bg_wait "$M" 60
    kt_test_start "a writer killed while it writes"; kt_test_pass "N/A: the write ended before a temp file was seen"
fi
rm -f "$IMGD"/*

uf_run "$H"'; export __KK_IMG_BGPAUSE=20 __KK_IMG_BGLIMIT=2; kk.image --background ia 2>/dev/null'
bg_marker; M=$BG_M
bg_started "$M"
bg_wait "$M" 30
r=$?
R=$(cat "${M%.bg}.hold" 2>/dev/null)
(( r == 0 )) && [[ $R == *" a background writer was stopped (TERM)" ]] && (( EPOCHSECONDS - ${R%% *} >= 2990 ))
uf_check "the limit (__KK_IMG_BGLIMIT=2 s, the timeout tool): the writer and its children stopped, its marker removed, a hold of 10 minutes" $?
rm -f "$IMGD"/*

uf_run "$H"'; export __KK_IMG_BGNOTOOLS=1 __KK_IMG_BGPAUSE=20 __KK_IMG_BGLIMIT=2; kk.image --background ia 2>/dev/null'
bg_marker; M=$BG_M
bg_started "$M"
bg_wait "$M" 30
r=$?
R=$(cat "${M%.bg}.hold" 2>/dev/null)
(( r == 0 )) && [[ $R == *" a background writer timed out after 2 s" ]]
uf_check "the watchdog mode (no setsid / timeout / nice): at the limit the writer is stopped, a hold of 10 minutes" $?
rm -f "$IMGD"/*
uf_run "$H"'; __KK_IMG_BGSYNC=1 __KK_IMG_BGNOTOOLS=1; kk.image --background ia 2>/dev/null'
uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl "loaded from"'
[[ $UF_OUT == "kbool: image: loaded from $IMGD/ia-"*".img" ]]
uf_check "the watchdog mode writes the image" $?
rm -f "$IMGD"/*

# ---------------------------------------------------------------------------
kt_test_section "029: holds, the key, the unit table, KBOOL_IMAGE=off, P, options"

uf_run "$H"'; __KK_IMG_BGSYNC=1; kk.image --background itr 2>/dev/null; trap -p USR1'
for f in "$IMGD"/itr-*.hold; do HOLD=$f; done
R=$(cat "${HOLD-}" 2>/dev/null)
[[ $UF_OUT == "trap -- ':' SIGUSR1" && $R == *" the load changed the shell state: trap" ]] && ! ls "$IMGD"/itr-*.img >/dev/null 2>&1
uf_check "a writer that refuses (a unit sets a trap): no image, the foreground writer's hold" $?
uf_run "$H; $FL"'; kk.image --background itr 2>"$FX/e.txt"; fl "held"'
bg_marker
[[ $UF_OUT == *"; held (the load changed the shell state: trap, "*"); a normal load (kk.uses itr)" && -z $BG_M ]]
uf_check "the next call: held — a plain load, no writer started" $?
rm -f "$IMGD"/*

printf '#!/bin/sh\nexit 0\n' > "$FX/cksum"; chmod +x "$FX/cksum"
uf_run "$H"'; __KK_IMG_BGSYNC=1 KBOOL_IMAGE_CHECK=hash; hash -p "$FX/cksum" cksum; kk.image --background ia 2>/dev/null'
for f in "$IMGD"/ia-*.hold; do HOLD=$f; done
R=$(cat "${HOLD-}" 2>/dev/null)
[[ $R == *" background writer: its key differs from the caller's" ]] && ! ls "$IMGD"/ia-*.img >/dev/null 2>&1
uf_check "a writer whose key is not the caller's (the caller's hash table names another cksum): no image, a hold" $?
rm -f "$IMGD"/* "$FX/cksum"

uf_run "$H"'; __KK_IMG_BGSYNC=1; __KK_UNIT_ORDER+=("s${__KK_SEP}zz"); kk.image --background ia 2>/dev/null'
for f in "$IMGD"/ia-*.hold; do HOLD=$f; done
R=$(cat "${HOLD-}" 2>/dev/null)
[[ $R == *" background writer: the caller's unit table is not a fresh kbool.sh's" ]] && ! ls "$IMGD"/ia-*.img >/dev/null 2>&1
uf_check "a caller whose unit table is not a fresh kbool.sh's: no image, a hold" $?
rm -f "$IMGD"/*

uf_run "$H; $FL"'; __KK_IMG_BGSYNC=1 KBOOL_IMAGE=off; kk.image --background ia 2>"$FX/e.txt"; echo "rc=$? ${__KK_UNIT_PID[ia]+normal}"; fl ""'
[[ $UF_OUT == "rc=0 normal"$'\n'"kbool: image: KBOOL_IMAGE=off; a normal load (kk.uses ia)" && -z $(ls -A "$IMGD") ]]
uf_check "KBOOL_IMAGE=off: a plain load, nothing in the image folder, no writer" $?

uf_run "$H; $FL"'; __KK_IMG_BGSYNC=1; kk.uses ib; kk.image --background ia 2>"$FX/e.txt"; echo "rc=$? ${__KK_UNIT_PID[ia]+normal}"; fl "background"'
[[ $UF_OUT == "rc=0 normal"$'\n'"kbool: image: no image "*": a normal load (kk.uses ia); no background writer: a prior set is loaded (ib): --background writes no chained image" && -z $(ls -A "$IMGD") ]]
uf_check "a prior set P (kk.uses ib first): a plain load, no background writer, nothing written" $?

uf_run "$H"'; kk.image --background --rebuild ia; echo "rc=$?"; kk.image --path --background ia; echo "rc=$?"'
[[ $UF_OUT == *"only one of --rebuild, --forget, --path, --background"*"rc=2"*"only one of --rebuild, --forget, --path, --background"*"rc=2" ]]
uf_check "--background with --rebuild / --path: rc 2 (usage)" $?

# ---------------------------------------------------------------------------
kt_test_section "029: --forget and pruning take the marker"

uf_run 'source "$FX/kbool.sh" || exit 9; kk.image --path ia'
MK=${UF_OUT%.img}.bg
printf '%s tok - x -\n' "$EPOCHSECONDS" > "$MK"
uf_run "$H"'; kk.image --forget ia'
[[ ! -e $MK ]]
uf_check "--forget removes the request's marker" $?
printf '%s tok - x -\n' $(( EPOCHSECONDS - 700 )) > "$IMGD/zz-0000abcd.bg"
printf '%s tok - x -\n' $(( EPOCHSECONDS - 10 )) > "$IMGD/zz-0000abce.bg"
printf 'garbage\n' > "$IMGD/zz-0000abcf.bg"
uf_run "$H"'; __KK_IMG_BGSYNC=1; kk.image --background ib 2>/dev/null'
[[ ! -e $IMGD/zz-0000abcd.bg && -e $IMGD/zz-0000abce.bg && ! -e $IMGD/zz-0000abcf.bg ]] && ls "$IMGD"/ib-*.img >/dev/null 2>&1
uf_check "pruning (on a write): a marker older than 10 minutes and an unreadable one removed, a young one kept" $?
rm -f "$IMGD"/*

# ---------------------------------------------------------------------------
kt_test_section "029: no writer left"
bg_guard
kt_test_start "every background writer of this file ended (none killed by the guard)"
if [[ -z $BG_LEFT ]]; then kt_test_pass ok; else kt_test_fail "leftover writer(s):$BG_LEFT"; fi
BG_LEFT="" BG_SEEN=()

kt_test_log "029_ImageBackground.sh completed"
