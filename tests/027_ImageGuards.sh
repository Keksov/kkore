#!/usr/bin/env bash
# ImageGuards — the I2a critic round (kklass/docs/dev/IMAGE_PLAN.md; scratch
# p4/I2a_critic): H1 a caller's variable named like an image variable (a hit
# would write into it, or die on X[key] of an indexed one inside the source):
# a plain load; M1 a pre-existing variable a unit file assigns (an env preset
# of an internal self-default, a caller's local hiding a unit global): no
# image; M2 a hold that cannot be written under set -e; M3 a failed optional
# dependency is a negative edge; L1 the writer under a caller IFS=:; L2
# readonly functions, enable -n, complete -p; L5 an uncreatable folder costs
# no writer; L8 a relative KBOOL_IMAGE_DIR, --forget and a 64-character
# request name; and the cases the critic's mutations survived: another key's
# image under this file name, a hook VAR written outside its hook (the
# simulation), a umask change. Fixture: image_fixture.sh (dates mode).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImageGuards" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9; VERBOSE_KKLASS=debug'   # (debug in every key alike)
D='VERBOSE_KKLASS=debug'
WIN=0
if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then WIN=1; fi

if_unit "$FX" zz <<'EOF'
declare -gA ZZ_M=(["key two"]=2 [a.b]=1)
declare -g ZZ_S=unit
zz.n() { echo "n=${#ZZ_M[@]} two=${ZZ_M[key two]-none} s=${ZZ_S-none}"; }
EOF
if_unit "$FX" zp <<'EOF'
declare -gA ZP_M=([a]=1 [b]=2)
EOF
if_unit "$FX" zd <<'EOF'
: "${__ZD_P:=0}"
zd.p() { echo "p=${__ZD_P-unset}"; }
EOF
# zq (the critic's): globals set in an init function run at load and in an
# indented file-scope `if` — no column-0 assignment at all
if_unit "$FX" zq <<'EOF'
zq._init() {
    declare -g ZQ_G=fromfn
    : "${__ZQ_D:=5}"
}
zq._init
if [[ -z ${ZQ_C+x} ]]; then
    ZQ_C=guarded
