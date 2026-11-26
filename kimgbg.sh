#!/usr/bin/env bash
# kkore/kimgbg.sh — the background writer of `kk.image --background`
# (kklass/docs/dev/IMAGE_PLAN.md, owner decision IMG-D10, "I5 as built").
# Part of the unit loader like kuse.sh: no unit header. Two roles in one file:
#
#   * the foreground (sourced by kk.image on a --background miss, kuse.sh
#     kk._image_bglib; never on a hit): kk._imgbg_fore — a plain kk.uses, then
#     the image folder's marker NAME.bg taken (`set -C`) and the writer
#     started detached (kk._imgbg_spawn); the caller does not wait for it;
#   * the writer (this file run as a script by a fresh $BASH of the same
#     runtime: `bash kimgbg.sh --kbool-image-writer …`): kk._imgbg_main —
#     stdin from /dev/null before anything is sourced, kbool.sh sourced, the
#     request keyed again and written by kimage.sh exactly as a foreground
#     miss would write it, when its key equals the caller's.
#
# THE SPAWN (one subshell, so the caller keeps its `$!`, its job table, its
# traps and options; the subshell ends at once, the writer is reparented: no
# zombie, a later `wait` of the caller never waits for it): ERR / DEBUG /
# RETURN traps dropped and `set +eEuxf`; every descriptor above 2 closed (the
# list of /proc/$BASHPID/fd, else of /dev/fd, else 3..`ulimit -n` (at most 4096) — a `$(fvdlg … 3>&1 1>&2 2>&3)` must
# not wait for the writer to drop the substitution's pipe); then, each part
# where it is found (next to $BASH on Git-bash / MSYS2 / Cygwin, on PATH
# elsewhere):
#     setsid  timeout -k 10 LIMIT  nice -n 10  "$BASH" kimgbg.sh …  </dev/null >/dev/null 2>/dev/null &
#   setsid: a session of its own, no controlling terminal (Linux, MSYS2,
#   Cygwin; Git-bash has none: the writer keeps the console / pty session);
#   timeout: the hard limit (LIMIT 120 s, then KILL 10 s later) — GNU
#   coreutils' timeout (Linux glibc, Git-bash, MSYS2, Cygwin, brew's gtimeout
#   is not looked for) puts itself and the writer in a process group of their
#   own and at the limit signals that whole group: the writer AND its
#   children; busybox's timeout (Alpine) signals only its child, the writer
#   (its children, when the limit hits during one, end on their own: each is
#   a bounded step of the write); FreeBSD's timeout signals its child, and
#   with --kill-after its descendants it reaped; nice: a lower priority.
#   Without a timeout (stock macOS) the writer is its own watchdog (mode
#   `watch`: it runs the real writer again, mode `inner`, as a process
#   substitution and waits on that pipe with `read -t`; at the limit TERM,
#   10 s later KILL, to that writer's pid; a signal to the watcher stops it
#   too; the writer's children are not killed as a group there). The writer's
#   own TERM / HUP / INT trap does not signal a group: it leads none (the
#   tools above do), and the caller's group is never signalled.
#   The marker's PGID field names the writer's group only when it is not the
#   caller's (the caller passes its group in __KK_IMG_BGCPG; '-' otherwise —
#   watch mode, busybox, no /proc), so a guard may signal it safely.
# What the writer reproduces: umask, cwd, the exported variables (inherited);
# the settings this shell keys or reads at load — every KBOOL_* (KBOOL_CONFIG
# made absolute), VERBOSE_KKLASS, __KK_CFG_ETC, HOME, USERPROFILE, ProgramData,
# LANG, LC_ALL, LC_CTYPE, BASH_COMPAT and the image seams __KK_IMG_MINLOAD /
# _MAXN / _MAXB — exported in the subshell only (the ones this shell has
# unexported are named in __KK_IMG_KUNX and unexported again by the writer:
# ONE list with kimage.sh kk._img__child: kimghit.sh kk._image_kenv); IFS, the
# shopts extglob / expand_aliases / nocasematch, `set -u` / `-f`; on argv
# the calling file as this shell resolved it (as kk._img__child resolves it),
# the project file, kbool.sh's path, the caller's __KK_UNIT_ORDER and the
# request; in the environment the caller's full key (__KK_IMG_BGKEY) and the
# marker's token (__KK_IMG_BGTOK). No temp file: nothing another user could
# swap. The writer writes only when its own key equals the caller's (else no
# image, a hold), and only when its unit order after a fresh kbool.sh equals
# the caller's (a start's base check would refuse the image otherwise).
#
# THE MARKER NAME.bg (in the image folder, next to NAME.img; one writer per
# image): `TIME TOKEN PID TAG PGID` (PID / PGID `-` until the writer has
# started; TAG = FNV-1a of $BASH, the runtime). The caller takes it after its
# load with `set -C` (atomic); the writer writes its pid into it, makes it
# mode 600 and removes it at its end (while it still holds its TOKEN). A
# marker is FRESH (a writer is running: no second writer, no wait) while
# younger than LIMIT + 20 s and its pid answers `kill -0` (another runtime's
# pid: the age alone; no pid yet: younger than 30 s). A marker that is not
# fresh but younger than 600 s means the last writer did not finish (killed,
# a container that ended): a hold of 10 minutes instead of a new writer;
# older: taken over. Pruning (kimage.sh) removes markers older than 600 s and
# --forget the request's.
#
# HOLDS. A writer that refuses holds as a foreground writer does (kimage.sh,
# an hour); a writer stopped by a signal or the limit: 10 minutes (the reason
# is the environment, not the image); its own failures — kbool.sh not
# sourced, another key, another unit order, not applicable — an hour; no
# image and no hold after the write: 10 minutes. So a failing writer is never
# started again on every call.
#
# Not a background writer (the call is still a hit when an image is valid,
# else a plain kk.uses, one debug line): a prior set P (units loaded before
# kk.image: a chained writer proves its image against its own script, which a
# fresh process cannot see), a fresh marker, a stale one (the hold above), an
# image folder that cannot be made. A caller's NON-EXPORTED globals named
# like a unit's words are not seen by the background writer's M1 probe (the
# foreground writer refuses such a load); such a caller's starts are plain
# loads through the start's clash check — safe, no hit (documented limit).
#
# Test seams (internal): __KK_IMG_BGSYNC=1 runs the same command chain
# without `&` (the call waits); __KK_IMG_BGPAUSE=S makes the writer wait S s
# after taking the marker; __KK_IMG_BGLIMIT=S the hard limit (default 120);
# __KK_IMG_BGERR=FILE the writer's stderr (else /dev/null) — with
# VERBOSE_KKLASS=debug its `kbool: image: …` lines; __KK_IMG_BGNOTOOLS=1 no
# setsid / timeout / nice (the watchdog mode); __KK_IMG_BGNOPROC=1 / 2 the
# descriptor list without /proc / without /proc and /dev/fd (the 3..ulimit
# loop); kk._img_bgwait waits for a writer to end.
#
# Locals: __kk_ib*_ / __kk_imbg_* (the dump of kimage.sh skips every name
# starting with __kk_im).

