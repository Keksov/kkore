#!/usr/bin/env bash
# ImageStart — the image start of kk.image (kklass/docs/dev/IMAGE_PLAN.md §7.2,
# §8.3, §9; stage I2a-1): staleness (`dates`: a stamped file newer than the
# reference file; a dependency edge resolving elsewhere), the undo of a
# truncated image (under a caller's set -eu: the script survives, the state is
# a normal load's), a failing hook on start (undo, then the unit's own error
# and rc), a readonly collision (a plain load), the hook-run guard on start
# (kk._image_hook: no unit loads inside a hook), no fork on a hit, the writer's
# refusals (an export, a trap, a changed variable, a redefined function, a
# failed load, a CR function the parser would drop). Fixture: image_fixture.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImageStart" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9'
# D = the debug lines of kk.image only (VERBOSE_KKLASS=debug in the key)
D='VERBOSE_KKLASS=debug'
# FL: fl TEXT = the first line of $FX/e.txt holding TEXT (kk.image's stderr
# kept in a file: in a pipeline it would run in a subshell)
FL='fl() { local l; while IFS= read -r l; do [[ $l == *"$1"* ]] && { echo "$l"; return 0; }; done < "$FX/e.txt"; return 0; }'

# ---------------------------------------------------------------------------
kt_test_section "022: staleness (dates, §7.6) and dependency edges (§7.2)"

