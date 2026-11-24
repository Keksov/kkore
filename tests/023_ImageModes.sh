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
# and OUT is what ib.f printed: "stale", or in stat mode "racy" (ib.sh changed
# in the second its stamp was taken — the image was written right after the
# case restored ib.sh: the change cannot be told from the stamps, a miss)
seen() {
    [[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh changed"*$'\n'"$1" \
       || ( $M == stat && $UF_OUT == "kbool: image: $FX/kcl/ib/ib.sh changed in the second its stamp was taken (racy)"*$'\n'"$1" ) ]]
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
    want=-; if [[ $M == stat ]]; then want=bsd; (( REAL_GNU )) && want=gnu; fi
    r=no; [[ -f ${IMG%.img}.ref ]] && r=yes
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
        seen ib.g
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
        seen ib.g
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
for t in mv rm mkdir head grep ls; do
    printf '#!%s\nexec %q "$@"\n' "$REAL_BASH" "$(type -P "$t")" > "$FX/fb/$t"; chmod +x "$FX/fb/$t"
done
for v in stat hash; do
    uf_run "$H"'; PATH="$FX/fb"; KBOOL_IMAGE_CHECK='"$v"' kk.image ia 2>&1 | head -1; KBOOL_IMAGE_CHECK=dates kk.image --path ia; echo "rc=$?"'
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
uf_run "$H"'; PATH="$FX/fs"; kk.image ia 2>&1 | head -1'
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
touch "$FX/kcl/ib/ib.sh"; if_age "$IMG" 3600
uf_run "$H"'; PATH="$FX/fbsd"; kk.image ia 2>&1 | head -1'
[[ $UF_OUT == "kbool: image: stale: $FX/kcl/ib/ib.sh changed after the image was made (stat)"* || $UF_OUT == *"(racy)"* ]]
uf_check "bsd flavour: an edit is stale" $?
touch -t 202001010000 "$FX/kcl/ib/ib.sh"; rm -f "$FX"/img/*

# ---------------------------------------------------------------------------
kt_test_section "023: stat mode's permission bits (§8.1; POSIX only — emulated)"

# OSTYPE=linux-gnu in the child after kbool.sh (the bits are not checked on
# the Windows runtimes, whose modes are no guard); fgw/stat reports mode 775
# for every path listed in IFAKE_GW and the real modes without their group /
# other write bits for the rest (one real stat per path)
mkdir -p "$FX/fgw"; cp "$FX"/fb/* "$FX/fgw/"
cat > "$FX/fgw/stat" <<EOF
#!$REAL_BASH
flag=\$1 fmt=\$2; shift 3
for p; do
    l=\$("$REAL_STAT" "\$flag" "\$fmt" -- "\$p") || exit 1
    printf -v m '%o' \$(( 8#\${l##* } & ~8#022 ))      # (Cygwin's ACLs report 770 for our own folders)
    l="\${l% *} \$m"
    case " \$IFAKE_GW " in *" \$p "*) l="\${l% *} 775" ;; esac
    printf '%s\n' "\$l"
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
uf_run "$P; export IFAKE_GW=\"$IMG\""'; { kk.image ia; echo "rc=$?"; kk.unit --forget ia ib; kk.image ia; echo "rc=$?"; } 2>&1 | grep -v "kbool: image:"'
[[ $UF_OUT == "kbool: WARNING: image $IMG is not trusted ($IMG is group- or world-writable (mode 775)); loading normally"$'\n'"rc=0"$'\n'"rc=0" ]]
uf_check "a group-writable image in stat mode (POSIX): ONE WARNING (twice checked), a plain load, nothing written" $?
uf_run "$P; export IFAKE_GW=\"$FX/img\""'; kk.image ia 2>&1 | head -1'
[[ $UF_OUT == "kbool: WARNING: image $IMG is not trusted ($FX/img is group- or world-writable (mode 775)); loading normally" ]]
uf_check "a group-writable image folder with an image in it: the WARNING" $?
rm -f "$FX"/img/*
uf_run "$P; export IFAKE_GW=\"$FX/img\""'; kk.image ia 2>&1 | grep "no image written"; ls "$FX/img" | grep -c .'
[[ $UF_OUT == "kbool: image: no image written: untrusted folder: $FX/img is group- or world-writable (mode 775)"$'\n'"0" ]]
uf_check "a group-writable image folder, no image yet: the writer writes nothing (no image, no hold, no temp)" $?
if (( ! WIN )); then
    chmod g+w "$FX/img"
    uf_run "$H"'; KBOOL_IMAGE_CHECK=stat kk.image ia 2>&1 | grep "no image written"'
    chmod g-w "$FX/img"
    [[ $UF_OUT == "kbool: image: no image written: untrusted folder: $FX/img is group- or world-writable"* ]]
    uf_check "POSIX, real chmod g+w on the folder: stat mode writes nothing" $?
fi

kt_test_log "023_ImageModes.sh completed"
