#!/usr/bin/env bash
# ImagePrune — the image folder over time (kklass/docs/dev/IMAGE_PLAN.md
# §7.4; stage I2a-2): pruning on each write (images whose KBOOL_HOME is gone —
# this runtime's only —, older than 30 days, unreadable; beyond 8 per (request,
# prior set), 16 per request name, __KK_IMG_MAXN (64) or __KK_IMG_MAXB bytes
# (256 MB, lowered here) per folder — the oldest; orphan .ref files, the .ref
# and .hold of a pruned image, holds older than an hour, temps of this
# runtime whose pid is gone), with ONE rm (counted by a logging rm on PATH);
# the writer's temps on every exit path (a failing load under set -e, an
# `exit` in a unit) and a writer killed midway (its temps pruned later); two
# writers at once; a reader holding the image open across the rename; a
# rename that fails (a native holder: a stand-in mv) — silent, the old image
# kept. Fixture: image_fixture.sh; the fake images carry only the two lines
# pruning reads.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImagePrune" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9'
US=$'\x1f'
REAL_BASH=$BASH
if_unit "$FX" ikill <<'EOF'
IKILL_V=1
kill -KILL "$BASHPID"
EOF
if_unit "$FX" iexit <<'EOF'
exit 4
EOF
touch -t 202001010000 "$FX"/kcl/*/*.sh

# fake NAME WTIME [SIZE [TAG [HOME [PRIOR]]]] — an image file with the two
# lines pruning reads (line 1, the plain line); default TAG = this runtime's
fake() {
    local p
    printf -v p '#P%s%s%s%012d%s%s%s%s%s%s%sdates%s-%s0' "$US" "$2" "$US" "${3:-100}" "$US" "${4:-$TAG}" "$US" "${5:-$FX}" \
        "$US" "${6-}" "$US" "$US" "$US"
    printf '# kbool image v1 %s\n%s\n' "$(( ${#p} + 1 ))" "$p" > "$FX/img/$1"
}
# left PATTERN… -> LEFT: the basenames in img/ matching the globs (sorted)
left() {
    local f p
    LEFT=""
    for f in "$FX"/img/*; do
        for p; do [[ ${f##*/} == $p ]] && { LEFT+="${f##*/} "; break; }; done
    done
    LEFT=${LEFT% }
}
# lb/: a logging rm and mv on PATH (each call appended to $FX/calls)
mkdir -p "$FX/lb"
for t in rm mv; do
    printf '#!%s\nprintf "%s\\n" >> %q\nexec %q "$@"\n' "$REAL_BASH" "$t" "$FX/calls" "$(type -P "$t")" > "$FX/lb/$t"
    chmod +x "$FX/lb/$t"
done

