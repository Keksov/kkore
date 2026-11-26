#!/usr/bin/env bash
# ImageRefuse — what gets no image, and what an image is trusted from
# (kklass/docs/dev/IMAGE_PLAN.md §6.3, §6.4, §8; stage I2a-2): a load that
# leaves a file descriptor open or closes one (kklass's pair excepted —
# 027/kcl), starts a background job or a coprocess, changes the hash table
# outside its hooks (a hook that does is fine: the hooks run on every start),
# an alias, a function attribute, a shell option, stores the shell's pid in a
# plain scalar outside the hooks (held 10 minutes; a readonly or integer one is
# a constant: imaged — I3 fix 1, 2); IMG-D9 (`&> "$f"`: written
# on bash >= 5.2; refused on bash < 5.2 — the branch tested by overriding
# kk._img_oldbash; a real 5.1 runs it on the CI alpine 5.1 row); the CR
# matrix (a function with $'\r' in a string, in a pattern, a raw CR in a
# here-doc — each round-trips or is refused as §6.4 says, per runtime; kklass
# copied into the fixture for kk._fn_text_cr); trust: a junction (Windows,
# `cmd /c mklink /J`, no admin rights) as the image folder and as a parent
# level, the WARNING exactly once per process. Fixture: image_fixture.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImageRefuse" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9; VERBOSE_KKLASS=debug'
WIN=0
if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then WIN=1; fi
cp "$UF_REAL"/kklass/*.sh "$FX/kklass/" || { kt_test_start "fixture"; kt_test_fail "no kklass"; exit 1; }

if_unit "$FX" ifd <<'EOF'
exec {IFD_FD}>/dev/null
EOF
if_unit "$FX" ifdc <<'EOF'
exec 7>&-
EOF
# (both end by themselves within 2 s; the cases `wait` for them)
if_unit "$FX" ijob <<'EOF'
sleep 2 &
EOF
if_unit "$FX" icop <<'EOF'
coproc ICOP { read -r -t 2 ICOP_X; }
EOF
if_unit "$FX" ihash <<'EOF'
hash -p /kbool/no/such/cmd kbool_fake_cmd
EOF
if_unit "$FX" ihashk <<'EOF'
ihashk._s() { hash -p /kbool/no/such/cmd2 kbool_hook_cmd; }
kk.settings ihashk._s || return
EOF
if_unit "$FX" ial <<'EOF'
alias kbool_al=:
EOF
if_unit "$FX" ift <<'EOF'
ift.f() { :; }
declare -ft ift.f
EOF
if_unit "$FX" iopt <<'EOF'
shopt -s nullglob
EOF
# ipid (I3 fix 1, critic M3): pid state stored at load outside any hook
if_unit "$FX" ipid <<'EOF'
declare -g IPID_P=$BASHPID
EOF
# ipidc (I3 fix 2): a readonly and an integer global that equal the pid —
# constants by kind (a pid coincidence with fv's FV_OF_CENTERED=768 on
# Cygwin): no pid state, imaged
if_unit "$FX" ipidc <<'EOF'
[[ -n ${IPIDC_R+x} ]] || declare -gr IPIDC_R=$BASHPID
declare -gi IPIDC_I=$BASHPID
EOF
if_unit "$FX" id9 <<'EOF'
id9.f() { echo "to $1" &> "$1"; }
EOF
touch -t 202001010000 "$FX"/kcl/*/*.sh

# ---------------------------------------------------------------------------
kt_test_section "026: no image (§6.3): descriptors, jobs, coprocesses, the hash table, the shell state"

