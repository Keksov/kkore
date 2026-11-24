#!/usr/bin/env bash
# Image — kk.image, the load image of kklass/docs/dev/IMAGE_PLAN.md (stage
# I2a-1: unchained, `dates`): the contract — a miss writes, the next start
# hits and leaves the state a normal load leaves (the kkore state dump, the
# allow-list in image_fixture.sh's cmp.sh); not applicable (KBOOL_IMAGE=off,
# a prior set, inside a unit's load, set -a); the flags and their debug lines;
# the image folder (the location chain with each variable unset in turn, root
# only under KBOOL_IMAGE_DIR); the trust checks and their one WARNING. The
# start itself (staleness, undo, hooks, forks, refusals) is 022_ImageStart.sh.
# Every scenario runs in a FRESH bash against a throw-away kbool tree
# (unit_fixture.sh + image_fixture.sh); every image folder is under it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Image" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
if_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "if_build failed"; exit 1; }
FX="$UF_FX"
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
H='source "$FX/kbool.sh" || exit 9'
WIN=0
if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then WIN=1; fi

# ---------------------------------------------------------------------------
kt_test_section "021: a miss writes, the next start hits, the state is a normal load's"

# (no locale variable: kk.localeDefault in ia's hook exports LC_CTYPE;
# __KK_UNIT_PID[ia] set = loaded normally, absent = loaded from the image)
R='; echo "rc=$?"; ia.f; ib.f; echo "w=$IA_W c=$IA_C i=$IA_I lc=${LC_CTYPE-} pid=${__KK_UNIT_PID[ia]+normal}"'
uf_run "$H"'; unset LANG LC_ALL LC_CTYPE; VERBOSE_KKLASS=debug; kk.image ia'"$R"
if_imgs
[[ $UF_RC == 0 && $UF_OUT == "kbool: image: no image $FX/img/ia-"*".img yet: a normal load, then an image"$'\n'"kbool: image: wrote $FX/img/ia-"*".img"*$'\n'"rc=0"$'\n''ia.f a b "q" $x 4 v 2 7'$'\n'"ib.f"$'\n'"w=80 c=const i=42 lc=C.UTF-8 pid=normal" \
   && $IF_IMGS == ia-????????.img && -f $(echo "$FX/img/${IF_IMGS%.img}".*.ref) ]]
uf_check "a miss: a normal load (rc 0, the units work), then NAME-HASH.img and its NAME-HASH.NONCE.ref are written [§6.2, §7.1]" $?
IMG=$FX/img/$IF_IMGS

uf_run "$H"'; unset LANG LC_ALL LC_CTYPE; VERBOSE_KKLASS=debug; kk.image ia'"$R"
[[ $UF_RC == 0 && $UF_OUT == "kbool: image: loaded from $IMG"$'\n'"rc=0"$'\n''ia.f a b "q" $x 4 v 2 7'$'\n'"ib.f"$'\n'"w=80 c=const i=42 lc=C.UTF-8 pid=" ]]
uf_check "the next start hits (one debug line, rc 0): the functions, variables and readonly constant are there; the hook ran (IA_W, LC_CTYPE) [§9]" $?

uf_run "$H"'; IA_W=5; VERBOSE_KKLASS=debug; kk.image ia 2>/dev/null; echo "w=$IA_W ${__KK_UNIT_PID[ia]-image}"; kk.uses ia ib; echo "uses=$?"; source "$FX/kcl/ia/ia.sh"; echo "src=$?"; kk.unit --forget ia; echo "f=$? ${__KK_UNITS[ia]-gone}"'
[[ $UF_RC == 0 && $UF_OUT == "w=5 image"$'\n'"uses=0"$'\n'"src=0"$'\n'"f=0 gone" ]]
uf_check "an image start: the hook sees the caller's preset; the units count as loaded (kk.uses and a re-source are no-ops; --forget works)" $?

