#!/usr/bin/env bash
# ImageHolds — the holds of kk.image (kklass/docs/dev/IMAGE_PLAN.md §7.5;
# stage I2a-2): NAME.hold after a refusal, after an image written less than
# 10 minutes before is stale again (the repeat-miss guard, H2) or fails on its
# start (undone: no undo on every start); while younger than an hour every
# start is a plain kk.uses with no write; age-out; --rebuild / --forget clear
# (021_Image.sh). And the damage matrix (§8.3, IMG-D8) under a caller's
# `set -e` and, separately, `set -u`: a truncation in each section, an empty
# file, a binary file, another key's image under this name, format v2 — the
# script survives, the state equals a normal load's, the image is written
# again (or, when it was written less than 10 minutes before, a hold).
# Fixture: image_fixture.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImageHolds" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9; VERBOSE_KKLASS=debug'
FL='fl() { local l; while IFS= read -r l; do [[ $l == *"$1"* ]] && { echo "$l"; return 0; }; done < "$FX/e.txt"; return 0; }'
# (the dates mode everywhere: the holds and the damage do not depend on it)

# ---------------------------------------------------------------------------
kt_test_section "024: the repeat-miss guard (H2) and the age-out"

uf_run "$H"'; kk.image ia 2>/dev/null'
for f in "$FX"/img/ia-*.img; do IMG=$f; done
HOLD=${IMG%.img}.hold
touch "$FX/kcl/ib/ib.sh"
uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl ""; echo "rc=$? ${__KK_UNIT_PID[ia]+normal}"'
[[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh changed after the image was made; the image was written "*" s ago: a hold for an hour; a normal load (kk.uses ia)"$'\n'"rc=0 normal" \
   && -f $HOLD ]]
uf_check "an image written less than 10 minutes before is stale again: a plain load and NAME.hold, no rewrite [§7.5, H2]" $?
R=$(cat "$HOLD")
[[ $R == [0-9]*" an image written less than 10 minutes before was stale again" ]]
uf_check "the hold is one line: TIME REASON" $?
uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl ""'
[[ $UF_OUT == "kbool: image: stale: "*"; held (an image written less than 10 minutes before was stale again, "*" s ago); a normal load (kk.uses ia)" ]]
uf_check "the next start: held (the stale image stays, nothing written)" $?
printf '%s %s\n' $(( EPOCHSECONDS - 3700 )) "old" > "$HOLD"
if_age "$IMG" 3700
uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl "stale"; fl "wrote"'
[[ $UF_OUT == "kbool: image: stale: "*": a normal load, then an image"$'\n'"kbool: image: wrote $IMG" ]]
uf_check "a hold older than an hour no longer counts: the miss writes (an image written an hour before)" $?
if_age "$IMG" 3600
touch "$FX/kcl/ib/ib.sh"
uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl "wrote"'
[[ $UF_OUT == "kbool: image: wrote $IMG" ]]
uf_check "a stale image written more than 10 minutes before: rewritten (no hold)" $?
rm -f "$FX"/img/*

# ---------------------------------------------------------------------------
kt_test_section "024: a refusal leaves a hold (§6.3, §7.5)"

uf_run "$H"'; kk.image itr 2>&1 | grep "no image written\|held for"'
[[ $UF_OUT == "kbool: image: no image written: the load changed the shell state: trap"$'\n'"kbool: image: held for an hour: $FX/img/itr-"*".hold" ]]
uf_check "a refusal (a trap): no image, a hold" $?
uf_run "$H; $FL"'; kk.image itr 2>"$FX/e.txt"; fl ""; trap -p USR1'
[[ $UF_OUT == "kbool: image: no image "*"; held (the load changed the shell state: trap, "*" s ago); a normal load (kk.uses itr)"$'\n'"trap -- ':' SIGUSR1" ]]
uf_check "the next start: held — a plain kk.uses (the unit's trap is set), no writer run" $?
uf_run "$H"'; kk.image --rebuild itr 2>&1 | grep -c "held for"'
[[ $UF_OUT == 1 ]]
uf_check "--rebuild of a start that refuses again: the hold is written again" $?
rm -f "$FX"/img/*

# ---------------------------------------------------------------------------
kt_test_section "024: an undone start: rewritten, or held when the image is new (§8.3)"

uf_run "$H"'; kk.image ihf 2>/dev/null'
for f in "$FX"/img/ihf-*.img; do IMG=$f; done
uf_run "$H; $FL"'; IHF_FAIL=1 kk.image ihf 2>"$FX/e.txt"; echo "rc=$?"; fl "undone"; fl "hold"'
[[ $UF_OUT == "rc=5"$'\n'"kbool: image: the settings hook ihf._s of unit 'ihf' failed; undone"$'\n'"kbool: image: the settings hook ihf._s of unit 'ihf' failed; the image was written "*" s ago: a hold for an hour; a normal load (kk.uses ihf)" \
   && -f ${IMG%.img}.hold ]]
uf_check "a start that fails (a hook) on an image written less than 10 minutes before: undone, a plain load (the unit's rc 5), a hold — not undone again on every start" $?
rm -f "$FX"/img/*.hold
uf_run "$H"'; kk.image --rebuild ihf 2>/dev/null'
if_age "$IMG" 3600
uf_run "$H; $FL"'; IHF_FAIL=1 kk.image ihf 2>"$FX/e.txt"; echo "rc=$?"; fl "then an image"; fl "no image written"'
[[ $UF_OUT == "rc=5"$'\n'"kbool: image: the settings hook ihf._s of unit 'ihf' failed: a normal load, then an image"$'\n'"kbool: image: no image written: the load failed (rc 5)" ]]
uf_check "the same on an older image: undone, then the writer (a rewrite — here the load fails too: no image, a hold)" $?
rm -f "$FX"/img/*

# ---------------------------------------------------------------------------
kt_test_section "024: the damage matrix under set -e and under set -u (§8.3, IMG-D8)"

cat > "$FX/st.sh" <<'EOF'
# st.sh MODE OPT FILE — kk.image ia under `set OPT`, then the state dump
source "$FX/kbool.sh" || exit 9
set "$2"
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image ia; else kk.image ia; fi
echo "survived rc=$? pid=${__KK_UNIT_PID[ia]+normal} f=$(ia.f)"
set +eu
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
kk._img_state "$3" canon
EOF
uf_run 'bash "$FX/st.sh" miss -e "$FX/s0.d"; bash "$FX/st.sh" plain -e "$FX/plain.d"; :'
for f in "$FX"/img/ia-*.img; do IMG=$f; done
for REF in "${IMG%.img}".*.ref; do :; done     # (NAME.NONCE.ref)
cp "$IMG" "$FX/img.full"
cp "$REF" "$FX/ref.full"
# another key's image: ib's (written by KBOOL_IMAGE_CHECK=dates kk.image ib)
uf_run 'source "$FX/kbool.sh"; kk.image ib'
for f in "$FX"/img/ib-*.img; do OTHER=$f; done
IFS= read -r -d '' Z < "$FX/img.full" || :
# off MARK -> OFF: the byte offset of MARK in the image, plus 4
off() { local LC_ALL=C p=${Z%%"$1"*}; OFF=$(( ${#p} + 4 )); }
IFS= read -r L1 < "$FX/img.full"
for opt in -e -u; do
    for case in header functions variables final registration hooks end empty binary otherkey v2; do
        cp "$FX/img.full" "$IMG"
        cp "$FX/ref.full" "$REF"
        rm -f "$FX"/img/*.hold
        case $case in
            header)       head -c $(( ${#L1} + 40 )) "$FX/img.full" > "$IMG" ;;
            functions)    off 'ia.f ()'; head -c "$OFF" "$FX/img.full" > "$IMG" ;;
            variables)    off 'declare -g'; head -c "$OFF" "$FX/img.full" > "$IMG" ;;
            final)        off $'\nreadonly '; head -c "$OFF" "$FX/img.full" > "$IMG" ;;
            registration) off '__KK_UNITS['; head -c "$OFF" "$FX/img.full" > "$IMG" ;;
            hooks)        off '__kk_img_hooks='; head -c "$OFF" "$FX/img.full" > "$IMG" ;;
            end)          off '__kk_img_end='; head -c $(( OFF + 6 )) "$FX/img.full" > "$IMG" ;;
            empty)        : > "$IMG" ;;
            binary)       printf '\0\1\2\377\376 kbool\0\n\r\n' > "$IMG" ;;
            otherkey)     cp "$OTHER" "$IMG" ;;
            v2)           printf '%s\n' "# kbool image v2 1" "x" > "$IMG"; tail -n +2 "$FX/img.full" >> "$IMG" ;;
        esac
        [[ $case == empty || $case == binary || $case == v2 || $case == header ]] || if_age "$IMG" 3600
        uf_run 'bash "$FX/st.sh" hit '"$opt"' "$FX/s1.d" 2>&1; bash "$FX/cmp.sh" "$FX/plain.d" "$FX/s1.d"; source "$FX/kbool.sh"; kk.image --path ia >/dev/null; echo "valid=$?"'
        [[ $UF_OUT == 'survived rc=0 pid=normal f=ia.f a b "q" $x 4 v 2 7'$'\n'"cmp rc=0 "$'\n'"valid=0" ]]
        uf_check "set $opt, $case: the script survives, the state equals a normal load's, the image is valid again" $?
    done
done
# a new damaged image (written less than 10 minutes before): undone once, then
# a hold, and the image removed (not sourced and undone on every start)
rm -f "$FX"/img/*.hold
uf_run 'source "$FX/kbool.sh"; kk.image --rebuild ia'
for REF in "${IMG%.img}".*.ref; do :; done
[[ -f $REF ]] || { kt_test_start "the rebuilt image's .ref"; kt_test_fail "none"; }
cp "$IMG" "$FX/img.full"
IFS= read -r -d '' Z < "$FX/img.full" || :
off '__KK_UNITS['; head -c "$OFF" "$FX/img.full" > "$IMG"
uf_run 'bash "$FX/st.sh" hit -e "$FX/s1.d" 2>&1; bash "$FX/cmp.sh" "$FX/plain.d" "$FX/s1.d"'
[[ $UF_OUT == 'survived rc=0 pid=normal f=ia.f a b "q" $x 4 v 2 7'$'\n'"cmp rc=0 " && -f ${IMG%.img}.hold && ! -e $IMG && ! -e $REF ]]
uf_check "a damaged image written less than 10 minutes before: the script survives with a normal load's state; a hold, the image and its .ref removed, no rewrite" $?
uf_run 'source "$FX/kbool.sh"; set -e; kk.image ia 2>&1; echo "survived ${__KK_UNIT_PID[ia]+normal}"'
[[ $UF_OUT == "survived normal" ]]
uf_check "the next start under set -e: held, a plain load, silent" $?

kt_test_log "024_ImageHolds.sh completed"