# kk._imgbg_fore — kk.image's --background miss (kimghit.sh kk._image_run,
# kk.image's locals): the plain load, then the writer (or a debug line why
# none). rc = the load's.
kk._imgbg_fore() {
    local __kk_ibf_rc=0 __kk_ibf_no="" __kk_ibf_w0=$__kk_im_why __kk_ibf_ord="" __kk_imbg_tok="" __kk_imbg_tag=""
    if [[ -n $__kk_im_pn ]]; then
        __kk_ibf_no="a prior set is loaded ($__kk_im_pn): --background writes no chained image"
    fi
    # (the unit table BEFORE the load: the writer compares it with a fresh kbool.sh's)
    printf -v __kk_ibf_ord '%s\n' "${__KK_UNIT_ORDER[@]}"
    kk._uses "$__kk_im_caller" "${__kk_im_args[@]}"
    __kk_ibf_rc=$?
    if [[ -z $__kk_ibf_no ]] && (( __kk_ibf_rc != 0 )); then
        # (as the foreground writer: a failed load writes no image, a hold)
        __kk_ibf_no="the load failed (rc $__kk_ibf_rc): a hold for an hour"
        kk._image_hold "the load failed (rc $__kk_ibf_rc)"
    fi
    if [[ -z $__kk_ibf_no ]] && ! kk._imgbg_take; then __kk_ibf_no=$__kk_im_why; fi
    if [[ -n $__kk_ibf_no ]]; then
        kk._image_dbg "$__kk_ibf_w0: a normal load (kk.uses ${__kk_im_args[*]}); no background writer: $__kk_ibf_no"
        return "$__kk_ibf_rc"
    fi
    kk._imgbg_spawn "$__kk_im_dir/$__kk_im_name.bg" "$__kk_imbg_tok" "$__kk_ibf_ord"
    kk._image_dbg "$__kk_ibf_w0: a normal load (kk.uses ${__kk_im_args[*]}), then a background writer ($__kk_im_dir/$__kk_im_name.bg)"
    return "$__kk_ibf_rc"
}

