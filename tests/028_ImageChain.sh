#!/usr/bin/env bash
# ImageChain — chained load images (kklass/docs/dev/IMAGE_PLAN.md §7.7,
# IMG-D2; stage I2b): units loaded before kk.image (the prior set P, in
# load order with their files) key the image and are stamped; the image
# holds only this call's delta — its changes to slots that existed before
# (P's registries, scalars, a redefined function of P's) as element deltas
# with their earlier values in the base list; a start checks that base
# before sourcing (any difference: a plain kk.uses, no write) and the undo
# puts it back; the writer's simulation runs in a fresh process (P as its
# own load leaves it, the image applied, compared) and refuses an image that
# depends on what this script changed in P (the writer's side of R13; the
# reader's side: the read base, P's variables the load names); holds and pruning per
# (request, P); KBOOL_IMAGE_CHAIN. Fixture: image_fixture.sh + the units
# below. The real-unit chains (tstringlist + fv.dlg, kklass classes) are
# kcl/tests/009_ImageChain.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImageChain" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9; VERBOSE_KKLASS=debug'
WIN=0
if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then WIN=1; fi
REAL_BASH=$BASH
REAL_STAT=$(type -P stat)

# the units of the chains:
#   pb   P: a registry (associative), a list (indexed), an internal default
#        __PB_N (D6), a variable PB_V, a declared unset PB_D, functions pb.f, pb.g
#   pc   uses pb; adds to its registry and list, increments __PB_N, copies
#        PB_V (a READ of P's state: the reader's side of R13, the read base)
#   pd   uses pb; redefines pb.f
#   pe   uses pb; changes and removes registry elements, keys that are not
#        plain (a blank, `$(`, `@`, `]`)
#   pr   uses pb; changes the caller's PRX (no P slot: refused)
#   pf   uses pb; reads __PB_N, counts PB_LIST and PB_REG (the read base only)
#   pk   P: kills the simulated start in the writer's fresh process (F1)
#   pm   uses pb; `: "${PM_OPT:=d}"` (a default of a caller's variable: M1)
#   ps   uses pb; `: "${PB_D:=d}"` (PB_D declared unset by pb: an `s` delta, `-`)
#   pa   uses pb; `declare -gi PB_V` (attributes changed: refused)
#   ph   uses pb; runs od (the hash table changed: refused)
#   py   loads pz unless the caller set PBY (P as its own load leaves it differs)
#   pg   uses pb; changes PB_REG[pb] (an `=` element delta)
#   pn   uses pb; reads NO_COLOR and names Q in a function only (no read base)
#   pq, pz  other prior units
if_unit "$FX" pb <<'EOF'
PB_V=1
declare -gA PB_REG=([pb]=1 [old]=o ['o k']=ok ['o j']=oj)
declare -ga PB_LIST=(pb)
: "${__PB_N:=0}"
pb.f() { echo "pb.f"; }
pb.g() { PB_G=orig; }
declare -g PB_D
EOF
if_unit "$FX" pc <<'EOF'
kk.uses pb || return
PB_REG[pc]=2
PB_LIST+=(pc)
__PB_N=$(( __PB_N + 1 ))
PC_COPY=$PB_V
PC_V=3
pc.f() { echo "pc.f $__PB_N ${PB_REG[pc]} ${#PB_LIST[@]} $PC_COPY"; }
EOF
if_unit "$FX" pd <<'EOF'
kk.uses pb || return
pb.g; PD_SAW=$PB_G
pb.f() { echo "pd's pb.f"; }
pb.g() { PB_G=pd; }
PD_V=1
EOF
if_unit "$FX" pe <<'EOF'
kk.uses pb || return
PE_SAW="${PB_REG[pb]}/${PB_REG[old]-gone}"
PB_REG[pb]=changed
unset 'PB_REG[old]' 'PB_REG[o k]' 'PB_REG[o j]'
PE_K=('a b' '$(echo no)' '@' 'x]y')
for PE_I in "${!PE_K[@]}"; do PB_REG[${PE_K[PE_I]}]="v$PE_I"; done
pe.n() { local k='@'; echo "pe ${#PB_REG[@]} ${PB_REG[pb]} ${PB_REG[old]-gone} ${PB_REG[a b]} ${PB_REG[$k]}"; }
EOF
if_unit "$FX" pr <<'EOF'
kk.uses pb || return
PRX=changed
EOF
if_unit "$FX" pf <<'EOF2'
kk.uses pb || return
PF_N=$__PB_N
PF_C=${#PB_LIST[@]}
PF_R=${#PB_REG[@]}
pf.n() { echo "pf $PF_N $PF_C $PF_R"; }
EOF2
if_unit "$FX" pk <<'EOF2'
# (in the writer's fresh process only — kk._img__child exports __KK_IMG_KSET
# there: the simulated start's image check dies, saying nothing)
if [[ -n ${__KK_IMG_KSET+x} ]]; then kk._img__kidfit() { echo "pk: boom" >&2; exit 7; }; fi
PK_V=1
EOF2
if_unit "$FX" pm <<'EOF2'
kk.uses pb || return
: "${PM_OPT:=d}"
EOF2
if_unit "$FX" ps <<'EOF2'
kk.uses pb || return
: "${PB_D:=d}"
EOF2
if_unit "$FX" pa <<'EOF2'
kk.uses pb || return
declare -gi PB_V
EOF2
if_unit "$FX" ph <<'EOF2'
kk.uses pb || return
od </dev/null >/dev/null
EOF2
if_unit "$FX" py <<'EOF2'
[[ -n ${PBY-} ]] || kk.uses pz || return
PY_V=1
EOF2
if_unit "$FX" pg <<'EOF2'
kk.uses pb || return
PB_REG[pb]=changed2
EOF2
if_unit "$FX" pn <<'EOF2'
kk.uses pb || return
pn.f() { local Q=${NO_COLOR-}; echo "pn ${Q:-none}"; }
EOF2
if_unit "$FX" pq <<'EOF'
PQ_V=1
EOF
if_unit "$FX" pz <<'EOF'
PZ_V=1
EOF
touch -t 202001010000 "$FX"/kcl/*/*.sh

# ch.sh MODE "P..." REQ FILE [OPT] — kk.uses P...; kk.image REQ (MODE plain:
# KBOOL_IMAGE=off) under `set OPT` (when given); says whether it hit; the
# state dump into FILE (VERBOSE_KKLASS=debug as in H: one key)
cat > "$FX/ch.sh" <<'EOF'
source "$FX/kbool.sh" || exit 9
VERBOSE_KKLASS=debug
kk.uses $2 || exit 8
if [[ -n ${5-} ]]; then set "$5"; fi
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image "$3" 2>/dev/null; else kk.image "$3" 2>/dev/null; fi
echo "$1 rc=$? ${__KK_UNIT_PID[$3]+loaded}"
set +eu
kk._image_lib || exit 9
kk._img_state "$4" canon
EOF
# im "P…" REQ -> IM: the image path (kk.image --path) of `kk.uses P…; kk.image REQ`
im() { local o=$UF_OUT; uf_run "$H"'; [[ -z "'"$1"'" ]] || kk.uses '"$1"'; kk.image --path '"$2"' 2>/dev/null'; IM=$UF_OUT; UF_OUT=$o; }
# age every image an hour (a stale one written < 10 minutes before is held: 024)
age() { local f; for f in "$FX"/img/*.img; do [[ -e $f ]] && if_age "$f" 3600; done; }
noholds() { local f; for f in "$FX"/img/*.hold; do [[ -e $f ]] && rm -f "$f"; done; }
# (kk.image's stderr into $FX/e.txt — in a pipeline it would run in a
# subshell —, then E1 / FL: its first line / the first line holding TEXT)
E1='e1() { local l=""; IFS= read -r l < "$FX/e.txt"; echo "$l"; }'
FL='fl() { local l; while IFS= read -r l; do [[ $l == *"$1"* ]] && { echo "$l"; return 0; }; done < "$FX/e.txt"; return 0; }'
H="$H; $E1; $FL"

# ---------------------------------------------------------------------------
kt_test_section "028: a chained image (§7.7, IMG-D2)"

uf_run "$H"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; fl "wrote"; fl "no image written"'
im pb pc; PCIMG=$IM
[[ $UF_OUT == "kbool: image: wrote $PCIMG" && -f $PCIMG ]]
uf_check "kk.uses pb; kk.image pc: a miss writes a chained image" $?
uf_run "$H"'; kk.uses pb; kk.image pc 2>&1; echo "rc=$? ${__KK_UNIT_PID[pc]-image}"; pc.f; pb.f'
[[ $UF_OUT == "kbool: image: loaded from $PCIMG"$'\n'"rc=0 image"$'\n'"pc.f 1 2 2 1"$'\n'"pb.f" ]]
uf_check "the next start is a hit: P's registry, list and default carry the delta" $?
uf_run 'bash "$FX/ch.sh" hit pb pc "$FX/c1.d"; bash "$FX/ch.sh" plain pb pc "$FX/c0.d"; bash "$FX/cmp.sh" "$FX/c0.d" "$FX/c1.d"'
[[ $UF_OUT == "hit rc=0 "$'\n'"plain rc=0 loaded"$'\n'"cmp rc=0 " ]]
uf_check "the hit's state equals \`kk.uses pb pc\` loaded normally (the round-trip compare) [§10 chained starts]" $?
if_pfield "$PCIMG" 4
[[ $IF_F == [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]:pb ]]
uf_check "the plain line's PRIOR slot: HASH:pb ('$IF_F') [§6.1]" $?
IFS= read -r -d '' z < "$PCIMG" || :
[[ $z == *"__kk_img_key="*"prior=pb="*"$FX/kcl/pb/pb.sh"* && $z == *"#P"*"$FX/kcl/pb/pb.sh"* && $z != *"pb.f ()"* && $z != *"PB_V="* ]]
uf_check "P's name and file are a key row, P's file is stamped; P itself is not in the image (no pb.f, no PB_V)" $?

im "" pc; A=$IM
im "pq pb" pc; B=$IM
im "pb pq" pc; C=$IM
im "pz pb" pc; E=$IM
[[ $A == "$FX/img/pc-"*.img && $B == "$FX/img/pc-"*.img && $C == "$FX/img/pc-"*.img && $E == "$FX/img/pc-"*.img ]] \
    && [[ $A != "$PCIMG" && $B != "$PCIMG" && $C != "$PCIMG" && $E != "$PCIMG" && $B != "$C" && $B != "$E" && $A != "$B" ]]
uf_check "\`kk.image pc\` alone, another P and P in another order are other image files (the prior set is in the file name hash)" $?
uf_run "$H"'; kk.uses pq pb; kk.image pc 2>/dev/null'
uf_run "$H"'; kk.uses pq pb; kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: loaded from $B" ]]
uf_check "P = pq pb: its own image, then a hit" $?
cp "$PCIMG" "$B"
uf_run "$H"'; kk.uses pq pb; kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: the image has another key: a normal load, then an image" ]]
uf_check "the image of P = pb under the file name of P = pq pb: another key (the prior rows are in the key itself, not only in the file name)" $?

age
touch "$FX/kcl/pb/pb.sh"
uf_run "$H"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: stale: $FX/kcl/pb/pb.sh changed after the image was made"* ]]
uf_check "a P file edited: stale (P's files are stamped)" $?
touch -t 202001010000 "$FX/kcl/pb/pb.sh"
uf_run "$H"'; kk.uses pb; kk.image --rebuild pc 2>/dev/null'
uf_run "$H"'; kk.uses pb; KBOOL_IMAGE_CHAIN=maybe kk.image pc 2>"$FX/e.txt"; fl "KBOOL_IMAGE_CHAIN"; fl "loaded from"'
[[ $UF_OUT == "kbool: image: KBOOL_IMAGE_CHAIN=maybe is not on|off; using on"$'\n'"kbool: image: loaded from $PCIMG" ]]
uf_check "KBOOL_IMAGE_CHAIN=maybe: on (the chained image hits) and a debug line [§3]" $?
uf_run "$H"'; kk.uses pb; KBOOL_IMAGE_CHAIN=off kk.image pc 2>&1; echo "rc=$? ${__KK_UNIT_PID[pc]+loaded}"'
[[ $UF_OUT == "kbool: image: KBOOL_IMAGE_CHAIN=off and unit 'pb' is loaded already; a normal load (kk.uses pc)"$'\n'"rc=0 loaded" ]]
uf_check "KBOOL_IMAGE_CHAIN=off with a prior set: a plain kk.uses (the valid chained image is not read)" $?
uf_run "$H"'; source "$FX/kcl/pb/pb.sh"; kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: loaded from $PCIMG" ]]
uf_check "P loaded by a plain source (complete): the same prior set, a hit" $?
uf_run "$H"'; source "$FX/kcl/pb/pb.sh"; kk.image --rebuild pc 2>"$FX/e.txt"; fl "wrote"; fl "no image written"'
A=$UF_OUT
uf_run "$H"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; e1'
B=$UF_OUT
uf_run "$H"'; source "$FX/kcl/pb/pb.sh"; kk.image pc 2>"$FX/e.txt"; e1'
[[ $A == "kbool: image: wrote $PCIMG" && $B == "kbool: image: __KK_UNIT_DONE[pb] differs from the image's base; a normal load (kk.uses pc)" \
   && $UF_OUT == "kbool: image: loaded from $PCIMG" ]]
uf_check "P sourced plainly (no completion mark; pc's kk.uses pb sets it): written (the fresh process sources P plainly too); a start with P loaded by kk.uses: a plain kk.uses (the mark is a base slot); sourced plainly again: a hit" $?
uf_run "$H"'; kk.uses pb; kk.image --rebuild pc 2>/dev/null'

# ---------------------------------------------------------------------------
kt_test_section "028: the base check (§7.7: before sourcing, fork-free)"

uf_run "$H"'; kk.uses pb; PB_REG[pc]=preset; kk.image pc 2>&1; echo "rc=$? ${__KK_UNIT_PID[pc]+loaded}"; pc.f'
[[ $UF_OUT == "kbool: image: PB_REG[pc] differs from the image's base; a normal load (kk.uses pc)"$'\n'"rc=0 loaded"$'\n'"pc.f 1 2 2 1" ]]
uf_check "a registry entry the delta writes pre-set: a plain kk.uses (no write), the state a normal load's" $?
uf_run "$H"'; kk.uses pb; PB_LIST+=(mine); kk.image pc 2>"$FX/e.txt"; e1; pc.f'
[[ $UF_OUT == "kbool: image: PB_LIST[1] differs from the image's base; a normal load (kk.uses pc)"$'\n'"pc.f 1 2 3 1" ]]
uf_check "an element of an indexed P list pre-set: a plain kk.uses" $?
uf_run "$H"'; kk.uses pb; __PB_N=5; kk.image pc 2>"$FX/e.txt"; e1; pc.f'
[[ $UF_OUT == "kbool: image: __PB_N differs from the image's base; a normal load (kk.uses pc)"$'\n'"pc.f 6 2 2 1" ]]
uf_check "a P scalar the delta changes has another value: a plain kk.uses" $?
uf_run "$H"'; kk.uses pb; f() { local __PB_N=9; kk.image pc; }; f 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: __PB_N differs from the image's base; a normal load (kk.uses pc)" ]]
uf_check "H1: a caller's local named like a delta variable: the base check sees it (the caller's view) — a plain kk.uses" $?
uf_run "$H"'; kk.uses pb; PC_V=mine; kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: 'PC_V' exists in this shell already"*"; a normal load (kk.uses pc)" ]]
uf_check "H1: a caller's variable named like a variable the image creates: a plain kk.uses" $?
noholds
if_pfield "$PCIMG" 7; NC1=$IF_F
uf_run "$H"'; kk.uses pb; PB_REG[pc]=x; kk.image pc 2>/dev/null; ls "$FX/img" | grep -c "pc-.*\.hold$"'
if_pfield "$PCIMG" 7
[[ $UF_OUT == 0 && $IF_F == "$NC1" ]]
uf_check "a base that differs writes nothing: no hold, the image kept (its nonce '$NC1')" $?

# a redefined function of P's (f in the base list: its earlier text)
uf_run "$H"'; kk.uses pb; kk.image pd 2>/dev/null'
im pb pd; PDIMG=$IM
uf_run "$H"'; kk.uses pb; kk.image pd 2>"$FX/e.txt"; e1; pb.f; pb.g; echo "$PB_G $PD_SAW"'
[[ $UF_OUT == "kbool: image: loaded from $PDIMG"$'\n'"pd's pb.f"$'\n'"pd orig" ]]
uf_check "a unit redefining P's functions: a chained image (their new texts in it), a hit" $?
IFS= read -r -d '' z < "$PDIMG" || :
[[ $z == *"__kk_img_base=("*"pb.f"*"pb.f () "*"echo \"pb.f\""* && $z == *"__kk_img_fns=()"* ]]
uf_check "its base entries hold the earlier texts (not a hash: the undo defines them again); pb.f / pb.g are not in the undo's unset list" $?
uf_run "$H"'; kk.uses pb; pb.f() { echo mine; }; kk.image pd 2>"$FX/e.txt"; e1; pb.f'
[[ $UF_OUT == "kbool: image: pb.f() differs from the image's base; a normal load (kk.uses pd)"$'\n'"pd's pb.f" ]]
uf_check "P's function redefined by the caller first: a plain kk.uses" $?
# (bash < 5.3: the text through PDIMG's NAME.fnc; __KK_IMG_FNFILE forces that path on 5.3)
uf_run "$H"'; kk.uses pb; __KK_IMG_FNFILE=1; kk.image pd 2>"$FX/e.txt"; e1; pb.f'
[[ $UF_OUT == "kbool: image: loaded from $PDIMG"$'\n'"pd's pb.f" && -f ${PDIMG%.img}.fnc ]]
uf_check "the text check through NAME.fnc (bash < 5.3; forced here): a hit" $?
rm -f "${PDIMG%.img}.fnc"
PDN=${PDIMG##*/}; PDN=${PDN%.img}
uf_run "$H"'; kk.uses pb; __KK_IMG_FNFILE=1; kk.image pd 2>"$FX/e.txt"; e1; fl "wrote"; [[ -f "'"${PDIMG%.img}.fnc"'" ]] && echo fnc; ls "$FX/img" | grep -c "^pd-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no $PDN.fnc (the function text check of this image): a normal load, then an image"$'\n'"kbool: image: wrote $PDIMG"$'\n'"fnc"$'\n'"0" ]]
uf_check "NAME.fnc missing: a miss (no hold), written again with its .fnc" $?
# NAME.fnc that is not this user's regular file to write (I2b fix round F5):
# a start (the text path forced) is a plain kk.uses naming it; the writer
# writes no image and holds, naming it; a symbolic link is refused, never
# followed; a read-only one is a write failure, said as such
F=${PDIMG%.img}.fnc
rm -f "$F"; mkdir "$F"
uf_run "$H"'; kk.uses pb; __KK_IMG_FNFILE=1; kk.image pd 2>"$FX/e.txt"; e1; pb.f'
[[ $UF_OUT == "kbool: image: $F is not a regular file of this user (a symbolic link, a folder, another user's): the function text check cannot run; a normal load (kk.uses pd)"$'\n'"pd's pb.f" ]]
uf_check "a start whose NAME.fnc is a folder: a plain kk.uses, the reason names the .fnc [F5]" $?
uf_run "$H"'; kk.uses pb; kk.image --rebuild pd 2>"$FX/e.txt"; fl "no image written"; ls "$FX/img" | grep -c "^pd-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: $F is not a regular file of this user (a folder, another user's): the function text check of this image cannot run"$'\n'"1" ]]
uf_check "the writer, NAME.fnc a folder: no image, a hold naming the .fnc [F5]" $?
rmdir "$F"; noholds
ln -s "$FX/fnc.target" "$F" 2>/dev/null
if [[ -L $F ]]; then
    uf_run "$H"'; kk.uses pb; kk.image --rebuild pd 2>"$FX/e.txt"; fl "no image written"; ls "$FX/img" | grep -c "^pd-.*\.hold$"; [[ -e "$FX/fnc.target" ]] && echo followed'
    [[ $UF_OUT == "kbool: image: no image written: $F is a symbolic link (refused, not followed): the function text check of this image cannot run"$'\n'"1" ]]
    uf_check "the writer, NAME.fnc a symbolic link: refused (not skipped, not followed), a hold [F5]" $?
