#!/usr/bin/env bash
# Shared fixture of the load-image tests (021_Image.sh, 022_ImageStart.sh;
# kklass/docs/dev/IMAGE_PLAN.md, stage I2a-1). Not a test file: the runner
# only picks up NNN_*.sh. Needs unit_fixture.sh (uf_build, uf_run) sourced.
#
# if_build DIR — uf_build DIR plus the image units below; every file is dated
# 2020 (`dates` staleness: a stamped file must be older than the image's
# reference file, made at the load's start — a file written in the same clock
# tick would not be), and the image folder is DIR/img (KBOOL_IMAGE_DIR, through
# uf_run's UF_ENV). Units:
#   ib    a dependency: a function, a scalar
#   ia    kk.uses ib; scalars (quotes, $, a newline), an indexed array (an empty
#         element, a CR), an assoc array (keys with blanks and quotes), an
#         integer, a readonly constant (guarded per name), a function, a hook
#         ia._s (IA_W:=80, kk.localeDefault) with VARs IA_W LC_CTYPE
#   ihf   a hook that fails when IHF_FAIL=1 (rc 5): `kk.settings … || return`
#   ihg   a hook that, when IHG_EVIL=1, tries to load ib2 (kk.uses) and to
#         source ib3 (the hook-run guard on an image start)
#   iex   exports IEX_V at load (a refusal); itr sets a trap (a refusal);
#         ichg changes the caller's ICHG_V; ifn redefines the caller's
#         function userfn; ifail returns 3 (a load failure)
#   icr   a function whose text holds a CR byte ($'\r')
#   iin   calls `kk.image ib` inside its own load (not applicable there)
#   iro   a readonly constant IRO_C guarded per name
#   iuv   variables declared without a value (an associative and an indexed
#         array, an integer, a scalar: `declare -gA IUV_A` …) and iuv.f, which
#         uses them (image I3: compgen -v does not list such variables)
#   irw   irw.f FILE: writes ab, then X over its first byte through `1<>`
#         (image I3: bash 5.2 prints `1<> F` as `<> F`, fd 0 when read back)
# Helpers in DIR: dump.sh FILE (kk._img_state FILE canon, in the child's
# state), cmp.sh A B (kk._img_cmp A B set with the documented allow-list:
# prints `cmp rc=N DIFF`).

# if_unit DIR NAME — a unit NAME whose body is read from stdin (a quoted
# here-document: no quoting games)
if_unit() {
    local dir="$1/kcl/$2"
    mkdir -p "$dir"
    {
        printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%'"$2"'.sh}../../kbool.sh" || return'
        printf '%s\n' "kk.unit $2 || return \$__kk_unit_rc"
        cat
    } > "$dir/$2.sh"
}