uf_run "$H; $D"'; kk.image ia 2>/dev/null'
uf_run "$H; $D"'; kk.image ia 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: loaded from $FX/img/ia-"*".img" ]]
uf_check "the fixture image hits" $?
REF0=$(cat "$FX"/img/ia-*.ref)
# (each image aged by an hour first: one written less than 10 minutes before
# that is stale again gets a hold instead of a rewrite — 024_ImageHolds.sh)
age() { local f; for f in "$FX"/img/*.img; do if_age "$f" 3600; done; }
age
touch "$FX/kcl/ib/ib.sh"
uf_run "$H; $D"'; kk.image ia 2>&1 | grep -v "writer profile"'
[[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh changed after the image was made: a normal load, then an image"$'\n'"kbool: image: wrote $FX/img/ia-"*".img" ]]
uf_check "a dependency's file edited (newer than NAME.ref): stale, a normal load, the image written again" $?
uf_run "$H; $D"'; kk.image ia 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: loaded from $FX/img/ia-"*".img" && $(cat "$FX"/img/ia-*.ref) != "$REF0" ]]
uf_check "the rewritten image hits; its reference nonce is new" $?
age
touch "$FX/kkore/kimage.sh"
uf_run "$H; $D"'; kk.image ia 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: stale: $FX/kkore/kimage.sh changed"* ]]
uf_check "kkore/kimage.sh edited: stale (kbool.sh, kkore and kklass.sh are stamped too) [§7.1, H3]" $?
touch -t 202001010000 "$FX/kkore/kimage.sh"
mv "$FX/kcl/ib/ib.sh" "$FX/ib.keep"
age
uf_run "$H; $D; $FL"'; kk.image ia 2>"$FX/e.txt"; fl "stale"'
mv "$FX/ib.keep" "$FX/kcl/ib/ib.sh"
[[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh is missing: a normal load, then an image" && -f $(echo "$FX"/img/ia-*.hold) ]]
uf_check "a stamped file removed: stale (the load then fails: kk.uses' own error, and a hold)" $?
rm -f "$FX"/img/*.hold
uf_run "$H; $D"'; kk.image ia 2>/dev/null'
uf_run "$H; $D"'; kk.image ia 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: loaded from $FX/img/ia-"*".img" ]]
uf_check "an edited file dated back (cp -p, an old archive) is not seen by dates — the documented blind spot (§7.6, R15; KBOOL_VERSION is keyed for releases)" $?
age
printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%ib.sh}../../kbool.sh" || return' \
    'kk.unit ib || return $__kk_unit_rc' 'ib.f() { echo "shadow ib.f"; }' 'IB_V=shadow' > "$FX/kcl/ia/ib.sh"
touch -t 202001010000 "$FX/kcl/ia/ib.sh"
uf_run "$H; $D; $FL"'; kk.image ia 2>"$FX/e.txt"; fl ""; ib.f'
[[ $UF_OUT == "kbool: image: stale: the dependency 'ib' (used from $FX/kcl/ia) resolves to another file now: a normal load, then an image"$'\n'"shadow ib.f" ]]
uf_check "a dependency shadowed in its user's folder (ia uses ib: kcl/ia/ib.sh appears): the edge differs, a normal load takes the new file [§7.2, M1]" $?
age
rm -f "$FX/kcl/ia/ib.sh"
uf_run "$H; $D; $FL"'; kk.image ia 2>"$FX/e.txt"; fl ""; ib.f'
[[ $UF_OUT == "kbool: image: stale: "*$'\n'"ib.f" ]]
uf_check "the shadow removed again: the image of the shadowed load is not used either" $?

# ---------------------------------------------------------------------------
kt_test_section "022: a damaged image: undo, then a normal load (§8.3, IMG-D8)"

cat > "$FX/st.sh" <<'EOF'
# st.sh MODE FILE — kk.image ia under set -eu, then the state dump (in this process)
source "$FX/kbool.sh" || exit 9
set -eu
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image ia; else kk.image ia; fi
echo "survived rc=$? pid=${__KK_UNIT_PID[ia]+normal} f=$(ia.f)"
set +eu
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
kk._img_state "$2" canon
EOF
rm -f "$FX"/img/*
uf_run 'bash "$FX/st.sh" miss "$FX/s0.d"; bash "$FX/st.sh" plain "$FX/plain.d"; :'
for f in "$FX"/img/ia-*.img; do IMG=$f; done
for REFN in "${IMG%.img}".*.ref; do :; done     # (NAME.NONCE.ref)
cp "$IMG" "$FX/img.full"; cp "$REFN" "$FX/ref.full"
SZ=$(( $(wc -c < "$IMG") ))
IFS= read -r L1 < "$IMG"
HL=$(( ${#L1} + 1 + ${L1##* } ))          # line 1 + the header it measures
for cut in body last; do
    # (a cut inside the header is another case: a miss, the image written again;
    # the image is new: undone, then a hold and the image removed — 024)
    cp "$FX/ref.full" "$REFN"; rm -f "$FX"/img/*.hold
    if [[ $cut == body ]]; then
        head -c $(( HL + (SZ - HL) / 2 )) "$FX/img.full" > "$IMG"
    else                                   # the last line (the end mark) dropped
        IFS= read -r -d '' z < "$FX/img.full" || :
        z=${z%$'\n'}
        printf '%s\n' "${z%$'\n'*}" > "$IMG"
    fi
    uf_run 'bash "$FX/st.sh" hit "$FX/s1.d" 2>&1; bash "$FX/cmp.sh" "$FX/plain.d" "$FX/s1.d"'
    [[ $UF_OUT == 'survived rc=0 pid=normal f=ia.f a b "q" $x 4 v 2 7'$'\n'"cmp rc=0 " ]]
    uf_check "an image truncated ($cut): undone, then a normal load under set -eu — the script survives, the state equals a normal load's [§8.3]" $?
done
cp "$FX/img.full" "$IMG"; cp "$FX/ref.full" "$REFN"; rm -f "$FX"/img/*.hold
uf_run 'bash "$FX/st.sh" hit "$FX/s2.d"; bash "$FX/cmp.sh" "$FX/plain.d" "$FX/s2.d"'
[[ $UF_OUT == 'survived rc=0 pid= f=ia.f a b "q" $x 4 v 2 7'$'\n'"cmp rc=0 " ]]
uf_check "the whole image again: a hit under set -eu, the state a normal load's" $?
printf 'garbage(\n' >> "$IMG"
uf_run 'bash "$FX/st.sh" hit "$FX/s3.d"; bash "$FX/cmp.sh" "$FX/plain.d" "$FX/s3.d"'
[[ $UF_OUT == 'survived rc=0 pid=normal f=ia.f a b "q" $x 4 v 2 7'$'\n'"cmp rc=0 " ]]
uf_check "a syntax error after the end mark: undone (the source fails), a normal load" $?
cp "$FX/img.full" "$IMG"; cp "$FX/ref.full" "$REFN"; rm -f "$FX"/img/*.hold

# ---------------------------------------------------------------------------
kt_test_section "022: the written image reads back to the same state (associative keys)"

# (the simulation replays the hooks but never sources the image; this case
# does: every key byte 0x80-0xFF and ] \ * @ " $ ` ' space [ ~ ! = — bash 5.1
# read a key `@` written into a subscript as "every element", CI 45467673135)
cat > "$FX/ak.sh" <<'EOF'
source "$FX/kbool.sh" || exit 9
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image iak; else kk.image iak; fi
echo "$1 rc=$? ${__KK_UNIT_PID[iak]-image} $(iak.n)"
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
kk._img_state "$2" canon
EOF
uf_run 'bash "$FX/ak.sh" miss "$FX/ak0.d"; bash "$FX/ak.sh" hit "$FX/ak1.d"; bash "$FX/ak.sh" plain "$FX/ak2.d"; bash "$FX/cmp.sh" "$FX/ak2.d" "$FX/ak1.d"'
W='n=281 at=v@ star=v* br=v] ff=2'
[[ $UF_OUT == "miss rc=0 "?*" $W"$'\n'"hit rc=0 image $W"$'\n'"plain rc=0 "?*" $W"$'\n'"cmp rc=0 " && $UF_OUT != "miss rc=0 image"* ]]
uf_check "281 associative keys (every high byte, the subscript specials, control bytes) round-trip: the hit reads them as written, its state equals a normal load's" $?
for f in "$FX"/img/iak-*.img; do IAK=$f; done
IFS= read -r -d '' z < "$IAK" || :
[[ $z == *'__kk_img_k=('*'for __kk_img_i in "${!__kk_img_k[@]}"; do IAK_M[${__kk_img_k[__kk_img_i]}]=${__kk_img_v[__kk_img_i]}; done'* \
   && $z != *'IAK_M[@]='* && $z != *'IAK_M[\*]='* ]]
uf_check "keys that are not plain go through the loop form (never \`X[@]=\` / \`X[\\*]=\` in the image)" $?

# variables declared without a value (image I3, found by kcl 011: fv.views'
# `declare -gA __FV_VW_LIVE …` and kklass's class tables): compgen -v does
# not list them — the writer left them out of the image and the dump out of
# every compare, so after a hit `IUV_A[key]=v` made an INDEXED array (fv.dlg:
# every view a "live view") and `IUV_N+=7` a string append. The hit declares
# them again without a value: the same kinds and attributes, still no value
# (listed by the dump: kk._img__inv), and the first use works as after a
# normal load
cat > "$FX/uv.sh" <<'EOF'
source "$FX/kbool.sh" || exit 9
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image iuv; else kk.image iuv; fi
r=$?
echo "$1 rc=$r ${__KK_UNIT_PID[iuv]-image} $(declare -p IUV_A IUV_X IUV_N IUV_S IUV_R | tr '\n' '|') fake=${IUV_FAKE@a}${IUV_FAKE-none}"
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
unset r
kk._img_state "$2" canon
# (the dump half, I3 fix 1 critic M4: the canon dump lists them, by their records)
IFS= read -r -d '' d < "$2" || :
[[ $d == *$'\n''declare -A IUV_A'$'\n'* && $d == *$'\n''declare -i IUV_N'$'\n'* && $d == *$'\n''declare -n IUV_R'$'\n'* && $d != *'declare -a IUV_FAKE'$'\n'* ]] && echo "dump=listed" || echo "dump=missing"
unset d
iuv.f
EOF
uf_run 'bash "$FX/uv.sh" miss "$FX/uv0.d"; bash "$FX/uv.sh" hit "$FX/uv1.d"; bash "$FX/uv.sh" plain "$FX/uv2.d"; bash "$FX/cmp.sh" "$FX/uv2.d" "$FX/uv1.d"'
W='declare -A IUV_A|declare -a IUV_X|declare -i IUV_N|declare -- IUV_S|declare -n IUV_R| fake=none'$'\n''dump=listed'$'\n''A=v N=8 kind=A'
[[ $UF_OUT == "miss rc=0 "?*" $W"$'\n'"hit rc=0 image $W"$'\n'"plain rc=0 "?*" $W"$'\n'"cmp rc=0 " && $UF_OUT != "miss rc=0 image"* ]]
uf_check "variables declared without a value (declare -gA / -ga / -gi / -g / -gn): a hit declares them again without a value (the same kinds and attributes — a nameref stays one; a normal load's state; the canon dump lists them), the first use makes an associative array and integer arithmetic as after a normal load; a value line 'declare -a IUV_FAKE' (a line of its own on bash 5.1) makes no variable [I3, I3 fix 1 M2 M4 L1]" $?
for f in "$FX"/img/iuv-*.img; do IUV=$f; done
IFS= read -r -d '' z < "$IUV" || :
[[ $z == *$'\n''declare -gA IUV_A'$'\n'* && $z == *$'\n''declare -gi IUV_N'$'\n'* && $z == *$'\n''declare -ga IUV_X'$'\n'* \
   && $z == *$'\n''declare -g IUV_S'$'\n'* && $z == *$'\n''declare -gn IUV_R'$'\n'* && $z != *'IUV_A=()'* \
   && $z != *IUV_FAKE$'\n'* ]]
uf_check "(the image declares them without a value — the nameref as one —, never as an empty \`X=()\`, and no IUV_FAKE)" $?

# `1<> FILE` (image I3, found by kcl 010 on Cygwin bash 5.2: TFile.encrypt):
# bash 5.2's declare -f prints it as `<> FILE`, which reads back as fd 0 — an
# image would write to stdin. Probed (kk._img__rwbug): such a bash writes no
# image (a hold, the reason named), any other one writes it and its start
# keeps `1<>`; irw.f's file is "Xb" after a hit and after a normal load
cat > "$FX/rw.sh" <<'EOF'
source "$FX/kbool.sh" || exit 9
VERBOSE_KKLASS=debug
kk.image irw 2>"$FX/rw.err"
r=$?
irw.f "$FX/rw.dat" > "$FX/rw.out"
IFS= read -r d < "$FX/rw.dat"
f=$(declare -f irw.f)
case $f in *" 1<> "*) k=fd1 ;; *" 0<> "*) k=fd0 ;; *" <> "*) k=bare ;; *) k=? ;; esac
echo "$1 rc=$r ${__KK_UNIT_PID[irw]-image} file=$d out=$(< "$FX/rw.out") $k"
w=""; while IFS= read -r l; do case $l in *"no image written: "*) w="nowrite: ${l#*no image written: }" ;; *"image: wrote "*) w=wrote ;; *"loaded from "*) w=loaded ;; esac; done < "$FX/rw.err"
echo "$w"
EOF
uf_run 'bash "$FX/rw.sh" miss; bash "$FX/rw.sh" start'
eval 'rwp() { : 1<> /dev/null; }'
if [[ $(declare -f rwp) == *'1<>'* ]]; then
    [[ $UF_OUT == "miss rc=0 "[0-9]*" file=Xb out= fd1"$'\n'"wrote"$'\n'"start rc=0 image file=Xb out= fd1"$'\n'"loaded" ]]
    uf_check "a function with \`1<> FILE\` on a bash that prints it back: the image keeps \`1<>\`, irw.f writes over its file after a hit as after a normal load [I3]" $?
else
    [[ $UF_OUT == "miss rc=0 "[0-9]*" file=Xb out= bare"$'\n'"nowrite: bash $BASH_VERSION prints \`1<> FILE\` as \`<> FILE\`"*$'\n'"start rc=0 "[0-9]*" file=Xb out= bare"* ]] \
        && compgen -G "$FX/img/irw-*.hold" >/dev/null && ! compgen -G "$FX/img/irw-*.img" >/dev/null
    uf_check "a function with \`1<> FILE\` on a bash that prints it as \`<> FILE\` (5.2): no image, a hold naming why; the starts are normal loads, irw.f writes over its file [I3]" $?
fi
unset -f rwp

# ---------------------------------------------------------------------------
kt_test_section "022: hooks on start (§5.2, §8.3; the hook-run guard, I1a L9)"

uf_run "$H"'; kk.image ihf; echo "rc=$?"'
uf_run "$H"'; IHF_FAIL=1; kk.image ihf; echo "rc=$? ${__KK_UNITS[ihf]-not-registered} ${IHF_OK-unset}"'
A=$UF_OUT
uf_run "$H"'; IHF_FAIL=1; KBOOL_IMAGE=off kk.image ihf; echo "rc=$? ${__KK_UNITS[ihf]-not-registered} ${IHF_OK-unset}"'
[[ $A == "kbool: error: kk.uses: loading unit 'ihf' failed (rc=5)"$'\n'"rc=5 not-registered unset" && $A == "$UF_OUT" ]]
uf_check "a hook failing on start: the image undone, then the normal load — the unit's own error and rc, the same as without an image" $?

uf_run "$H"'; kk.image ihg'
uf_run "$H"'; IHG_EVIL=1; kk.image ihg; echo "rc=$? uses=$IHG_USES src=$IHG_SRC ib2=${IB2_LOADED-no} ib3=${IB3_LOADED-no} ${__KK_UNITS[ib2]-}${__KK_UNITS[ib3]-}"'
[[ $UF_OUT == "kbool: error: kk.uses ib2: a settings hook may not load units (inside the hook ihg._s of unit 'ihg')"$'\n'"kbool: error: kk.unit ib3: a settings hook may not load units (inside the hook ihg._s of unit 'ihg'; in "*")"$'\n'"rc=0 uses=2 src=2 ib2=no ib3=no " ]]
uf_check "the hooks of an image start run marked (kk._image_hook): a kk.uses or a source loading a unit inside one is refused with kk.settings' message [I1a L9]" $?
uf_run "$H"'; kk.image ihg; IHG_EVIL=1; ihg._s; echo "uses=$IHG_USES ib2=${IB2_LOADED-no}"'
[[ $UF_OUT == "uses=0 ib2=1" ]]
uf_check "(the same hook called outside any hook run loads ib2: the guard is the mark, not the hook)" $?

uf_run "$H; $D"'; kk.image iro 2>/dev/null'
uf_run "$H; $D"'; readonly IRO_C=1; kk.image iro 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: 'IRO_C' exists in this shell already (r): the image would write into it; a normal load (kk.uses iro)" ]]
uf_check "a name the image assigns is readonly in the caller: a plain load, no image read or written [§8.3]" $?
uf_run "$H"'; readonly IRO_C=1; kk.image iro; echo "rc=$? c=$IRO_C v=$IRO_V"'
[[ $UF_OUT == "rc=0 c=1 v=2" ]]
uf_check "(the unit loads normally: its readonly guard keeps the caller's constant)" $?

# ---------------------------------------------------------------------------
kt_test_section "022: no fork on a hit (§9)"

uf_run "$H"'; kk.image ia'
uf_run "$H"'; exec 8>"$FX/fk.trace"; BASH_XTRACEFD=8; PS4='"'"'+${BASHPID}|'"'"'; printf "MAIN=%s\n" "$BASHPID" >&8; set -x; kk.image ia; set +x; unset BASH_XTRACEFD; echo "pid=${__KK_UNIT_PID[ia]+normal}"'
forks=0 lines=0 main="" src=0
while IFS= read -r line; do
    case $line in MAIN=*) main=${line#MAIN=}; continue ;; +*) ;; *) continue ;; esac
    p=${line%%|*}; p=${p##*+}
    [[ -n $p && $p != *[!0-9]* ]] || continue
    lines=$(( lines + 1 ))
    [[ $line == *"source "*".img"* ]] && src=1
    [[ $p == "$main" ]] || forks=$(( forks + 1 ))
done < "$FX/fk.trace"
[[ $UF_OUT == "pid=" && -n $main && $lines -gt 50 && $src == 1 && $forks == 0 ]]
uf_check "an image start (key, trust, header, edges, stamps, readonly check, source, hooks) runs in ONE process: 0 forks over $lines traced commands" $?

# ---------------------------------------------------------------------------
kt_test_section "022: no image (the refusals of I2a-1, §6.3)"

declare -A RF=(
    [iex]="the load exported IEX_V outside the settings hooks"
    [itr]="the load changed the shell state: trap"
    [ichg]="the load changed the existing variable ICHG_V outside the settings hooks"
    [ifn]="the load redefined an existing function"
    [ifail]="the load failed (rc 3)"
)
for u in iex itr ichg ifn ifail; do
    uf_run "$H; $D"'; ICHG_V=orig; userfn() { echo mine; }; kk.image '"$u"' 2>&1 | grep "no image written"; '"$D"' kk.image '"$u"' 2>/dev/null; echo "rc=$?"'
    if_imgs
    [[ $UF_OUT == "kbool: image: no image written: ${RF[$u]}"$'\n'"rc="* && $IF_IMGS != *"$u-"* ]]
    uf_check "unit $u: no image (${RF[$u]}); the units stay loaded with kk.uses' rc" $?
done

cr=$(printf '\r')
eval "probe='$cr'"
if [[ -z $probe ]]; then
    uf_run "$H; $D; $FL"'; kk.image icr 2>"$FX/e.txt"; fl "no image written"; icr.f'
    [[ $UF_OUT == "kbool: image: no image written: a function text holds a CR byte this parser drops, and kklass (kk._fn_text_cr) is not loaded"$'\n'"cr=1" ]]
    uf_check "a function with a CR byte on a CR-dropping parser without kklass: no image (it would lose the CR); the function works [§6.4]" $?
else
    uf_run "$H; $D"'; kk.image icr 2>/dev/null'
    uf_run "$H; $D; $FL"'; kk.image icr 2>"$FX/e.txt"; fl ""; icr.f'
    [[ $UF_OUT == "kbool: image: loaded from "*$'\n'"cr=1" ]]
    uf_check "a function with a CR byte on a parser that keeps CR: imaged as it is; the CR survives the start [§6.4]" $?
fi

kt_test_log "022_ImageStart.sh completed"
