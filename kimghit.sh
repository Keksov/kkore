#!/usr/bin/env bash
# kkore/kimghit.sh — the image start of kk.image (kklass/docs/dev/IMAGE_PLAN.md
# §3, §7, §8, §9): the applicability, the prior set P of a chained image
# (§7.7: the units loaded before, keyed with their files), the folder and its
# trust, the key and the file names, the header (its plain line read without
# eval), staleness per check mode, the readonly / clash checks and the base
# check (every pre-existing slot the image changes — kkore's tables, P's
# kklass tables and registries, scalars, redefined functions — still holds
# its recorded earlier value), the source under `if`, the hooks, the holds
# and --path. Part of the unit loader like kuse.sh: no
# unit header. kk.image (kuse.sh) sources it on every image start
# (kk._image_hitlib; a `source kbool.sh` does not pay for its parse, critic
# M6); kimage.sh (the writer) needs it too (kk._image_lib sources both).
# Fork-free in `dates` mode; one stat / cksum in the other modes. Sourcing
# it again redefines the functions. It is a stamped file of every image.
#
# Every local here starts with __kk_ (kk.image's own are __kk_im_*, the
# image header's __kk_img_*), so a unit's file-scope names never meet them.

# kk._image_euid — __kk_im_euid = $EUID (a function, so a test can pretend root).
kk._image_euid() { __kk_im_euid=$EUID; }

