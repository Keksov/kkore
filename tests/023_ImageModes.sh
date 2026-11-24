#!/usr/bin/env bash
# ImageModes — the check modes of kk.image (kklass/docs/dev/IMAGE_PLAN.md
# §7.6, IMG-D1; stage I2a-2), each forced by KBOOL_IMAGE_CHECK on every
# runtime: what each notices (a content edit of the same size with the mtime
# put back, a size change, `touch`, an old-dated copy, a removed file, an
# edit during the write window, a future mtime: no write, a hold), the
# missing tool and the unknown `stat` flavour (-> dates, keyed), the BSD
# flavour (a stand-in stat that takes only -f), the permission bits of `stat`
# mode on POSIX (emulated on every runtime: OSTYPE=linux-gnu and a stand-in
# stat reporting a group-writable mode; real chmod where it takes effect),
# and the forks of a hit per mode (0 / 1 stat / 1 cksum). Fixture:
# image_fixture.sh (one throw-away tree per mode).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ImageModes" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
source "$SCRIPT_DIR/image_fixture.sh"
H='source "$FX/kbool.sh" || exit 9; VERBOSE_KKLASS=debug'
FL='fl() { local l; while IFS= read -r l; do [[ $l == *"$1"* ]] && { echo "$l"; return 0; }; done < "$FX/e.txt"; return 0; }'
WIN=0
if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then WIN=1; fi
REAL_STAT=$(type -P stat)
REAL_GNU=0; stat -c %Y -- / >/dev/null 2>&1 && REAL_GNU=1      # the host stat: GNU (-c) or BSD (-f)
# the flavour kk.image probes on this host: nanosecond times when the stat has them
REAL_FL=bsd; t=$(stat -f %Fm -- / 2>/dev/null); [[ $t == [0-9]*.[0-9]* && $t != *[!0-9.]* ]] && REAL_FL=bsd9
if (( REAL_GNU )); then REAL_FL=gnu; t=$(stat -c %.9Y -- / 2>/dev/null); [[ $t == [0-9]*.[0-9]* && $t != *[!0-9.]* ]] && REAL_FL=gnu9; fi
REAL_BASH=$BASH