# (this file runs KBOOL_IMAGE_CHECK=dates throughout, so that its cases mean
# the same on every runtime; the other modes: 023_ImageModes.sh. Here once
# the runtime's default: stat on POSIX, dates on the Windows runtimes)
uf_run "$H"'; unset KBOOL_IMAGE_CHECK; kk.image ia; echo "rc=$? ${__KK_UNIT_PID[ia]+normal}"'
A=$UF_OUT
uf_run "$H"'; unset KBOOL_IMAGE_CHECK; kk.image ia; echo "rc=$? ${__KK_UNIT_PID[ia]-image}"'
# (stat: a file changed in the second the stamps were taken makes the next
# start one "racy" rewrite — the fixture was just built; 023_ImageModes.sh)
[[ $UF_OUT == "rc=0 image" ]] || uf_run "$H"'; unset KBOOL_IMAGE_CHECK; kk.image ia; echo "rc=$? ${__KK_UNIT_PID[ia]-image}"'
[[ $A == "rc=0 normal" && $UF_OUT == "rc=0 image" ]]
uf_check "the runtime's default mode (no KBOOL_IMAGE_CHECK): a miss writes, the next start hits" $?

# each dump is taken in the process that loaded (an image start vs KBOOL_IMAGE=off)
cat > "$FX/both.sh" <<'EOF'
source "$FX/kbool.sh" || exit 9
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image ia; else kk.image ia; fi
if [[ $1 == hit && -n ${__KK_UNIT_PID[ia]+x} ]]; then echo "not a hit"; fi
kk._image_lib || exit 9     # (kimghit.sh + kimage.sh: the same functions in both dumps)
kk._img_state "$2" canon
EOF
uf_run 'bash "$FX/both.sh" miss "$FX/miss.d"; bash "$FX/both.sh" hit "$FX/hit.d"; bash "$FX/both.sh" plain "$FX/plain.d"; bash "$FX/cmp.sh" "$FX/plain.d" "$FX/hit.d"'
[[ $UF_OUT == "cmp rc=0 " ]]
uf_check "the state after an image start equals a normal load's (kkore's dump, canon; allow-list: frame indices, pid state, name index, caller-keyed tables, hash table) [§4, M6]" $?

# (the edit in bash: `sed -i` is GNU-only — BSD sed wants `-i ''`)
uf_run 'bash "$FX/both.sh" hit "$FX/hit.d"; bash "$FX/both.sh" plain "$FX/plain.d"'
IFS= read -r -d '' z < "$FX/hit.d" || :
printf '%s' "${z/'declare -i IA_I="42"'/'declare -i IA_I="43"'}" > "$FX/hit.d.new" && mv -f "$FX/hit.d.new" "$FX/hit.d"
uf_run 'bash "$FX/cmp.sh" "$FX/plain.d" "$FX/hit.d"'
[[ $UF_OUT == 'cmp rc=1 V:IA_I before=declare -i IA_I="42"| after=declare -i IA_I="43"|' ]]
uf_check "the compare is not vacuous: one changed value is reported with both texts" $?

# ---------------------------------------------------------------------------
kt_test_section "021: not applicable: a plain kk.uses, nothing read or written"