# kk._image_run UNIT... — kk.image after its options (kuse.sh): prep, then
# --path / --forget, the hit, the hold or H2 decision, the writer or a plain
# kk.uses. rc = kk.image's.
kk._image_run() {
    kk._image_prep "$@" || __kk_im_rc=$?
    if (( __kk_im_rc == 2 )); then return 2; fi
    case $__kk_im_act in
        path) kk._image_path; return ;;
        forget)
            if (( __kk_im_rc == 0 )) && kk._image_lib; then kk._img_forget; return 0; fi
            kk._image_dbg "--forget: ${__kk_im_why:-kkore/kimage.sh cannot be loaded}; nothing deleted"
            return 0 ;;
    esac
    if (( __kk_im_rc == 0 )); then
        if [[ $__kk_im_act == rebuild ]]; then
            __kk_im_why="--rebuild"
            __kk_im_rc=1
        else
            kk._image_hit || __kk_im_rc=$?
            if (( __kk_im_rc == 0 )); then return 0; fi
            # a miss (1) or an undone start (3): a hold says "no write" (§7.5);
            # an image written less than 10 minutes ago that is stale again
            # (H2) or failed on its start (a damaged image is not undone on
            # every start) gets one instead of a rewrite
            if (( __kk_im_rc != 2 )); then
                if kk._image_held; then
                    __kk_im_why+="; held ($__kk_im_hr)"
                    __kk_im_rc=2
                elif [[ -n $__kk_im_wt && $__kk_im_wt != *[!0-9]* && ${#__kk_im_wt} -le 12 ]] \
                     && (( (__kk_im_rc == 3 || __kk_im_stale) && EPOCHSECONDS >= 10#$__kk_im_wt && EPOCHSECONDS - 10#$__kk_im_wt < 600 )); then
                    __kk_im_why+="; the image was written $(( EPOCHSECONDS - 10#$__kk_im_wt )) s ago: a hold for an hour"
                    if (( __kk_im_rc == 3 )); then
                        kk._image_hold "an image written less than 10 minutes before failed on its start" "" "" drop
                    else
                        kk._image_hold "an image written less than 10 minutes before was stale again"
                    fi
                    __kk_im_rc=2
                fi
            fi
        fi
        # (an existing folder this user cannot write in: no writer — L5)
        if (( __kk_im_rc != 2 )) && [[ -d $__kk_im_dir && ! -w $__kk_im_dir ]]; then
            __kk_im_why+="; the image folder is not writable"
            __kk_im_rc=2
        fi
        if (( __kk_im_rc != 2 )); then
            kk._image_dbg "$__kk_im_why: a normal load, then an image"
            if kk._image_lib; then
                kk._img_write
                return
            fi
            __kk_im_why="kkore/kimage.sh cannot be loaded"
        fi
    fi
    kk._image_dbg "${__kk_im_why:-not applicable}; a normal load (kk.uses ${__kk_im_args[*]})"
    kk._uses "$__kk_im_caller" "${__kk_im_args[@]}"
}

# kk._image_hash STR [VAR] -> VAR (default __kk_im_h): FNV-1a (32 bit, 8 hex
# digits) over the characters of STR (a character's code in the current
# locale; the key's string compare decides validity, the hash only names).
kk._image_hash() {
    local __kk_ih_s=$1 __kk_ih_h=2166136261 __kk_ih_i __kk_ih_c __kk_ih_n=${#1}
    for (( __kk_ih_i = 0; __kk_ih_i < __kk_ih_n; __kk_ih_i++ )); do
        printf -v __kk_ih_c %d "'${__kk_ih_s:__kk_ih_i:1}"
        __kk_ih_h=$(( ((__kk_ih_h ^ __kk_ih_c) * 16777619) & 4294967295 ))
    done
    printf -v "${2:-__kk_im_h}" %08x "$__kk_ih_h"
}

# kk._image_prep UNIT... — the flags, the applicability, the folder, the
# request and the key (§3, §7.1), after kk.image's options: fills kk.image's
# locals. rc 0 applicable; 1 not (a plain kk.uses, __kk_im_why says why).
# --forget needs only the folder and the request name; --path without units
# only the folder.
kk._image_prep() {
    local __kk_ip_v __kk_ip_d __kk_ip_a __kk_ip_f __kk_ip_nm __kk_ip_k \
          __kk_hk="" __kk_found __kk_d __kk_n
    if [[ $__kk_im_act == forget ]]; then
        kk._image_reqname
        kk._image_hash "$__kk_im_req" __kk_im_rh
        kk._image_dir
        return
    fi
    if [[ $__kk_im_act == path ]] && (( ! $# )); then
        kk._image_dir
        return
    fi
    case ${1-} in
        --*) __kk_im_why="option $1"; return 1 ;;
        '') __kk_im_why="no unit named"; return 1 ;;
    esac
    if [[ $- == *a* ]]; then __kk_im_why="set -a is on"; return 1; fi
    if kk._unit_loading __kk_ip_v; then __kk_im_why="inside the load of unit '$__kk_ip_v'"; return 1; fi
    if [[ -n ${__KK_SETTINGS_RUN-} ]] && kk._settings_hook 1; then
        __kk_im_why="inside the settings hook $__kk_hk"; return 1
    fi
    # KBOOL_IMAGE_CHECK (IMG-D1): the effective mode is keyed
    case $OSTYPE in msys*|cygwin*) __kk_ip_d=dates ;; *) __kk_ip_d=stat ;; esac
    __kk_ip_v=${KBOOL_IMAGE_CHECK-}
    case $__kk_ip_v in
        stat|dates|hash) ;;
        '') __kk_ip_v=$__kk_ip_d ;;
        *)  kk._image_dbg "KBOOL_IMAGE_CHECK=$__kk_ip_v is not stat|dates|hash; using $__kk_ip_d"
            __kk_ip_v=$__kk_ip_d ;;
    esac
    __kk_im_mode=$__kk_ip_v
    # KBOOL_IMAGE_CHAIN (IMG-D2): on (the default) — an image may sit on top
    # of the units loaded before (the prior set P, §7.7); off — only the first
    # load of a script (rev 2's rule). Another value: on, and a debug line
    __kk_ip_v=on
    case ${KBOOL_IMAGE_CHAIN-} in
        ''|on) ;;
        off) __kk_ip_v=off ;;
        *) kk._image_dbg "KBOOL_IMAGE_CHAIN=$KBOOL_IMAGE_CHAIN is not on|off; using on" ;;
    esac
    kk._image_prior || return 1
    if [[ $__kk_ip_v == off && -n $__kk_im_pn ]]; then
        __kk_im_why="KBOOL_IMAGE_CHAIN=off and unit '${__kk_im_pn%%+*}' is loaded already"; return 1
    fi
    kk._image_dir || return 1
    # an image folder that cannot be made (its deepest existing level is not
    # writable): no image can be there, no writer can make one — a plain
    # kk.uses, without sourcing the writer and its mkdir on every start (L5)
    if (( __kk_im_mk )) && ! kk._image_canmk; then return 1; fi
    # a mode without its tool runs as `dates` (§7.6): `stat` / `cksum` not on
    # PATH (kk._image_toolpath: no fork; the path is keyed), or a `stat` that takes neither -c nor -f — the
    # writer found that out and left FOLDER/stat.hold, valid for an hour
    case $__kk_im_mode in
        stat)
            if ! kk._image_toolpath stat; then
                __kk_im_from="stat is not on PATH"
            elif kk._image_hfile "$__kk_im_dir/stat.hold"; then
                __kk_im_from="stat.hold ($__kk_im_hr)"
            fi ;;
        hash)
            if ! kk._image_toolpath cksum; then __kk_im_from="cksum is not on PATH"; fi ;;
    esac
    if [[ -n $__kk_im_from ]]; then
        kk._image_dbg "KBOOL_IMAGE_CHECK=$__kk_im_mode: $__kk_im_from; using dates"
        __kk_im_mode=dates __kk_im_tool=""
    fi
    # the permission bits are checked in `stat` mode, but not on the Windows
    # runtimes, whose modes are no guard (§8.2)
    if [[ $__kk_im_mode == stat ]]; then
        case $OSTYPE in msys*|cygwin*) ;; *) __kk_im_modes=1 ;; esac
    fi
    # the request, resolved as kk._uses resolves it (U12, U43)
    case $__kk_im_caller in
        ''|main|environment)
            __kk_ip_d=$PWD
            if [[ $- == *i* ]]; then __kk_im_cdir=$PWD; fi ;;
        *)  kk._unit_caller_dir "$__kk_im_caller"
            __kk_im_cdir=$__kk_d
            __kk_ip_d=$__kk_d ;;
    esac
    for __kk_ip_a; do
        if [[ $__kk_ip_a == */* || $__kk_ip_a == *\\* || $__kk_ip_a == *.sh ]]; then
            if [[ $__kk_ip_a == /* || $__kk_ip_a == [A-Za-z]:* ]]; then __kk_ip_f=$__kk_ip_a; else __kk_ip_f=$__kk_ip_d/$__kk_ip_a; fi
            __kk_ip_nm=${__kk_ip_f##*[/\\]}
            __kk_ip_nm=${__kk_ip_nm%.sh}
            if ! kk._unit_has_header "$__kk_ip_f" "$__kk_ip_nm"; then
                __kk_im_why="'$__kk_ip_a' is not a unit file"; return 1
            fi
        else
            if [[ $__kk_ip_a == *[[:space:]*?\[]* ]]; then __kk_im_why="'$__kk_ip_a' is not a unit name"; return 1; fi
            __kk_ip_nm=$__kk_ip_a
            __kk_ip_k=$__kk_im_cdir$__KK_SEP$__kk_ip_a
            if [[ -z ${__KK_UNIT_RES[$__kk_ip_k]+x} ]]; then
                if kk._unit_find "$__kk_ip_a" "$__kk_im_cdir"; then
                    __KK_UNIT_RES[$__kk_ip_k]=$__kk_found
                else
                    __KK_UNIT_RES[$__kk_ip_k]=""
                fi
            fi
            __kk_ip_f=${__KK_UNIT_RES[$__kk_ip_k]}
            if [[ -z $__kk_ip_f ]]; then __kk_im_why="unit '$__kk_ip_a' not found"; return 1; fi
            __kk_im_reqk+=("$__kk_ip_k")
        fi
        if [[ -n ${__KK_UNITS[$__kk_ip_nm]+x} ]]; then __kk_im_why="unit '$__kk_ip_nm' is loaded already"; return 1; fi
        __kk_im_reqf+=("$__kk_ip_f")
        kk._unit_lexnorm "$__kk_ip_f"
        __kk_im_files+=$__kk_n$__KK_SEP
    done
    case $OSTYPE in
        msys*|cygwin*)      # the runtime family (I1b critic M1): MSYS_NT, MINGW64_NT, CYGWIN_NT
            __kk_im_fam=""
            { IFS=' ' read -r __kk_im_fam __kk_ip_v < /proc/version; } 2>/dev/null || :
            __kk_im_fam=${__kk_im_fam%%-*}
            __kk_im_fam=${__kk_im_fam:-?} ;;
    esac
    kk._image_key
}

# kk._image_prior — the prior set P of a chained image (§7.7, IMG-D2): the
# non-system units registered complete now, in __KK_UNIT_ORDER order ->
# __kk_im_pn (their names, `+`-joined; '' = none), __kk_im_pf (their files as
# registered: the writer's fresh process loads P by them), __kk_im_prior (the
# key rows NAME=FILE<US>…, FILE lexically normalised) and __kk_im_ph (the
# same rows for the file-name hash, shorter: NAME alone when FILE is the
# canonical KBOOL_HOME/kcl/NAME/NAME.sh, NAME/ for KBOOL_HOME/NAME/NAME.sh,
# else NAME=LENGTH:DIGEST (the path's length; each folder level's length,
# first and last character) — the key
# string decides validity, the hash only names the file, and FNV costs ~10 µs
# per character on the laptop). rc 1 (__kk_im_why: a plain kk.uses) when a
# non-system unit is not complete (loading, or tainted) or not in the order
# list, or a header-less file was loaded by path (no unit: not replayable).
kk._image_prior() {
    local __kk_ip_e __kk_ip_n __kk_ip_c=0 __kk_ip_k=0 __kk_ip_h __kk_ip_s __kk_ip_t __kk_n
    __kk_im_pn="" __kk_im_prior="" __kk_im_ph=""
    __kk_im_pf=()
    if (( ${#__KK_UNIT_FILES[@]} )); then
        __kk_im_why="a file without a unit header is loaded by path already (it cannot be part of a prior set)"; return 1
    fi
    for __kk_ip_n in "${!__KK_UNITS[@]}"; do
        [[ -n ${__KK_UNIT_SYS[$__kk_ip_n]+x} ]] || __kk_ip_c=$(( __kk_ip_c + 1 ))
    done
    (( __kk_ip_c )) || return 0
    kk._unit_lexnorm "$KBOOL_HOME"
    __kk_ip_h=$__kk_n
    for __kk_ip_e in "${__KK_UNIT_ORDER[@]}"; do
        [[ $__kk_ip_e == "u$__KK_SEP"* ]] || continue
        __kk_ip_n=${__kk_ip_e#*"$__KK_SEP"}
        if ! kk._unit_complete "$__kk_ip_n"; then
            __kk_im_why="unit '$__kk_ip_n' is not completely loaded"; return 1
        fi
        __kk_ip_k=$(( __kk_ip_k + 1 ))
        __kk_im_pf+=("${__KK_UNITS[$__kk_ip_n]}")
        kk._unit_lexnorm "${__KK_UNITS[$__kk_ip_n]}"
        __kk_im_prior+=$__kk_ip_n=$__kk_n$__KK_SEP
        __kk_im_pn+=+$__kk_ip_n
        # (the file-name hash's row: the name alone for KBOOL_HOME/kcl/N/N.sh,
        # `N/` for KBOOL_HOME/N/N.sh — two places, two rows (F7) —, else the
        # name, the path's length and a digest of its folder levels: cheap, as the
        # hash runs per character (~10 µs each) and only names the file; the
        # key's full rows decide, a collision costs a rewrite — F6)
        if [[ $__kk_n == "$__kk_ip_h/kcl/$__kk_ip_n/$__kk_ip_n.sh" ]]; then
            __kk_im_ph+=$__kk_ip_n$__KK_SEP
        elif [[ $__kk_n == "$__kk_ip_h/$__kk_ip_n/$__kk_ip_n.sh" ]]; then
            __kk_im_ph+=$__kk_ip_n/$__KK_SEP
        else
            # (each folder level's length, first and last character: two
            # checkouts of one length in other folders — aa / bb, wt1 / wt2,
            # proj-v1 / proj-v2 — get other rows; critic N4, I2b fix round 3:
            # three expansions per level, no per-character loop)
            __kk_ip_e="" __kk_ip_s=${__kk_n%/*}/
            while [[ -n $__kk_ip_s ]]; do
                __kk_ip_t=${__kk_ip_s%%/*}
                __kk_ip_s=${__kk_ip_s#*/}
                __kk_ip_e+=${#__kk_ip_t}${__kk_ip_t:0:1}${__kk_ip_t: -1}
            done
            __kk_im_ph+=$__kk_ip_n=${#__kk_n}:$__kk_ip_e$__KK_SEP
        fi
    done
    __kk_im_pn=${__kk_im_pn#+}
    if (( __kk_ip_k != __kk_ip_c )); then
        __kk_im_why="a loaded unit is not in the load order list"; return 1
    fi
    return 0
}

# kk._image_reqname — __kk_im_rn: the request (__kk_im_req, <US>-joined)
# made a file name stem: `+` between the units, every other byte outside
# [A-Za-z0-9._+-] an `_`, at most 64 characters.
kk._image_reqname() {
    local __kk_ir_v=${__kk_im_req%"$__KK_SEP"}
    __kk_ir_v=${__kk_ir_v//"$__KK_SEP"/+}
    __kk_ir_v=${__kk_ir_v//[!A-Za-z0-9._+-]/_}
    __kk_im_rn=${__kk_ir_v:0:64}
}

# kk._image_key — the key (§7.1, every row but the stamps; the EFFECTIVE check
# mode) -> __kk_im_key, and the file names __kk_im_name / _img / _ref. The
# writer calls it again when its `stat` turns out unusable (-> dates).
kk._image_key() {
    local __kk_ik_po="extglob:0 expand_aliases:0" __kk_ik_a __kk_ik_b __kk_n
    if [[ :$BASHOPTS: == *:extglob:* ]]; then __kk_ik_po=${__kk_ik_po/extglob:0/extglob:1}; fi
    if [[ :$BASHOPTS: == *:expand_aliases:* ]]; then __kk_ik_po=${__kk_ik_po/aliases:0/aliases:1}; fi
    kk._unit_lexnorm "$KBOOL_HOME"
    printf -v __kk_ik_a '%s\n' "kbool image v1" "home=$__kk_n" "bash=$BASH" "version=$BASH_VERSION" \
        "ostype=$OSTYPE" "machtype=$MACHTYPE" "euid=$__kk_im_euid" "family=$__kk_im_fam" \
        "parse=$__kk_ik_po compat:${BASH_COMPAT-}" "check=$__kk_im_mode" "tool=$__kk_im_tool" "kbool=${KBOOL_VERSION-}" \
        "request=$__kk_im_req" "files=$__kk_im_files"
    printf -v __kk_ik_b '%s\n' \
        "unitpath=${__KK_CFG[unitpath]-}" "defines=${__KK_CFG[defines]-}" "debug=${__KK_CFG[debug]-}" \
        "ckkdir=${__KK_CFG[ckkdir]-}" "project=${__KK_PROJECT-}" "verbose=${VERBOSE_KKLASS+=}${VERBOSE_KKLASS-}"
    # the prior set (§7.7): its full rows in the key, the shorter form in the
    # file-name hash (kk._image_prior)
    __kk_im_key=$__kk_ik_a"prior=$__kk_im_prior"$'\n'$__kk_ik_b
    kk._image_hash "$__kk_ik_a"prior="$__kk_im_ph"$'\n'"$__kk_ik_b"
    kk._image_reqname
    __kk_im_name=$__kk_im_rn-$__kk_im_h
    __kk_im_img=$__kk_im_dir/$__kk_im_name.img
    __kk_im_ref=""                     # (NAME.NONCE.ref: the image names its nonce)
    kk._image_hash "$__kk_im_req" __kk_im_rh   # (the request alone: --forget)
    return 0
}

# kk._image_dir — the image folder (§7.3, IMG-D4) -> __kk_im_dir, and its
# trust (§8.1): every existing level from the base root down must be a folder
# owned by this user (-O) and not a symbolic link; the first missing level
# sets __kk_im_mk (the writer makes it under umask 077), the first failing one
# __kk_im_bad (the reason). __kk_im_ml = the levels whose permission bits
# `stat` mode checks (KBOOL_IMAGE_DIR itself; else from kbool/ down). rc 1
# (__kk_im_why) when there is no folder: no base variable, or EUID 0 without
# KBOOL_IMAGE_DIR. Fork-free.
kk._image_dir() {
    local __kk_id_r="" __kk_id_l
    kk._image_euid
    if [[ -n ${KBOOL_IMAGE_DIR-} ]]; then
        __kk_im_dir=${KBOOL_IMAGE_DIR//\\//}
        # (absolute only: a relative one would follow the caller's cd — L8)
        if [[ $__kk_im_dir != /* && $__kk_im_dir != [A-Za-z]:/* ]]; then
            __kk_im_why="KBOOL_IMAGE_DIR=$KBOOL_IMAGE_DIR is not an absolute path"; return 1
        fi
        [[ $__kk_im_dir == / ]] || __kk_im_dir=${__kk_im_dir%/}
        __kk_id_l=$__kk_im_dir
        __kk_im_ml=$__kk_im_dir
    elif [[ $__kk_im_euid == 0 ]]; then
        __kk_im_why="EUID 0: images are read and written only under KBOOL_IMAGE_DIR"; return 1
    else
        case $OSTYPE in
            msys*|cygwin*)
                if [[ -n ${LOCALAPPDATA-} ]]; then
                    __kk_id_r=$LOCALAPPDATA
                elif [[ -n ${USERPROFILE-} ]]; then
                    __kk_id_r=$USERPROFILE/AppData/Local
                elif [[ -n ${HOME-} ]]; then
                    __kk_id_r=$HOME/.cache
                    case ${HOME//\\//} in
                        /cygdrive/*|/[A-Za-z]/*|[A-Za-z]:/*)
                            kk._image_dbg "LOCALAPPDATA and USERPROFILE are not set: images go to $__kk_id_r/kbool/image/v1" ;;
                        *)  kk._image_dbg "LOCALAPPDATA and USERPROFILE are not set: images go to $__kk_id_r/kbool/image/v1, inside the runtime's install folder (other local users may be able to write there: on a shared machine set KBOOL_IMAGE_DIR or KBOOL_IMAGE=off)" ;;
                    esac
                fi ;;
            *)  if [[ ${XDG_CACHE_HOME-} == /* ]]; then
                    __kk_id_r=$XDG_CACHE_HOME
                elif [[ -n ${HOME-} ]]; then
                    __kk_id_r=$HOME/.cache
                fi ;;
        esac
        if [[ -z $__kk_id_r ]]; then __kk_im_why="no folder for images (HOME is not set)"; return 1; fi
        __kk_id_r=${__kk_id_r//\\//}
        __kk_id_r=${__kk_id_r%/}
        __kk_im_dir=$__kk_id_r/kbool/image/v1
        __kk_im_ml=$__kk_id_r/kbool$__KK_SEP$__kk_id_r/kbool/image$__KK_SEP$__kk_im_dir
        __kk_id_l=$__kk_id_r$__KK_SEP$__kk_im_ml
    fi
    __kk_im_lv=$__kk_id_l
    kk._image_levels
}

# kk._image_levels — the trust walk of kk._image_dir over __kk_im_lv (the
# folders from the base root down, <US>-separated): __kk_im_mk / __kk_im_bad.
# The writer walks again after making the folder.
kk._image_levels() {
    local __kk_id_l=$__kk_im_lv __kk_id_p
    __kk_im_mk=0 __kk_im_bad=""
    while [[ -n $__kk_id_l ]]; do
        __kk_id_p=${__kk_id_l%%"$__KK_SEP"*}
        if [[ $__kk_id_l == *"$__KK_SEP"* ]]; then __kk_id_l=${__kk_id_l#*"$__KK_SEP"}; else __kk_id_l=""; fi
        if [[ -L $__kk_id_p ]]; then
            __kk_im_bad="the folder $__kk_id_p is a symbolic link"; return 0
        elif [[ ! -e $__kk_id_p ]]; then
            __kk_im_mk=1; return 0
        elif [[ ! -d $__kk_id_p ]]; then
            __kk_im_bad="$__kk_id_p is not a folder"; return 0
        elif [[ ! -O $__kk_id_p ]]; then
            __kk_im_bad="the folder $__kk_id_p is owned by another user"; return 0
        fi
    done
    return 0
}

# kk._image_toolpath NAME — __kk_im_tool = the file `command NAME` runs (the
# hash table's entry, else the first executable NAME on PATH), fork-free; rc
# 1 when there is none. Keyed (critic N3): another stat / cksum — brew's
# GNU stat in one shell, the BSD one in another — is another image, not a
# "stat failed" stale image and a hold.
kk._image_toolpath() {
    local __kk_it_p=${PATH-} __kk_it_d
    __kk_im_tool=""
    if [[ -n ${BASH_CMDS[$1]+x} ]]; then __kk_im_tool=${BASH_CMDS[$1]}; return 0; fi
    while [[ -n $__kk_it_p ]]; do
        __kk_it_d=${__kk_it_p%%:*}
        if [[ $__kk_it_p == *:* ]]; then __kk_it_p=${__kk_it_p#*:}; else __kk_it_p=""; fi
        [[ -n $__kk_it_d ]] || __kk_it_d=.
        if [[ -f $__kk_it_d/$1 && -x $__kk_it_d/$1 ]]; then __kk_im_tool=$__kk_it_d/$1; return 0; fi
    done
    return 1
}

# kk._image_canmk — rc 0 when the missing levels of __kk_im_lv can be made:
# the deepest existing level is a writable folder (-w, fork-free); else rc 1
# and __kk_im_why.
kk._image_canmk() {
    local __kk_ic_l=$__kk_im_lv __kk_ic_p __kk_ic_e=""
    while [[ -n $__kk_ic_l ]]; do
        __kk_ic_p=${__kk_ic_l%%"$__KK_SEP"*}
        if [[ $__kk_ic_l == *"$__KK_SEP"* ]]; then __kk_ic_l=${__kk_ic_l#*"$__KK_SEP"}; else __kk_ic_l=""; fi
        [[ -e $__kk_ic_p ]] || break
        __kk_ic_e=$__kk_ic_p
    done
    if [[ -z $__kk_ic_e ]]; then        # no level exists: its parent folder
        __kk_ic_e=${__kk_im_lv%%"$__KK_SEP"*}
        __kk_ic_e=${__kk_ic_e%/*}
        [[ -n $__kk_ic_e ]] || __kk_ic_e=/
        while [[ ! -e $__kk_ic_e && $__kk_ic_e == */* ]]; do __kk_ic_e=${__kk_ic_e%/*}; [[ -n $__kk_ic_e ]] || __kk_ic_e=/; done
    fi
    if [[ -d $__kk_ic_e && -w $__kk_ic_e ]]; then return 0; fi
    __kk_im_why="the image folder $__kk_im_dir cannot be made ($__kk_ic_e is not a writable folder)"
    return 1
}

# kk._image_warn REASON — the one WARNING of a process (IMG-D3): an existing
# image file fails a trust check.
kk._image_warn() {
    if [[ -z ${__KK_IMG_WARNED-} ]]; then
        __KK_IMG_WARNED=1
        kk._unit_warn "image $__kk_im_img is not trusted ($1); loading normally"
    fi
    return 0
}

# kk._image_hfile FILE — rc 0 when FILE is a hold (§7.5): a regular file of
# this user, not a symbolic link, whose first line `TIME REASON` was written
# less than an hour ago (by this clock); __kk_im_hr = "REASON, N s ago".
kk._image_hfile() {
    local __kk_ih_t="" __kk_ih_r=""
    [[ -f $1 && ! -L $1 && -O $1 ]] || return 1
    { IFS=' ' read -r __kk_ih_t __kk_ih_r < "$1"; } 2>/dev/null || [[ -n $__kk_ih_t ]] || return 1
    [[ -n $__kk_ih_t && $__kk_ih_t != *[!0-9]* && ${#__kk_ih_t} -le 12 ]] || return 1
    (( EPOCHSECONDS >= 10#$__kk_ih_t && EPOCHSECONDS - 10#$__kk_ih_t < 3600 )) || return 1
    __kk_im_hr="$__kk_ih_r, $(( EPOCHSECONDS - 10#$__kk_ih_t )) s ago"
    return 0
}

# kk._image_held — rc 0 when this image name has a hold younger than an hour
# (one -f on the miss path); __kk_im_hr says which.
kk._image_held() {
    kk._image_hfile "$__kk_im_dir/$__kk_im_name.hold"
}

# kk._image_hold REASON [UMASK [FILE [drop [TIME]]]] — write FILE (default
# NAME.hold) as `TIME REASON` (TIME default EPOCHSECONDS; the writer dates a
# near miss of kk._img__worth 50 minutes back) under umask 077: with UMASK (the
# caller's, known to the writer) fork-free, else in a subshell, which with
# `drop` also removes the image and its .ref (a damaged image that failed on
# its start is not sourced and undone again on every start of the hour).
# Nothing in an untrusted or missing folder, or over a symbolic link. Silent.
kk._image_hold() {
    local __kk_ih_f=${3:-$__kk_im_dir/$__kk_im_name.hold} __kk_ih_r=${1//$'\n'/ } __kk_ih_t=${5:-$EPOCHSECONDS}
    [[ -z $__kk_im_bad && -d $__kk_im_dir && ! -L $__kk_ih_f ]] || return 0
    # (never fatal under the caller's set -e: a hold that cannot be written —
    # a folder in its place, a full disk — is no reason to end the script;
    # critic M2)
    if [[ -n ${2-} ]]; then
        umask 077
        { printf '%s %s\n' "$__kk_ih_t" "$__kk_ih_r" > "$__kk_ih_f"; } 2>/dev/null || :
        umask "$2"
    else
        ( set +e; umask 077; printf '%s %s\n' "$__kk_ih_t" "$__kk_ih_r" > "$__kk_ih_f"
          if [[ ${4-} == drop ]]; then command rm -f -- "$__kk_im_img" "$__kk_im_ref"; fi ) 2>/dev/null || :
    fi
    return 0
}

# kk._image_pline LINE — the plain header line `#P<US>WTIME<US>SIZE<US>TAG<US>
# HOME<US>PRIOR<US>MODE<US>FLAVOUR<US>NONCE<US>RHASH<US>N<US>FILE…` (read
# WITHOUT eval: the `stat` mode check runs before any byte of the image does;
# pruning and --forget read only this) -> the caller's __kk_img_files (the N
# stamped files) and __kk_im_pl (the 10 fields before them, an array). NONCE
# names the image's reference file (NAME.NONCE.ref, dates mode); RHASH = the
# FNV-1a of the request (--forget). rc 1 when it is not such a line.
kk._image_pline() {
    local - IFS=$__KK_SEP
    local -a __kk_ip_a=()
    set -f
    [[ $1 == "#P$__KK_SEP"* ]] || return 1
    __kk_ip_a=(${1#"#P$__KK_SEP"})
    (( ${#__kk_ip_a[@]} >= 10 )) || return 1
    [[ -n ${__kk_ip_a[9]} && ${__kk_ip_a[9]} != *[!0-9]* && ${#__kk_ip_a[9]} -le 6 \
       && -n ${__kk_ip_a[0]} && ${__kk_ip_a[0]} != *[!0-9]* && ${#__kk_ip_a[0]} -le 12 \
       && ${__kk_ip_a[7]} != *[!0-9a-f]* ]] || return 1
    (( ${#__kk_ip_a[@]} == 10#${__kk_ip_a[9]} + 10 )) || return 1
    __kk_im_pl=("${__kk_ip_a[@]:0:10}")
    __kk_img_files=("${__kk_ip_a[@]:10}")
    return 0
}

# kk._image_stamp FLAVOUR FILE... -> __kk_im_so: the stamps of `stat` mode,
# `SIZE MTIME CTIME INODE UID MODE` per FILE — FLAVOUR gnu9: stat -c '%s
# %.9Y %.9Z %i %u %a' (nanosecond times, GNU coreutils >= 8.32); gnu: the same
# with whole seconds; bsd9: stat -f '%z %Fm %Fc %i %u %Mp%Lp'; bsd: '%z %m %c %i
# %u %Mp%Lp' (%Mp: the suid / sgid / sticky digit, which %Lp leaves out) — or of `hash` mode (FLAVOUR hash: cksum), one line per FILE — ONE
# fork (the command substitution runs the command itself). rc 1 when the
# command fails, the line count is not the file count, or (stat) a line is
# not six fields with the times in the flavour's form (a stat that ignores a
# format it does not know is not taken for that flavour). The tool runs under
# LC_ALL=C (a prefix assignment: no fork more): GNU stat prints %.9Y with the
# locale's decimal point — `1764134503,123456789` under ru_RU.UTF-8 —, which
# made every start under another locale than the writer's "stale" (I3 fix 1,
# CI 45760665404).
kk._image_stamp() {
    local - __kk_is_f=$1 IFS=$'\n' __kk_is_l __kk_is_t
    local -a __kk_is_a=() __kk_is_w=()
    shift
    case $__kk_is_f in
        gnu9) __kk_im_so=$(LC_ALL=C command stat -c '%s %.9Y %.9Z %i %u %a' -- "$@" 2>/dev/null) || return 1 ;;
        gnu)  __kk_im_so=$(LC_ALL=C command stat -c '%s %Y %Z %i %u %a' -- "$@" 2>/dev/null) || return 1 ;;
        bsd9) __kk_im_so=$(LC_ALL=C command stat -f '%z %Fm %Fc %i %u %Mp%Lp' -- "$@" 2>/dev/null) || return 1 ;;
        bsd)  __kk_im_so=$(LC_ALL=C command stat -f '%z %m %c %i %u %Mp%Lp' -- "$@" 2>/dev/null) || return 1 ;;
        hash) __kk_im_so=$(LC_ALL=C command cksum -- "$@" 2>/dev/null) || return 1 ;;
        *)    return 1 ;;
    esac
    set -f
    __kk_is_a=($__kk_im_so)
    (( ${#__kk_is_a[@]} == $# )) || return 1
    [[ $__kk_is_f != hash ]] || return 0
    # (the Windows runtimes make the mode up — from the stat process's umask
    # among others —: it is no stamp there, `-` instead; nor is it checked)
    local __kk_is_w9=0 __kk_is_o=""
    case $OSTYPE in msys*|cygwin*) __kk_is_w9=1 ;; esac
    for __kk_is_l in "${__kk_is_a[@]}"; do
        if (( __kk_is_w9 )); then __kk_is_o+=${__kk_is_l% *}' -'$'\n'; fi
        IFS=' '
        __kk_is_w=($__kk_is_l)
        IFS=$'\n'
        (( ${#__kk_is_w[@]} == 6 )) || return 1
        for __kk_is_t in "${__kk_is_w[1]}" "${__kk_is_w[2]}"; do
            if [[ $__kk_is_f == *9 ]]; then
                [[ $__kk_is_t == [0-9]*.[0-9]* && $__kk_is_t != *[!0-9.]* && $__kk_is_t != *.*.* ]] || return 1
            else
                [[ -n $__kk_is_t && $__kk_is_t != *[!0-9]* ]] || return 1
            fi
        done
    done
    if (( __kk_is_w9 )); then __kk_im_so=${__kk_is_o%$'\n'}; fi
    return 0
}

# kk._image_lines TEXT ARRAY — the caller's ARRAY = TEXT's lines (not empty).
kk._image_lines() {
    local - IFS=$'\n'
    local -n __kk_il_r=$2
    set -f
    __kk_il_r=($1)
}

# kk._image_wbits LINE... — the permission bits (the last field of a stamp
# line) of __kk_im_ml's levels, then (when given) the image (critic M4): rc 1
# and __kk_im_why when a FOLDER is world-writable without the sticky bit (a
# group-writable folder is accepted: the image and its .ref must be this
# user's and no symbolic link, -O / ! -L; a sticky 1777 folder keeps others
# from renaming or removing them), or the IMAGE is group- or world-writable.
kk._image_wbits() {
    local __kk_iw_l __kk_iw_m __kk_iw_p=$__kk_im_ml$__KK_SEP$__kk_im_img$__KK_SEP __kk_iw_n __kk_iw_k=0 __kk_iw_f
    __kk_iw_f=${__kk_im_ml//[!"$__KK_SEP"]/}
    __kk_iw_f=$(( ${#__kk_iw_f} + 1 ))                  # the folder levels
    for __kk_iw_l; do
        __kk_iw_m=${__kk_iw_l##* }
        __kk_iw_n=${__kk_iw_p%%"$__KK_SEP"*}
        __kk_iw_p=${__kk_iw_p#*"$__KK_SEP"}
        __kk_iw_k=$(( __kk_iw_k + 1 ))
        if [[ -z $__kk_iw_m || $__kk_iw_m == *[!0-7]* ]]; then
            __kk_im_why="$__kk_iw_n has no readable mode (${__kk_iw_m:-?})"; return 1
        elif (( __kk_iw_k <= __kk_iw_f )); then
            if (( (8#$__kk_iw_m & 8#002) && ! (8#$__kk_iw_m & 8#1000) )); then
                __kk_im_why="$__kk_iw_n is world-writable without the sticky bit (mode $__kk_iw_m)"; return 1
            fi
        elif (( 8#$__kk_iw_m & 8#022 )); then
            __kk_im_why="$__kk_iw_n is group- or world-writable (mode $__kk_iw_m)"; return 1
        fi
    done
    return 0
}

# kk._image_hit — the start through the image (§9): rc 0 done (the units are
# loaded); 1 a miss (no image, another key, stale: write one); 2 not usable
# here (untrusted, a readonly collision, the base differs: a plain kk.uses,
# no write); 3 the image failed while sourced or a hook failed: undone (rc 3:
# kk.image loads normally and rewrites, or holds). Fork-free in `dates` mode;
# one fork (stat / cksum) in the others.
kk._image_hit() {
    local __kk_img_key="" __kk_img_nonce="" __kk_img_wtime="" __kk_img_end="" __kk_img_stamp="" __kk_img_stime="" __kk_img_i="" __kk_hi_e \
          __kk_hi_rc=0
    local -a __kk_img_files=() __kk_img_edges=() __kk_img_reqf=() __kk_img_units=() __kk_img_classes=() \
          __kk_img_vars=() __kk_img_fns=() __kk_img_ro=() __kk_img_base=() __kk_img_hooks=() __kk_im_pl=() __kk_img_k=() __kk_img_v=()
    kk._image_check || return
    kk._image__apply || __kk_hi_rc=1
    if (( __kk_hi_rc )); then
        kk._image_dbg "$__kk_im_why; undone"
        if kk._image_lib; then kk._img_undo; fi
        return 3
    fi
    # what kk.uses leaves for this caller: its fast-path entries for the request
    if [[ $__kk_im_caller == /* ]]; then
        for __kk_hi_e in "${__kk_im_reqk[@]}"; do
            __KK_UNIT_HIT[$__kk_im_caller$__KK_SEP${__kk_hi_e#*"$__KK_SEP"}]=${__KK_UNITS[${__kk_hi_e#*"$__KK_SEP"}]-}
        done
    fi
    kk._image_dbg "loaded from $__kk_im_img"
    return 0
}

# kk._image__apply — source the checked image (its header evaluated, in the
# caller's __kk_img_*) under `if`, check its end mark, run the settings hooks
# of its units in __KK_UNIT_SETTINGS order (§5.2). rc 1 (__kk_im_why) when the
# image did not load completely or a hook failed: the caller undoes it. The
# image start and the writer's fresh-process simulation of a chained image
# (kimage.sh kk._img_kid) both apply an image through it.
kk._image__apply() {
    local __kk_ia_e __kk_ia_ok=0
    # (debug: its stderr as it is — `2>/dev/stderr` would open the caller's
    # stderr file again, truncating what the start printed into it before)
    if [[ ${VERBOSE_KKLASS:-} == debug ]]; then
        source "$__kk_im_img" && __kk_ia_ok=1
    else
        source "$__kk_im_img" 2>/dev/null && __kk_ia_ok=1
    fi
    if (( __kk_ia_ok )) && [[ $__kk_img_end == "$__kk_img_nonce" ]]; then
        for __kk_ia_e in "${__kk_img_hooks[@]}"; do
            [[ ${__kk_ia_e#*"$__KK_SEP"} != : ]] || continue
            if ! kk._image_hook "${__kk_ia_e%%"$__KK_SEP"*}" "${__kk_ia_e#*"$__KK_SEP"}"; then
                __kk_im_why="the settings hook ${__kk_ia_e#*"$__KK_SEP"} of unit '${__kk_ia_e%%"$__KK_SEP"*}' failed"
                return 1
            fi
        done
        return 0
    fi
    __kk_im_why="the image $__kk_im_img did not load completely"
    return 1
}

# kk._image_path — kk.image --path: print the image path this start would
# use (without units: the folder) on stdout. rc 0 the image is valid (the
# folder: usable); 1 none, stale, not applicable, refused or held (nothing
# printed when there is no path); fork-free in `dates` mode.
kk._image_path() {
    local __kk_img_key="" __kk_img_nonce="" __kk_img_wtime="" __kk_img_end="" __kk_img_stamp="" __kk_img_stime="" __kk_hi_rc=0
    local -a __kk_img_files=() __kk_img_edges=() __kk_img_reqf=() __kk_img_units=() __kk_img_classes=() \
          __kk_img_vars=() __kk_img_fns=() __kk_img_ro=() __kk_img_base=() __kk_img_hooks=() __kk_im_pl=()
    if (( __kk_im_rc != 0 )); then
        kk._image_dbg "--path: ${__kk_im_why:-not applicable}"
        return 1
    fi
    if [[ -z $__kk_im_req ]]; then
        printf '%s\n' "$__kk_im_dir"
        if [[ -n $__kk_im_bad ]]; then kk._image_dbg "--path: untrusted folder: $__kk_im_bad"; return 1; fi
        return 0
    fi
    printf '%s\n' "$__kk_im_img"
    kk._image_check || __kk_hi_rc=$?
    if (( __kk_hi_rc == 0 )); then return 0; fi
    if (( __kk_hi_rc == 1 )) && kk._image_held; then __kk_im_why+="; held ($__kk_im_hr)"; fi
    kk._image_dbg "--path: $__kk_im_why"
    return 1
}

# kk._image_check — kk._image_hit's checks before a byte is sourced (rc as
# kk._image_hit's 0 / 1 / 2): trust, the header (read; its plain line parsed;
# in `stat` mode the one stat, whose permission bits of the folder and the
# image are checked before the header runs; then its lines run), the key, the
# request files (-ef), the dependency edges (header form, §7.2), staleness
# per mode (§7.6), the readonly pre-check and the base check (§8.3, §7.7).
# Stale reasons set __kk_im_stale; __kk_im_wt = the image's write time. Its
# own options: nounset and nocasematch off.
kk._image_check() {
    local - __kk_hc_1 __kk_hc_2="" __kk_hc_x __kk_hc_d __kk_hc_n __kk_hc_f __kk_hc_k \
          __kk_hc_i __kk_hc_nc=0 __kk_hc_rc=0 __kk_hc_st="" __kk_found
    local -a __kk_hc_a=() __kk_hc_b=()
    set +u
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_hc_nc=1; shopt -u nocasematch; fi
    kk._image__check || __kk_hc_rc=$?
    if (( __kk_hc_nc )); then shopt -s nocasematch; fi
    return "$__kk_hc_rc"
}
kk._image__check() {
    if [[ -n $__kk_im_bad ]]; then
        if [[ -e $__kk_im_img || -L $__kk_im_img ]]; then kk._image_warn "$__kk_im_bad"; fi
        __kk_im_why="untrusted folder: $__kk_im_bad"; return 2
    fi
    if [[ -L $__kk_im_img ]]; then
        kk._image_warn "a symbolic link"; __kk_im_why="the image is a symbolic link"; return 2
    elif [[ ! -e $__kk_im_img ]]; then
        __kk_im_why="no image $__kk_im_img yet"; return 1
    elif [[ ! -f $__kk_im_img ]]; then
        kk._image_warn "not a regular file"; __kk_im_why="the image is not a regular file"; return 2
    elif [[ ! -O $__kk_im_img ]]; then
        kk._image_warn "owned by another user"; __kk_im_why="the image is owned by another user"; return 2
    fi
    kk._image__hdr || return 1
    if [[ ${__kk_im_pl[5]} != "$__kk_im_mode" ]]; then __kk_im_why="the image has another key (check mode ${__kk_im_pl[5]})"; return 1; fi
    for __kk_hc_f in "${__kk_img_files[@]}"; do
        if [[ ! -f $__kk_hc_f ]]; then
            __kk_im_why="stale: $__kk_hc_f is missing"; __kk_im_stale=1
            __kk_im_wt=${__kk_im_pl[0]}
            return 1
        fi
    done
    # `stat` mode where the permission bits count: ONE stat over the folder
    # levels, the image and the stamped files, its bits checked before the
    # header runs (§8.1)
    if (( __kk_im_modes )); then
        kk._image__levels __kk_hc_a
        __kk_hc_n=$(( ${#__kk_hc_a[@]} + 1 ))        # the levels + the image
        if ! kk._image_stamp "${__kk_im_pl[6]}" "${__kk_hc_a[@]}" "$__kk_im_img" "${__kk_img_files[@]}"; then
            __kk_im_why="stale: stat (${__kk_im_pl[6]}) failed over the stamped files"; __kk_im_stale=1
            __kk_im_wt=${__kk_im_pl[0]}
            return 1
        fi
        kk._image_lines "$__kk_im_so" __kk_hc_b
        if ! kk._image_wbits "${__kk_hc_b[@]:0:__kk_hc_n}"; then
            kk._image_warn "$__kk_im_why"; return 2
        fi
        printf -v __kk_hc_st '%s\n' "${__kk_hc_b[@]:__kk_hc_n}"
        __kk_hc_st=${__kk_hc_st%$'\n'}
    fi
    { eval "$__kk_hc_2"; } 2>/dev/null || { __kk_im_why="the image header is damaged"; return 1; }
    if [[ $__kk_img_key != "$__kk_im_key" ]]; then __kk_im_why="the image has another key"; return 1; fi
    if [[ -z $__kk_img_nonce || $__kk_img_nonce == *[!0-9a-f]* ]]; then __kk_im_why="the image header is damaged"; return 1; fi
    __kk_im_wt=$__kk_img_wtime
    if (( ${#__kk_img_reqf[@]} != ${#__kk_im_reqf[@]} )); then __kk_im_why="the image has another request"; return 1; fi
    for (( __kk_hc_i = 0; __kk_hc_i < ${#__kk_im_reqf[@]}; __kk_hc_i++ )); do
        if [[ ! ${__kk_img_reqf[__kk_hc_i]} -ef ${__kk_im_reqf[__kk_hc_i]} ]]; then
            __kk_im_why="stale: the request resolves to another file than the image's"; __kk_im_stale=1; return 1
        fi
    done
    # dependency edges DIR<US>NAME<US>FILE: what `kk.uses NAME` from DIR found;
    # FILE empty = found nothing (a failed `kk.uses --optional NAME`, critic
    # M3): still no DIR/NAME.sh and no headered candidate in the index
    for __kk_hc_x in "${__kk_img_edges[@]}"; do
        __kk_hc_d=${__kk_hc_x%%"$__KK_SEP"*}
        __kk_hc_x=${__kk_hc_x#*"$__KK_SEP"}
        __kk_hc_n=${__kk_hc_x%%"$__KK_SEP"*}
        __kk_hc_f=${__kk_hc_x#*"$__KK_SEP"}
        if [[ -z $__kk_hc_f ]]; then
            if (( ! __KK_UNIT_IDX_OK )); then kk._unit_index_build; fi
            # (the index: a headered candidate, or any candidate file NAME.sh
            # in the search path — then the lookup decides as kk.uses would:
            # a header-less NAME.sh resolves to nothing, critic N1)
            if [[ ( -z $__kk_hc_d || ! -e $__kk_hc_d/$__kk_hc_n.sh ) && -z ${__KK_UNIT_IDX[$__kk_hc_n]-} \
                  && -z ${__KK_UNIT_CAND[$__kk_hc_n]-} ]]; then continue; fi
            if ! kk._unit_find "$__kk_hc_n" "$__kk_hc_d"; then continue; fi
            __kk_im_why="stale: the dependency '$__kk_hc_n' (used from ${__kk_hc_d:-a prompt}), not found when the image was made, is found now"
            __kk_im_stale=1; return 1
        fi
        if [[ -n $__kk_hc_d && -e $__kk_hc_d/$__kk_hc_n.sh ]]; then
            [[ $__kk_hc_d/$__kk_hc_n.sh != "$__kk_hc_f" ]] || continue
        else
            if (( ! __KK_UNIT_IDX_OK )); then kk._unit_index_build; fi
            if [[ -n ${__KK_UNIT_IDX[$__kk_hc_n]+x} ]]; then
                __kk_hc_k=${__KK_UNIT_IDX[$__kk_hc_n]}
            else
                __kk_hc_k=${__KK_UNIT_CAND[$__kk_hc_n]-}
                __kk_hc_k=${__kk_hc_k%%$'\n'*}
            fi
            [[ $__kk_hc_k != "$__kk_hc_f" ]] || continue
        fi
        if kk._unit_find "$__kk_hc_n" "$__kk_hc_d" && [[ $__kk_found == "$__kk_hc_f" || $__kk_found -ef $__kk_hc_f ]]; then
            continue
        fi
        __kk_im_why="stale: the dependency '$__kk_hc_n' (used from $__kk_hc_d) resolves to another file now"; __kk_im_stale=1; return 1
    done
    # staleness per mode (§7.6)
    case $__kk_im_mode in
        dates)  # NAME.NONCE.ref was made before the image's load (named after
            # the image's nonce: two writers at once each rename their own,
            # the image that wins finds its reference — critic L3); this
            # user's and no symbolic link, like the image (L8)
            __kk_im_ref=$__kk_im_dir/$__kk_im_name.$__kk_img_nonce.ref
            if [[ -L $__kk_im_ref || ( -e $__kk_im_ref && ( ! -f $__kk_im_ref || ! -O $__kk_im_ref ) ) ]]; then
                kk._image_warn "its reference file is a symbolic link, not a file or another user's"
                __kk_im_why="the reference file $__kk_im_ref is not trusted"; return 2
            fi
            if [[ ! -f $__kk_im_ref ]]; then __kk_im_why="no reference file $__kk_im_ref"; return 1; fi
            __kk_hc_x=""
            { IFS= read -r __kk_hc_x < "$__kk_im_ref"; } 2>/dev/null || :
            if [[ $__kk_hc_x != "$__kk_img_nonce" ]]; then __kk_im_why="the reference file belongs to another image"; return 1; fi
            for __kk_hc_f in "${__kk_img_files[@]}"; do
                if [[ ! $__kk_hc_f -ot $__kk_im_ref ]]; then
                    __kk_im_why="stale: $__kk_hc_f changed after the image was made"; __kk_im_stale=1; return 1
                fi
            done ;;
        stat|hash)
            if (( ! __kk_im_modes )); then
                __kk_hc_k=${__kk_im_pl[6]}
                [[ $__kk_im_mode == stat ]] || __kk_hc_k=hash
                if ! kk._image_stamp "$__kk_hc_k" "${__kk_img_files[@]}"; then
                    __kk_im_why="stale: $__kk_hc_k failed over the stamped files"; __kk_im_stale=1; return 1
                fi
                __kk_hc_st=$__kk_im_so
            fi
            if [[ $__kk_hc_st != "$__kk_img_stamp" ]]; then
                kk._image_lines "$__kk_hc_st" __kk_hc_a
                kk._image_lines "$__kk_img_stamp" __kk_hc_b
                for (( __kk_hc_i = 0; __kk_hc_i < ${#__kk_img_files[@]}; __kk_hc_i++ )); do
                    [[ ${__kk_hc_a[__kk_hc_i]-} == "${__kk_hc_b[__kk_hc_i]-}" ]] || break
                done
                __kk_im_why="stale: ${__kk_img_files[__kk_hc_i]-a stamped file} changed after the image was made ($__kk_im_mode)"
                __kk_im_stale=1
                return 1
            fi
            # "racy" (stat with whole-second times only: the gnu / bsd
            # flavours; gnu9 / bsd9 stamp nanoseconds): a file whose MTIME is
            # the second the stamps were taken in (or later) may have changed
            # after them within that second — a miss, written again with a
            # later stamp second, not "stale" (no hold). Like git's racy
            # index entries, on the mtime: files dated back (touch -t, an
            # archive) are no racy case; an mtime-keeping change inside that
            # one second is not seen (documented)
            # (a nanosecond flavour whose fractions are ALL zero — FAT/exFAT,
            # HFS+, ext3, some NFS/SMB mounts keep whole seconds — is whole
            # seconds too: critic N2)
            __kk_hc_k=0
            if [[ ${__kk_im_pl[6]} == gnu || ${__kk_im_pl[6]} == bsd ]]; then __kk_hc_k=1
            elif [[ ${__kk_im_pl[6]} == *9 && $__kk_hc_st == *.* ]]; then
                __kk_hc_x=${__kk_hc_st//.000000000 / }
                [[ $__kk_hc_x == *.* ]] || __kk_hc_k=1
            fi
            if [[ $__kk_im_mode == stat && $__kk_hc_k == 1 ]]; then
                kk._image_lines "$__kk_hc_st" __kk_hc_a
                for (( __kk_hc_i = 0; __kk_hc_i < ${#__kk_hc_a[@]}; __kk_hc_i++ )); do
                    __kk_hc_x=${__kk_hc_a[__kk_hc_i]#* }
                    __kk_hc_x=${__kk_hc_x%% *}
                    __kk_hc_x=${__kk_hc_x%%.*}            # (a zero fraction: the whole seconds)
                    if [[ -z $__kk_hc_x || $__kk_hc_x == *[!0-9]* || -z $__kk_img_stime || $__kk_img_stime == *[!0-9]* ]] \
                       || (( 10#$__kk_hc_x >= 10#$__kk_img_stime )); then
                        __kk_im_why="${__kk_img_files[__kk_hc_i]-a stamped file} changed in the second its stamp was taken (racy)"
                        return 1
                    fi
                done
            fi ;;
    esac
    kk._image__fits
}

# kk._image__hdr — read the header of __kk_im_img (no eval): __kk_hc_2 = its
# lines after line 1 (`# kbool image v1 N`, N = their byte length, read at
# once as bytes: LC_ALL=C for that read — the plain line's paths may be
# UTF-8; a line-by-line read is slow on the MSYS-family runtimes; a read -N
# that succeeds read all N), its plain line parsed (kk._image_pline:
# __kk_im_pl, __kk_img_files). rc 1 (__kk_im_why) when it is no such header.
# The caller's locals __kk_hc_1 / __kk_hc_2.
kk._image__hdr() {
    { IFS= read -r __kk_hc_1 && [[ $__kk_hc_1 == "# kbool image v1 "[1-9]* && ${__kk_hc_1#"# kbool image v1 "} != *[!0-9]* \
                                   && ${#__kk_hc_1} -le 30 ]] \
      && LC_ALL=C IFS= read -r -N "${__kk_hc_1#"# kbool image v1 "}" __kk_hc_2; } < "$__kk_im_img" 2>/dev/null \
      || { __kk_im_why="not an image of format v1, or its header is incomplete"; return 1; }
    if [[ $__kk_hc_2 != *$'\n' ]]; then
        __kk_im_why="the image header is incomplete"; return 1
    fi
    if ! kk._image_pline "${__kk_hc_2%%$'\n'*}"; then __kk_im_why="the image header is damaged"; return 1; fi
    return 0
}

# kk._image__fits — does the image fit this shell (its header evaluated):
# rc 0; 1 (a miss) when its base list is damaged or its NAME.fnc is gone; 2
# (__kk_im_why: a plain kk.uses, no write) when a name it creates exists
# already (the clash check) or a slot of its base list differs (the base
# check, §7.7). Its options as kk._image_check sets them (nounset,
# nocasematch off); the writer's fresh-process simulation runs it too.
# Fork-free.
kk._image__fits() {
    local __kk_hc_x __kk_hc_n __kk_hc_k __kk_hc_t="" __kk_hc_m="" __kk_hc_f __kk_hc_q="" __kk_hc_e=0 __kk_hc_s
    local -a __kk_hc_l=()
    # a name the image creates that exists here already, in the caller's view
    # (critic H1): readonly (§8.3), a caller's local of any kind, a global
    # array of the other kind, a nameref, a preset — the image would write
    # into it (or die on `X[key]` of an indexed one inside the source), and
    # the undo would unset it. A plain kk.uses decides instead. `${!X@a}`
    # sees `local -a X=()` / a global `declare -a X=()`, `${!N@a}` with
    # N=NAME[@] an array with no element yet (`local -a X`), `+x` a set
    # scalar, -R a nameref. Limit (documented): a bare `local NAME` (neither
    # a value nor an attribute) is not seen — only one `declare -p` per name
    # would tell, measured ~25 ms per start for fv.dlg's 1335 array names —
    # and when NAME is an image ARRAY name, its element lines can then end
    # the caller's script (an arithmetic error inside the source).
    for __kk_hc_x in "${__kk_img_vars[@]}"; do
        __kk_hc_n="$__kk_hc_x[@]"
        if [[ -n ${!__kk_hc_x@a} || -n ${!__kk_hc_n@a} || -n ${!__kk_hc_x+x} || -R $__kk_hc_x ]]; then
            __kk_im_why="'$__kk_hc_x' exists in this shell already (${!__kk_hc_n@a}): the image would write into it"; return 2
        fi
    done
    # the base (§7.7): every pre-existing slot the image changes holds the
    # value it had when the image was made (the delta was made against it),
    # and every pre-existing variable of P's the load READ (a word of this
    # call's unit files) is as it was — KIND<US>NAME<US>KEY<US>FLAG<US>VALUE,
    # FLAG `-` = absent, `=` = VALUE:
    #   e  the element NAME[KEY] of an array: its kind read from the attributes
    #      BEFORE a key is used (an associative key on a variable that is not
    #      associative is arithmetic: R14); an indexed array takes digits only;
    #      the element read through an eval of the table's own name with the
    #      key in a variable — no nameref (a precaution of fix round 1, whose
    #      guess that bash 5.1 re-reads `ref[KEY]` as text was disproved: the
    #      5.1 death was the image's own removal loop, kimage.sh
    #      kk._img__vdelta, fix round 2), no `${!X}` indirection (a key text
    #      `$(`, `]`, `@` is re-read there on every bash);
    #   s  the scalar NAME;
    #   f  the function NAME, VALUE its earlier `declare -f` text
    #      (kk._image__fntext);
    #   r  a read of P's variable NAME (I2b fix round): KEY s = a scalar (`-`
    #      unset, `=` its value), a = an indexed array (VALUE `COUNT:LAST`, the
    #      element count and the last index: an append writes LAST+1), A = an
    #      associative array (VALUE its element count).
    # (Unchained: kkore's registration slots only; chained also P's kklass
    # tables and registries, scalars, redefined functions, reads.)
    # (per entry the fewest operations — ~35 µs on the laptop each otherwise:
    # the kind is the first byte, a table's name is checked once per table)
    for __kk_hc_x in "${__kk_img_base[@]}"; do
        __kk_hc_f=${__kk_hc_x:0:1}
        __kk_hc_x=${__kk_hc_x:2}
        __kk_hc_n=${__kk_hc_x%%"$__KK_SEP"*}
        __kk_hc_x=${__kk_hc_x#*"$__KK_SEP"}
        __kk_hc_k=${__kk_hc_x%%"$__KK_SEP"*}
        __kk_hc_x=${__kk_hc_x#*"$__KK_SEP"}
        case $__kk_hc_f in
            e)  if [[ $__kk_hc_n != "$__kk_hc_t" ]]; then
                    if [[ -z $__kk_hc_n || $__kk_hc_n == *[!A-Za-z0-9_]* || $__kk_hc_n == [0-9]* ]]; then
                        __kk_im_why="the image base list is damaged"; return 1
                    fi
                    __kk_hc_t=$__kk_hc_n
                    __kk_hc_m="$__kk_hc_n[@]"
                    __kk_hc_m=${!__kk_hc_m@a}
                    case $__kk_hc_m in
                        *A*) __kk_hc_m=A ;;
                        *a*) __kk_hc_m=a ;;
                        *)   if [[ -z ${!__kk_hc_n+x} ]]; then __kk_hc_m=-; else __kk_hc_m=x; fi ;;
                    esac
                fi
                case $__kk_hc_m in
                    A)  ;;
                    a)  if [[ -z $__kk_hc_k || $__kk_hc_k == *[!0-9]* || ${#__kk_hc_k} -gt 18 ]]; then
                            __kk_im_why="$__kk_hc_n[$__kk_hc_k] differs from the image's base"; return 2
                        fi ;;
                    -)  [[ $__kk_hc_x != -* ]] || continue
                        __kk_im_why="$__kk_hc_n[$__kk_hc_k] differs from the image's base"; return 2 ;;
                    *)  __kk_im_why="$__kk_hc_n[$__kk_hc_k] differs from the image's base"; return 2 ;;
                esac
                case $__kk_hc_x in
                    -*) eval "[[ -z \${$__kk_hc_t[\$__kk_hc_k]+x} ]]" && continue ;;
                    =*) eval "[[ -n \${$__kk_hc_t[\$__kk_hc_k]+x} && \${$__kk_hc_t[\$__kk_hc_k]} == \"\${__kk_hc_x:2}\" ]]" && continue ;;
                    *)  __kk_im_why="the image base list is damaged"; return 1 ;;
                esac
                __kk_hc_n+="[$__kk_hc_k]" ;;
            s)  if [[ -z $__kk_hc_n || $__kk_hc_n == *[!A-Za-z0-9_]* || $__kk_hc_n == [0-9]* ]]; then
                    __kk_im_why="the image base list is damaged"; return 1
                fi
                case $__kk_hc_x in
                    -*) [[ -z ${!__kk_hc_n+x} ]] && continue ;;
                    =*) [[ -n ${!__kk_hc_n+x} && ${!__kk_hc_n} == "${__kk_hc_x:2}" ]] && continue ;;
                    *)  __kk_im_why="the image base list is damaged"; return 1 ;;
                esac ;;
            r)  if [[ -z $__kk_hc_n || $__kk_hc_n == *[!A-Za-z0-9_]* || $__kk_hc_n == [0-9]* ]]; then
                    __kk_im_why="the image base list is damaged"; return 1
                fi
                __kk_hc_m="$__kk_hc_n[@]"
                __kk_hc_m=${!__kk_hc_m@a}
                case $__kk_hc_k$__kk_hc_x in
                    s-*) [[ $__kk_hc_m != *[aA]* && -z ${!__kk_hc_n+x} ]] && continue ;;
                    s=*) [[ $__kk_hc_m != *[aA]* && -n ${!__kk_hc_n+x} && ${!__kk_hc_n} == "${__kk_hc_x:2}" ]] && continue ;;
                    a=*) if [[ $__kk_hc_m == *a* ]]; then
                             eval "__kk_hc_l=(\"\${!$__kk_hc_n[@]}\")"
                             __kk_hc_s=0:
                             (( ! ${#__kk_hc_l[@]} )) || __kk_hc_s=${#__kk_hc_l[@]}:${__kk_hc_l[-1]}
                             [[ $__kk_hc_s == "${__kk_hc_x:2}" ]] && continue
                         fi ;;
                    A=*) if [[ $__kk_hc_m == *A* ]]; then
                             eval "__kk_hc_s=\${#$__kk_hc_n[@]}"
                             [[ $__kk_hc_s == "${__kk_hc_x:2}" ]] && continue
                         fi ;;
                    *)   __kk_im_why="the image base list is damaged"; return 1 ;;
                esac
                __kk_im_why="$__kk_hc_n, which this call's load reads, differs from when the image was made"; return 2 ;;
            f)  if [[ -z $__kk_hc_n || $__kk_hc_n == *[!A-Za-z0-9_.:-]* || $__kk_hc_x != =* ]]; then
                    __kk_im_why="the image base list is damaged"; return 1
                fi
                if declare -F -- "$__kk_hc_n" >/dev/null; then
                    __kk_hc_e=0
                    kk._image__fntext "$__kk_hc_n" || __kk_hc_e=$?
                    case $__kk_hc_e in
                        0)  [[ $__kk_hc_q != "${__kk_hc_x:2}" ]] || continue ;;
                        2)  __kk_im_why="no $__kk_im_name.fnc (the function text check of this image)"; return 1 ;;
                        3)  __kk_im_why="$__kk_im_dir/$__kk_im_name.fnc is not a regular file of this user (a symbolic link, a folder, another user's): the function text check cannot run"; return 2 ;;
                        *)  __kk_im_why="cannot write or read $__kk_im_dir/$__kk_im_name.fnc (the function text check of this image)"; return 2 ;;
                    esac
                fi
                __kk_hc_n+="()" ;;
            *)  __kk_im_why="the image base list is damaged"; return 1 ;;
        esac
        __kk_im_why="$__kk_hc_n differs from the image's base"; return 2
    done
    return 0
}

# kk._image__fntext NAME -> __kk_hc_q: the `declare -f NAME` text (trailing
# newlines cut), fork-free: on bash >= 5.3 its `${ …; }` substitution runs in
# this shell; older ones print it into the image folder's NAME.fnc (this
# image's own: the writer makes it, under umask 077, with every image that
# redefines a function; a start writes over it, keeping its mode, and does
# not remove it — pruning and --forget take it with its image) and read it
# back. rc 2 when NAME.fnc is missing (a miss: the writer makes it again); 3
# when it exists but is not a regular file of this user's (a symbolic link —
# refused, not followed —, a folder, another user's: a plain kk.uses); 4
# when it cannot be written or read (a read-only folder: a plain kk.uses);
# 1 an empty text. Only images that redefine an earlier function (chained:
# a unit of this call redefining one of P's) run it. (__KK_IMG_FNFILE
# non-empty: the NAME.fnc path on bash >= 5.3 too — a test seam, kkore 028.)
kk._image__fntext() {
    local __kk_it_f=$__kk_im_dir/$__kk_im_name.fnc __kk_it_z=""
    __kk_hc_q=""
    if (( BASH_VERSINFO[0] > 5 || ( BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3 ) )) && [[ -z ${__KK_IMG_FNFILE-} ]]; then
        eval '__kk_hc_q=${ declare -f -- "$1"; }'
        [[ -n $__kk_hc_q ]]
        return
    fi
    if [[ -L $__kk_it_f ]]; then return 3; fi
    [[ -e $__kk_it_f ]] || return 2
    [[ -f $__kk_it_f && -O $__kk_it_f ]] || return 3
    { declare -f -- "$1" > "$__kk_it_f"; } 2>/dev/null || return 4
    { IFS= read -r -d '' __kk_it_z < "$__kk_it_f"; } 2>/dev/null
    while [[ $__kk_it_z == *$'\n' ]]; do __kk_it_z=${__kk_it_z%$'\n'}; done
    __kk_hc_q=$__kk_it_z
    [[ -n $__kk_hc_q ]]
}

# kk._image__levels ARRAY — the caller's ARRAY = __kk_im_ml's levels.
kk._image__levels() {
    local -n __kk_iv_r=$1
    local __kk_iv_l=$__kk_im_ml
    __kk_iv_r=()
    while [[ -n $__kk_iv_l ]]; do
        __kk_iv_r+=("${__kk_iv_l%%"$__KK_SEP"*}")
        if [[ $__kk_iv_l == *"$__KK_SEP"* ]]; then __kk_iv_l=${__kk_iv_l#*"$__KK_SEP"}; else __kk_iv_l=""; fi
    done
}

