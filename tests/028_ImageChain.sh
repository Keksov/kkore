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
# reader's side is a documented limit, asserted); holds and pruning per
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
#        __PB_N (D6), a variable PB_V, a function pb.f
#   pc   uses pb; adds to its registry and list, increments __PB_N, copies
#        PB_V (a READ of P's state: the reader's side of R13)
#   pd   uses pb; redefines pb.f
#   pe   uses pb; changes and removes registry elements, keys that are not
#        plain (a blank, `$(`, `@`, `]`)
#   pr   uses pb; changes the caller's PRX (no P slot: refused)
#   pq, pz  other prior units
if_unit "$FX" pb <<'EOF'
PB_V=1
declare -gA PB_REG=([pb]=1 [old]=o ['o k']=ok ['o j']=oj)
declare -ga PB_LIST=(pb)
: "${__PB_N:=0}"
pb.f() { echo "pb.f"; }
pb.g() { PB_G=orig; }
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

# keys that are not plain, a change and a removal of P's elements
uf_run 'bash "$FX/ch.sh" miss pb pe "$FX/e0.d" >/dev/null; bash "$FX/ch.sh" hit pb pe "$FX/e1.d"; bash "$FX/ch.sh" plain pb pe "$FX/e2.d"; bash "$FX/cmp.sh" "$FX/e2.d" "$FX/e1.d"'
A=$UF_OUT
uf_run "$H"'; kk.uses pb; kk.image pe 2>/dev/null; echo "${__KK_UNIT_PID[pe]-image}"; pe.n'
[[ $A == "hit rc=0 "$'\n'"plain rc=0 loaded"$'\n'"cmp rc=0 " && $UF_OUT == "image"$'\n'"pe 5 changed gone v0 v2" ]]
uf_check "element deltas on P's registry: a change, a removal, keys with a blank, \$( and @ — the hit's state equals a normal load's" $?
uf_run "$H"'; kk.uses pb; PB_REG[pb]=other; kk.image pe 2>"$FX/e.txt"; e1; pe.n; echo "$PE_SAW"'
[[ $UF_OUT == "kbool: image: PB_REG[pb] differs from the image's base; a normal load (kk.uses pe)"$'\n'"pe 5 changed gone v0 v2"$'\n'"other/o" ]]
uf_check "an element the delta changes holds another value: a plain kk.uses" $?
uf_run "$H"'; IFS=:; kk.uses pb; kk.image --rebuild pe 2>"$FX/e.txt"; fl "wrote"; fl "no image written"'
A=$UF_OUT
uf_run "$H"'; kk.uses pb; kk.image pe 2>/dev/null; echo "${__KK_UNIT_PID[pe]-image}"; pe.n'
[[ $A == "kbool: image: wrote "*"/pe-"*".img" && $UF_OUT == "image"$'\n'"pe 5 changed gone v0 v2" ]]
uf_check "written under a caller's IFS=: (the loop form of keys that are not plain joins its lists itself), then a hit" $?

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
uf_check "a truncated image that changed and removed P's elements: undone (both put back), then the normal load" $?

# ---------------------------------------------------------------------------
kt_test_section "028: the writer's fresh-process simulation (§5.2; R13)"

noholds
uf_run "$H"'; kk.uses pb; kk.image pc 2>/dev/null'
uf_run "$H"'; kk.uses pb; PB_V=9; kk.image pc 2>/dev/null; echo "copy=$PC_COPY ${__KK_UNIT_PID[pc]-image}"'
[[ $UF_OUT == "copy=1 image" ]]
uf_check "R13, the reader's side (a documented limit): an image made against an unchanged P hits after the script changed P's PB_V, which pc's load reads — PC_COPY=1 where a normal load gives 9" $?
uf_run "$H"'; kk.uses pb; PB_V=9; kk.image --rebuild pc 2>"$FX/e.txt"; fl "no image written"; echo "copy=$PC_COPY"; ls "$FX/img" | grep -c "^pc-.*\.hold$"'
[[ $UF_OUT == "kbool: image: no image written: the simulated image start differs: V:PB_V differs from the writer's"$'\n'"copy=9"$'\n'"1" ]]
uf_check "R13, the writer's side: the script changed P before kk.image — the fresh process (P as its own load leaves it) differs: no image, a hold" $?
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