# refused U WHY [PRE [POST]] — kk.image U (PRE before it, POST after it):
# the "no image written" line is WHY, the unit is loaded (rc 0), no image
refused() {
    uf_run "$H; ${3:-:}"'; kk.image '"$1"' 2>"$FX/e.txt"; echo "rc=$? ${__KK_UNITS['"$1"']+loaded}"; '"${4:-:}"'; while IFS= read -r l; do [[ $l == *"no image written"* ]] && echo "$l"; done < "$FX/e.txt"'
    if_imgs
    [[ $UF_OUT == "rc=0 loaded"$'\n'"kbool: image: no image written: "$2 && $IF_IMGS != *"$1-"* ]]
    uf_check "unit $1: no image ($2), the unit loaded, rc 0" $?
}
refused ifd "the load left the file descriptor "[0-9]*" open"
refused ifdc "the load closed the file descriptor 7" 'exec 7>/dev/null'
refused ijob "the load changed the shell state: jobs" ':' 'wait'
refused icop "the load changed the shell state: jobs" ':' 'wait'
refused ihash "the simulated image start differs: the load changed the hash table (kbool_fake_cmd) outside the settings hooks"
refused ial "the load changed the shell state: alias"
refused ift "the load changed the shell state: fattr"
refused iopt "the load changed the shell state: options"
refused ipid "the load stored this shell's pid in IPID_P outside the settings hooks (pid state: a hook VAR sets it on every start; or a constant that equals this pid by chance): held 10 minutes"
# (I3 fix 2) the pid refusal's hold is the short one — dated 50 minutes back,
# as kk._img__worth's near miss (028 K2): a pid coincidence is gone on the
# next start
uf_run "$H"'; for f in "$FX"/img/ipid-*.hold; do read -r t r < "$f"; echo "age $(( EPOCHSECONDS - t ))"; done; while IFS= read -r l; do [[ $l == *"held for"* ]] && echo "${l%%:*}"; done < "$FX/e.txt"'
a=${UF_OUT#age }; a=${a%%$'\n'*}
[[ $UF_OUT == "age "*$'\n'"kbool" && $a == [0-9]* && $a != *[!0-9]* ]] && (( a >= 3000 && a < 3060 ))
uf_check "the pid refusal is held 10 minutes (the hold dated 50 minutes back), not an hour [I3 fix 2]" $?
uf_run "$H"'; kk.image ipidc 2>"$FX/e.txt"; while IFS= read -r l; do [[ $l == *"no image written"* || $l == *"image: wrote "* ]] && echo "${l%% /*}"; done < "$FX/e.txt"'
A=$UF_OUT
uf_run "$H"'; kk.image ipidc 2>&1; echo "${__KK_UNIT_PID[ipidc]-image} r=$(( IPIDC_R > 0 )) i=${IPIDC_I@a}"'
UF_OUT="$A | $UF_OUT"
[[ $A == "kbool: image: wrote" && $UF_OUT == *" | kbool: image: loaded from $FX/img/ipidc-"*".img"$'\n'"image r=1 i=i" ]]
uf_check "a readonly and an integer global equal to the pid (constants by kind): imaged, a hit [I3 fix 2]" $?
uf_run "$H"'; kk.image ihashk 2>&1 | grep -c "wrote"'
A=$UF_OUT
uf_run "$H"'; kk.image ihashk 2>&1; echo "${BASH_CMDS[kbool_hook_cmd]-none}"'
[[ $A == 1 && $UF_OUT == "kbool: image: loaded from $FX/img/ihashk-"*".img"$'\n'"/kbool/no/such/cmd2" ]]
uf_check "a hash-table change made by a settings hook: imaged (the hook makes it again on every start: the entry is there after a hit)" $?

# ---------------------------------------------------------------------------
kt_test_section "026: IMG-D9 — bash < 5.2 and &> \"\$"

old=0; (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2) )) && old=1
uf_run "$H"'; kk.image id9 2>&1 | grep "wrote\|no image written"'
if (( old )); then
    [[ $UF_OUT == "kbool: image: no image written: bash $BASH_VERSION (< 5.2) and a function text with &> \"\$ (IMG-D9)" ]]
    uf_check "bash $BASH_VERSION (< 5.2): a function text with &> \"\$: no image [IMG-D9]" $?
else
    [[ $UF_OUT == "kbool: image: wrote $FX/img/id9-"*".img" ]]
    uf_check "bash $BASH_VERSION (>= 5.2): a function with &> \"\$f\" is imaged [IMG-D9]" $?
fi
rm -f "$FX"/img/id9-*
# (kk._img_oldbash lives in kimage.sh, sourced lazily: kk._image_lib first,
# then the override — kk._image_lib does not source it again)
uf_run "$H"'; kk._image_lib; kk._img_oldbash() { return 0; }; kk.image id9 2>"$FX/e.txt"; grep "no image written" "$FX/e.txt"; id9.f "$FX/d9.out"; cat "$FX/d9.out"'
[[ $UF_OUT == "kbool: image: no image written: bash $BASH_VERSION (< 5.2) and a function text with &> \"\$ (IMG-D9)"$'\n'"to $FX/d9.out" ]]
uf_check "the bash < 5.2 branch (kk._img_oldbash overridden to rc 0): no image; the function works" $?
uf_run "$H"'; kk._image_lib; kk._img_oldbash() { return 0; }; kk.image ib 2>&1 | grep -c wrote'
[[ $UF_OUT == 1 ]]
uf_check "(the same override and a unit without &> \"\$: imaged)" $?