rm -f "$FX"/img/*
uf_run "$H"'; KBOOL_IMAGE=off VERBOSE_KKLASS=debug kk.image ia; echo "rc=$?"; KBOOL_IMAGE=0 kk.image ib; echo "rc=$?"'
if_imgs
[[ $UF_RC == 0 && $UF_OUT == "kbool: image: KBOOL_IMAGE=off; a normal load (kk.uses ia)"$'\n'"rc=0"$'\n'"rc=0" && -z $IF_IMGS ]]
uf_check "KBOOL_IMAGE=off (and 0): a plain kk.uses (rc 0), a debug line, no image" $?

uf_run "$H"'; kk.uses ib; VERBOSE_KKLASS=debug kk.image ia; echo "rc=$? ${__KK_UNITS[ia]+loaded}"'
if_imgs
[[ $UF_RC == 0 && $UF_OUT == "kbool: image: unit 'ib' is loaded already (chained images: I2b); a normal load (kk.uses ia)"$'\n'"rc=0 loaded" && -z $IF_IMGS ]]
uf_check "a prior set (a unit loaded before): a plain kk.uses, nothing written (unchained, I2a) [§7.7]" $?

uf_run "$H"'; kk.uses "$FX/kcl/a/helper.sh"; VERBOSE_KKLASS=debug kk.image ia 2>&1 | { head -1; cat >/dev/null; }; kk.image ia; echo "rc=$?"'
if_imgs
[[ $UF_OUT == "kbool: image: a file is loaded by path already (chained images: I2b); a normal load (kk.uses ia)"$'\n'"rc=0" && -z $IF_IMGS ]]
uf_check "a header-less file loaded by path before: a plain kk.uses, nothing written" $?

uf_run "$H"'; VERBOSE_KKLASS=debug kk.image iin; echo "rc=$? inner=$IIN_RC"'
if_imgs
[[ $UF_RC == 0 && $UF_OUT == *"kbool: image: inside the load of unit 'iin'; a normal load (kk.uses ib)"*"kbool: image: wrote $FX/img/iin-"*$'\n'"rc=0 inner=0" && $IF_IMGS == iin-*.img ]]
uf_check "kk.image inside a unit's load: a plain kk.uses there (the outer kk.image still writes its own image)" $?

rm -f "$FX"/img/*
uf_run "$H"'; set -a; VERBOSE_KKLASS=debug kk.image ia; echo "rc=$?"'
if_imgs
[[ $UF_RC == 0 && $UF_OUT == "kbool: image: set -a is on; a normal load (kk.uses ia)"$'\n'"rc=0" && -z $IF_IMGS ]]
uf_check "set -a: a plain kk.uses, nothing written (every image assignment would be exported) [§3]" $?

uf_run "$H"'; kk.image --rebuild --path ia; echo "rc=$?"; kk.image --path --bogus ia; echo "rc=$?"; kk.image --forget; echo "rc=$?"; kk.image nosuch; echo "rc=$?"; kk.image; echo "rc=$?"'
[[ $UF_OUT == "kbool: error: kk.image --path: only one of --rebuild, --forget, --path"$'\n'"rc=2"$'\n'"kbool: error: kk.image --path: unknown option '--bogus'"$'\n'"rc=2"$'\n'"kbool: error: kk.image --forget: no unit named"$'\n'"rc=2"$'\n'"kbool: error: kk.uses: unit 'nosuch' not found"*$'\n'"rc=2"$'\n'"kbool: error: kk.uses: no unit named"$'\n'"rc=2" ]]
uf_check "usage errors (rc 2): two actions, an unknown option after one, --forget without a unit; an unknown unit or no unit is kk.uses' own error and rc" $?

# ---------------------------------------------------------------------------
kt_test_section "021: the flags (IMG-D1, IMG-D2)"

rm -f "$FX"/img/*
uf_run "$H"'; KBOOL_IMAGE_CHECK=bogus VERBOSE_KKLASS=debug kk.image ib 2>&1 | { head -2; cat >/dev/null; }'
case $OSTYPE in msys*|cygwin*) d=dates ;; *) d=stat ;; esac
want="kbool: image: KBOOL_IMAGE_CHECK=bogus is not stat|dates|hash; using $d"$'\n'"kbool: image: no image "
[[ $UF_OUT == "$want"* ]]
uf_check "KBOOL_IMAGE_CHECK=bogus: the runtime's default ($d) and the debug line of §3" $?

rm -f "$FX"/img/*
for v in stat hash dates; do
    uf_run "$H"'; KBOOL_IMAGE_CHECK='"$v"' VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep -c KBOOL_IMAGE_CHECK'
    [[ $UF_OUT == 0 ]]
    uf_check "KBOOL_IMAGE_CHECK=$v: taken as it is (no debug line about the mode; the tools are on PATH)" $?
done
if_imgs
[[ $IF_IMGS == ib-*.img\ ib-*.img\ ib-*.img ]]
uf_check "the three modes are three keys: three image files [§7.1, IMG-D1]" $?

uf_run "$H"'; KBOOL_IMAGE_CHECK=dates VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep -c "KBOOL_IMAGE_CHECK"; KBOOL_IMAGE_CHAIN=maybe VERBOSE_KKLASS=debug kk.image ib 2>&1 | { head -1; cat >/dev/null; }; KBOOL_IMAGE_CHAIN=off VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep -c CHAIN'
[[ $UF_OUT == "0"$'\n'"kbool: image: KBOOL_IMAGE_CHAIN=maybe is not on|off; using on"$'\n'"0" ]]
uf_check "KBOOL_IMAGE_CHECK=dates: no line; KBOOL_IMAGE_CHAIN=maybe: on + a debug line; =off: accepted silently" $?

rm -f "$FX"/img/*
for p in "" "KBOOL_VERSION=9.9.9;" "VERBOSE_KKLASS=quiet;" "KBOOL_IMAGE_CHECK=stat;"; do uf_run "$H; $p"' kk.image ib'; done
if_imgs
n=0; for f in $IF_IMGS; do n=$(( n + 1 )); done
want=4
SUMS=$(cksum "$FX"/img/*.img)
[[ $UF_RC == 0 && $n == "$want" ]]
uf_check "KBOOL_VERSION and VERBOSE_KKLASS are keyed: other file names; KBOOL_IMAGE_CHECK=stat is another file unless it is the default ($want images) [§7.1]" $?
for p in "" "KBOOL_VERSION=9.9.9;" "VERBOSE_KKLASS=quiet;" "KBOOL_IMAGE_CHECK=stat;"; do uf_run "$H; $p"' kk.image ib'; done
[[ $(cksum "$FX"/img/*.img) == "$SUMS" ]]
uf_check "each of those images is a hit for its own key (no image rewritten)" $?

uf_run "$H"'; kk.uses --optional nosuch; VERBOSE_KKLASS=debug kk.image ia 2>&1 | grep "no image written"'
[[ $UF_OUT == "kbool: image: no image written: a unit was used before this load (__KK_UNIT_USED=nosuch): no image of a fresh start can be made" ]]
uf_check "a unit used before (kk.project closed, __KK_UNIT_USED): no image (it would lack that in a fresh start)" $?
uf_run "$H"'; kk.image ib; kk.unit --forget ib; VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep "no image written"'
[[ $UF_OUT == "kbool: image: no image written: a unit was used before this load"* ]]
uf_check "a unit forgotten and loaded again in one process: no image of that second load" $?

# ---------------------------------------------------------------------------
kt_test_section "021: --path, --forget, --rebuild, --optional (§3)"

rm -f "$FX"/img/*
uf_run "$H"'; kk.image --path; echo "rc=$?"; kk.image --path ia; echo "rc=$?"; KBOOL_IMAGE=off kk.image --path ia; echo "rc=$?"'
[[ $UF_OUT == "$FX/img"$'\n'"rc=0"$'\n'"$FX/img/ia-"????????".img"$'\n'"rc=1"$'\n'"rc=1" ]]
uf_check "--path: without units the folder (rc 0); with units the path this start would use, rc 1 while there is none; KBOOL_IMAGE=off: nothing, rc 1" $?
P1=${UF_OUT#*$'\n'*$'\n'}; P1=${P1%%$'\n'*}
uf_run "$H"'; kk.image ia; kk.image --path ia; echo "rc=$?"'
[[ $UF_OUT == "rc=1" ]]
uf_check "--path after the units are loaded: not applicable here, nothing printed, rc 1" $?
uf_run "$H"'; kk.image --path ia; echo "rc=$? ${__KK_UNITS[ia]-notloaded}"'
[[ $UF_OUT == "$P1"$'\n'"rc=0 notloaded" && -f $P1 ]]
uf_check "--path once the image is written: the same path, rc 0 (valid); nothing is loaded" $?
uf_run "$H"'; KBOOL_IMAGE_CHECK=hash; kk.image --path ia; echo "rc=$?"'
[[ $UF_OUT == "$FX/img/ia-"????????".img"$'\n'"rc=1" && ${UF_OUT%%$'\n'*} != "$P1" ]]
uf_check "--path follows the key (another mode: another path, none yet: rc 1)" $?
if_age "$P1" 3600
touch "$FX/kcl/ib/ib.sh"
uf_run "$H"'; kk.image --path ia; echo "rc=$?"'
[[ $UF_OUT == "$P1"$'\n'"rc=1" ]]
uf_check "--path of a stale image: the same path, rc 1" $?
touch -t 202001010000 "$FX/kcl/ib/ib.sh"

for v in hash stat dates; do uf_run "$H"'; KBOOL_IMAGE_CHECK='"$v"' kk.image ia'; done
uf_run "$H"'; KBOOL_IMAGE_CHECK=dates kk.image ib'
printf '%s noted\n' "$EPOCHSECONDS" > "${P1%.img}.hold"
: > "$FX/img/ia2-12345678.img"; : > "$FX/img/ia-b-12345678.img"
uf_run "$H"'; VERBOSE_KKLASS=debug kk.image --forget ia; echo "rc=$?"; KBOOL_IMAGE=off kk.image --forget ib; echo "rc=$?"'
if_imgs
[[ $UF_OUT == "kbool: image: --forget: 5 file(s) of 'ia' removed from $FX/img"$'\n'"rc=0"$'\n'"rc=0" \
   && $IF_IMGS == "ia-b-12345678.img ia2-12345678.img" && ! -e ${P1%.img}.hold ]]
uf_check "--forget ia: its images of every key (three modes), its .ref and .hold go — not another request's (ia2, ia-b); rc 0; it works under KBOOL_IMAGE=off too (ib gone)" $?
rm -f "$FX"/img/*

DBG='VERBOSE_KKLASS=debug'                # (VERBOSE_KKLASS is keyed: the same value throughout)
uf_run "$H; $DBG"'; kk.image ia 2>/dev/null'
REF1=$(cat "$FX"/img/ia-*.ref)
uf_run "$H; $DBG"'; kk.image --rebuild ia 2>&1 | grep -v profile; echo "rc=${PIPESTATUS[0]} ${__KK_UNITS[ia]+loaded}"'
[[ $UF_OUT == "kbool: image: --rebuild: a normal load, then an image"$'\n'"kbool: image: wrote $FX/img/ia-"*".img"$'\n'"rc=0 " \
   && $(cat "$FX"/img/ia-*.ref) != "$REF1" ]]
uf_check "--rebuild with a valid image: a normal load, the image written again (a new nonce), rc 0" $?
for f in "$FX"/img/ia-*.img; do printf '%s test\n' "$EPOCHSECONDS" > "${f%.img}.hold"; done
uf_run "$H; $DBG"'; kk.image --rebuild ia 2>&1 | grep -c wrote'
[[ $UF_OUT == 1 && -z $(ls "$FX"/img/*.hold 2>/dev/null) ]]
uf_check "--rebuild clears a hold" $?
uf_run "$H"'; kk.image --rebuild ifail; echo "rc=$?"'
[[ $UF_OUT == "kbool: error: kk.uses: loading unit 'ifail' failed (rc=3)"$'\n'"rc=3" ]]
uf_check "--rebuild's rc is the load's (a failing unit: its error, rc 3)" $?

rm -f "$FX"/img/*
uf_run "$H"'; VERBOSE_KKLASS=debug kk.image --optional ia ib; echo "rc=$?"'
uf_run "$H"'; VERBOSE_KKLASS=debug kk.image --optional ia ib 2>&1; echo "rc=$?"'
[[ $UF_OUT == "kbool: image: loaded from $FX/img/ia+ib-"*".img"$'\n'"rc=0" ]]
uf_check "--optional goes through the image: the first start writes it, the next is a hit (rc 0) [the --optional decision]" $?
uf_run "$H"'; VERBOSE_KKLASS=debug kk.image --optional ib ifail 2>&1 | grep -v profile; echo "rc=${PIPESTATUS[0]} ${__KK_UNITS[ib]-}"'
[[ $UF_OUT == "kbool: image: no image "*": a normal load, then an image"$'\n'"kbool: image: no image written: the load failed (rc 3)"$'\n'"kbool: image: held for an hour: $FX/img/ib+ifail-"*".hold"$'\n'"rc=3 " ]]
uf_check "--optional with a failing unit: kk.uses --optional's quiet rc, no image, a hold (the same start would fail again)" $?
uf_run "$H"'; VERBOSE_KKLASS=debug kk.image --optional ib ifail 2>&1; echo "rc=$?"'
[[ $UF_OUT == "kbool: image: no image "*"; held (the load failed (rc 3), "*" s ago); a normal load (kk.uses --optional ib ifail)"$'\n'"rc=3" ]]
uf_check "the next start is held: a plain kk.uses --optional" $?
uf_run "$H"'; VERBOSE_KKLASS=debug kk.image --optional ia nosuch 2>&1; echo "rc=$?"'
[[ $UF_OUT == "kbool: image: unit 'nosuch' not found; a normal load (kk.uses --optional ia nosuch)"$'\n'"rc=2" ]]
uf_check "--optional with a unit that is not found: a plain kk.uses --optional (quiet, rc 2)" $?

# ---------------------------------------------------------------------------
kt_test_section "021: the image folder (§7.3, IMG-D4) and root (§8.1)"

# the chain, with OSTYPE set for the branch under test (the key holds it)
L='source "$FX/kbool.sh" || exit 9; OSTYPE=${IOS:-$OSTYPE}; VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep -o "wrote .*" | sed "s|$FX|FX|; s|-[0-9a-f]*\.img$||"'
rm -rf "$FX/loc"; mkdir -p "$FX/loc/lad" "$FX/loc/up" "$FX/loc/home" "$FX/loc/xdg"
UF_ENV=(IOS=msys LOCALAPPDATA="$FX/loc/lad" USERPROFILE="$FX/loc/up" HOME="$FX/loc/home")
uf_run "$L"
[[ $UF_OUT == "wrote FX/loc/lad/kbool/image/v1/ib" ]]
uf_check "Windows runtimes: \$LOCALAPPDATA/kbool/image/v1 first" $?
UF_ENV=(IOS=cygwin USERPROFILE="$FX/loc/up" HOME="$FX/loc/home")
uf_run "$L"
[[ $UF_OUT == "wrote FX/loc/up/AppData/Local/kbool/image/v1/ib" ]]
uf_check "Windows runtimes without LOCALAPPDATA: \$USERPROFILE/AppData/Local/kbool/image/v1" $?
UF_ENV=(IOS=msys HOME="$FX/loc/home")
uf_run 'source "$FX/kbool.sh"; OSTYPE=$IOS; VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep "LOCALAPPDATA and USERPROFILE"'
[[ $UF_OUT == "kbool: image: LOCALAPPDATA and USERPROFILE are not set: images go to $FX/loc/home/.cache/kbool/image/v1"* && -d $FX/loc/home/.cache/kbool/image/v1 ]]
uf_check "Windows runtimes without both: \$HOME/.cache/kbool/image/v1 with the debug line naming it (IMG-D4)" $?
UF_ENV=(IOS=msys HOME=/home/someone)
# (kimage.sh refused: nothing is made under that HOME, only the message is read)
uf_run 'source "$FX/kbool.sh"; OSTYPE=$IOS; kk._image_lib() { return 1; }; VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep -c "inside the runtime.s install folder"'
[[ $UF_OUT == 1* ]]
uf_check "the fallback HOME inside the runtime's install folder (an MSYS2 / Cygwin /home): the debug line says so (§8.2)" $?
UF_ENV=(IOS=linux-gnu KBOOL_IMAGE_CHECK=dates XDG_CACHE_HOME="$FX/loc/xdg" HOME="$FX/loc/home" LOCALAPPDATA="$FX/loc/lad")
uf_run "$L"
[[ $UF_OUT == "wrote FX/loc/xdg/kbool/image/v1/ib" ]]
uf_check "POSIX: \$XDG_CACHE_HOME/kbool/image/v1 first (LOCALAPPDATA is not read)" $?
UF_ENV=(IOS=linux-gnu KBOOL_IMAGE_CHECK=dates XDG_CACHE_HOME=relative/x HOME="$FX/loc/home")
uf_run "$L"
[[ $UF_OUT == "wrote FX/loc/home/.cache/kbool/image/v1/ib" ]]
uf_check "POSIX: a relative XDG_CACHE_HOME is ignored; \$HOME/.cache/kbool/image/v1" $?
UF_ENV=(IOS=linux-gnu)
uf_run 'unset HOME; source "$FX/kbool.sh"; OSTYPE=$IOS; VERBOSE_KKLASS=debug kk.image ib 2>&1 | grep "no folder"'
[[ $UF_OUT == "kbool: image: no folder for images (HOME is not set); a normal load (kk.uses ib)" ]]
uf_check "no base variable at all: a plain kk.uses" $?
UF_ENV=(KBOOL_IMAGE_DIR="$FX/loc/own/deeper" LOCALAPPDATA="$FX/loc/lad")
uf_run "$L"
[[ $UF_OUT == "wrote FX/loc/own/deeper/ib" ]]
uf_check "KBOOL_IMAGE_DIR replaces the base (made when missing)" $?
UF_ENV=(LOCALAPPDATA="$FX/loc/lad" XDG_CACHE_HOME="$FX/loc/xdg" HOME="$FX/loc/home")
uf_run "$H"'; kk._image_hitlib; kk._image_euid() { __kk_im_euid=0; }; VERBOSE_KKLASS=debug kk.image ib 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: EUID 0: images are read and written only under KBOOL_IMAGE_DIR; a normal load (kk.uses ib)" ]]
uf_check "root (EUID 0, pretended by overriding kk._image_euid) without KBOOL_IMAGE_DIR: a plain kk.uses [§8.1]" $?
UF_ENV=(KBOOL_IMAGE_DIR="$FX/loc/root")
uf_run "$H"'; kk._image_hitlib; kk._image_euid() { __kk_im_euid=0; }; kk.image ib'; uf_run "$H"'; kk._image_hitlib; kk._image_euid() { __kk_im_euid=0; }; kk.image ib; echo "${__KK_UNIT_PID[ib]-image} $(echo "$KBOOL_IMAGE_DIR"/ib-*.img)"'
[[ $UF_OUT == "image $FX/loc/root/ib-"*".img" ]]
uf_check "root with KBOOL_IMAGE_DIR: images are written and read there (EUID is keyed)" $?
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)

# ---------------------------------------------------------------------------
kt_test_section "021: trust (§8.1) and the one WARNING (IMG-D3)"

rm -rf "$FX"/img/*
uf_run "$H"'; kk.image ib'
if_imgs
B=$FX/img/${IF_IMGS%.img}
mv "$B.img" "$B.keep"; mkdir "$B.img"
uf_run "$H"'; kk.image ib; echo "rc=$?"; kk.unit --forget ib; kk.image ib; echo "rc=$?"'
[[ $UF_OUT == "kbool: WARNING: image $B.img is not trusted (not a regular file); loading normally"$'\n'"rc=0"$'\n'"rc=0" ]]
uf_check "an image path that is not a regular file: ONE WARNING per process (twice checked), a plain load, rc 0" $?
[[ -d $B.img ]]
uf_check "nothing is deleted or written over" $?
uf_run "$H"'; VERBOSE_KKLASS=quiet; kk.image ib'
for f in "$FX"/img/ib-*.img; do [[ -d $f ]] || Q=${f%.img}; done
mv "$Q.img" "$Q.keep"; mkdir "$Q.img"
uf_run "$H"'; VERBOSE_KKLASS=quiet; kk.image ib; echo "rc=$?"'
[[ $UF_OUT == "rc=0" ]]
uf_check "VERBOSE_KKLASS=quiet silences the WARNING (an image of the quiet key, made a folder)" $?
rmdir "$Q.img" "$B.img"; mv "$Q.keep" "$Q.img"
if ln -s "$B.keep" "$B.img" 2>/dev/null && [[ -L $B.img ]]; then
    uf_run "$H"'; kk.image ib; echo "rc=$? ${__KK_UNITS[ib]+loaded}"'
    [[ $UF_OUT == "kbool: WARNING: image $B.img is not trusted (a symbolic link); loading normally"$'\n'"rc=0 loaded" ]]
    uf_check "a symbolic link as the image: the WARNING, a plain load (POSIX symlink)" $?
    rm -f "$B.img"
else
    rm -f "$B.img"
    kt_test_start "a symbolic link as the image"
    kt_test_pass "N/A: this runtime's ln -s makes no symbolic link (junctions: I2a-2)"
fi
mv "$B.keep" "$B.img"
mkdir -p "$FX/loc/real"
if ln -s "$FX/loc/real" "$FX/loc/link" 2>/dev/null && [[ -L $FX/loc/link ]]; then
    UF_ENV=(KBOOL_IMAGE_DIR="$FX/loc/link")
    uf_run "$H"'; VERBOSE_KKLASS=debug kk.image ib 2>&1 | { head -1; cat >/dev/null; }'
    [[ $UF_OUT == "kbool: image: untrusted folder: the folder $FX/loc/link is a symbolic link; a normal load (kk.uses ib)" ]]
    uf_check "a symbolic link as the image folder: a plain load, nothing written (no image there: no WARNING)" $?
    UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=dates)
else
    kt_test_start "a symbolic link as the image folder"
    kt_test_pass "N/A: this runtime's ln -s makes no symbolic link"
fi
# (POSIX only: on the Windows runtimes chmod does not take effect, so the case
# would pass without testing anything; on POSIX the writer's first temp file
# failed with "Permission denied" on stderr until I2a-2 — CI run 45467673135)
if (( ! WIN )); then
    chmod 000 "$FX/img" 2>/dev/null
    uf_run "$H"'; kk.unit --forget ib 2>/dev/null; kk.image ia; echo "rc=$?"; kk.image --forget ia; echo "rc=$?"'
    A=$UF_OUT
    uf_run "$H"'; KBOOL_IMAGE_CHECK=stat kk.image ia; echo "rc=$?"; KBOOL_IMAGE_CHECK=hash kk.image ib; echo "rc=$?"'
    chmod 755 "$FX/img"
    [[ $A == "rc=0"$'\n'"rc=0" && $UF_OUT == "rc=0"$'\n'"rc=0" ]]
    uf_check "an unwritable image folder: silent (each mode, --forget too), a normal load, rc 0 (IMG-D3)" $?
fi

kt_test_log "021_Image.sh completed"