else
    kt_test_start "the writer, NAME.fnc a symbolic link: refused, a hold [F5]"
    kt_test_pass "no symbolic links on this runtime (Windows without winsymlinks): the folder case above covers the check"
fi
rm -f "$F"; noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild pd 2>/dev/null'
chmod a-w "$F" 2>/dev/null
if [[ -f $F && ! -w $F ]]; then
    uf_run "$H"'; kk.uses pb; __KK_IMG_FNFILE=1; kk.image pd 2>"$FX/e.txt"; e1; pb.f'
    [[ $UF_OUT == "kbool: image: cannot write or read $F (the function text check of this image); a normal load (kk.uses pd)"$'\n'"pd's pb.f" ]]
    uf_check "a start whose NAME.fnc cannot be written (as in a read-only folder, bash < 5.3): the write failure named, not 'pb.f() differs' [F5]" $?
else
    kt_test_start "a start whose NAME.fnc cannot be written: the write failure named [F5]"
    kt_test_pass "a read-only file stays writable here (root): not testable"
fi
chmod u+w "$F" 2>/dev/null
noholds

# keys that are not plain, a change and a removal of P's elements
# (CI diagnosis, I2b fix round 2: for the pe cases below the writer's fresh
# process keeps its stderr in $FX/kid.err — an xtrace of the simulated start
# too on bash < 5.2 —, and a failing pe case shows its error lines and tail)
UF_ENV0=("${UF_ENV[@]}")
UF_ENV+=(__KK_IMG_KIDERR="$FX/kid.err")
if (( BASH_VERSINFO[0] < 5 || ( BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2 ) )); then UF_ENV+=(__KK_IMG_KIDX=1); fi
kx() {
    local r=$? l t=""
    if (( r != 0 )) && [[ -s $FX/kid.err ]]; then
        while IFS= read -r l; do t+=${l:0:200}$'\n'; done < <(grep -a -n -E -i 'error|bad |substitution|unbound|syntax|not found|readonly|cannot' "$FX/kid.err" | head -n 10; echo '--- tail:'; tail -n 30 "$FX/kid.err")
        UF_OUT+=$'\n'"kid.err:"$'\n'"$t"
    fi
    return "$r"
}
uf_run 'bash "$FX/ch.sh" miss pb pe "$FX/e0.d" >/dev/null; bash "$FX/ch.sh" hit pb pe "$FX/e1.d"; bash "$FX/ch.sh" plain pb pe "$FX/e2.d"; bash "$FX/cmp.sh" "$FX/e2.d" "$FX/e1.d"'
A=$UF_OUT
uf_run "$H"'; kk.uses pb; kk.image pe 2>/dev/null; echo "${__KK_UNIT_PID[pe]-image}"; pe.n'
[[ $A == "hit rc=0 "$'\n'"plain rc=0 loaded"$'\n'"cmp rc=0 " && $UF_OUT == "image"$'\n'"pe 5 changed gone v0 v2" ]]
kx; uf_check "element deltas on P's registry: a change, a removal, keys with a blank, \$( and @ — the hit's state equals a normal load's" $?
uf_run "$H"'; kk.uses pb; PB_REG[pb]=other; kk.image pe 2>"$FX/e.txt"; e1; pe.n; echo "$PE_SAW"'
[[ $UF_OUT == "kbool: image: PB_REG[pb] differs from the image's base; a normal load (kk.uses pe)"$'\n'"pe 5 changed gone v0 v2"$'\n'"other/o" ]]
kx; uf_check "an element the delta changes holds another value: a plain kk.uses" $?
uf_run "$H"'; IFS=:; kk.uses pb; kk.image --rebuild pe 2>"$FX/e.txt"; fl "wrote"; fl "no image written"'
A=$UF_OUT
uf_run "$H"'; kk.uses pb; kk.image pe 2>/dev/null; echo "${__KK_UNIT_PID[pe]-image}"; pe.n'
[[ $A == "kbool: image: wrote "*"/pe-"*".img" && $UF_OUT == "image"$'\n'"pe 5 changed gone v0 v2" ]]
kx; uf_check "written under a caller's IFS=: (the loop form of keys that are not plain joins its lists itself), then a hit" $?