# ---------------------------------------------------------------------------
kt_test_section "026: CR functions (§6.4, IMG-D7), per runtime"

cr=$(printf '\r')
eval "probe='$cr'"
drops=0; [[ -z $probe ]] && drops=1
if_unit "$FX" icrs <<'EOF'
kk.uses kklass || return
icrs.f() { local s=$'a\rb'; echo "s=${#s}"; }
EOF
if_unit "$FX" icrp <<'EOF'
kk.uses kklass || return
icrp.f() { local x=$'1\r2'; if [[ $x == *$'\r'* ]]; then echo "p=cr"; else echo "p=none"; fi; }
EOF
# icrh: a raw CR byte inside a here-doc body (dropped by a CR-dropping
# parser already when the unit is sourced)
mkdir -p "$FX/kcl/icrh"
{
    printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%icrh.sh}../../kbool.sh" || return' \
        'kk.unit icrh || return $__kk_unit_rc' 'kk.uses kklass || return' 'icrh.f() {' '    local t' '    t=$(cat <<HD'
    printf 'x%sy\n' "$cr"
    printf '%s\n' 'HD' ')' '    echo "h=${#t}"' '}'
} > "$FX/kcl/icrh/icrh.sh"
touch -t 202001010000 "$FX"/kcl/*/*.sh "$FX"/kklass/*.sh
cat > "$FX/cr.sh" <<'EOF'
# cr.sh MODE UNIT DUMP — load UNIT (plain: KBOOL_IMAGE=off), run its function, dump
source "$FX/kbool.sh" || exit 9
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image "$2"; else VERBOSE_KKLASS=debug kk.image "$2" 2>"$3.err"; fi
echo "$1 rc=$? $("$2.f")"
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
kk._img_state "$3" canon
EOF
for u in icrs icrp icrh; do
    uf_run 'bash "$FX/cr.sh" miss '"$u"' "$FX/c0.d"; bash "$FX/cr.sh" hit '"$u"' "$FX/c1.d"; bash "$FX/cr.sh" plain '"$u"' "$FX/c2.d"; bash "$FX/cmp.sh" "$FX/c2.d" "$FX/c1.d"; :'
    W=""; while IFS= read -r l; do [[ $l == *"no image written"* || $l == *"wrote "* ]] && W=$l; done < "$FX/c0.d.err"
    H1=""; while IFS= read -r l; do [[ $l == *"loaded from"* ]] && H1=$l; done < "$FX/c1.d.err"
    want=${UF_OUT%%$'\n'*}; want=${want#miss rc=0 }
    if [[ $W == *"wrote "* ]]; then
        [[ $UF_OUT == "miss rc=0 $want"$'\n'"hit rc=0 $want"$'\n'"plain rc=0 $want"$'\n'"cmp rc=0 " && -n $H1 && $want == [shp]=* ]]
        uf_check "$u (CR dropped by this parser: $drops): imaged, the hit's function behaves as a normal load's ($want), the state equal [§6.4]" $?
    else
        [[ $W == *"no image written: the CR bytes of function"*"cannot be rewritten (kk._fn_text_cr)" && $UF_OUT == "miss rc=0 $want"$'\n'"hit rc=0 $want"$'\n'"plain rc=0 $want"* && -z $H1 ]]
        uf_check "$u (CR dropped by this parser: $drops): refused (kk._fn_text_cr rc 1), the function works ($want) [§6.4]" $?
    fi
done
uf_run 'bash "$FX/cr.sh" plain icrs "$FX/c3.d"'
[[ $UF_OUT == "plain rc=0 s=3" ]]
uf_check "(icrs's string holds its CR after a normal load: s=3)" $?

# ---------------------------------------------------------------------------
kt_test_section "026: trust — junctions (Windows), the WARNING once (§8.1, §8.2, IMG-D3)"

# (the Windows cmd.exe by its path: MSYS2 has a /usr/bin/cmd shell script)
WCMD=""
if (( WIN )) && type -P cygpath >/dev/null; then WCMD=$(cygpath -u "${SYSTEMROOT:-${SystemRoot:-C:/Windows}}/System32/cmd.exe"); fi
if [[ -n $WCMD && -f $WCMD ]]; then
    jmk() { MSYS2_ARG_CONV_EXCL='*' "$WCMD" /c mklink /J "$(cygpath -w "$1")" "$(cygpath -w "$2")" < /dev/null > /dev/null 2>&1; }
    jrm() { MSYS2_ARG_CONV_EXCL='*' "$WCMD" /c rmdir "$(cygpath -w "$1")" < /dev/null > /dev/null 2>&1; }
    mkdir -p "$FX/jt"
    UF_ENV=(KBOOL_IMAGE_DIR="$FX/jt" KBOOL_IMAGE_CHECK=dates)
    uf_run 'source "$FX/kbool.sh"; kk.image ia'
    uf_run 'source "$FX/kbool.sh"; kk.image ib'
    if jmk "$FX/jl" "$FX/jt" && [[ -L $FX/jl ]]; then
        UF_ENV=(KBOOL_IMAGE_DIR="$FX/jl" KBOOL_IMAGE_CHECK=dates)
        uf_run 'source "$FX/kbool.sh"; kk.image ia; echo "rc=$? ${__KK_UNIT_PID[ia]+normal}"; kk.unit --forget ia ib; kk.image ib; echo "rc=$?"'
        [[ $UF_OUT == "kbool: WARNING: image $FX/jl/ia-"*".img is not trusted (the folder $FX/jl is a symbolic link); loading normally"$'\n'"rc=0 normal"$'\n'"rc=0" ]]
        uf_check "a junction as the image folder: ONE WARNING for two images refused in one process, plain loads" $?
        jrm "$FX/jl"
        [[ ! -e $FX/jl && -d $FX/jt ]]
        uf_check "(the junction removed, its target kept)" $?
    else
        kt_test_start "a junction as the image folder"; kt_test_fail "mklink /J failed"
    fi
    mkdir -p "$FX/lad" "$FX/jk/image/v1"
    cp "$FX"/jt/ia-*.img "$FX"/jt/ia-*.ref "$FX/jk/image/v1/" 2>/dev/null
    if jmk "$FX/lad/kbool" "$FX/jk" && [[ -L $FX/lad/kbool ]]; then
        UF_ENV=(LOCALAPPDATA="$FX/lad" KBOOL_IMAGE_CHECK=dates)
        uf_run 'source "$FX/kbool.sh"; kk.image ia; echo "rc=$?"; ls "$FX/jk/image/v1" | grep -c "\.tmp\."'
        [[ $UF_OUT == "kbool: WARNING: image $FX/lad/kbool/image/v1/ia-"*".img is not trusted (the folder $FX/lad/kbool is a symbolic link); loading normally"$'\n'"rc=0"$'\n'"0" ]]
        uf_check "a junction as a parent level (LOCALAPPDATA/kbool): the WARNING, a plain load, nothing written through it" $?
        jrm "$FX/lad/kbool"
        [[ ! -e $FX/lad/kbool && -d $FX/jk ]]
        uf_check "(the parent junction removed)" $?
    else
        kt_test_start "a junction as a parent level"; kt_test_fail "mklink /J failed"
    fi
    UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
else
    kt_test_start "junctions"
    kt_test_pass "N/A off the Windows runtimes (021_Image.sh tests POSIX symbolic links)"
fi
if (( ! WIN )) && (( EUID == 0 )) && type -P chown >/dev/null; then
    UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
    uf_run "$H"'; kk.image ib 2>/dev/null'
    for f in "$FX"/img/ib-*.img; do chown 65534 "$f" 2>/dev/null; done
    uf_run 'source "$FX/kbool.sh"; VERBOSE_KKLASS=debug; kk.image ib 2>&1 | grep -c "owned by another user"'
    [[ $UF_OUT == 2 ]]
    uf_check "an image owned by another user (root's chown): the WARNING and the reason" $?
else
    kt_test_start "an image owned by another user"
    kt_test_pass "N/A: needs root on POSIX to chown a file to another user"
fi

kt_test_log "026_ImageRefuse.sh completed"