fi
zq.v() { echo "g=${ZQ_G-unset} d=${__ZQ_D-unset} c=${ZQ_C-unset}"; }
EOF
# zvl (I3 fix 1, critic M1): a global declared without a value — after a
# start without it `ZVL_A[k]=1` would make an indexed array
if_unit "$FX" zvl <<'EOF'
declare -gA ZVL_A
zvl.k() { ZVL_A[k]=1; echo "kind=${ZVL_A@a}"; }
EOF
if_unit "$FX" zo <<'EOF'
if kk.uses --optional zdep; then ZO_MODE=dep; else ZO_MODE=fallback; fi
EOF
if_unit "$FX" ihv <<'EOF'
ihv._s() { IHV_X=${IHV_X:-1}; }
kk.settings ihv._s IHV_X || return
IHV_X=2
EOF
if_unit "$FX" ium <<'EOF'
umask 027
EOF
if_unit "$FX" zr <<'EOF'
zr.f() { :; }
if [[ ${ZR_WHAT-} == ro ]]; then readonly -f zr.f; fi
if [[ ${ZR_WHAT-} == en ]]; then enable -n test; fi
if [[ ${ZR_WHAT-} == co ]]; then complete -W x zr_cmd; fi
EOF
# zm: a public self-default (an exported preset is a candidate too)
if_unit "$FX" zm <<'EOF'
: "${MYAPP_X:=0}"
zm.v() { echo "x=${MYAPP_X-unset}"; }
EOF
# zf: a load that needs a caller's variable; zu: one whose units depend on it
# (the probe, without it, cannot do the same load: fail-closed)
if_unit "$FX" zf <<'EOF'
if [[ -z ${ZF_NEED-} ]]; then return 3; fi
ZF_V=1
EOF
if_unit "$FX" zu <<'EOF'
if [[ -n ${ZU_DEP-} ]]; then kk.uses ib || return; fi
ZU_V=1
EOF
# zk (the critic's xu.cfg repro): a unit outside the search folders, reached
# only through an unexported KBOOL_CONFIG's unitpath
mkdir -p "$FX/xu/zk"
cat > "$FX/xu/zk/zk.sh" <<'EOF'
[[ ${__KK_UNITS[@]@a} == A* ]] || source "$KBOOL_HOME/kbool.sh" || return
kk.unit zk || return $__kk_unit_rc
zk._init() {
    declare -g ZK_G=fromfn
}
zk._init
zk.v() { echo "g=${ZK_G-unset}"; }
EOF
printf 'unitpath = %s\n' "$FX/xu/*" > "$FX/xu.cfg"
touch -t 202001010000 "$FX/xu/zk/zk.sh" "$FX/xu.cfg"
touch -t 202001010000 "$FX"/kcl/*/*.sh

# ---------------------------------------------------------------------------
kt_test_section "027: H1 — a caller's variable named like an image variable"

uf_run "$H"'; kk.image zz 2>/dev/null'
uf_run "$H; $D"'; set -e; f() { local -a ZZ_M; kk.image zz 2>"$FX/e.txt"; echo "rc=$? ${ZZ_M[*]-}"; }; f; echo "survived $(zz.n)"; grep -c "exists in this shell already" "$FX/e.txt"'
[[ $UF_OUT == "rc=0 "$'\n'"survived n=2 two=2 s=unit"$'\n'"1" ]]
uf_check "set -e; f() { local -a ZZ_M; kk.image zz; }: no death — a plain load (the clash named), the script goes on" $?
uf_run "$H"'; f() { local -a ZZ_M; kk.image zz 2>/dev/null; echo "in=${#ZZ_M[@]}"; }; f; echo "out $(zz.n)"'
A=$UF_OUT
uf_run "$H"'; f() { local -a ZZ_M; KBOOL_IMAGE=off kk.image zz 2>/dev/null; echo "in=${#ZZ_M[@]}"; }; f; echo "out $(zz.n)"'
[[ $A == "$UF_OUT" ]]
uf_check "the same as a normal load in that caller (${A//$'\n'/ | })" $?
uf_run "$H; $D"'; declare -ga ZZ_M=(x); kk.image zz 2>&1 | grep -c "exists in this shell already"; kk.image zz 2>/dev/null; echo "rc=$?"'
[[ $UF_OUT == "1"$'\n'"rc="* ]]
uf_check "a global indexed array of that name: a plain load (no write into it)" $?
uf_run "$H; $D"'; f() { local ZZ_S=mine; kk.image zz 2>"$FX/e.txt"; echo "in=$ZZ_S"; }; f; echo "out=${ZZ_S-unset}"; grep -c "exists in this shell already" "$FX/e.txt"'
[[ $UF_OUT == "in=mine"$'\n'"out=unit"$'\n'"1" ]]
uf_check "a caller's local scalar (with a value): a plain load — the unit's declare -g sets the global, the local stays, as a normal load leaves them" $?
uf_run "$H; $D"'; f() { local -n ZZ_M=zz_tgt; kk.image zz 2>"$FX/e.txt"; echo "rc=$?"; }; f; grep -c "exists in this shell already" "$FX/e.txt"'
[[ $UF_OUT == "rc=0"$'\n'"1" ]]
uf_check "a caller's nameref of that name: a plain load" $?
uf_run "$H"'; set -e; f() { local -a ZZ_M=(); kk.image zz 2>"$FX/e.txt"; echo "rc=$?"; }; f; echo "survived $(zz.n)"; grep -c "exists in this shell already" "$FX/e.txt"'
[[ $UF_OUT == "rc=0"$'\n'"survived n=2 two=2 s=unit"$'\n'"1" ]]
uf_check "set -e; f() { local -a ZZ_M=(); kk.image zz; }: a plain load, the script goes on (\${!X@a} sees an array assigned ())" $?
# (a global indexed ZZ_M: the unit's own `declare -gA ZZ_M=(…)` fails in a
# normal load too — under set -e that ends the script either way)
uf_run "$H"'; declare -a ZZ_M=(); kk.image zz 2>"$FX/e.txt"; echo "rc=$? $(declare -p ZZ_M)"; grep -c "exists in this shell already" "$FX/e.txt"'
A=$UF_OUT
uf_run "$H"'; declare -a ZZ_M=(); KBOOL_IMAGE=off kk.image zz 2>/dev/null; echo "rc=$? $(declare -p ZZ_M)"; echo 1'
[[ $A == "$UF_OUT" && $A == *$'\n'1 ]]
uf_check "a global declare -a ZZ_M=() before kk.image: a plain load (the clash named) — the same as a normal load (${A%%$'\n'*})" $?
# a bare `local NAME` of an image ARRAY name (neither a value nor an
# attribute): before I4 not seen (the element lines then ended the script, a
# documented limit); the clash check is ONE declare -p over the names now,
# which sees it — a plain load, the script goes on
uf_run "$H; $D"'; f() { local ZZ_M; kk.image zz 2>"$FX/e.txt"; echo "rc=$?"; }; f; echo "survived $(zz.n)"; grep -c "exists in this shell already" "$FX/e.txt"'
[[ $UF_OUT == "rc=0"$'\n'"survived n=2 two=2 s=unit"$'\n'"1" ]]
uf_check "f() { local ZZ_M; kk.image zz; } (a bare local of an image array name): a plain load, the clash named, the script goes on — the limit before I4 is closed" $?
# bash < 5.3 reads that declare -p through the image's NAME.vck (made by the
# writer, a marker line closes it); __KK_IMG_VCKFILE takes that path on 5.3
uf_run "$H"'; kk.image --forget zz 2>/dev/null; __KK_IMG_VCKFILE=1 kk.image zz 2>/dev/null; ls "$FX/img" | grep -c "^zz-.*\.vck$"'
[[ $UF_OUT == 1 ]]
uf_check "the writer makes NAME.vck beside the image (bash < 5.3; forced by __KK_IMG_VCKFILE) [I4]" $?
E1='IFS= read -r l < "$FX/e.txt"; echo "$l"'
uf_run "$H; $D"'; __KK_IMG_VCKFILE=1; kk.image zz 2>"$FX/e.txt"; '"$E1"'; echo "${__KK_UNIT_PID[zz]-image}"'
[[ $UF_OUT == "kbool: image: loaded from "*"/zz-"*".img"$'\n'"image" ]]
uf_check "the clash check through NAME.vck: a hit when no name exists [I4]" $?
uf_run "$H; $D"'; __KK_IMG_VCKFILE=1; f() { local ZZ_M; kk.image zz 2>"$FX/e.txt"; echo "rc=$?"; }; f; echo "survived $(zz.n)"; grep -c "exists in this shell already" "$FX/e.txt"'
[[ $UF_OUT == "rc=0"$'\n'"survived n=2 two=2 s=unit"$'\n'"1" ]]
uf_check "... and a plain load when one exists (a bare local), the script goes on [I4]" $?
# NAME.vck that cannot serve (missing, a symbolic link — never followed —, not
# writable): one declare -p per name, the same answers
for VCK in "$FX"/img/zz-*.vck; do :; done
for v in gone link ro; do
    rm -f "$VCK" "$FX/vck.target"
    case $v in
        link) ln -s "$FX/vck.target" "$VCK" 2>/dev/null || { : > "$VCK"; v=link-copied; } ;;
        ro)   : > "$VCK"; chmod a-w "$VCK" ;;
    esac
    uf_run "$H; $D"'; __KK_IMG_VCKFILE=1; f() { local ZZ_M; kk.image zz 2>"$FX/e.txt"; echo "rc=$?"; }; f; echo "survived $(zz.n)"; grep -c "exists in this shell already" "$FX/e.txt"'
    A=$UF_OUT
    uf_run "$H; $D"'; __KK_IMG_VCKFILE=1; kk.image zz 2>"$FX/e.txt"; '"$E1"'; [[ -e "$FX/vck.target" ]] && echo followed'
    UF_OUT="$A | $UF_OUT"
    [[ $A == "rc=0"$'\n'"survived n=2 two=2 s=unit"$'\n'"1" && $UF_OUT == *" | kbool: image: loaded from "*"/zz-"*".img" ]]
    uf_check "NAME.vck $v: the clash check name by name — a plain load with a bare local, a hit without, nothing followed [I4]" $?
    chmod u+w "$VCK" 2>/dev/null; rm -f "$VCK" "$FX/vck.target"
done
# (I4 fix round 1, critic L4) NAME.vck a symbolic link to an EXISTING regular
# file: not followed (the target keeps its bytes), the check name by name —
# where this runtime makes a real link
uf_run "$H"'; __KK_IMG_VCKFILE=1 kk.image --rebuild zz 2>/dev/null'
for VCK in "$FX"/img/zz-*.vck; do :; done
rm -f "$VCK"; printf 'keep\n' > "$FX/vck.target"
if ln -s "$FX/vck.target" "$VCK" 2>/dev/null && [[ -L $VCK ]]; then
    uf_run "$H; $D"'; __KK_IMG_VCKFILE=1; f() { local ZZ_M; kk.image zz 2>"$FX/e.txt"; echo "rc=$?"; }; f; grep -c "exists in this shell already" "$FX/e.txt"; IFS= read -r -d "" t < "$FX/vck.target"; printf "target=%s" "$t"'
    [[ $UF_OUT == "rc=0"$'\n'"1"$'\n'"target=keep" ]]
    uf_check "NAME.vck a symbolic link to an existing file: not written through (the target keeps its bytes), the clash found name by name [I4 fix 1, L4]" $?
else
    kt_test_start "NAME.vck a symbolic link to an existing file [I4 fix 1, L4]"; kt_test_pass "no symbolic links on this runtime (ln -s copies): the link cases above cover the check"
fi
rm -f "$VCK" "$FX/vck.target"
# a NAME.vck that another start wrote between this start's write and read
# (__KK_IMG_VCKHOOK, run between them): a marker of the same image but another
# shell, or this start's own marker after a hole of NUL bytes (a truncation by
# another start: its names lost) — never "no name exists": the check name by
# name finds the bare local
uf_run "$H"'; __KK_IMG_VCKFILE=1 kk.image --rebuild zz 2>/dev/null'
VH='vh_foreign() { local z m; IFS= read -r -d "" z < "$1"; m=${z%$'"'"'\n'"'"'}; m=${m##*$'"'"'\n'"'"'}; printf "%s\n" "${m%%.*}.1.1" > "$1"; }
vh_hole() { local z m; IFS= read -r -d "" z < "$1"; m=${z%$'"'"'\n'"'"'}; m=${m##*$'"'"'\n'"'"'}; { printf "\0%.0s" 1 2 3 4 5 6 7 8; printf "%s\n" "$m"; } > "$1"; }'
for hk in vh_foreign vh_hole; do
    uf_run "$H; $D; $VH"'; __KK_IMG_VCKFILE=1 __KK_IMG_VCKHOOK='"$hk"'; f() { local ZZ_M; kk.image zz 2>"$FX/e.txt"; echo "rc=$?"; }; f; echo "survived $(zz.n)"; grep -c "exists in this shell already" "$FX/e.txt"'
    [[ $UF_OUT == "rc=0"$'\n'"survived n=2 two=2 s=unit"$'\n'"1" ]]
    uf_check "NAME.vck rewritten between write and read ($hk): not taken for \"no name exists\" — the bare local found name by name, a plain load [I4 fix 1, L4]" $?
done
# (I4 fix 1, L6) a result with names is not left in NAME.vck
uf_run "$H; $D"'; __KK_IMG_VCKFILE=1; f() { local ZZ_M; kk.image zz 2>/dev/null; }; f; for v in "$FX"/img/zz-*.vck; do [[ -s $v ]] && echo "left" || echo "empty"; done'
[[ $UF_OUT == "empty" ]]
uf_check "a clash found through NAME.vck: the file emptied after the read (no caller's records left beside the image) [I4 fix 1, L6]" $?
# (I4 fix 1, L1) the check's output sink cannot be opened (no free descriptor;
# __KK_IMG_NULL a folder stands for it): the declare -p and its marker do not
# run — never read as "no name exists" —, nor does the loop: a plain kk.uses
for vk in "" 1; do
    uf_run "$H; $D"'; __KK_IMG_VCKFILE='"$vk"' __KK_IMG_NULL="$FX"; kk.image zz 2>"$FX/e.txt"; echo "rc=$? ${__KK_UNIT_PID[zz]+normal}"; grep -c "the clash check could not run" "$FX/e.txt"'
    [[ $UF_OUT == "rc=0 normal"$'\n'"1" ]]
    uf_check "the clash check's sink cannot be opened (${vk:+NAME.vck, }no clash in fact): a plain kk.uses, the reason named — not a hit [I4 fix 1, L1]" $?
done
uf_run "$H"'; kk.image zp 2>/dev/null'
uf_run "$H"'; f() { local -a ZP_M; kk.image zp 2>/dev/null; echo "rc=$?"; }; f; declare -p ZP_M'
[[ $UF_OUT == "rc=0"$'\n'"declare -A ZP_M=([a]=\"1\" [b]=\"2\" )" || $UF_OUT == "rc=0"$'\n'"declare -A ZP_M=([b]=\"2\" [a]=\"1\" )" ]]
uf_check "plain keys (the critic's zp): the global table is complete — the image did not write into the caller's local" $?

# ---------------------------------------------------------------------------
kt_test_section "027: M1 — a pre-existing variable a unit file assigns"

uf_run "$H; $D"'; export __ZD_P=1; kk.image zd 2>"$FX/e.txt"; grep "no image written\|held for" "$FX/e.txt"; zd.p'
[[ $UF_OUT == "kbool: image: no image written: the variable __ZD_P existed before the load, and the load sets it when it does not"*$'\n'"kbool: image: held for an hour: "*$'\n'"p=1" ]]
uf_check "(a) an environment preset of an internal self-default (: \"\${__ZD_P:=0}\"): no image, a hold — a later start without the preset would lack it" $?
uf_run "$H"'; kk.image --forget zd 2>/dev/null; kk.image zd 2>/dev/null; zd.p'
uf_run "$H"'; kk.image zd 2>/dev/null; zd.p; echo "${__KK_UNIT_PID[zd]-image}"'
[[ $UF_OUT == "p=0"$'\n'"image" ]]
uf_check "(without the preset the image is written and hits, p=0)" $?
uf_run "$H; $D"'; kk.image --forget zz 2>/dev/null; f() { local ZZ_S=mine; kk.image zz 2>"$FX/e.txt"; }; f; grep "no image written" "$FX/e.txt"'
[[ $UF_OUT == "kbool: image: no image written: the variable ZZ_S existed before the load, and the load sets it when it does not"* ]]
uf_check "(b) a caller's local hiding a unit global (f() { local ZZ_S=mine; kk.image zz; }): no image" $?
uf_run "$H"'; kk.image --forget zz 2>/dev/null; main() { kk.image zz 2>/dev/null; echo "rc=$?"; }; main'
uf_run "$H"'; main() { kk.image zz 2>/dev/null; echo "rc=$? ${__KK_UNIT_PID[zz]-image} $(zz.n)"; }; main'
[[ $UF_OUT == "rc=0 image n=2 two=2 s=unit" ]]
uf_check "a script with a main() function (no clash): written and hit below top level" $?
for c in 'f() { local ZQ_G=mine; kk.image zq 2>"$FX/e.txt"; }; f' 'export __ZQ_D=1; kk.image zq 2>"$FX/e.txt"' 'ZQ_C=preset; kk.image zq 2>"$FX/e.txt"' 'export ZQ_C=guarded; kk.image zq 2>"$FX/e.txt"'; do
    uf_run "$H"'; kk.image --forget zq 2>/dev/null; '"$c"'; grep -o "the variable [A-Z_]* existed before the load, and the load sets it when it does not" "$FX/e.txt"'
    n=${c#*local }; n=${n#export }; n=${n%%=*}
    [[ $UF_OUT == "the variable $n existed before the load, and the load sets it when it does not" ]]
    uf_check "zq: $n set before the load (${c%%;*}) and set by the load in an init function / an indented if: no image (the probe)" $?
done
uf_run "$H"'; kk.image --forget zq 2>/dev/null; kk.image zq 2>/dev/null'
uf_run "$H"'; kk.image zq 2>/dev/null; echo "${__KK_UNIT_PID[zq]-image} $(zq.v)"'
[[ $UF_OUT == "image g=fromfn d=5 c=guarded" ]]
uf_check "zq without those presets: written, then a hit with all three set" $?
# (critic M1, I3 fix 1) a caller's local named like a global the unit declares
# WITHOUT a value (declare -gA ZVL_A): the probe's checks read ${!X@a}, empty for
# such a variable — so the image was written without ZVL_A and a later start
# made `ZVL_A[k]=1` an indexed array; now the probe reports it: no image
for c in 'local -A ZVL_A' 'local -A ZVL_A=()'; do
    uf_run "$H"'; kk.image --forget zvl 2>/dev/null; f() { '"$c"'; kk.image zvl 2>"$FX/e.txt"; }; f; grep -o "the variable [A-Z_]* existed before the load, and the load sets it when it does not" "$FX/e.txt"; zvl.k'
    [[ $UF_OUT == "the variable ZVL_A existed before the load, and the load sets it when it does not"$'
'"kind=A" ]]
    uf_check "zvl: a caller's '$c' hiding the unit's value-less 'declare -gA ZVL_A': no image (the probe sees a variable without a value) [I3 fix 1 M1]" $?
done
uf_run "$H"'; kk.image --forget zvl 2>/dev/null; kk.image zvl 2>/dev/null'
uf_run "$H"'; kk.image zvl 2>/dev/null; echo "${__KK_UNIT_PID[zvl]-image} $(zvl.k)"'
[[ $UF_OUT == "image kind=A" ]]
uf_check "zvl without the local: written, a hit keeps ZVL_A associative" $?
uf_run "$H"'; value=1 rc=2 y=3 i=4; kk.image --forget zz 2>/dev/null; kk.image zz 2>&1 | grep -c "^kbool: image: wrote "'
[[ $UF_OUT == 1 ]]
uf_check "ordinary caller globals (value rc y i) that the units do not set: no false refusal" $?
# an exported public preset is a candidate too (critic M1 round 3)
uf_run "$H"'; export MYAPP_X=1; kk.image zm 2>"$FX/e.txt"; grep -o "the variable [A-Z_]* existed before the load, and the load sets it when it does not" "$FX/e.txt"; zm.v'
A=$UF_OUT
uf_run "$H"'; kk.image --forget zm 2>/dev/null; kk.image zm 2>/dev/null'
uf_run "$H"'; kk.image zm 2>/dev/null; echo "${__KK_UNIT_PID[zm]-image} $(zm.v)"'
[[ $A == "the variable MYAPP_X existed before the load, and the load sets it when it does not"$'\n'"x=1" && $UF_OUT == "image x=0" ]]
uf_check "an exported MYAPP_X and a unit with : \"\${MYAPP_X:=0}\": no image; without it written, a hit gives x=0" $?
# the probe does this shell's load: an unexported KBOOL_CONFIG (the critic's
# xu.cfg repro, unitpath to zk), a script that cd's after loading kbool
X='KBOOL_CONFIG="$FX/xu.cfg"; '"$H"
uf_run "$X"'; f() { local ZK_G=mine; kk.image zk 2>"$FX/e.txt"; }; f; grep -o "the variable [A-Z_]* existed before the load, and the load sets it when it does not" "$FX/e.txt"'
A=$UF_OUT
# a script run as ./app.sh that cd's after loading kbool: its relative
# spelling is resolved against the PWD it was loaded from (U43), in the probe too
cat > "$FX/xu/app.sh" <<'EOF2'
source "$FX/kbool.sh" || exit 9
VERBOSE_KKLASS=debug
cd "$FX/cwd" || exit 9
f() { local ZK_G=mine; kk.image zk/zk.sh 2>"$FX/e.txt"; }
f
grep -o "the variable [A-Z_]* existed before the load, and the load sets it when it does not" "$FX/e.txt"
EOF2
uf_run 'cd "$FX/xu" && "$BASH" ./app.sh'
B=$UF_OUT
uf_run "$X"'; kk.image --forget zk 2>/dev/null; kk.image zk 2>/dev/null'
uf_run "$X"'; kk.image zk 2>/dev/null; echo "${__KK_UNIT_PID[zk]-image} $(zk.v)"'
[[ $A == "the variable ZK_G existed before the load, and the load sets it when it does not" && $A == "$B" && $UF_OUT == "image g=fromfn" ]]
uf_check "an unexported KBOOL_CONFIG / a relative script spelling after a cd: the probe does the same load (ZK_G found, no image); without the local written and hit" $?
# fail-closed: a probe that cannot do the same load refuses, with a hold
cp "$FX/xu.cfg" "$FX/xu2.cfg"
uf_run 'KBOOL_CONFIG="$FX/xu2.cfg"; '"$H"'; kk.image --forget zk 2>/dev/null; rm -f "$FX/xu2.cfg"; f() { local ZK_G=mine; kk.image zk 2>"$FX/e.txt"; echo "rc=$? $(zk.v)"; }; f; grep "no image written\|held for" "$FX/e.txt"; ls "$FX/img" | grep -c "^zk-.*\.hold$"'
[[ $UF_OUT == "rc=0 g=mine"$'\n'"kbool: image: no image written: the fresh-process probe of the variables ZK_G cannot do this load: it gave no result"*$'\n'"kbool: image: held for an hour: "*$'\n'"1" ]]
uf_check "a probe that cannot start (its KBOOL_CONFIG gone): no image, a hold; the load itself done" $?
uf_run "$H"'; ZF_NEED=1; kk.image zf 2>"$FX/e.txt"; echo "rc=$? $ZF_V"; grep -o "cannot do this load: its load failed (rc [0-9]*)" "$FX/e.txt"; ls "$FX/img" | grep -c "^zf-.*\.hold$"'
[[ $UF_OUT == "rc=0 1"$'\n'"cannot do this load: its load failed (rc "*")"$'\n'"1" ]]
uf_check "a load that needs a caller's variable (ZF_NEED): the probe's load fails — no image, a hold" $?
uf_run "$H"'; ZU_DEP=1; kk.image zu 2>"$FX/e.txt"; echo "rc=$? $ZU_V $IB_V"; grep -o "cannot do this load: it loaded other units" "$FX/e.txt"; ls "$FX/img" | grep -c "^zu-.*\.hold$"'
[[ $UF_OUT == "rc=0 1 7"$'\n'"cannot do this load: it loaded other units"$'\n'"1" ]]
uf_check "units that depend on a caller's variable (ZU_DEP): the probe loads other units — no image, a hold" $?

# ---------------------------------------------------------------------------
kt_test_section "027: M2 / M3 / L1 / L2 / L5 / L8"

uf_run "$H; $D"'; kk.image ib 2>&1 | grep -o "wrote .*"'
IBIMG=${UF_OUT#wrote }
mkdir -p "${IBIMG%.img}.hold"
touch "$FX/kcl/ib/ib.sh"
uf_run "$H; $D"'; set -e; kk.image ib 2>/dev/null; echo "survived $(ib.f)"'
rmdir "${IBIMG%.img}.hold"; touch -t 202001010000 "$FX/kcl/ib/ib.sh"
[[ $UF_OUT == "survived ib.f" ]]
uf_check "M2: a hold that cannot be written (a folder named NAME.hold) under set -e: the script goes on" $?

uf_run "$H; $D"'; kk.image zo 2>/dev/null; echo "$ZO_MODE"'
A=$UF_OUT
if_unit "$FX" zdep <<'EOF'
ZDEP_V=1
EOF
touch -t 202001010000 "$FX/kcl/zdep/zdep.sh"
for f in "$FX"/img/zo-*.img; do if_age "$f" 3600; done
uf_run "$H; $D"'; kk.image zo 2>"$FX/e.txt"; echo "$ZO_MODE"; grep -o "not found when the image was made, is found now" "$FX/e.txt"'
rm -rf "$FX/kcl/zdep"
[[ $A == fallback && $UF_OUT == "dep"$'\n'"not found when the image was made, is found now" ]]
uf_check "M3: a failed optional dependency is a negative edge: installed later, the image is stale and the new load takes it" $?
# N1: a header-less zdep.sh in a search folder is no unit (kk.uses does not
# find it by name): the negative edge still holds — a hit, not stale forever
uf_run "$H"'; kk.image --forget zo 2>/dev/null; kk.image zo 2>/dev/null'
mkdir -p "$FX/kcl/zdep"; printf '%s\n' 'ZDEP_PLAIN=1' > "$FX/kcl/zdep/zdep.sh"; touch -t 202001010000 "$FX/kcl/zdep/zdep.sh"
uf_run "$H"'; kk.image zo 2>&1 | { head -1; cat >/dev/null; }; kk.image zo 2>/dev/null; echo "$ZO_MODE"'
A=$UF_OUT
uf_run "$H"'; kk.image zo 2>&1; echo "$ZO_MODE ${ZDEP_PLAIN-none}"'
rm -rf "$FX/kcl/zdep"
[[ $UF_OUT == "kbool: image: loaded from $FX/img/zo-"*".img"$'\n'"fallback none" && $A != *stale* ]]
uf_check "N1: a header-less NAME.sh in a search folder: the negative edge holds (kk._unit_find resolves nothing) — a hit" $?

uf_run "$H; $D"'; f() { local IFS=:; kk.image ib 2>&1 | grep -c "file descriptor"; }; kk.image --forget ib 2>/dev/null; f'
[[ $UF_OUT == 0 ]]
uf_check "L1: the writer under a caller's local IFS=: (no false 'file descriptor' refusal)" $?

for w in ro:fattr en:enable co:complete; do
    uf_run "$H; $D"'; ZR_WHAT='"${w%%:*}"' kk.image zr 2>&1 | grep "no image written"; kk.image --forget zr 2>/dev/null'
    [[ $UF_OUT == "kbool: image: no image written: the load changed the shell state: ${w#*:}" ]]
    uf_check "L2: a load that does ${w%%:*} (readonly -f / enable -n / complete): no image (${w#*:})" $?
done

if (( ! WIN )) && (( EUID != 0 )); then
    mkdir -p "$FX/ro"; chmod 555 "$FX/ro"
    UF_ENV=(KBOOL_IMAGE_DIR="$FX/ro/img" KBOOL_IMAGE_CHECK=dates)
    uf_run "$H; $D"'; kk.image ib 2>&1 | { head -1; cat >/dev/null; }; declare -F kk._img_write >/dev/null && echo "writer sourced" || echo "no writer"'
    chmod 755 "$FX/ro"
    [[ $UF_OUT == "kbool: image: the image folder $FX/ro/img cannot be made ($FX/ro is not a writable folder); a normal load"*$'\n'"no writer" ]]
    uf_check "L5: an image folder that cannot be made: a plain kk.uses without the writer (no kimage.sh, no mkdir)" $?
fi
: > "$FX/afile"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/afile/img" KBOOL_IMAGE_CHECK=dates)
uf_run "$H; $D"'; kk.image ib 2>&1 | { head -1; cat >/dev/null; }; declare -F kk._img_write >/dev/null && echo "writer sourced" || echo "no writer"'
[[ $UF_OUT == "kbool: image: the image folder $FX/afile/img cannot be made ($FX/afile is not a writable folder); a normal load"*$'\n'"no writer" ]]
uf_check "L5: a folder under a regular file: a plain kk.uses without the writer" $?
UF_ENV=(KBOOL_IMAGE_DIR=rel/img KBOOL_IMAGE_CHECK=dates)
uf_run "$H; $D"'; kk.image ib 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: KBOOL_IMAGE_DIR=rel/img is not an absolute path; a normal load (kk.uses ib)" ]]
uf_check "L8: a relative KBOOL_IMAGE_DIR: a plain load (a debug line)" $?
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)

# two requests whose names cut at 64 characters are one stem
L64=$(printf 'z%.0s' {1..70})
mkdir -p "$FX/kcl/${L64}a" "$FX/kcl/${L64}b"
for s in a b; do
    printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%'"$L64$s"'.sh}../../kbool.sh" || return' \
        "kk.unit $L64$s || return \$__kk_unit_rc" "V$s=1" > "$FX/kcl/$L64$s/$L64$s.sh"
done
touch -t 202001010000 "$FX/kcl/$L64"?/*.sh
uf_run "$H"'; kk.image '"${L64}a"' 2>/dev/null'
uf_run "$H"'; kk.image '"${L64}b"' 2>/dev/null'
n0=0; for f in "$FX"/img/"${L64:0:64}"-*.img; do n0=$(( n0 + 1 )); done
uf_run "$H; $D"'; kk.image --forget '"${L64}a"
n1=0; for f in "$FX"/img/"${L64:0:64}"-*.img; do n1=$(( n1 + 1 )); done
# (bash < 5.3: the image's NAME.vck goes with it too — I4)
nf=2; (( BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 3 )) && nf=3
[[ $n0 == 2 && $n1 == 1 && $UF_OUT == "kbool: image: --forget: $nf file(s) of '${L64:0:64}' removed from $FX/img" ]]
uf_check "L8: --forget of a request whose 64-character name is another's: only its own image (and .ref, and on bash < 5.3 its .vck) go, matched by the request hash ($n0 -> $n1)" $?

# ---------------------------------------------------------------------------
kt_test_section "027: what the critic's mutations survived"

# key: another key's image (VERBOSE_KKLASS=quiet: the same request, edges and
# files) put under this key's file name — "another key", never a hit
rm -f "$FX"/img/*
uf_run "$H"'; kk.image ia 2>/dev/null'
for f in "$FX"/img/ia-*.img; do IMGA=$f; done
uf_run "$H"'; VERBOSE_KKLASS=quiet kk.image ia 2>/dev/null'
for f in "$FX"/img/ia-*.img; do [[ $f == "$IMGA" ]] || IMGQ=$f; done
cp "$IMGQ" "$IMGA"
uf_run "$H; $D"'; kk.image ia 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: the image has another key: a normal load, then an image" ]]
uf_check "key: an image of another key under this file name is not used (the key compare)" $?

uf_run "$H; $D"'; kk.image ihv 2>&1 | grep "no image written"'
[[ $UF_OUT == "kbool: image: no image written: the simulated image start differs: V:IHV_X"* ]]
uf_check "the simulation: a hook VAR written outside its hook (IHV_X=2 after kk.settings) — no image" $?
uf_run "$H; $D"'; kk.image ium 2>"$FX/e.txt"; grep "no image written" "$FX/e.txt"; umask'
[[ $UF_OUT == "kbool: image: no image written: the load changed the shell state: umask"$'\n'"0027" ]]
uf_check "a load that changes the umask: no image; the umask the load set stays (as a normal load leaves it)" $?

kt_test_log "027_ImageGuards.sh completed"