# kk._imgbg_limit — RESULT = the writer's hard limit in seconds
# (__KK_IMG_BGLIMIT, default 120).
kk._imgbg_limit() {
    RESULT=${__KK_IMG_BGLIMIT-}
    [[ -n $RESULT && $RESULT != *[!0-9]* && ${#RESULT} -le 5 ]] || RESULT=120
    RESULT=$(( 10#$RESULT ))
    (( RESULT > 0 )) || RESULT=120
}

# kk._imgbg_marker FILE — read a marker into the caller's __kk_imbg_mt (time),
# _mo (token), _mp (pid), _mg (tag), _mq (pgid). rc 1 when FILE is not a
# regular file of this user (or a symbolic link).
kk._imgbg_marker() {
    __kk_imbg_mt="" __kk_imbg_mo="" __kk_imbg_mp="" __kk_imbg_mg="" __kk_imbg_mq=""
    [[ -f $1 && ! -L $1 && -O $1 ]] || return 1
    { IFS=' ' read -r __kk_imbg_mt __kk_imbg_mo __kk_imbg_mp __kk_imbg_mg __kk_imbg_mq < "$1"; } 2>/dev/null || :
    return 0
}

# kk._imgbg_age — RESULT = the age of the marker read (seconds; 999999 when
# its time is not a number, negative for a future time).
kk._imgbg_age() {
    if [[ -n $__kk_imbg_mt && $__kk_imbg_mt != *[!0-9]* && ${#__kk_imbg_mt} -le 12 ]]; then
        RESULT=$(( EPOCHSECONDS - 10#$__kk_imbg_mt ))
    else
        RESULT=999999
    fi
}

# kk._imgbg_fresh — rc 0 when the marker read names a running writer (see
# the header); needs __kk_imbg_tag (this runtime's).
kk._imgbg_fresh() {
    local __kk_ibh_a __kk_ibh_l
    kk._imgbg_age; __kk_ibh_a=$RESULT
    kk._imgbg_limit; __kk_ibh_l=$(( RESULT + 20 ))
    (( __kk_ibh_a >= 0 && __kk_ibh_a < __kk_ibh_l )) || return 1
    if [[ -n $__kk_imbg_mp && $__kk_imbg_mp != *[!0-9]* ]]; then
        if [[ $__kk_imbg_mg == "$__kk_imbg_tag" ]]; then kill -0 "$__kk_imbg_mp" 2>/dev/null; return; fi
        return 0
    fi
    (( __kk_ibh_a < 30 ))
}

# kk._imgbg_take — after the load: make the image folder when it is missing
# (one mkdir, the trust walk again), then take the marker (fork-free).
# rc 0 taken (the caller's __kk_imbg_tok, __kk_imbg_tag); 1 not (__kk_im_why
# says why).
kk._imgbg_take() {
    local - __kk_ibt_m=$__kk_im_dir/$__kk_im_name.bg __kk_ibt_i __kk_ibt_r __kk_ibt_s RESULT="" \
          __kk_imbg_mt __kk_imbg_mo __kk_imbg_mp __kk_imbg_mg __kk_imbg_mq
    if (( __kk_im_mk )); then
        ( umask 077 && mkdir -p -- "$__kk_im_dir" ) 2>/dev/null
        kk._image_levels
        if (( __kk_im_mk )) || [[ -n $__kk_im_bad ]]; then
            __kk_im_why="cannot make the image folder $__kk_im_dir${__kk_im_bad:+ ($__kk_im_bad)}"; return 1
        fi
    fi
    kk._image_hash "$BASH" __kk_imbg_tag
    printf -v __kk_imbg_tok '%08x%08x' "$SRANDOM" "$SRANDOM"
    # (a few rounds: a marker can vanish or change between the reads — a
    # writer that just ended, another start that just took it; fix round 1 X4b)
    for (( __kk_ibt_i = 0; __kk_ibt_i < 4; __kk_ibt_i++ )); do
        if [[ ! -e $__kk_ibt_m && ! -L $__kk_ibt_m ]]; then
            set -C
            if { printf '%s %s - %s -\n' "$EPOCHSECONDS" "$__kk_imbg_tok" "$__kk_imbg_tag" > "$__kk_ibt_m"; } 2>/dev/null; then return 0; fi
            set +C
            continue                    # (another start made it first: read it)
        fi
        if ! kk._imgbg_marker "$__kk_ibt_m"; then
            __kk_im_why="the writer's marker $__kk_ibt_m is not a regular file of this user"; return 1
        fi
        # (an empty read: a marker being written this instant — read again)
        for (( __kk_ibt_r = 0; __kk_ibt_r < 5 && ${#__kk_imbg_mt} == 0; __kk_ibt_r++ )); do
            [[ -e $__kk_ibt_m ]] || break
            kk._imgbg_marker "$__kk_ibt_m" || break
        done
        [[ -e $__kk_ibt_m ]] || continue
        if kk._imgbg_fresh; then
            kk._imgbg_age
            __kk_im_why="a background writer is running (pid ${__kk_imbg_mp:--}, marked $RESULT s ago)"; return 1
        fi
        # not fresh: the same marker still there? (a writer removes its marker
        # and exits: read before the removal, its pid gone after it — no hold)
        __kk_ibt_s="$__kk_imbg_mt $__kk_imbg_mo $__kk_imbg_mp"
        kk._imgbg_marker "$__kk_ibt_m" || continue
        [[ -e $__kk_ibt_m && "$__kk_imbg_mt $__kk_imbg_mo $__kk_imbg_mp" == "$__kk_ibt_s" ]] || continue
        kk._imgbg_age
        if (( RESULT >= 0 && RESULT < 600 )); then
            __kk_im_why="the last background writer did not finish (marked $RESULT s ago): a hold for 10 minutes"
            kk._image_hold "a background writer did not finish" "" "" "" $(( EPOCHSECONDS - 3000 ))
            return 1
        fi
        # (older: a leftover, taken over — no rm: fork-free; a race here at
        # worst starts two writers, both images valid: §7.4)
        { printf '%s %s - %s -\n' "$EPOCHSECONDS" "$__kk_imbg_tok" "$__kk_imbg_tag" > "$__kk_ibt_m"; } 2>/dev/null \
            || { __kk_im_why="cannot write the marker $__kk_ibt_m"; return 1; }
        return 0
    done
    __kk_im_why="the writer's marker $__kk_ibt_m kept changing"
    return 1
}

# kk._imgbg_unstale — kk.image --rebuild: remove this image's marker unless a
# writer runs (fresh): a stale one would make the next background miss hold.
kk._imgbg_unstale() {
    local __kk_ibu_m=$__kk_im_dir/$__kk_im_name.bg __kk_imbg_tag="" RESULT="" \
          __kk_imbg_mt __kk_imbg_mo __kk_imbg_mp __kk_imbg_mg __kk_imbg_mq
    kk._imgbg_marker "$__kk_ibu_m" || return 0
    kk._image_hash "$BASH" __kk_imbg_tag
    if ! kk._imgbg_fresh; then command rm -f -- "$__kk_ibu_m" 2>/dev/null; fi
    return 0
}

# kk._imgbg_tool NAME VAR — VAR = the NAME to run: next to $BASH on the
# Windows runtimes (their own: Git-bash's timeout cannot signal an MSYS2
# process), else the first executable NAME on PATH; rc 1 none. Fork-free.
kk._imgbg_tool() {
    local __kk_ibo_p __kk_ibo_d
    printf -v "$2" '%s' ""
    case $OSTYPE in
        msys*|cygwin*)
            __kk_ibo_d=${BASH%/*}
            if [[ -f $__kk_ibo_d/$1 || -f $__kk_ibo_d/$1.exe ]]; then printf -v "$2" '%s' "$__kk_ibo_d/$1"; return 0; fi
            return 1 ;;
    esac
    __kk_ibo_p=${PATH-}
    while [[ -n $__kk_ibo_p ]]; do
        __kk_ibo_d=${__kk_ibo_p%%:*}
        if [[ $__kk_ibo_p == *:* ]]; then __kk_ibo_p=${__kk_ibo_p#*:}; else __kk_ibo_p=""; fi
        [[ -n $__kk_ibo_d ]] || __kk_ibo_d=.
        if [[ -f $__kk_ibo_d/$1 && -x $__kk_ibo_d/$1 ]]; then printf -v "$2" '%s' "$__kk_ibo_d/$1"; return 0; fi
    done
    return 1
}

# kk._imgbg_spawn MARKER TOKEN ORDER — start the writer (see the header),
# from kk.image's locals; ORDER = the caller's __KK_UNIT_ORDER before its
# load, one entry per line. Never fails the caller.
kk._imgbg_spawn() {
    local __kk_ibs_cl=$__kk_im_caller __kk_ibs_drv=${__KK_UNITS[kuse]-} __kk_ibs_n __kk_ibs_x __kk_ibs_o="" __kk_ibs_k="" \
          __kk_ibs_ord=$3 __kk_ibs_md=watch __kk_ibs_t="" __kk_ibs_err=${__KK_IMG_BGERR:-/dev/null} __kk_ibs_pg=- \
          __kk_imke_x="" RESULT=""
    local -a __kk_ibs_ch=() __kk_ibs_s=() __kk_imke_s=() __kk_imke_u=()
    __kk_ibs_drv=${__kk_ibs_drv%[/\\]*}/kimgbg.sh
    # the calling file as this shell resolved it (kimage.sh kk._img__child)
    case $__kk_ibs_cl in
        ''|main|environment) if [[ $- == *i* ]]; then __kk_ibs_cl=$PWD/.kbool-prompt; fi ;;
        /*|[A-Za-z]:*) ;;
        *) if [[ -n ${__KK_FILE_PWD[$__kk_ibs_cl]+x} && ${__KK_FILE_PWD[$__kk_ibs_cl]} != "$PWD" ]]; then
               __kk_ibs_cl=${__KK_FILE_PWD[$__kk_ibs_cl]}/$__kk_ibs_cl
           fi ;;
    esac
    if [[ :$BASHOPTS: == *:extglob:* ]]; then __kk_ibs_o+=" extglob"; fi
    if [[ :$BASHOPTS: == *:expand_aliases:* ]]; then __kk_ibs_o+=" expand_aliases"; fi
    if [[ $- == *u* ]]; then __kk_ibs_k+=" u"; fi
    if [[ $- == *f* ]]; then __kk_ibs_k+=" f"; fi
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_ibs_k+=" nocasematch"; fi
    # the settings (kimghit.sh kk._image_kenv: the list kimage.sh's fresh
    # processes get, plus the image seams); the unset ones are not exported
    # in this shell, so the writer does not get them anyway
    kk._image_kenv bg
    __kk_ibs_s=("${__kk_imke_s[@]}")
    if [[ -n ${IFS+x} ]]; then __kk_ibs_s+=("__KK_IMG_KIFS=$IFS"); else __kk_ibs_s+=(__KK_IMG_KIFU=1); fi
    # this shell's process group (/proc, fork-free; '-' unknown): the writer
    # records a group of its own in the marker only when it is not this one
    # (a test's guard signals that group: never the caller's — fix round 1 M1)
    if [[ -r /proc/$BASHPID/stat ]]; then
        { read -r __kk_ibs_x < "/proc/$BASHPID/stat"; } 2>/dev/null || __kk_ibs_x=""
        __kk_ibs_x=${__kk_ibs_x##*) }
        __kk_ibs_pg=${__kk_ibs_x#* }; __kk_ibs_pg=${__kk_ibs_pg#* }; __kk_ibs_pg=${__kk_ibs_pg%% *}
        [[ -n $__kk_ibs_pg && $__kk_ibs_pg != *[!0-9]* ]] || __kk_ibs_pg=-
    fi
    __kk_ibs_s+=("__KK_IMG_KOPT=${__kk_ibs_o# }" "__KK_IMG_KSET=${__kk_ibs_k# }" "__KK_IMG_KUNX=${__kk_imke_x# }" \
                 "__KK_IMG_BGKEY=$__kk_im_key" "__KK_IMG_BGTOK=$2" "__KK_IMG_BGCPG=$__kk_ibs_pg")
    if [[ -z ${__KK_IMG_BGNOTOOLS-} ]]; then
        if kk._imgbg_tool setsid __kk_ibs_t; then __kk_ibs_ch+=("$__kk_ibs_t"); fi
        if kk._imgbg_tool timeout __kk_ibs_t; then
            kk._imgbg_limit
            __kk_ibs_ch+=("$__kk_ibs_t" -k 10 "$RESULT")
            __kk_ibs_md=run
        fi
        if kk._imgbg_tool nice __kk_ibs_t; then __kk_ibs_ch+=("$__kk_ibs_t" -n 10); fi
    fi
    (
        trap - ERR DEBUG RETURN
        set +eEuxf
        # every descriptor above 2 closed: the list of /proc/$BASHPID/fd, else
        # of /dev/fd (macOS / BSD: the process's own), else 3..`ulimit -n`
        # (at most 4096); __KK_IMG_BGNOPROC=1 / 2 (a test seam) skips /proc /
        # /proc and /dev/fd
        __kk_ibs_x=""
        if [[ ${__KK_IMG_BGNOPROC-} != [12] && -d /proc/$BASHPID/fd ]]; then __kk_ibs_x=/proc/$BASHPID/fd
        elif [[ ${__KK_IMG_BGNOPROC-} != 2 && -d /dev/fd ]]; then __kk_ibs_x=/dev/fd; fi
        if [[ -n $__kk_ibs_x ]]; then
            for __kk_ibs_x in "$__kk_ibs_x"/*; do
                __kk_ibs_n=${__kk_ibs_x##*/}
                if [[ -n $__kk_ibs_n && $__kk_ibs_n != *[!0-9]* ]] && (( __kk_ibs_n > 2 )); then exec {__kk_ibs_n}>&-; fi
            done
        else
            __kk_ibs_t=$(ulimit -n 2>/dev/null)     # (a fork in this subshell: the rare path only)
            if [[ -z $__kk_ibs_t || $__kk_ibs_t == *[!0-9]* || ${#__kk_ibs_t} -gt 6 ]] || (( __kk_ibs_t > 4096 || __kk_ibs_t < 3 )); then
                __kk_ibs_t=4096
            fi
            for (( __kk_ibs_n = 3; __kk_ibs_n < __kk_ibs_t; __kk_ibs_n++ )); do exec {__kk_ibs_n}>&-; done
        fi
        for __kk_ibs_x in "${__kk_ibs_s[@]}"; do export "${__kk_ibs_x?}"; done
        unset -v BASH_ENV ENV
        if [[ ${__KK_IMG_BGSYNC-} == 1 ]]; then
            "${__kk_ibs_ch[@]}" "$BASH" "$__kk_ibs_drv" --kbool-image-writer "$__kk_ibs_md" "$1" "${__KK_UNITS[kbool]-}" \
                "${__KK_PROJECT-}" "$__kk_ibs_cl" "$__kk_ibs_ord" "${__kk_im_args[@]}" </dev/null >/dev/null 2>"$__kk_ibs_err"
        else
            "${__kk_ibs_ch[@]}" "$BASH" "$__kk_ibs_drv" --kbool-image-writer "$__kk_ibs_md" "$1" "${__KK_UNITS[kbool]-}" \
                "${__KK_PROJECT-}" "$__kk_ibs_cl" "$__kk_ibs_ord" "${__kk_im_args[@]}" </dev/null >/dev/null 2>"$__kk_ibs_err" &
        fi
    ) 2>/dev/null || :
    return 0
}

# ---------------------------------------------------------------------------
# The writer (a fresh bash running this file)

# kk._imgbg_hold REASON BACK — the writer's hold: NAME.hold next to the
# marker, `TIME REASON` with TIME = now - BACK (3000: a hold of 10 minutes),
# under umask 077; nothing over a symbolic link.
kk._imgbg_hold() {
    local __kk_ibd_f=${__KK_IMG_BGM%.bg}.hold
    [[ -n ${__KK_IMG_BGM-} && ! -L $__kk_ibd_f && -d ${__KK_IMG_BGM%/*} ]] || return 0
    ( umask 077; printf '%s %s\n' "$(( EPOCHSECONDS - $2 ))" "${1//$'\n'/ }" > "$__kk_ibd_f" ) 2>/dev/null || :
    return 0
}

# kk._imgbg_exit — the writer's EXIT trap: the marker removed while it holds
# this writer's token.
kk._imgbg_exit() {
    local __kk_imbg_mt __kk_imbg_mo __kk_imbg_mp __kk_imbg_mg __kk_imbg_mq
    if [[ -n ${__KK_IMG_BGM-} ]] && kk._imgbg_marker "$__KK_IMG_BGM" && [[ $__kk_imbg_mo == "${__KK_IMG_BGT-}" ]]; then
        command rm -f -- "$__KK_IMG_BGM" 2>/dev/null
    fi
    return 0
}

# kk._imgbg_term SIG — the writer stopped by a signal (the limit, a logout):
# the pause's sleep stopped, a hold of 10 minutes, exit (the EXIT trap
# removes the marker).
kk._imgbg_term() {
    if [[ -n ${__KK_IMG_BGSP-} ]]; then kill "$__KK_IMG_BGSP" 2>/dev/null; fi
    kk._imgbg_hold "a background writer was stopped ($1)" 3000
    exit 143
}

# kk._imgbg_watch ARG… — mode `watch` (no timeout tool): the writer run again
# as mode `inner` in a process substitution whose pipe tells its end; at the
# limit TERM, 10 s later KILL, to its pid; a hold of 10 minutes.
kk._imgbg_watch() {
    local __kk_ibw_p __kk_ibw_r=0 __kk_ibw_l __kk_ibw_dl __kk_ibw_x="" __kk_ibw_e
    kk._imgbg_limit; __kk_ibw_l=$RESULT
    exec 3< <(exec "$BASH" "${BASH_SOURCE[0]}" --kbool-image-writer inner "$@")
    __kk_ibw_p=$!
    __KK_IMG_BGSP=$__kk_ibw_p     # (a signal to this watcher stops the writer too: kk._imgbg_term)
    __kk_ibw_dl=$(( EPOCHSECONDS + __kk_ibw_l ))
    while :; do
        __kk_ibw_e=$(( __kk_ibw_dl - EPOCHSECONDS ))
        if (( __kk_ibw_e <= 0 )); then __kk_ibw_r=142; break; fi
        IFS= read -r -t "$__kk_ibw_e" -u 3 __kk_ibw_x; __kk_ibw_r=$?
        (( __kk_ibw_r == 0 )) || break
    done
    if (( __kk_ibw_r > 128 )); then
        kill -TERM "$__kk_ibw_p" 2>/dev/null
        __kk_ibw_dl=$(( EPOCHSECONDS + 10 ))
        while (( EPOCHSECONDS < __kk_ibw_dl )); do
            IFS= read -r -t 1 -u 3 __kk_ibw_x; __kk_ibw_r=$?
            (( __kk_ibw_r == 0 || __kk_ibw_r > 128 )) || break
        done
        kill -KILL "$__kk_ibw_p" 2>/dev/null
        kk._imgbg_hold "a background writer timed out after $__kk_ibw_l s" 3000
    fi
    exec 3<&-
    wait "$__kk_ibw_p" 2>/dev/null
    return 0
}

# kk._imgbg_main MODE MARKER KBOOL PROJECT CALLER ORDER KK.IMAGE-ARG… — the
# writer process. MODE run (under setsid / timeout as found), watch (its own
# watchdog), inner (watch's writer: no marker work).
kk._imgbg_main() {
    local __kk_ibm_m=$1 __kk_ibm_kb=$3 __kk_ibm_pj=$4 __kk_ibm_cl=$5 __kk_ibm_ord=$6 __kk_ibm_key=${__KK_IMG_BGKEY-} \
          __kk_ibm_x="" __kk_ibm_n __kk_ibm_s="" __kk_ibm_q=- __kk_imbg_mt __kk_imbg_mo __kk_imbg_mp __kk_imbg_mg __kk_imbg_mq
    declare -g __KK_IMG_BGM=$2 __KK_IMG_BGT=${__KK_IMG_BGTOK-} __KK_IMG_BGSP="" __KK_IMG_BGOUT=""
    if [[ $__kk_ibm_m != inner ]]; then
        # the marker: still this start's (else another took it over: nothing to do)
        kk._imgbg_marker "$__KK_IMG_BGM" && [[ -n $__KK_IMG_BGT && $__kk_imbg_mo == "$__KK_IMG_BGT" ]] || return 0
        if [[ -r /proc/$$/stat ]]; then
            { read -r __kk_ibm_x < "/proc/$$/stat"; } 2>/dev/null || __kk_ibm_x=""
            __kk_ibm_x=${__kk_ibm_x##*) }
            __kk_ibm_q=${__kk_ibm_x#* }; __kk_ibm_q=${__kk_ibm_q#* }; __kk_ibm_q=${__kk_ibm_q%% *}
            [[ -n $__kk_ibm_q && $__kk_ibm_q != *[!0-9]* ]] || __kk_ibm_q=-
            # (a group of its own only: never the caller's — a guard that signals
            # the recorded group must not hit the caller: fix round 1 M1)
            [[ ${__KK_IMG_BGCPG-} == [0-9]* && $__kk_ibm_q != "${__KK_IMG_BGCPG-}" ]] || __kk_ibm_q=-
        fi
        { printf '%s %s %s %s %s\n' "$EPOCHSECONDS" "$__KK_IMG_BGT" "$$" "${__kk_imbg_mg:--}" "$__kk_ibm_q" 1<> "$__KK_IMG_BGM"; } 2>/dev/null || return 0
        command chmod 600 -- "$__KK_IMG_BGM" 2>/dev/null
        trap 'kk._imgbg_exit' EXIT
        trap 'kk._imgbg_term TERM' TERM
        trap 'kk._imgbg_term HUP' HUP
        trap 'kk._imgbg_term INT' INT
        if [[ $__kk_ibm_m == watch ]]; then
            kk._imgbg_watch "${@:2}"
            return 0
        fi
    else
        # (the watcher owns the marker and the hold of a stop; the pause's
        # sleep stopped: nothing outlives this writer)
        trap 'if [[ -n ${__KK_IMG_BGSP-} ]]; then kill "$__KK_IMG_BGSP" 2>/dev/null; fi; exit 143' TERM HUP INT
    fi
    unset -v __KK_IMG_BGKEY __KK_IMG_BGTOK __KK_IMG_BGCPG
    # the pause seam: the writer waits, killable (kk._imgbg_term stops the sleep)
    __kk_ibm_x=${__KK_IMG_BGPAUSE-}
    if [[ -n $__kk_ibm_x && $__kk_ibm_x != *[!0-9.]* ]]; then
        sleep "$__kk_ibm_x" &
        __KK_IMG_BGSP=$!
        wait "$__KK_IMG_BGSP"
        __KK_IMG_BGSP=""
    fi
    # the caller's settings: unexported again, IFS, shopts (before kbool.sh)
    for __kk_ibm_n in ${__KK_IMG_KUNX-}; do export -n "$__kk_ibm_n" 2>/dev/null; done
    if [[ -n ${__KK_IMG_KOPT-} ]]; then shopt -s ${__KK_IMG_KOPT} 2>/dev/null; fi
    __kk_ibm_s=${__KK_IMG_KSET-}
    if [[ -n ${__KK_IMG_KIFU-} ]]; then unset -v IFS; elif [[ -n ${__KK_IMG_KIFS+x} ]]; then IFS=$__KK_IMG_KIFS; fi
    unset -v __KK_IMG_KUNX __KK_IMG_KOPT __KK_IMG_KSET __KK_IMG_KIFS __KK_IMG_KIFU
    shift 6
    if ! source "$__kk_ibm_kb" >/dev/null; then
        kk._imgbg_hold "background writer: kbool.sh cannot be sourced ($__kk_ibm_kb)" 0; return 0
    fi
    if [[ -n $__kk_ibm_pj ]] && ! kk.project "$__kk_ibm_pj" >/dev/null; then
        kk._imgbg_hold "background writer: kk.project $__kk_ibm_pj failed" 0; return 0
    fi
    printf -v __kk_ibm_x '%s\n' "${__KK_UNIT_ORDER[@]}"
    if [[ $__kk_ibm_x != "$__kk_ibm_ord" ]]; then
        kk._image_dbg "background writer: the caller's unit table is not a fresh kbool.sh's; no image"
        kk._imgbg_hold "background writer: the caller's unit table is not a fresh kbool.sh's" 0; return 0
    fi
    if [[ " $__kk_ibm_s " == *" u "* ]]; then set -u; fi
    if [[ " $__kk_ibm_s " == *" f "* ]]; then set -f; fi
    if [[ " $__kk_ibm_s " == *" nocasematch "* ]]; then shopt -s nocasematch; fi
    kk._imgbg_run "$__kk_ibm_cl" "$__kk_ibm_key" "$@"
    set +uf; shopt -u nocasematch
    case $__KK_IMG_BGOUT in
        wrote|valid|held) ;;
        'no image written') kk._imgbg_hold "background writer: no image written" 3000 ;;
        *) kk._imgbg_hold "background writer: ${__KK_IMG_BGOUT:-kk.image did not run}" 0 ;;
    esac
    return 0
}

# kk._imgbg_run CALLER KEY KK.IMAGE-ARG… — kk.image as the caller's file
# would call it: kk.image takes CALLER from the dynamic local below (and runs
# kk._imgbg_write instead of a start); nested kk.image calls see their own.
kk._imgbg_run() {
    local __kk_imbg_w=1 __kk_imbg_caller=$1 __kk_imbg_key=$2
    shift 2
    kk.image "$@"
}

# kk._imgbg_write — kimghit.sh kk._image_run in the writer (kk.image's locals
# after the prep): the key must be the caller's; held / a valid image: done;
# else kimage.sh's writer (the load, the delta, the simulation, the refusals
# and holds). __KK_IMG_BGOUT = wrote | valid | held | the reason of no image.
# rc = the load's (0 when none ran).
kk._imgbg_write() {
    local __kk_img_key="" __kk_img_vs="" __kk_img_nonce="" __kk_img_wtime="" __kk_img_end="" __kk_img_stamp="" __kk_img_stime="" \
          __kk_hi_rc=0 __kk_ibx_rc=0 __kk_ibx_t0=$EPOCHSECONDS __kk_ibx_1="" __kk_ibx_2=""
    local -a __kk_img_files=() __kk_img_edges=() __kk_img_reqf=() __kk_img_units=() __kk_img_classes=() \
          __kk_img_fns=() __kk_img_ro=() __kk_img_base=() __kk_img_hooks=() __kk_im_pl=()
    if (( __kk_im_rc != 0 )); then
        __KK_IMG_BGOUT="not applicable in the writer: ${__kk_im_why:-?}"
        kk._image_dbg "background writer: $__KK_IMG_BGOUT"; return 0
    fi
    if [[ $__kk_im_key != "${__kk_imbg_key-}" ]]; then
        __KK_IMG_BGOUT="its key differs from the caller's"
        kk._image_dbg "background writer: $__KK_IMG_BGOUT; no image"; return 0
    fi
    if kk._image_held; then
        __KK_IMG_BGOUT=held
        kk._image_dbg "background writer: held ($__kk_im_hr)"; return 0
    fi
    kk._image_check || __kk_hi_rc=$?
    if (( __kk_hi_rc == 0 )); then
        __KK_IMG_BGOUT=valid
        kk._image_dbg "background writer: $__kk_im_img is valid already"; return 0
    fi
    if (( __kk_hi_rc == 2 )); then
        __KK_IMG_BGOUT="the image is not usable: $__kk_im_why"
        kk._image_dbg "background writer: $__KK_IMG_BGOUT"; return 0
    fi
    kk._image_dbg "background writer: $__kk_im_why: a normal load, then an image"
    if ! kk._image_lib; then __KK_IMG_BGOUT="kkore/kimage.sh cannot be loaded"; return 0; fi
    kk._img_write || __kk_ibx_rc=$?
    # written now? (its plain line's write time; the start's checks cannot
    # run here: the units are loaded in this shell)
    __KK_IMG_BGOUT="no image written"
    if [[ -f $__kk_im_img && ! -L $__kk_im_img ]]; then
        { IFS= read -r __kk_ibx_1 && IFS= read -r __kk_ibx_2; } < "$__kk_im_img" 2>/dev/null
        if kk._image_pline "$__kk_ibx_2" && [[ -n ${__kk_im_pl[0]} && ${__kk_im_pl[0]} != *[!0-9]* ]] \
           && (( 10#${__kk_im_pl[0]} >= __kk_ibx_t0 )); then
            __KK_IMG_BGOUT=wrote
        fi
    fi
    if [[ $__KK_IMG_BGOUT != wrote ]] && kk._image_held; then __KK_IMG_BGOUT=held; fi
    return "$__kk_ibx_rc"
}

# kk._img_bgwait PATH [SECONDS] — a test seam: wait until the writer of the
# image PATH (NAME.img, or its marker NAME.bg) has ended — its marker gone,
# or its pid gone — polling every 0.1 s for at most SECONDS (default 150).
# rc 0 ended; 1 still running (RESULT = its pid, or '').
kk._img_bgwait() {
    local __kk_ibq_m=${1%.img} __kk_ibq_n __kk_imbg_mt __kk_imbg_mo __kk_imbg_mp __kk_imbg_mg __kk_imbg_mq
    __kk_ibq_m=${__kk_ibq_m%.bg}.bg
    __kk_ibq_n=$(( ${2:-150} * 10 ))
    RESULT=""
    while (( __kk_ibq_n-- > 0 )); do
        [[ -e $__kk_ibq_m ]] || return 0
        kk._imgbg_marker "$__kk_ibq_m" || return 0
        if [[ -n $__kk_imbg_mp && $__kk_imbg_mp != *[!0-9]* ]] && ! kill -0 "$__kk_imbg_mp" 2>/dev/null; then return 0; fi
        sleep 0.1
    done
    RESULT=${__kk_imbg_mp-}
    [[ $RESULT != - ]] || RESULT=""
    return 1
}

# ---- run as the writer ----
if [[ ${1-} == --kbool-image-writer && ${#BASH_SOURCE[@]} -eq 1 ]]; then
    exec </dev/null
    kk._imgbg_main "${@:2}"
    exit 0
fi