# fx MODE — a fresh fixture for MODE: FX, UF_FX, UF_ENV
fx() {
    UF_FX="$_KT_TMPDIR/fx_$1"
    if_build "$UF_FX" || { kt_test_start "fixture $1"; kt_test_fail "if_build failed"; exit 1; }
    FX=$UF_FX
    UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK="$1")
}
# start TEXT — one start of `kk.image ia` (debug), UF_OUT = its first debug
# line holding TEXT, then the output of ib.f (which file's code is loaded)
start() { uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl "'"$1"'"; ib.f'; }
# seen OUT — the start of `start "a normal load"` noticed the change of ib.sh
# and OUT is what ib.f printed: "stale"; or, with a whole-second stat flavour
# (gnu / bsd: no nanoseconds on this host), "racy" (ib.sh's mtime is the
# second its stamp was taken: a miss)
seen() {
    [[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh changed"*$'\n'"$1" \
       || ( $M == stat && ( $REAL_FL == gnu || $REAL_FL == bsd ) \
            && $UF_OUT == "kbool: image: $FX/kcl/ib/ib.sh changed in the second its stamp was taken (racy)"*$'\n'"$1" ) ]]
}
# seen_keep OUT — seen, for a change that keeps the mtime (touch -r, cp -p):
# with a whole-second flavour a change inside the second of the stamp is not
# seen (documented; the nanosecond flavours gnu9 / bsd9 see it)
seen_keep() {
    seen "$1" || [[ $M == stat && ( $REAL_FL == gnu || $REAL_FL == bsd ) && $UF_OUT == ib.f ]]
}
# fresh — a valid image again (the file content restored first by the case)
fresh() { uf_run "$H"'; kk.image --rebuild ia 2>/dev/null'; }
IBF='ib.f() { echo "ib.f"; }'
IBG='ib.f() { echo "ib.g"; }'      # the same size
ibset() {   # ibset LINE — ib.sh's function line (the rest kept)
    printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%ib.sh}../../kbool.sh" || return' \
        'kk.unit ib || return $__kk_unit_rc' "$1" 'IB_V=7' > "$FX/kcl/ib/ib.sh"
}

for M in stat hash dates; do
    kt_test_section "023: KBOOL_IMAGE_CHECK=$M"
    fx "$M"
    start ""
    A=$UF_OUT
    start ""
    [[ $UF_OUT == *"loaded from"* ]] || start ""   # (stat: at most one "racy" rewrite first)
    [[ $A == "kbool: image: no image "*$'\n'"ib.f" && $UF_OUT == "kbool: image: loaded from $FX/img/ia-"*$'\n'"ib.f" ]]
    uf_check "$M: a miss writes, the next start hits" $?
    for f in "$FX"/img/ia-*.img; do IMG=$f; done
    if_pfield "$IMG" 5; m=$IF_F; if_pfield "$IMG" 6; fl=$IF_F
    want=-; [[ $M != stat ]] || want=$REAL_FL
    r=no; for x in "${IMG%.img}".*.ref; do [[ -f $x ]] && r=yes; done
    rw=no; [[ $M == dates ]] && rw=yes
    [[ $m == "$M" && $fl == "$want" && $r == "$rw" ]]
    uf_check "$M: the plain header line names the mode ($m) and the stat flavour ($fl); a .ref file only in dates mode" $?

    # a content edit of the same size, the mtime put back (also: an old-dated copy)
    touch -r "$FX/kcl/ib/ib.sh" "$FX/mt.keep"
    ibset "$IBG"; touch -r "$FX/mt.keep" "$FX/kcl/ib/ib.sh"
    start "a normal load"
    if [[ $M == dates ]]; then
        [[ $UF_OUT == "ib.f" ]]
        uf_check "dates: a same-size edit with the old mtime is NOT seen (the image's old code runs: the documented blind spot, R15)" $?
    else
        seen_keep ib.g
        uf_check "$M: a same-size edit with the old mtime is stale (the new code loads)" $?
    fi
    ibset "$IBF"; touch -t 202001010000 "$FX/kcl/ib/ib.sh"; fresh

    # an old-dated copy of another file over a stamped one (cp -p)
    ibset "$IBG"; touch -t 201901010000 "$FX/kcl/ib/ib.sh"; cp -p "$FX/kcl/ib/ib.sh" "$FX/ib.copy"
    ibset "$IBF"; touch -t 202001010000 "$FX/kcl/ib/ib.sh"; fresh
    cp -p "$FX/ib.copy" "$FX/kcl/ib/ib.sh"
    start "a normal load"
    if [[ $M == dates ]]; then
        [[ $UF_OUT == "ib.f" ]]
        uf_check "dates: cp -p of an older file is NOT seen (only a KBOOL_VERSION change would be: it is keyed)" $?
    else
        seen_keep ib.g
        uf_check "$M: cp -p of an older file is stale" $?
    fi
    ibset "$IBF"; touch -t 202001010000 "$FX/kcl/ib/ib.sh"; fresh

    # a size change (a new mtime)
    ibset "$IBF # longer"
    start "a normal load"
    seen ib.f
    uf_check "$M: a size change is stale" $?
    ibset "$IBF"; touch -t 202001010000 "$FX/kcl/ib/ib.sh"; fresh

    # touch: the mtime only
    touch "$FX/kcl/ib/ib.sh"
    start "a normal load"
    if [[ $M == hash ]]; then
        [[ $UF_OUT == "ib.f" ]]
        uf_check "hash: touch alone is not a change (the content is the same): still a hit" $?
    else
        seen ib.f
        uf_check "$M: touch is stale" $?
    fi
    touch -t 202001010000 "$FX/kcl/ib/ib.sh"; fresh

    # a removed file
    mv "$FX/kcl/ib/ib.sh" "$FX/ib.keep"
    uf_run "$H; $FL"'; kk.image ia 2>"$FX/e.txt"; fl "stale"'
    mv "$FX/ib.keep" "$FX/kcl/ib/ib.sh"
    [[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh is missing"* ]]
    uf_check "$M: a removed stamped file is stale" $?
    rm -f "$FX"/img/*.hold; fresh

    # an edit during the write window: iwin touches its own file in its load
    if_unit "$FX" iwin <<'EOF'
IWIN_V=1
[[ -z ${IWIN_TOUCH-} ]] || command touch "$KK_UNIT_DIR/iwin.sh"
EOF
    touch -t 202001010000 "$FX/kcl/iwin/iwin.sh"
    uf_run "$H"'; IWIN_TOUCH=1 kk.image iwin 2>&1 | grep "no image written\|held"; kk.image --path iwin >/dev/null 2>&1; echo "path=$?"'
    [[ $UF_OUT == "kbool: image: no image written: $FX/kcl/iwin/iwin.sh changed during the load"$'\n'"path=1" \
       && -z $(ls "$FX"/img/iwin-* 2>/dev/null) ]]
    uf_check "$M: a stamped file edited during the load: no image, no hold (the next start writes)" $?

    # a future mtime: no write, a hold; the next start is a plain load
    touch -t 203801010000 "$FX/kcl/iwin/iwin.sh"
    uf_run "$H"'; kk.image iwin 2>&1 | grep "no image written\|held"'
    A=$UF_OUT
    uf_run "$H"'; kk.image iwin 2>&1 | grep -c "held ("'
    [[ $A == "kbool: image: no image written: $FX/kcl/iwin/iwin.sh has a future mtime"$'\n'"kbool: image: held for an hour: $FX/img/iwin-"*".hold" && $UF_OUT == 1 ]]
    uf_check "$M: a future mtime: no image, a hold; the next start is held" $?
    touch -t 202001010000 "$FX/kcl/iwin/iwin.sh"
    rm -f "$FX"/img/iwin-*

    # a future CTIME (stat; critic M5): a hold, like a future mtime — not a
    # writer run on every start. A ctime cannot be set portably: iwk changes
    # its own ctime in its load (touch -r keeps the old mtime), and "now" is
    # moved back a day through kk._img_now (the writer's clock seam).
    if [[ $M == stat ]]; then
        if_unit "$FX" iwk <<'EOF'
IWK_V=1
command touch -r "$KK_UNIT_DIR/../ib/ib.sh" "$KK_UNIT_DIR/iwk.sh"
EOF
        touch -t 202001010000 "$FX/kcl/iwk/iwk.sh"
        uf_run "$H"'; kk._image_lib; kk._img_now() { __kk_imw_now=$(( EPOCHSECONDS - 86400 )); }; kk.image iwk 2>&1 | grep "no image written\|held for"'
        [[ $UF_OUT == "kbool: image: no image written: $FX/kcl/iwk/iwk.sh has a future ctime ("*"kbool: image: held for an hour: $FX/img/iwk-"*".hold" ]]
        uf_check "stat: a stamped file with a future ctime (now moved back a day): no image, a hold" $?
        rm -f "$FX"/img/iwk-*
    fi

    # forks of a hit (the trace of every command: another BASHPID = a fork)
    uf_run "$H"'; kk.image ia 2>/dev/null'   # (settles a "racy" image first)
    uf_run 'source "$FX/kbool.sh"; exec 8>"$FX/fk.trace"; BASH_XTRACEFD=8; PS4='"'"'+${BASHPID}|'"'"'; printf "MAIN=%s\n" "$BASHPID" >&8; set -x; VERBOSE_KKLASS=debug kk.image ia 2>/dev/null; set +x; unset BASH_XTRACEFD; echo "pid=${__KK_UNIT_PID[ia]-image}"'
    # (a subshell traces with its own BASHPID; an external command is traced
    # by the shell that forks it: every command word of the main shell that
    # names a file on PATH counts too)
    forks=0 main="" cmd="" ext=""
    unset -v words; declare -A words=()
    while IFS= read -r line; do
        case $line in MAIN=*) main=${line#MAIN=}; continue ;; +*) ;; *) continue ;; esac
        p=${line%%|*}; p=${p##*+}
        [[ -n $p && $p != *[!0-9]* ]] || continue
        c=${line#*|}
        if [[ $p == "$main" ]]; then
            [[ $c == "command "* ]] && c=${c#command }
            c=${c%% *}
            [[ -z $c || $c == *[=\[\(\$]* ]] || words[$c]=1
            continue
        fi
        forks=$(( forks + 1 )); cmd=${c%% -*}
    done < "$FX/fk.trace"
    for c in "${!words[@]}"; do [[ $(type -t -- "$c" 2>/dev/null) != file ]] || ext+="$c "; done
    case $M in dates) w="0 " ;; stat) w="1 command stat" ;; hash) w="1 command cksum" ;; esac
    [[ $UF_OUT == "pid=image" && "$forks $cmd" == "$w" && -z $ext ]]
    uf_check "$M: a hit forks ${w% *} time(s)${cmd:+ ($cmd)}, no external command in the main shell${ext:+ (found: $ext)} [§9, image.forks]" $?
done

# ---------------------------------------------------------------------------
kt_test_section "023: a missing tool, an unknown or BSD stat flavour (§7.6)"

fx stat
# fb/: wrappers of the writer's mv, rm, mkdir and the test's head, grep, ls
# (no stat, no cksum on PATH)
mkdir -p "$FX/fb"
for t in mv rm mkdir head grep ls cat; do
    printf '#!%s\nexec %q "$@"\n' "$REAL_BASH" "$(type -P "$t")" > "$FX/fb/$t"; chmod +x "$FX/fb/$t"
done
for v in stat hash; do
    uf_run "$H"'; PATH="$FX/fb"; KBOOL_IMAGE_CHECK='"$v"' kk.image ia 2>&1 | { head -1; cat >/dev/null; }; KBOOL_IMAGE_CHECK=dates kk.image --path ia; echo "rc=$?"'
    tool=stat; [[ $v == hash ]] && tool=cksum
    [[ $UF_OUT == "kbool: image: KBOOL_IMAGE_CHECK=$v: $tool is not on PATH; using dates"$'\n'"$FX/img/ia-"*".img"$'\n'"rc=0" ]]
    uf_check "$v without $tool on PATH: runs as dates, keyed as dates (the dates image is the one written), a debug line" $?
    rm -f "$FX"/img/*
done

# fs/: a stat that takes neither -c nor -f (and the wrappers)
mkdir -p "$FX/fs"; cp "$FX"/fb/* "$FX/fs/"
printf '#!%s\necho "stat: unknown option" >&2\nexit 1\n' "$REAL_BASH" > "$FX/fs/stat"; chmod +x "$FX/fs/stat"
uf_run "$H"'; PATH="$FX/fs"; kk.image ia 2>&1 | grep -v profile'
A=$UF_OUT
uf_run "$H"'; PATH="$FX/fs"; kk.image ia 2>&1'
B=$UF_OUT
uf_run "$H"'; KBOOL_IMAGE_CHECK=dates kk.image --path ia 2>/dev/null'
[[ $A == "kbool: image: no image $FX/img/ia-"*"KBOOL_IMAGE_CHECK=stat: the stat on PATH takes neither -c nor -f; using dates (stat.hold)"$'\n'"kbool: image: wrote $UF_OUT" \
   && -f $FX/img/stat.hold \
   && $B == "kbool: image: KBOOL_IMAGE_CHECK=stat: stat.hold (the stat on PATH takes neither -c nor -f, "*" s ago); using dates"$'\n'"kbool: image: loaded from $UF_OUT" ]]
uf_check "a stat of an unknown flavour: the writer falls back to dates (the dates image), FOLDER/stat.hold; the next start runs as dates from the hold and hits" $?
printf '%s old\n' $(( EPOCHSECONDS - 4000 )) > "$FX/img/stat.hold"
uf_run "$H"'; PATH="$FX/fs"; kk.image ia 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: no image "* ]]
uf_check "stat.hold older than an hour: stat mode is tried again (a miss: no stat image yet)" $?
rm -f "$FX"/img/*

# fbsd/: a BSD stat (no -c; -f answered by the host stat in its own flavour)
mkdir -p "$FX/fbsd"; cp "$FX"/fb/* "$FX/fbsd/"
cat > "$FX/fbsd/stat" <<EOF
#!$REAL_BASH
[[ \$1 == -f && \$2 == '%z %m %c %i %u %Lp' && \$3 == -- ]] || { echo "stat: illegal option -- \${1#-}" >&2; exit 1; }
shift 3
if (( $REAL_GNU )); then exec "$REAL_STAT" -c '%s %Y %Z %i %u %a' -- "\$@"; else exec "$REAL_STAT" -f '%z %m %c %i %u %Lp' -- "\$@"; fi
EOF
chmod +x "$FX/fbsd/stat"
uf_run "$H"'; PATH="$FX/fbsd"; kk.image ia 2>/dev/null'
uf_run "$H"'; PATH="$FX/fbsd"; kk.image ia 2>/dev/null'   # (a "racy" rewrite at most)
uf_run "$H"'; PATH="$FX/fbsd"; kk.image ia 2>&1'
for f in "$FX"/img/ia-*.img; do IMG=$f; done
if_pfield "$IMG" 6
[[ $UF_OUT == "kbool: image: loaded from $IMG" && $IF_F == bsd ]]
uf_check "a BSD stat (only -f): probed as bsd (the plain line says so), the next start hits through stat -f" $?
# the racy rule of the whole-second flavours: a stamped file whose mtime is
# not before the second the stamps were taken in (here: that second set back
# to 2001 in the image) — a miss and a rewrite, not "stale" (no hold)
IFS= read -r -d '' z < "$IMG" || :
t=${z#*__kk_img_stime=}; t=${t%%[!0-9]*}
printf '%s' "${z/__kk_img_stime=$t/__kk_img_stime=1000000000}" > "$IMG.x" && mv -f "$IMG.x" "$IMG"
uf_run "$H"'; PATH="$FX/fbsd"; kk.image ia 2>&1 | grep -v profile; ls "$FX/img" | grep -c "\.hold$"'
[[ ${#t} == 10 && $UF_OUT == "kbool: image: $FX/kcl/ia/ia.sh changed in the second its stamp was taken (racy): a normal load, then an image"$'\n'"kbool: image: wrote $IMG"$'\n'"0" ]]
uf_check "bsd flavour (whole seconds): a file whose mtime is not before the stamp second is racy — a miss, rewritten, no hold" $?
touch "$FX/kcl/ib/ib.sh"; if_age "$IMG" 3600
uf_run "$H"'; PATH="$FX/fbsd"; kk.image ia 2>&1 | { head -1; cat >/dev/null; }'
[[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh changed after the image was made (stat)"* || $UF_OUT == *"(racy)"* ]]
uf_check "bsd flavour: an edit is stale" $?
touch -t 202001010000 "$FX/kcl/ib/ib.sh"; rm -f "$FX"/img/*

# ---------------------------------------------------------------------------
kt_test_section "023: stat mode's permission bits (§8.1, critic M4; POSIX only — emulated)"

# The rule: a group- or world-writable IMAGE is refused; a FOLDER only when it
# is world-writable without the sticky bit (a group-writable folder is fine:
# the image and its .ref must be this user's, -O, and no symbolic link; a
# sticky 1777 folder keeps others from renaming or removing them).
# OSTYPE=linux-gnu in the child after kbool.sh (the bits are not checked on
# the Windows runtimes, whose modes are no guard); fgw/stat reports the mode
# of IFAKE_MODE ("PATH=MODE PATH=MODE ...") for the paths listed there and
# the real modes without their group / other write bits for the rest (one
# real stat per path)
mkdir -p "$FX/fgw"; cp "$FX"/fb/* "$FX/fgw/"
cat > "$FX/fgw/stat" <<EOF
#!$REAL_BASH
flag=\$1 fmt=\$2; shift 3
for p; do
    l=\$("$REAL_STAT" "\$flag" "\$fmt" -- "\$p") || exit 1
    printf -v m '%o' \$(( 8#\${l##* } & ~8#022 ))      # (Cygwin's ACLs report 770 for our own folders)
    for e in \$IFAKE_MODE; do [[ \${e%=*} != "\$p" ]] || m=\${e##*=}; done
    printf '%s\n' "\${l% *} \$m"
done
EOF
chmod +x "$FX/fgw/stat"
P='source "$FX/kbool.sh" || exit 9; OSTYPE=linux-gnu; VERBOSE_KKLASS=debug; PATH="$FX/fgw"'
uf_run "$P"'; kk.image ia 2>/dev/null'
uf_run "$P"'; kk.image ia 2>/dev/null'   # (a "racy" rewrite at most)
for f in "$FX"/img/ia-*.img; do IMG=$f; done
uf_run "$P"'; kk.image ia 2>&1'
[[ $UF_OUT == "kbool: image: loaded from $IMG" ]]
uf_check "(OSTYPE=linux-gnu, the stand-in stat reporting the real modes: a hit)" $?
# (WARN U: kk.image ia twice in one process, kk.unit --forget between: the
# lines that are not debug lines)
W='{ kk.image ia; echo "rc=$?"; kk.unit --forget ia ib; kk.image ia; echo "rc=$?"; } 2>&1 | grep -v "kbool: image:"'
uf_run "$P; export IFAKE_MODE=\"$IMG=664\"; $W"
[[ $UF_OUT == "kbool: WARNING: image $IMG is not trusted ($IMG is group- or world-writable (mode 664)); loading normally"$'\n'"rc=0"$'\n'"rc=0" ]]
uf_check "a group-writable image file in stat mode (POSIX): ONE WARNING (twice checked), a plain load, nothing written" $?
uf_run "$P; export IFAKE_MODE=\"$FX/img=775\""'; kk.image ia 2>&1'
[[ $UF_OUT == "kbool: image: loaded from $IMG" ]]
uf_check "a group-writable (775) image folder: accepted, a hit" $?
uf_run "$P; export IFAKE_MODE=\"$FX/img=777\"; $W"
[[ $UF_OUT == "kbool: WARNING: image $IMG is not trusted ($FX/img is world-writable without the sticky bit (mode 777)); loading normally"$'\n'"rc=0"$'\n'"rc=0" ]]
uf_check "a world-writable (777) image folder without the sticky bit: ONE WARNING for two refusals, plain loads" $?
uf_run "$P; export IFAKE_MODE=\"$FX/img=1777\""'; kk.image ia 2>&1'
[[ $UF_OUT == "kbool: image: loaded from $IMG" ]]
uf_check "a sticky world-writable (1777) image folder: accepted (the image is this user's, -O / ! -L), a hit" $?
rm -f "$FX"/img/*
uf_run "$P; export IFAKE_MODE=\"$FX/img=777\""'; kk.image ia 2>&1 | grep "no image written"; ls "$FX/img" | grep -c .'
[[ $UF_OUT == "kbool: image: no image written: untrusted folder: $FX/img is world-writable without the sticky bit (mode 777)"$'\n'"0" ]]
uf_check "a 777 image folder, no image yet: the writer writes nothing (no image, no hold, no temp)" $?
if (( ! WIN )); then
    chmod 777 "$FX/img"
    uf_run "$H"'; KBOOL_IMAGE_CHECK=stat kk.image ia 2>&1 | grep "no image written"'
    chmod 700 "$FX/img"
    [[ $UF_OUT == "kbool: image: no image written: untrusted folder: $FX/img is world-writable without the sticky bit"* ]]
    uf_check "POSIX, real chmod 777 on the folder: stat mode writes nothing" $?
fi

# ---------------------------------------------------------------------------
kt_test_section "023: a caller's umask 002 (CI rows run so; §8.1, critic M4)"

# (1) a folder kk.image makes is 0700 whatever the caller's umask, and works
UF_ENV=(KBOOL_IMAGE_DIR="$FX/u2/img" KBOOL_IMAGE_CHECK=stat)
uf_run "$P"'; umask 002; kk.image ia 2>/dev/null; echo "rc=$?"'
A=$UF_OUT
uf_run "$P"'; umask 002; kk.image ia 2>&1; echo "rc=$? $(umask)"'
[[ $A == "rc=0" && $UF_OUT == "kbool: image: loaded from $FX/u2/img/ia-"*".img"$'\n'"rc=0 0002" ]]
uf_check "umask 002: the folder kk.image makes passes stat mode's bits check: written, then a hit (the caller's umask kept)" $?
for f in "$FX"/u2/img/ia-*.img; do IMG2=$f; done
if (( ! WIN )); then
    m=$(stat -c %a "$FX/u2/img" 2>/dev/null || stat -f %Lp "$FX/u2/img")
    m2=$(stat -c %a "$IMG2" 2>/dev/null || stat -f %Lp "$IMG2")
    kt_test_start "umask 002: the folder kk.image made is 700, the image 600 (POSIX)"
    if [[ $m == 700 && $m2 == 600 ]]; then kt_test_pass "ok"; else kt_test_fail "modes $m $m2"; fi
    # real modes (the key of the emulated starts: OSTYPE, VERBOSE_KKLASS)
    R='source "$FX/kbool.sh"; OSTYPE=linux-gnu; VERBOSE_KKLASS=debug; umask 002'
    chmod 775 "$FX/u2/img"
    uf_run "$R"'; kk.image ia 2>&1'
    [[ $UF_OUT == "kbool: image: loaded from $IMG2" ]]
    uf_check "umask 002, the folder made 775 (POSIX, real modes): stat mode works (a hit)" $?
    chmod 777 "$FX/u2/img"
    uf_run "$R; $W"
    [[ $UF_OUT == "kbool: WARNING: image $IMG2 is not trusted ($FX/u2/img is world-writable without the sticky bit (mode 777)); loading normally"$'\n'"rc=0"$'\n'"rc=0" ]]
    uf_check "umask 002, a 777 folder (POSIX, real modes): ONE WARNING for two refusals, plain loads" $?
    chmod 1777 "$FX/u2/img"
    uf_run "$R"'; kk.image ia 2>&1'
    [[ $UF_OUT == "kbool: image: loaded from $IMG2" ]]
    uf_check "umask 002, a 1777 folder (POSIX, real modes): accepted (a hit)" $?
    chmod 700 "$FX/u2/img"
fi
# (2)-(4) on every runtime, through the stand-in stat (OSTYPE=linux-gnu)
uf_run "$P; export IFAKE_MODE=\"$FX/u2/img=775\""'; umask 002; kk.image ia 2>&1'
[[ $UF_OUT == "kbool: image: loaded from $IMG2" ]]
uf_check "umask 002, a 775 folder (emulated): stat mode works (a hit)" $?
uf_run "$P; export IFAKE_MODE=\"$FX/u2/img=777\"; umask 002; $W"
[[ $UF_OUT == "kbool: WARNING: image $IMG2 is not trusted ($FX/u2/img is world-writable without the sticky bit (mode 777)); loading normally"$'\n'"rc=0"$'\n'"rc=0" ]]
uf_check "umask 002, a 777 folder (emulated): ONE WARNING for two refusals" $?
uf_run "$P; export IFAKE_MODE=\"$FX/u2/img=1777\""'; umask 002; kk.image ia 2>&1'
[[ $UF_OUT == "kbool: image: loaded from $IMG2" ]]
uf_check "umask 002, a 1777 folder (emulated): accepted (a hit)" $?
UF_ENV=(KBOOL_IMAGE_DIR="$FX/img" KBOOL_IMAGE_CHECK=stat)

kt_test_log "023_ImageModes.sh completed"