# ---------------------------------------------------------------------------
kt_test_section "028: no fork on a chained hit (dates; §9)"

# fk "P…" REQ PRE — a traced start (xtrace with $BASHPID): FK = "forks lines src"
fk() {
    local line p forks=0 lines=0 main="" src=0
    uf_run "$H"'; kk.uses '"$1"'; '"$3"'; exec 8>"$FX/fk.trace"; BASH_XTRACEFD=8; PS4='"'"'+${BASHPID}|'"'"'; printf "MAIN=%s\n" "$BASHPID" >&8; set -x; kk.image '"$2"' 2>/dev/null; set +x; unset BASH_XTRACEFD; echo "pid=${__KK_UNIT_PID['"$2"']+normal}"'
    while IFS= read -r line; do
        case $line in MAIN=*) main=${line#MAIN=}; continue ;; +*) ;; *) continue ;; esac
        p=${line%%|*}; p=${p##*+}
        [[ -n $p && $p != *[!0-9]* ]] || continue
        lines=$(( lines + 1 ))
        [[ $line == *"source "*".img"* ]] && src=1
        [[ $p == "$main" ]] || forks=$(( forks + 1 ))
    done < "$FX/fk.trace"
    FK="$forks $lines $src" FK_L=$lines
}
fk pb pc ":"
[[ $UF_OUT == "pid=" && $FK == "0 "*" 1" && $FK_L -gt 50 ]]
uf_check "a chained start (P key rows, base check, source, hooks) runs in ONE process: forks / traced lines / sourced = $FK" $?
fk pb pd "__KK_IMG_FNFILE=1"
[[ $UF_OUT == "pid=" && $FK == "0 "*" 1" ]]
uf_check "a chained start with a redefined function, its text read through NAME.fnc (the bash < 5.3 path): no fork either ($FK)" $?

# ---------------------------------------------------------------------------
kt_test_section "028: the undo of a chained image (§8.3: base slots put back)"

noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild pc 2>/dev/null'
for REFN in "${PCIMG%.img}".*.ref; do :; done
cp "$PCIMG" "$FX/pc.full"; cp "$REFN" "$FX/pc.ref"
IFS= read -r -d '' z < "$FX/pc.full" || :
# (cut right after the delta lines — P's registry, list and default changed —,
# inside kkore's registration: the undo must put P's slots back, or the normal
# load after it would add a second `pc` to the list and count __PB_N twice)
p=${z%%$'\n'__KK_UNITS\[*}
[[ $p == *$'\n'"__PB_N=1"$'\n'* ]]
uf_check "(the cut point lies after the delta lines)" $?
blen() { local LC_ALL=C; n=${#p}; }
blen
for opt in -e -u; do
    cp "$FX/pc.full" "$PCIMG"; cp "$FX/pc.ref" "$REFN"
    noholds
    if_age "$PCIMG" 3600
    ( umask 077; head -c $(( n + 20 )) "$FX/pc.full" > "$PCIMG.cut" ) && mv -f "$PCIMG.cut" "$PCIMG"
    uf_run 'bash "$FX/ch.sh" hit pb pc "$FX/u1.d" '"$opt"'; bash "$FX/cmp.sh" "$FX/c0.d" "$FX/u1.d"'
    [[ $UF_OUT == "hit rc=0 loaded"$'\n'"cmp rc=0 " ]]
    uf_check "a truncated chained image under set $opt: undone (P's registry, list and default put back), a normal load, the state a normal load's" $?
done
cp "$FX/pc.full" "$PCIMG"; cp "$FX/pc.ref" "$REFN"
noholds
cp "$PDIMG" "$FX/pd.full"
IFS= read -r -d '' z < "$FX/pd.full" || :
p=${z%%$'\n'__KK_UNITS\[*}; blen
if_age "$PDIMG" 3600
( umask 077; head -c $(( n + 20 )) "$FX/pd.full" > "$PDIMG.cut" ) && mv -f "$PDIMG.cut" "$PDIMG"
# (pd's load calls pb.g before redefining it: PD_SAW tells which pb.g the
# normal load after the undo found — the earlier one, put back, or the image's)
uf_run "$H"'; kk.uses pb; kk.image pd 2>/dev/null; echo "${__KK_UNIT_PID[pd]+normal} saw=$PD_SAW"; pb.f'
[[ $UF_OUT == "normal saw=orig"$'\n'"pd's pb.f" ]]
uf_check "a truncated image redefining P's functions: undone (pb.g's earlier text defined again), then the normal load" $?
# (pe's load reads PB_REG[pb] and PB_REG[old] before it changes / removes
# them: PE_SAW tells whether the undo put the changed and the removed element back)
noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild pe 2>/dev/null'
im pb pe; PEIMG=$IM
cp "$PEIMG" "$FX/pe.full"
IFS= read -r -d '' z < "$FX/pe.full" || :
p=${z%%$'\n'__KK_UNITS\[*}; blen
if_age "$PEIMG" 3600
( umask 077; head -c $(( n + 20 )) "$FX/pe.full" > "$PEIMG.cut" ) && mv -f "$PEIMG.cut" "$PEIMG"
uf_run "$H"'; kk.uses pb; kk.image pe 2>/dev/null; echo "${__KK_UNIT_PID[pe]+normal} saw=$PE_SAW"; pe.n'
[[ $p == *"unset -v 'PB_REG[old]'"* && $UF_OUT == "normal saw=1/o"$'\n'"pe 5 changed gone v0 v2" ]]
kx; uf_check "a truncated image that changed and removed P's elements: undone (both put back), then the normal load" $?
UF_ENV=("${UF_ENV0[@]}")

# ---------------------------------------------------------------------------
kt_test_section "028: the writer's fresh-process simulation (§5.2; R13)"

noholds
uf_run "$H"'; kk.uses pb; kk.image pc 2>/dev/null'
uf_run "$H"'; kk.uses pb; PB_V=9; kk.image pc 2>"$FX/e.txt"; echo "copy=$PC_COPY ${__KK_UNIT_PID[pc]+normal}"; e1'
[[ $UF_OUT == "copy=9 normal"$'\n'"kbool: image: PB_V, which this call's load reads, differs from when the image was made; a normal load (kk.uses pc)" ]]
uf_check "R13, the reader's side (the read base, I2b fix round): the script changed P's PB_V, which pc's load reads, after the image was made — a plain kk.uses (PC_COPY=9), no write" $?
# the read base: pf reads P's __PB_N and counts PB_LIST and PB_REG, changing
# nothing of P's — no delta, so only its `r` entries tell a P that differs
uf_run "$H"'; kk.uses pb; kk.image pf 2>/dev/null'
uf_run "$H"'; kk.uses pb; kk.image pf 2>/dev/null; echo "${__KK_UNIT_PID[pf]-image}"; pf.n'
[[ $UF_OUT == "image"$'\n'"pf 0 1 4" ]]
uf_check "the read base: an image of pf (reads P's __PB_N, counts P's list and registry; no delta) hits on an unchanged P" $?
uf_run "$H"'; export __PB_N=5; kk.uses pb; kk.image pf 2>"$FX/e.txt"; echo "${__KK_UNIT_PID[pf]+normal}"; pf.n; e1'
[[ $UF_OUT == "normal"$'\n'"pf 5 1 4"$'\n'"kbool: image: __PB_N, which this call's load reads, differs from when the image was made; a normal load (kk.uses pf)" ]]
uf_check "the read base (a): an environment preset of P's default __PB_N — a plain kk.uses, pf sees 5" $?
uf_run "$H"'; kk.uses pb; unset "PB_LIST[0]"; kk.image pc 2>"$FX/e.txt"; echo "${__KK_UNIT_PID[pc]+normal} ${!PB_LIST[*]}"; e1'
[[ $UF_OUT == "normal 0"$'\n'"kbool: image: PB_LIST, which this call's load reads, differs from when the image was made; a normal load (kk.uses pc)" ]]
uf_check "the read base (b): the caller removed P's list element, pc appends — a plain kk.uses (the append lands at index 0, not at the image's 1)" $?
uf_run "$H"'; kk.uses pb; PB_REG[zz]=1; kk.image pf 2>"$FX/e.txt"; echo "${__KK_UNIT_PID[pf]+normal}"; pf.n; e1'
[[ $UF_OUT == "normal"$'\n'"pf 0 1 5"$'\n'"kbool: image: PB_REG, which this call's load reads, differs from when the image was made; a normal load (kk.uses pf)" ]]
uf_check "the read base (c): the caller added a key to P's registry, which pf counts — a plain kk.uses (5, not the image's 4)" $?
# an environment name is a read of P's state only when P's files name it
# (critic N2, I2b fix round 2): pn's own NO_COLOR / Q (words of pn, not of pb)
# exported in the writer are no read base — its starts without them or with
# other values hit; __PB_N exported in the writer (a word of pb: P's default
# took it) is one — a start without it is a plain kk.uses
noholds
uf_run "$H"'; kk.uses pb; export NO_COLOR=1 Q=x; kk.image --rebuild pn 2>"$FX/e.txt"; fl "wrote"'
A=$UF_OUT
uf_run "$H"'; kk.uses pb; kk.image pn 2>"$FX/e.txt"; e1; pn.f; export NO_COLOR=yes Q=y; pn.f'
B=$UF_OUT
uf_run "$H"'; export NO_COLOR=yes Q=y; kk.uses pb; kk.image pn 2>"$FX/e.txt"; e1; pn.f'
UF_OUT="$A | $B | $UF_OUT"
[[ $A == "kbool: image: wrote "*"/pn-"*".img" && $B == "kbool: image: loaded from "*"/pn-"*".img"$'\n'"pn none"$'\n'"pn yes" \
   && $UF_OUT == *" | kbool: image: loaded from "*"/pn-"*".img"$'\n'"pn yes" ]]
uf_check "the request's own environment names (NO_COLOR, a one-letter Q) exported in the writer: no read base — starts without them or with other values hit" $?
noholds
uf_run "$H"'; export __PB_N=5; kk.uses pb; kk.image --rebuild pf 2>/dev/null'
uf_run "$H"'; kk.uses pb; kk.image pf 2>"$FX/e.txt"; e1; pf.n'
[[ $UF_OUT == "kbool: image: __PB_N, which this call's load reads, differs from when the image was made; a normal load (kk.uses pf)"$'\n'"pf 0 1 4" ]]
uf_check "P's default __PB_N exported in the writer (a word of P's file): a read base — a start without it is a plain kk.uses" $?
noholds
uf_run "$H"'; kk.uses pb; PB_V=9; kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; echo "copy=$PC_COPY"; ls "$FX/img" | grep -c "^pc-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: the simulated image start differs: V:PB_V differs from the writer's"$'\n'"copy=9"$'\n'"1" ]]
uf_check "R13, the writer's side: the script changed P before kk.image — the fresh process (P as its own load leaves it) differs: no image, a hold" $?
noholds
uf_run "$H"'; kk.uses pb pk; kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; ls "$FX/img" | grep -c "^pc-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: the simulated image start on the prior set as its own load leaves it failed: the simulated start died (rc 7) before it said why: a fatal error inside the image check, the source or the dump (__KK_IMG_KIDERR=FILE keeps its stderr)"$'\n'"1" ]]
uf_check "a simulated start that dies before it says why (a P unit kills its image check, in the fresh process only): its rc named, no image, a hold (CI 45564636006: bash 5.1 said '?')" $?
noholds
uf_run "$H"'; kk.uses pb pk; __KK_IMG_KIDERR=$FX/kid.err kk.image --rebuild pc 2>/dev/null; cat "$FX/kid.err"'
[[ $UF_OUT == *"pk: boom"* ]]
uf_check "__KK_IMG_KIDERR=FILE: the fresh process's stderr kept in FILE (the seam that names a fatal error of the simulated start)" $?
noholds
uf_run "$H"'; PRX=orig; kk.uses pb; kk.image pr 2>"$FX/e.txt"; fl "no image written"; echo "$PRX"; ls "$FX/img" | grep -c "^pr-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: the simulated image start on the prior set as its own load leaves it failed: PRX differs from the image's base"$'\n'"changed"$'\n'"1" ]]
uf_check "a load that changes a caller's variable (no P slot): the fresh process has no such variable — refused, a hold" $?
noholds
uf_run "$H"'; __PB_N=5; kk.uses pb; kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"'
[[ $UF_OUT == "kbool: image: no image written: the simulated image start on the prior set as its own load leaves it failed: __PB_N differs from the image's base" ]]
uf_check "a caller's (unexported) preset of P's internal default: P's own load sets it otherwise — refused" $?
noholds
# a preset of a P-owned name: an exported PB_V (P sets its own): the fresh
# process has it as this script had it; M1 runs there on top of P and finds
# that pc's load does not set it — written; a start without it hits
uf_run "$H"'; export PB_V=7; kk.uses pb; kk.image --rebuild pc 2>"$FX/e.txt"; fl "wrote"; fl "no image written"; echo "copy=$PC_COPY"'
A=$UF_OUT
uf_run "$H"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; e1; echo "copy=$PC_COPY"'
[[ $A == "kbool: image: wrote $PCIMG"$'\n'"copy=1" && $UF_OUT == "kbool: image: loaded from $PCIMG"$'\n'"copy=1" ]]
uf_check "M1: an exported preset of a P-owned name (P sets its own): no false refusal — written, then a hit without the preset" $?
# an exported preset of P's internal default that this call's load changes:
# a changed export (§6.3) — refused, a hold
uf_run "$H"'; export __PB_N=5; kk.uses pb; kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; pc.f; ls "$FX/img" | grep -c "^pc-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: the load changed the exported variable __PB_N outside the settings hooks"$'\n'"pc.f 6 2 2 1"$'\n'"1" ]]
uf_check "an exported preset of P's default changed by this call's load: a changed export — no image, a hold" $?
noholds

# ---------------------------------------------------------------------------
kt_test_section "028: each refusal and check on its own (the critic's mutation survivors, I2b fix round F4)"

noholds
uf_run "$H"'; kk.uses pb; PB_REG[z]=1; kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"'
[[ $UF_OUT == "kbool: image: no image written: the simulated image start differs: V:PB_REG[z]=1 (the writer's, not so in the simulated start)" ]]
uf_check "a key the caller added to P's registry before kk.image: the simulated start lacks it — the compare's element count differs, no image" $?
noholds
uf_run "$H"'; kk.uses pb; PM_OPT=x; kk.image --rebuild pm 2>"$FX/e.txt"; fl "no image written"'
[[ $UF_OUT == "kbool: image: no image written: the variable PM_OPT existed before the load, and the load sets it when it does not (a preset or a caller's variable would hide the unit's own value from the image)" ]]
uf_check "a caller's PM_OPT that pm's load defaults (\`: \${PM_OPT:=d}\`): the chained M1 probe on top of P refuses, no image" $?
noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild ps 2>/dev/null'
uf_run "$H"'; kk.uses pb; PB_D=x; kk.image ps 2>"$FX/e.txt"; e1; echo "PB_D=$PB_D"'
[[ $UF_OUT == "kbool: image: PB_D differs from the image's base; a normal load (kk.uses ps)"$'\n'"PB_D=x" ]]
uf_check "P's declared unset PB_D, which ps defaults (an \`s\` delta, \`-\`), set before the start: a plain kk.uses keeps the caller's x" $?
noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild pa 2>"$FX/e.txt"; fl "no image written"'
[[ $UF_OUT == "kbool: image: no image written: the load changed the attributes of the existing variable PB_V (-- -> -i)" ]]
uf_check "a load that changes the attributes of P's PB_V (declare -gi): no image" $?
noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild ph 2>"$FX/e.txt"; fl "no image written"'
[[ $UF_OUT == "kbool: image: no image written: the load changed the hash table (od): no chained image" ]]
uf_check "a load that runs a command (od): the hash table changed — no chained image" $?
noholds
uf_run "$H"'; PBY=1; kk.uses py; kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"'
[[ $UF_OUT == "kbool: image: no image written: the fresh-process simulation loaded another prior set ("*"pz="*")" ]]
uf_check "a P unit that loads pz unless the caller set PBY: the fresh process loads another prior set — no image" $?
noholds
uf_run "$H"'; printf "HL_V=1\n" > "$FX/hl.sh"; kk.uses "$FX/hl.sh"; kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: a file without a unit header is loaded by path already (it cannot be part of a prior set); a normal load (kk.uses pc)" ]]
uf_check "a header-less file loaded by path before kk.image: no prior set — a plain kk.uses" $?
uf_run "$H"'; source "$FX/kcl/pq/pq.sh"; __KK_UNIT_FAIL[pq]=1; kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: unit 'pq' is not completely loaded; a normal load (kk.uses pc)" ]]
uf_check "a prior unit that is not complete (plain-sourced, then tainted): a plain kk.uses" $?
uf_run "$H"'; kk.uses pb; __KK_UNIT_ORDER=("${__KK_UNIT_ORDER[@]:0:${#__KK_UNIT_ORDER[@]}-1}"); kk.image pc 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: a loaded unit is not in the load order list; a normal load (kk.uses pc)" ]]
uf_check "a registered unit missing from the load order list: a plain kk.uses" $?
noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild pd 2>/dev/null'
uf_run "$H"'; kk.uses pb; unset -f pb.f; kk.image pd 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: pb.f() differs from the image's base; a normal load (kk.uses pd)" ]]
uf_check "P's function pb.f, which pd redefines, removed by the caller first: a plain kk.uses (its base text is gone)" $?
noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild pg 2>/dev/null'
uf_run "$H"'; kk.uses pb; unset PB_REG; kk.image pg 2>"$FX/e.txt"; e1'
[[ $UF_OUT == "kbool: image: PB_REG[pb] differs from the image's base; a normal load (kk.uses pg)" ]]
uf_check "P's registry removed by the caller, pg changes PB_REG[pb] (an \`=\` element delta): a plain kk.uses" $?
noholds
# (the file-name hash's short rows: KBOOL_HOME/kcl/N/N.sh and KBOOL_HOME/N/N.sh
# are two rows, two file names — I2b fix round F7)
mkdir -p "$FX/pq"; cp "$FX/kcl/pq/pq.sh" "$FX/pq/pq.sh"; touch -t 202001010000 "$FX/pq/pq.sh"
uf_run "$H"'; kk.uses "$FX/kcl/pq/pq.sh"; kk.image --path pc 2>/dev/null'; A=$UF_OUT
uf_run "$H"'; kk.uses "$FX/pq/pq.sh"; kk.image --path pc 2>/dev/null'; B=$UF_OUT
rm -f "$FX/pq/pq.sh"; rmdir "$FX/pq"
UF_OUT="kcl=$A home=$B"
[[ $A == "$FX/img/pc-"*.img && $B == "$FX/img/pc-"*.img && $A != "$B" ]]
uf_check "a prior unit at KBOOL_HOME/kcl/N/N.sh and the same at KBOOL_HOME/N/N.sh: two image file names" $?
# (two checkouts of one path length elsewhere: their rows differ in the folder
# levels' digest — critic N4, I2b fix round 2)
for d in aa bb; do mkdir -p "$FX/$d/pq"; cp "$FX/kcl/pq/pq.sh" "$FX/$d/pq/pq.sh"; touch -t 202001010000 "$FX/$d/pq/pq.sh"; done
uf_run "$H"'; kk.uses "$FX/aa/pq/pq.sh"; kk.image --path pc 2>/dev/null'; A=$UF_OUT
uf_run "$H"'; kk.uses "$FX/bb/pq/pq.sh"; kk.image --path pc 2>/dev/null'; B=$UF_OUT
for d in aa bb; do rm -f "$FX/$d/pq/pq.sh"; rmdir "$FX/$d/pq" "$FX/$d"; done
UF_OUT="aa=$A bb=$B"
[[ $A == "$FX/img/pc-"*.img && $B == "$FX/img/pc-"*.img && $A != "$B" ]]
uf_check "a prior unit from two folders of one path length (FX/aa, FX/bb): two image file names" $?
# (folders that differ only in a last character — wt1 / wt2: each level's last
# character is in the digest too; critic N4, I2b fix round 3)
for d in wt1 wt2; do mkdir -p "$FX/$d/pq"; cp "$FX/kcl/pq/pq.sh" "$FX/$d/pq/pq.sh"; touch -t 202001010000 "$FX/$d/pq/pq.sh"; done
uf_run "$H"'; kk.uses "$FX/wt1/pq/pq.sh"; kk.image --path pc 2>/dev/null'; A=$UF_OUT
uf_run "$H"'; kk.uses "$FX/wt2/pq/pq.sh"; kk.image --path pc 2>/dev/null'; B=$UF_OUT
for d in wt1 wt2; do rm -f "$FX/$d/pq/pq.sh"; rmdir "$FX/$d/pq" "$FX/$d"; done
UF_OUT="wt1=$A wt2=$B"
[[ $A == "$FX/img/pc-"*.img && $B == "$FX/img/pc-"*.img && $A != "$B" ]]
uf_check "a prior unit from two folders that differ only in their last character (FX/wt1, FX/wt2): two image file names" $?

# ---------------------------------------------------------------------------
kt_test_section "028: holds and pruning per (request, P) (§7.4, §7.5)"

uf_run "$H"'; kk.uses pb; kk.image --rebuild pc 2>/dev/null'
uf_run "$H"'; kk.image --rebuild pc 2>/dev/null'
im "" pc; A=$IM
cp "$PCIMG" "$FX/pc.keep"
rm -f "$PCIMG"
printf '%s test\n' "$EPOCHSECONDS" > "${PCIMG%.img}.hold"
uf_run "$H"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; fl "held"; [[ -f "'"$PCIMG"'" ]] && echo written'
B=$UF_OUT
uf_run "$H"'; kk.image pc 2>"$FX/e.txt"; e1'
[[ $B == "kbool: image: no image $PCIMG yet; held (test, "*" s ago); a normal load (kk.uses pc)" && $UF_OUT == "kbool: image: loaded from $A" ]]
uf_check "a hold is per (request, P, mode): pc's chained hold stops pc's chained writer, not the unchained image of pc" $?
mv -f "$FX/pc.keep" "$PCIMG"
noholds
# "not worth it" (I2b fix rounds F6, G4): a normal load under 1.5 times what a
# start of the image costs here (the fresh process's simulated start + the
# steps before the writer; unchained the latter alone) — no image, a hold;
# __KK_IMG_MINLOAD=MS (this suite runs with 0) is an absolute floor instead
uf_run "$H"'; kk.uses pb; __KK_IMG_MINLOAD=600000 kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; ls "$FX/img" | grep -c "^pc-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: not worth an image: the normal load took "*" ms, under 600000 ms (__KK_IMG_MINLOAD)"$'\n'"1" ]]
uf_check "a normal load under __KK_IMG_MINLOAD ms: not worth an image — none written, a hold [F6]" $?
noholds
# a near miss (the load at least half the threshold) is held 10 minutes — the
# hold dated 50 minutes back —, a clear miss an hour (I2b fix round 3, K2;
# __KK_IMG_LOADMS stands for the measured load)
HA='for f in "$FX"/img/pc-*.hold; do read -r t r < "$f"; echo "age $(( EPOCHSECONDS - t ))"; done'
uf_run "$H"'; kk.uses pb; __KK_IMG_MINLOAD=100 __KK_IMG_LOADMS=60 kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; fl "held for"; '"$HA"
A=$UF_OUT
noholds
uf_run "$H"'; kk.uses pb; __KK_IMG_MINLOAD=100 __KK_IMG_LOADMS=40 kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; fl "held for"; '"$HA"
B=$UF_OUT
UF_OUT="$A | $B"
a=${A##*age }; b=${B##*age }
[[ $A == "kbool: image: no image written: not worth an image: the normal load took 60 ms, under 100 ms (__KK_IMG_MINLOAD); a near miss: held 10 minutes"$'\n'"kbool: image: held for 10 minutes: "*"/pc-"*".hold"$'\n'"age "* \
   && $a == [0-9]* && $a != *[!0-9]* && a -ge 3000 && a -lt 3060 \
   && $B == "kbool: image: no image written: not worth an image: the normal load took 40 ms, under 100 ms (__KK_IMG_MINLOAD)"$'\n'"kbool: image: held for an hour: "*"/pc-"*".hold"$'\n'"age "* \
   && $b == [0-9]* && $b != *[!0-9]* && b -lt 60 ]]
uf_check "not worth it: a near miss (60 of 100 ms) is held 10 minutes, a clear miss (40 of 100) an hour [K2]" $?
noholds
uf_run "$H"'; kk.uses pb; __KK_IMG_MINLOAD= kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; ls "$FX/img" | grep -c "^pc-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: not worth an image: the normal load took "*" ms, a start of the image would cost about "*" ms here (the simulated start "*" ms + the steps before the writer "*" ms): under 1.5 times that"*$'\n'"1" ]]
uf_check "without the seam (chained): pc's few-ms load against its measured start — not worth an image, a hold [G4]" $?
noholds
uf_run "$H"'; __KK_IMG_MINLOAD= kk.image --rebuild pq 2>"$FX/e.txt"; fl "no image written"; ls "$FX/img" | grep -c "^pq-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: not worth an image: the normal load took "*" ms, a start of the image would cost about "*" ms here (the steps before the writer "*" ms): under 1.5 times that"*$'\n'"1" ]]
uf_check "without the seam (unchained): pq's load against the steps before the writer — not worth an image, a hold [G4]" $?
for f in "$FX"/img/pq-*.hold; do [[ -e $f ]] && rm -f "$f"; done
noholds
uf_run "$H"'; kk.uses pb; kk.image --rebuild pc 2>/dev/null'
if_pfield "$PCIMG" 4; PR=$IF_F
US=$'\x1f'
if_pfield "$PCIMG" 2; TAG=$IF_F
fakep() {   # fakep NAME WTIME PRIOR — an image file with the two lines pruning reads
    local p
    printf -v p '#P%s%s%s%012d%s%s%s%s%s%s%sdates%s-%s0%s0%s0' "$US" "$2" "$US" 100 "$US" "$TAG" "$US" "$FX" "$US" "$3" "$US" "$US" "$US" "$US" "$US"
    printf '# kbool image v1 %s\n%s\n' "$(( ${#p} + 1 ))" "$p" > "$FX/img/$1"
}
N=$EPOCHSECONDS
for i in 1 2 3 4 5 6 7 8 9; do fakep "pc-y000000$i.img" $(( N - 1000 + i )) "$PR"; done
for i in 1 2 3; do fakep "pc-x000000$i.img" $(( N - 2000 + i )) "00000000:pz"; done
printf 'x\n' > "$FX/img/pc-y0000001.fnc"
uf_run "$H"'; kk.uses pb; kk.image --rebuild pc 2>/dev/null'
L=""; for f in "$FX"/img/pc-[xy]*; do L+="${f##*/} "; done; UF_OUT=$L
[[ $L == "pc-x0000001.img pc-x0000002.img pc-x0000003.img pc-y0000003.img pc-y0000004.img pc-y0000005.img pc-y0000006.img pc-y0000007.img pc-y0000008.img pc-y0000009.img " ]]
uf_check "more than 8 images per (request, P): the oldest of that P go (with a .fnc), another P's are kept" $?
rm -f "$FX"/img/pc-[xy]*

# ---------------------------------------------------------------------------
kt_test_section "028: a caller's umask 002; the POSIX branch (emulated on Windows)"

UF_ENV=(KBOOL_IMAGE_DIR="$FX/u2" KBOOL_IMAGE_CHECK=dates)
uf_run "$H"'; umask 002; kk.uses pb; kk.image pc 2>/dev/null; echo "rc=$?"'
A=$UF_OUT
uf_run "$H"'; umask 002; kk.uses pb; kk.image pc 2>/dev/null; echo "rc=$? ${__KK_UNIT_PID[pc]-image} $(umask)"; ls "$FX/u2" | grep -c "\.tmp\."'
[[ $A == "rc=0" && $UF_OUT == "rc=0 image 0002"$'\n'"0" ]]
uf_check "umask 002: a chained image written, then a hit (the caller's umask kept), no temp left" $?
if (( ! WIN )); then
    md() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
    for f in "$FX"/u2/pc-*.img; do U2I=$f; done
    for r in "${U2I%.img}".*.ref; do :; done
    kt_test_start "umask 002 (POSIX): the chained image and its .ref are 600"
    if [[ $(md "$U2I") == 600 && $(md "$r") == 600 ]]; then kt_test_pass "ok"; else kt_test_fail "modes $(md "$U2I") $(md "$r")"; fi
fi
# the POSIX branch on every runtime: OSTYPE=linux-gnu after kbool.sh (the
# bits checked), stat mode through a stand-in stat that reports the folders
# and the image without their group / other write bits (the Windows
# runtimes make modes up — 023_ImageModes.sh); env for the fresh process
mkdir -p "$FX/fgw"
for t in mv rm mkdir head grep ls cat env; do
    printf '#!%s\nexec %q "$@"\n' "$REAL_BASH" "$(type -P "$t")" > "$FX/fgw/$t"; chmod +x "$FX/fgw/$t"
done
cat > "$FX/fgw/stat" <<EOF
#!$REAL_BASH
flag=\$1 fmt=\$2; shift 3
for p; do
    l=\$("$REAL_STAT" "\$flag" "\$fmt" -- "\$p") || exit 1
    m=\${l##* }
    if [[ -d \$p || \$p == *.img ]]; then printf -v m '%o' \$(( 8#\$m & ~8#022 )); fi
    printf '%s\n' "\${l% *} \$m"
done
EOF
chmod +x "$FX/fgw/stat"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/u3" KBOOL_IMAGE_CHECK=stat)
P="$H"'; OSTYPE=linux-gnu; PATH="$FX/fgw"; umask 002'
uf_run "$P"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; fl "wrote"; fl "no image written"'
A=$UF_OUT
uf_run "$P"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; fl "loaded from"; fl "wrote"'      # (a "racy" rewrite at most)
[[ $UF_OUT == *"loaded from"* ]] || uf_run "$P"'; kk.uses pb; kk.image pc 2>"$FX/e.txt"; fl "loaded from"; fl "wrote"'
[[ $A == "kbool: image: wrote $FX/u3/pc-"*".img" && $UF_OUT == "kbool: image: loaded from $FX/u3/pc-"*".img" ]]
uf_check "umask 002, the POSIX branch (OSTYPE=linux-gnu, stat mode, the bits checked): a chained image written in a fresh process, then a hit" $?
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)

kt_test_log "028_ImageChain.sh completed"