uf_run "$H"'; kk.image ib'
for f in "$FX"/img/ib-*.img; do IBIMG=$f; done
if_pfield "$IBIMG" 2; TAG=$IF_F
if_pfield "$IBIMG" 1; IBSIZE=$(( 10#$IF_F ))
[[ -n $TAG && $IBSIZE == $(( $(wc -c < "$IBIMG") )) ]]
kt_test_start "the plain line's size field is the image's byte count; the tag is this runtime's"
if (( $? == 0 )); then kt_test_pass "ok"; else kt_test_fail "tag='$TAG' size=$IBSIZE wc=$(( $(wc -c < "$IBIMG") ))"; fi

# ---------------------------------------------------------------------------
kt_test_section "025: the pruning rules (§7.4), one rm"

N=$EPOCHSECONDS
fake home-a1111111.img $(( N - 10 )) 100 "$TAG" "$FX/gone"
fake home-b2222222.img $(( N - 10 )) 100 other "$FX/gone"
fake old-a1111111.img $(( N - 31 * 86400 ))
fake old-b2222222.img $(( N - 29 * 86400 ))
printf 'garbage\n' > "$FX/img/junk-a1111111.img"
fake gone-a1111111.img $(( N - 31 * 86400 )); : > "$FX/img/gone-a1111111.ref"; printf '%s x\n' "$N" > "$FX/img/gone-a1111111.hold"
: > "$FX/img/orphan-a1111111.ref"
printf '%s young\n' $(( N - 60 )) > "$FX/img/young-a1111111.hold"
printf '%s old\n' $(( N - 4000 )) > "$FX/img/oldhold-a1111111.hold"
: > "$FX/calls"
uf_run "$H"'; PATH="$FX/lb:$PATH"; kk.image --rebuild ib; echo "rc=$?"'
left 'home-*' 'old-*' 'junk-*' 'gone-*' 'orphan-*' 'young-*' 'oldhold-*'
R=$(grep -c '^rm$' "$FX/calls")
[[ $UF_OUT == "rc=0" && $LEFT == "home-b2222222.img old-b2222222.img young-a1111111.hold" && $R == 1 ]]
uf_check "one write prunes: a gone KBOOL_HOME (this runtime's tag only), > 30 days, unreadable, the .ref/.hold of a pruned image, an orphan .ref, a hold > 1 h — with ONE rm ($R)" $?
rm -f "$FX"/img/home-* "$FX"/img/old-* "$FX"/img/young-*

for i in 1 2 3 4 5 6 7 8 9 10; do fake "zz-0000000$(( i % 10 )).img" $(( N - 1000 + i )); done
uf_run "$H"'; kk.image --rebuild ib'
left 'zz-*'
[[ $LEFT == "zz-00000000.img zz-00000003.img zz-00000004.img zz-00000005.img zz-00000006.img zz-00000007.img zz-00000008.img zz-00000009.img" ]]
uf_check "more than 8 images per (request, prior set): the 2 oldest go" $?
rm -f "$FX"/img/zz-*
o=0; for g in a b c; do for i in 1 2 3 4 5 6; do fake "zz-${g}000000$i.img" $(( N - 1000 + i * 10 + o )) 100 "$TAG" "$FX" "P$g"; done; o=$(( o + 1 )); done
fake "zz-a0000000.img" $(( N - 2000 )) 100 "$TAG" "$FX" Pa
uf_run "$H"'; kk.image --rebuild ib'
left 'zz-*'
n=0; for f in $LEFT; do n=$(( n + 1 )); done
[[ $n == 16 && $LEFT != *zz-a0000000.img* && $LEFT != *zz-a0000001.img* && $LEFT != *zz-b0000001.img* && $LEFT == *zz-c0000001.img* ]]
uf_check "19 images of one request in three prior sets (each <= 8): the request cap 16 takes the 3 oldest ($n left)" $?
rm -f "$FX"/img/zz-*
for i in 1 2 3 4 5 6; do fake "r$i-00000000.img" $(( N - 1000 + i )); done
uf_run "$H"'; __KK_IMG_MAXN=5; kk.image --rebuild ib'
left 'r?-*' 'ib-*.img'
[[ $LEFT == "ib-"*".img r3-00000000.img r4-00000000.img r5-00000000.img r6-00000000.img" ]]
uf_check "more than __KK_IMG_MAXN (lowered to 5) images in the folder: the oldest go, never the image just written" $?
rm -f "$FX"/img/r?-*
for i in 1 2 3 4; do fake "s$i-00000000.img" $(( N - 1000 + i )) 1000; done
uf_run "$H"'; __KK_IMG_MAXB='$(( IBSIZE + 2500 ))'; kk.image --rebuild ib'
left 's?-*'
[[ $LEFT == "s3-00000000.img s4-00000000.img" ]]
uf_check "more than __KK_IMG_MAXB bytes (lowered: the image + 2500; 256 MB by default) in the folder: the oldest go" $?
rm -f "$FX"/img/s?-*

# ---------------------------------------------------------------------------
kt_test_section "025: temps — every exit path, a killed writer"

uf_run "$H"'; set -e; kk.image ifail; echo "not reached"'
A="rc=$UF_RC"
uf_run "$H"'; kk.image iexit; echo "not reached"'
left '*.tmp.*'
[[ $A == "rc=3" && $UF_RC == 4 && -z $LEFT ]]
uf_check "a load failing under set -e (the script exits, rc 3) and a unit's exit (rc 4): the writer's temps are gone (its EXIT trap)" $?
uf_run 'source "$FX/kbool.sh"; trap "echo mine" EXIT; set -e; kk.image ifail'
[[ $UF_OUT == *"mine" && $UF_RC == 3 ]]
uf_check "the caller's own EXIT trap still runs after the writer's" $?
uf_run 'source "$FX/kbool.sh"; trap "echo mine" EXIT; kk.image ib; trap -p EXIT'
[[ $UF_OUT == "trap -- 'echo mine' EXIT"$'\n'"mine" ]]
uf_check "after a load the caller's EXIT trap is back as it was" $?
uf_run "$H"'; kk.image ikill'
left 'ikill-*.tmp.*'
K=$LEFT
printf 'x\n' > "$FX/img/zz-00000000.tmp.$TAG.$$.1.sh0"
printf 'x\n' > "$FX/img/zz-00000000.tmp.other.999999.1.sh0"
uf_run "$H"'; kk.image --rebuild ib'
left '*.tmp.*'
[[ $UF_RC == 0 && -n $K && $LEFT == "zz-00000000.tmp.$TAG.$$.1.sh0 zz-00000000.tmp.other.999999.1.sh0" ]]
uf_check "a writer killed midway leaves its temps ($K); the next write prunes them — not a live pid's, not another runtime's" $?
rm -f "$FX"/img/zz-*

# ---------------------------------------------------------------------------
kt_test_section "025: concurrent writers, readers and renames (§7.4)"

rm -f "$FX"/img/*
cat > "$FX/w.sh" <<'EOF'
source "$FX/kbool.sh" || exit 9
kk.image ia
echo "w rc=$? $(ia.f)"
EOF
uf_run 'bash "$FX/w.sh" & bash "$FX/w.sh" & wait'
A=$UF_OUT
left 'ia-*' '*.tmp.*'
B=$LEFT
uf_run "$H"'; kk.image ia; kk.image --path ia >/dev/null; echo "path=$?"'
uf_run "$H"'; kk.image --path ia >/dev/null; echo "path=$?"'
[[ $A == 'w rc=0 ia.f a b "q" $x 4 v 2 7'$'\n''w rc=0 ia.f a b "q" $x 4 v 2 7' && $B == "ia-"*".img ia-"*".ref" && $UF_OUT == "path=0" ]]
uf_check "two writers at once: both loads fine, one image and one .ref left (the last rename wins), no temp; the folder settles to a valid image" $?

for f in "$FX"/img/ia-*.img; do IMG=$f; done
cp "$IMG" "$FX/img.old"
uf_run 'exec 3< "'"$IMG"'"; bash -c "source \"\$FX/kbool.sh\"; kk.image --rebuild ia"; IFS= read -r -d "" z <&3; exec 3<&-; printf "%s" "$z" > "$FX/img.read"'
cp "$IMG" "$FX/img.new"
[[ $(cksum < "$FX/img.read") == $(cksum < "$FX/img.old") && $(cksum < "$FX/img.new") != $(cksum < "$FX/img.old") ]]
uf_check "a reader holding the image open while a rename replaces it keeps reading the old bytes; the folder has the new image" $?

# fm/: an mv that fails like a rename over a file a native process holds open
mkdir -p "$FX/fm"
printf '#!%s\necho "mv: cannot move: Device or resource busy" >&2\nexit 1\n' "$REAL_BASH" > "$FX/fm/mv"; chmod +x "$FX/fm/mv"
cp "$IMG" "$FX/img.before"
uf_run "$H"'; PATH="$FX/fm:$PATH"; kk.image --rebuild ia; echo "rc=$?"'
A=$UF_OUT
left '*.tmp.*' '*.hold'
[[ $A == "rc=0" && $(cksum < "$IMG") == $(cksum < "$FX/img.before") && -z $LEFT ]]
uf_check "a rename that fails (Device or resource busy): silent, rc 0, the old image kept, the temp gone, no hold" $?
uf_run "$H"'; PATH="$FX/fm:$PATH"; VERBOSE_KKLASS=debug kk.image --rebuild ia 2>&1 | grep "no image written"'
[[ $UF_OUT == "kbool: image: no image written: cannot rename $FX/img/ia-"*".tmp."*".img" ]]
uf_check "(the debug line names it)" $?

kt_test_log "025_ImagePrune.sh completed"