if_build() {
    local fx=$1
    uf_build "$fx" || return 1
    if_unit "$fx" ib <<'EOF'
ib.f() { echo "ib.f"; }
IB_V=7
EOF
    if_unit "$fx" ib2 <<'EOF'
IB2_LOADED=1
EOF
    if_unit "$fx" ib3 <<'EOF'
IB3_LOADED=1
EOF
    if_unit "$fx" ia <<'EOF'
kk.uses ib || return
declare -g IA_S='a b "q" $x'
declare -g IA_NL=$'line1\nline2'
declare -ga IA_A=(one "two words" "" $'c\rr')
declare -gA IA_M=([k1]=v1 ["key two"]="v 2" [q]="it's")
declare -gi IA_I=42
[[ -n ${IA_C+x} ]] || declare -gr IA_C=const
ia.f() { echo "ia.f ${IA_S} ${#IA_A[@]} ${IA_M[key two]} $IB_V"; }
ia._s() {
    : "${IA_W:=80}"
    kk.localeDefault
    return 0
}
kk.settings ia._s IA_W LC_CTYPE || return
EOF
    if_unit "$fx" ihf <<'EOF'
ihf._s() { [[ ${IHF_FAIL-} != 1 ]] || return 5; IHF_OK=1; return 0; }
kk.settings ihf._s IHF_OK || return
EOF
    if_unit "$fx" ihg <<'EOF'
ihg._s() {
    if [[ ${IHG_EVIL-} == 1 ]]; then
        kk.uses ib2; IHG_USES=$?
        source "${IHG_DIR}/../ib3/ib3.sh"; IHG_SRC=$?
    fi
    return 0
}
IHG_DIR=$KK_UNIT_DIR
kk.settings ihg._s IHG_USES IHG_SRC || return
EOF
    if_unit "$fx" iex <<'EOF'
export IEX_V=1
EOF
    if_unit "$fx" itr <<'EOF'
trap ':' USR1
EOF
    if_unit "$fx" ichg <<'EOF'
ICHG_V=changed
EOF
    if_unit "$fx" ifn <<'EOF'
userfn() { echo redefined; }
EOF
    if_unit "$fx" ifail <<'EOF'
return 3
EOF
    if_unit "$fx" icr <<'EOF'
icr.f() { local cr=$'\r'; echo "cr=${#cr}"; }
EOF
    if_unit "$fx" iin <<'EOF'
kk.image ib
IIN_RC=$?
EOF
    if_unit "$fx" iuv <<'EOF'
declare -gA IUV_A
declare -ga IUV_X
declare -gi IUV_N
declare -g IUV_S
iuv.f() { IUV_A[key]=v; IUV_N+=7; IUV_N+=1; echo "A=${IUV_A[key]-} N=$IUV_N kind=${IUV_A@a}"; }
EOF
    if_unit "$fx" irw <<'EOF'
irw.f() { printf ab > "$1"; printf X 1<> "$1"; }
EOF
    if_unit "$fx" iro <<'EOF'
[[ -n ${IRO_C+x} ]] || declare -gr IRO_C=1
IRO_V=2
EOF
    # iak: an associative array whose keys are every byte 0x80-0xFF and the
    # characters a subscript treats specially — `]` `\` `*` `@` `"` `$` a
    # backtick `'` a space `[` `~` `!` `=` and a few words with them — the
    # keys %q-listed in an indexed array (read alike by every bash), set by a
    # loop (CI run 45467673135: bash 5.1 lost fv.mouse's table with a key `@`)
    local -a ks=(']' '\' '*' '@' '"' '$' '`' "'" ' ' '[' '~' '!' '=' 'a]b' 'x y' '$(echo no)' '*x' '@x' '\]' '-')
    local i o c q=""
    for (( i = 128; i < 256; i++ )); do printf -v o '%o' "$i"; printf -v c "\\$o"; ks+=("$c" "k$c"); done
    LC_ALL=C printf -v q '%q ' "${ks[@]}"
    if_unit "$fx" iak <<EOF
declare -ga IAK_K=(${q% })
declare -gA IAK_M=()
for IAK_I in "\${!IAK_K[@]}"; do IAK_M[\${IAK_K[IAK_I]}]="v\${IAK_K[IAK_I]}"; done
IAK_M[\$'\r']=vcr IAK_M[\$'\t']=vtab IAK_M[\$'\001']=v1 IAK_M[\$'\177']=v177 IAK_M[\$'a\rb']=vacrb
iak.n() { local a='@' s='*' b=']' h=\$'\xff'; echo "n=\${#IAK_M[@]} at=\${IAK_M[\$a]-none} star=\${IAK_M[\$s]-none} br=\${IAK_M[\$b]-none} ff=\${#IAK_M[\$h]}"; }
EOF
    cat > "$fx/dump.sh" <<'EOF'
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
kk._img_state "$1" canon
EOF
    cat > "$fx/cmp.sh" <<'EOF'
# the allow-list of a hit-vs-normal-load compare (IMAGE_PLAN §4, M6): the
# loader's frame index of each unit (inert once loaded), pid state, the name
# index and the caller-keyed tables, the hash table; CR function texts compare
# with ''<CR>'' as <CR> (kk._fn_text_cr's round trip)
source "$FX/kbool.sh" || exit 9
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
__KK_IMG_CMPV=(__KK_UNIT_BOT __KK_UNIT_PID __KK_UNIT_IDX __KK_UNIT_CAND __KK_UNIT_IDX_OK __KK_UNIT_RES
    __KK_UNIT_HIT __KK_FILE_PWD BASH_CMDS PPID)
__KK_IMG_CMPCR=1
__KK_IMG_ALL=${CMP_ALL-}
kk._img_cmp "$1" "$2" set
echo "cmp rc=$? $__KK_IMG_DIFF"
EOF
    # (the image folder under umask 077, as kk.image makes its own: a caller
    # umask 002 — some CI rows — gives 775, which stat mode refuses)
    ( umask 077 && mkdir -p "$fx/img" )
    mkdir -p "$fx/home"
    touch -t 202001010000 "$fx/kbool.sh" "$fx"/kkore/*.sh "$fx"/kcl/*/*.sh || return 1
}

# if_age IMG SECONDS — make IMG look written SECONDS earlier: its write time
# in the plain header line and in __kk_img_wtime (the same digit count, so the
# header length in line 1 stays right); the holds and pruning read it
# (pure bash, no `sed -i`: GNU-only; the image is read as bytes, no NUL in it)
if_age() {
    local l1 l2 t n z LC_ALL=C
    { IFS= read -r l1; IFS= read -r l2; } < "$1"
    t=${l2#"#P"$'\x1f'}
    t=${t%%$'\x1f'*}
    n=$(( t - $2 ))
    IFS= read -r -d '' z < "$1" || :
    z=${z/$'\n'"#P"$'\x1f'"$t"$'\x1f'/$'\n'"#P"$'\x1f'"$n"$'\x1f'}
    z=${z/"__kk_img_wtime=$t"$'\n'/"__kk_img_wtime=$n"$'\n'}
    ( umask 077; printf '%s' "$z" > "$1.age" ) && mv -f "$1.age" "$1"    # (077: as the writer makes it — under a caller umask 002 it would be 664, refused in stat mode)
}

# if_pfield IMG N -> IF_F: field N of IMG's plain header line (0 wtime, 1 size,
# 2 tag, 3 home, 4 prior, 5 mode, 6 flavour, 7 nonce, 8 request hash, 9 count,
# 10… files)
if_pfield() {
    local l1 l2 IFS=$'\x1f'
    local -a a=()
    { IFS= read -r l1; IFS= read -r l2; } < "$1"
    a=(${l2#"#P"$'\x1f'})
    IF_F=${a[$2]-}
}

# if_imgs — IF_IMGS = the image files (basenames, sorted by the glob) in $FX/img
if_imgs() {
    local f
    IF_IMGS=""
    for f in "$FX"/img/*.img; do
        [[ -e $f ]] && IF_IMGS+="${f##*/} "
    done
    IF_IMGS=${IF_IMGS% }
}
