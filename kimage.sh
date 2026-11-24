#!/usr/bin/env bash
# kkore/kimage.sh — the load-image writer, the undo of a failed image start,
# and THE STATE DUMP (kklass/docs/dev/IMAGE_PLAN.md §5.2, §6, §8.3; stage
# I2a-1: unchained, `dates`). Part of the unit loader like kuse.sh: no unit
# header. kk.image (kuse.sh) sources it only on a miss or a failed start
# (kk._image_lib); a test harness (kcl/tests/image_sim.sh) sources it for the
# dump, the compare and the hook replay. Sourcing it again redefines the
# functions. It is a stamped file of every image (§7.1).
#
# Every local here starts with __kk_im (kk.image's own are __kk_im_*), so the
# dump, which lists the variables visible to it, skips them all.
#
# The writer (kk._img_write, the miss path of §6.2):
#   1. before the load: the image folder (made under umask 077 the first time;
#      its trust checked again), the shell state (traps, aliases, umask,
#      options, function attributes), the reference file NAME.ref.tmp.* with
#      a fresh nonce (made NOW: a file edited during the load is newer than
#      it, so the next start finds the image stale), every variable's
#      `declare -p` record (through a temp file, never a pipe — IMAGE_PLAN
#      M12), the function names and texts, kkore's registration tables;
#   2. kk._uses CALLER UNIT... in the caller's options — its rc is kk.image's;
#   3. the delta: this call's units (registered complete now, not before),
#      their new functions and the variables the load created, the kkore
#      registration entries it added (each with the slot's earlier value or
#      `-` for absent: the base list, checked by every start and put back by
#      the undo), the hooks, the dependency edges, the stamped files. NO IMAGE
#      (a debug line says why) when the load failed; changed the shell state;
#      exported a variable or a function outside the hooks' VARs; changed,
#      removed or redefined an existing variable / function outside the hooks
#      (kkore's registration tables excepted: those are the base list —
#      chained deltas on other slots are I2b); changed another kkore table; left
#      a unit incomplete; or a stamped file is newer than the reference file;
#      or a function text holds a CR byte this parser drops and kklass's
#      kk._fn_text_cr cannot rewrite (IMG-D7);
#   4. the simulated image start (§5.2, no prior set): in a subshell every
#      hook VAR is put back to its state before the load, every hook runs in
#      __KK_UNIT_SETTINGS order (marked, kk._image_hook; their output is
#      discarded — I1b critic L5), and the full state must equal the
#      end-of-load state (pid-valued hook VARs compare in pairs);
#   5. the image text (format v1, §6.1, under LC_ALL=C) written by ONE printf
#      into NAME.img.tmp.PID.RANDOM (umask 077, noclobber), rc checked; `mv -f`
#      the image, then the reference file. A failed write or rename is silent.
# Never held: kbool.sh's state, hook VARs, __kk_ft, exports, the name index and
# the caller-keyed tables (__KK_UNIT_CAND / _IDX / _IDX_OK / _RES / _HIT,
# __KK_FILE_PWD), __KK_UNIT_PID (pid state: nothing reads it for a loaded unit,
# so an image start leaves it absent), __KK_SETTINGS_RUN, the shell-owned and
# scratch names of __KK_IMG_SKIP, the hash table and alias table variables.
#
# The format v1 (order matters for the undo):
#   # kbool image v1
#   __kk_img_key=… __kk_img_nonce=…                 the key (kuse.sh kk._image_prep), the nonce
#   __kk_img_files=(…) __kk_img_edges=(…) __kk_img_reqf=(…)   stamped files; DIR<US>NAME<US>FILE; the request files
#   __kk_img_units=(…) __kk_img_classes=(…) __kk_img_vars=(…) __kk_img_fns=(…) __kk_img_ro=(…) __kk_img_wtime=…
#   __kk_img_base=(…)                                KIND<US>NAME<US>KEY<US>FLAG<US>VALUE
#   <functions>                                      declare -f, CR-rewritten
#   <variables>                                      declare -g…; arrays X=() then X[k]=v
#   <final block>                                    kklass tables, then the readonly flags
#   <kkore registration>                             the base list's new values: LAST
#   __kk_img_hooks=(UNIT<US>FN …)
#   __kk_img_end=<the nonce>
#
# I2a-2 adds here: `stat` / `hash` stamps, holds, pruning, --rebuild /
# --forget / --path, the full refusal list (hash table, jobs, fds, `declare -ft`,
# the bash < 5.2 `&> "$` rule, failed --optional units), the rewrite after an
# undo, pruning temps of dead pids (a load that fails under `set -e` exits the
# script before the cleanup); I2b the chained deltas on non-kkore slots.

declare -g __KK_IMG_SKIP=" _ __kk_ft BASHPID BASH_MONOSECONDS BASH_TRAPSIG BASH_ARGC BASH_ARGV BASH_ARGV0 BASH_COMMAND BASH_LINENO BASH_REMATCH BASH_SOURCE BASH_SUBSHELL EPOCHREALTIME EPOCHSECONDS FUNCNAME HISTCMD LINENO PIPESTATUS RANDOM SECONDS SRANDOM COLUMNS LINES RESULT "
# the writer's kkore classes: held as element deltas (the base list) / never held
declare -ga __KK_IMG_REGA=(__KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_CLASSES __KK_UNIT_FILES
    __KK_UNIT_ORDER __KK_UNIT_SETTINGS __KK_SETTINGS_VARS __KK_NAMESPACES)
declare -g __KK_IMG_REG=" __KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_CLASSES __KK_UNIT_FILES __KK_UNIT_ORDER __KK_UNIT_SETTINGS __KK_SETTINGS_VARS __KK_NAMESPACES "
declare -g __KK_IMG_NEVER=" DIRSTACK GROUPS OLDPWD __KK_UNIT_CAND __KK_UNIT_IDX __KK_UNIT_IDX_OK __KK_UNIT_RES __KK_UNIT_HIT __KK_FILE_PWD __KK_UNIT_PID __KK_SETTINGS_RUN __kk_unit_rc BASH_CMDS BASH_ALIASES "
declare -ga __KK_IMG_XV __KK_IMG_XF __KK_IMG_CMPV __KK_IMG_CMPF
declare -gA __KK_IMG_RT=()

# ---------------------------------------------------------------------------
# The state dump (moved here from kcl/tests/image_sim.sh, image I2a-1)

# kk._img_state FILE [canon] — THE STATE DUMP, fork-free, under LC_ALL=C (the
# quoting `declare -p` picks depends on the locale), into FILE (and the
# scratch files FILE.pre, FILE.raw). Sections:
#   @@V every variable with its attributes (`declare -p` of the names
#       `compgen -v` lists); the caller's IFS and LC_ALL first (taken before
#       this function's locals shadow them). With `canon`, every associative
#       array is one `declare -A… NAME` line plus one `NAME[KEY]=VALUE` line
#       per element (%q), so that two processes that built one table in
#       another order compare equal (kk._img_cmp … set);
#   @@F every function (`declare -f`);
#   @@X the function attributes (`declare -Fx`, `declare -Ft`);
#   @@S the shell state: `trap -p`, `alias -p`, `umask`.
# Not dumped: the names of __KK_IMG_SKIP (bash's dynamic variables, RESULT,
# __kk_ft — never image state), every name starting with __kk_im (the image
# code's locals and header), __KK_IMG_* (its flags), and the globs of the
# arrays __KK_IMG_XV (variables) / __KK_IMG_XF (functions) a harness sets for
# its own names. The caller's shell options do not matter.
kk._img_state() {
    declare -p IFS LC_ALL > "$1.pre" 2>/dev/null || :    # (LC_ALL unset: rc 1, also under a caller's set -e)
    local - __kk_ims_nc=0
    set +eu
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_ims_nc=1; shopt -u nocasematch; fi
    # (in a function of its own: the locale its `local LC_ALL` leaves may
    # warn on stderr at its return)
    kk._img__dump "$1" "${2-}" 2>/dev/null
    if (( __kk_ims_nc )); then shopt -s nocasematch; fi
    return 0
}
kk._img__dump() {
    local LC_ALL=C IFS=$'\n' __kk_imd_f=$1 __kk_imd_c=$2 __kk_imd_z="" __kk_imd_x __kk_imd_p
    local -a __kk_imd_v=() __kk_imd_n=() __kk_imd_fn=() __kk_imd_an=()
    set -f
    compgen -v > "$__kk_imd_f.raw"
    read -r -N 268435456 __kk_imd_z < "$__kk_imd_f.raw" || :
    __kk_imd_v=($__kk_imd_z)
    for __kk_imd_x in "${__kk_imd_v[@]}"; do
        [[ $__KK_IMG_SKIP == *" $__kk_imd_x "* || $__kk_imd_x == __kk_im* || $__kk_imd_x == __KK_IMG_* \
           || $__kk_imd_x == IFS || $__kk_imd_x == LC_ALL ]] && continue
        for __kk_imd_p in "${__KK_IMG_XV[@]}"; do
            [[ $__kk_imd_x == $__kk_imd_p ]] && continue 2
        done
        if [[ -n $__kk_imd_c && ! -R $__kk_imd_x && ${!__kk_imd_x@a} == *A* ]]; then
            __kk_imd_an+=("$__kk_imd_x")
        else
            __kk_imd_n+=("$__kk_imd_x")
        fi
    done
    compgen -A function > "$__kk_imd_f.raw"
    __kk_imd_z=""
    read -r -N 268435456 __kk_imd_z < "$__kk_imd_f.raw" || :
    __kk_imd_v=($__kk_imd_z)
    for __kk_imd_x in "${__kk_imd_v[@]}"; do
        for __kk_imd_p in "${__KK_IMG_XF[@]}"; do
            [[ $__kk_imd_x == $__kk_imd_p ]] && continue 2
        done
        __kk_imd_fn+=("$__kk_imd_x")
    done
    __kk_imd_z=""
    read -r -N 268435456 __kk_imd_z < "$__kk_imd_f.pre" || :
    {
        printf '@@V\n%s' "$__kk_imd_z"
        if (( ${#__kk_imd_n[@]} )); then declare -p "${__kk_imd_n[@]}"; fi
        for __kk_imd_x in "${__kk_imd_an[@]}"; do
            eval '__kk_imd_p=${#'"$__kk_imd_x"'[@]}'
            if (( __kk_imd_p == 0 )); then declare -p "$__kk_imd_x"; continue; fi
            printf 'declare -%s %s\n' "${!__kk_imd_x@a}" "$__kk_imd_x"
            eval 'for __kk_imd_p in "${!'"$__kk_imd_x"'[@]}"; do printf "%s[%q]=%q\n" "$__kk_imd_x" "$__kk_imd_p" "${'"$__kk_imd_x"'[$__kk_imd_p]}"; done'
        done
        printf '@@F\n'
        if (( ${#__kk_imd_fn[@]} )); then declare -f "${__kk_imd_fn[@]}"; fi
        printf '@@X\n'
        declare -Fx
        declare -Ft
        printf '@@S\n'
        trap -p
        alias -p
        umask
    } > "$__kk_imd_f"
}

# kk._img_cmp A B [set] — rc 0 when the dumps A and B are equal; else rc 1 and
# __KK_IMG_DIFF = "KIND:NAME before=TEXT after=TEXT" of the first differing
# record (A's order, then B's records A lacks; KIND V F X S; newlines as |, cut
# to 300 chars); with __KK_IMG_ALL non-empty " KIND:NAME" of every differing
# record instead (no texts). Without `set` the equal case costs two reads (the
# records are parsed only to explain a difference). With `set` the records are
# compared as a set (canon dumps of two processes), minus the records of the
# variables whose name matches a glob of __KK_IMG_CMPV and of the functions
# matching __KK_IMG_CMPF (a test's allow-list).
kk._img_cmp() {
    local - __kk_imc_nc=0 __kk_imc_a="" __kk_imc_b="" __kk_imc_r=0
    set +eu -f
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_imc_nc=1; shopt -u nocasematch; fi
    __KK_IMG_DIFF=""
    if [[ ${3-} == set ]]; then
        kk._img__explain "$1" "$2" set || __kk_imc_r=1
    else
        read -r -N 268435456 __kk_imc_a < "$1" || :
        read -r -N 268435456 __kk_imc_b < "$2" || :
        if [[ $__kk_imc_a != "$__kk_imc_b" ]]; then kk._img__explain "$1" "$2"; __kk_imc_r=1; fi
    fi
    if (( __kk_imc_nc )); then shopt -s nocasematch; fi
    return "$__kk_imc_r"
}

# kk._img__records FILE [set] — __KK_IMG_RK (record keys, in order) and
# __KK_IMG_RT[KEY] (record text) of a dump; with `set` without the records of
# the allow-listed names. Keys: V:NAME (a declare line and the lines of a
# multi-line value after it), V:NAME[… (an element line of a canon dump, the
# whole line), F:NAME, X:LINE, S:LINE.
kk._img__records() {
    local __kk_imr_x __kk_imr_k="" __kk_imr_t="" __kk_imr_s="" __kk_imr_n __kk_imr_z="" __kk_imr_p __kk_imr_d=0 IFS=$'\n'
    local -a __kk_imr_l=()
    __KK_IMG_RK=() __KK_IMG_RT=()
    read -r -N 268435456 __kk_imr_z < "$1" || :
    __kk_imr_l=($__kk_imr_z)
    for __kk_imr_x in "${__kk_imr_l[@]}"; do
        if [[ $__kk_imr_x == @@[VFXS] ]]; then
            if [[ -n $__kk_imr_k ]] && (( ! __kk_imr_d )); then __KK_IMG_RT[$__kk_imr_k]=$__kk_imr_t; fi
            __kk_imr_s=${__kk_imr_x:2:1} __kk_imr_k="" __kk_imr_t="" __kk_imr_d=0
            continue
        fi
        __kk_imr_n=""
        case $__kk_imr_s in
            V)  if [[ $__kk_imr_x == 'declare -'* ]]; then
                    __kk_imr_n=${__kk_imr_x#declare -* }
                    __kk_imr_n=V:${__kk_imr_n%%=*}
                elif [[ $__kk_imr_x == [A-Za-z_]*\[* && ${__kk_imr_x%%\[*} != *[!A-Za-z0-9_]* ]]; then
                    __kk_imr_n=V:$__kk_imr_x
                fi ;;
            F)  if [[ $__kk_imr_x == *' () ' && $__kk_imr_x != [[:space:]]* ]]; then __kk_imr_n=F:${__kk_imr_x% () }; fi ;;
            *)  __kk_imr_n=$__kk_imr_s:$__kk_imr_x ;;
        esac
        if [[ -n $__kk_imr_n ]]; then
            if [[ -n $__kk_imr_k ]] && (( ! __kk_imr_d )); then __KK_IMG_RT[$__kk_imr_k]=$__kk_imr_t; fi
            __kk_imr_k=$__kk_imr_n __kk_imr_t="" __kk_imr_d=0
            if [[ ${2-} == set ]]; then
                __kk_imr_p=${__kk_imr_k#?:}
                if [[ $__kk_imr_k == V:* ]]; then
                    __kk_imr_p=${__kk_imr_p%%\[*}
                    for __kk_imr_z in "${__KK_IMG_CMPV[@]}"; do [[ $__kk_imr_p == $__kk_imr_z ]] && __kk_imr_d=1; done
                elif [[ $__kk_imr_k == F:* ]]; then
                    for __kk_imr_z in "${__KK_IMG_CMPF[@]}"; do [[ $__kk_imr_p == $__kk_imr_z ]] && __kk_imr_d=1; done
                fi
            fi
            if (( ! __kk_imr_d )); then __KK_IMG_RK+=("$__kk_imr_k"); fi
        fi
        __kk_imr_t+=$__kk_imr_x$'\n'
    done
    if [[ -n $__kk_imr_k ]] && (( ! __kk_imr_d )); then __KK_IMG_RT[$__kk_imr_k]=$__kk_imr_t; fi
}

# kk._img__explain A B [set] — __KK_IMG_DIFF (see kk._img_cmp); rc 1 when a
# record differs.
kk._img__explain() {
    local __kk_ime_i __kk_ime_a __kk_ime_b __kk_ime_cr __kk_ime_q
    local -a __kk_ime_ord=()
    local -A __kk_ime_ra=() __kk_ime_rb=() __kk_ime_in=()
    printf -v __kk_ime_cr '\r'
    __kk_ime_q="''$__kk_ime_cr''"
    kk._img__records "$1" "${3-}"
    __kk_ime_ord=("${__KK_IMG_RK[@]}")
    for __kk_ime_i in "${__KK_IMG_RK[@]}"; do __kk_ime_ra[$__kk_ime_i]=${__KK_IMG_RT[$__kk_ime_i]}; __kk_ime_in[$__kk_ime_i]=1; done
    kk._img__records "$2" "${3-}"
    for __kk_ime_i in "${__KK_IMG_RK[@]}"; do
        __kk_ime_rb[$__kk_ime_i]=${__KK_IMG_RT[$__kk_ime_i]}
        [[ -n ${__kk_ime_in[$__kk_ime_i]-} ]] || __kk_ime_ord+=("$__kk_ime_i")
    done
    # __KK_IMG_CMPCR (set mode): a function text kk._fn_text_cr rewrote prints
    # a CR as ''<CR>'' (the same word) after its round trip — compared as <CR>
    if [[ ${3-} == set && -n ${__KK_IMG_CMPCR-} ]]; then
        for __kk_ime_i in "${!__kk_ime_ra[@]}"; do
            [[ $__kk_ime_i == F:* ]] || continue
            while [[ ${__kk_ime_ra[$__kk_ime_i]} == *"$__kk_ime_q"* ]]; do
                __kk_ime_ra[$__kk_ime_i]=${__kk_ime_ra[$__kk_ime_i]//"$__kk_ime_q"/$__kk_ime_cr}
            done
        done
        for __kk_ime_i in "${!__kk_ime_rb[@]}"; do
            [[ $__kk_ime_i == F:* ]] || continue
            while [[ ${__kk_ime_rb[$__kk_ime_i]} == *"$__kk_ime_q"* ]]; do
                __kk_ime_rb[$__kk_ime_i]=${__kk_ime_rb[$__kk_ime_i]//"$__kk_ime_q"/$__kk_ime_cr}
            done
        done
    fi
    for __kk_ime_i in "${__kk_ime_ord[@]}"; do
        if [[ ${__kk_ime_ra[$__kk_ime_i]-<none>} != "${__kk_ime_rb[$__kk_ime_i]-<none>}" ]]; then
            if [[ -n ${__KK_IMG_ALL-} ]]; then __KK_IMG_DIFF+=" $__kk_ime_i"; continue; fi
            __kk_ime_a=${__kk_ime_ra[$__kk_ime_i]-<none>} __kk_ime_b=${__kk_ime_rb[$__kk_ime_i]-<none>}
            __kk_ime_a=${__kk_ime_a//$'\n'/|} __kk_ime_b=${__kk_ime_b//$'\n'/|}
            __KK_IMG_DIFF="$__kk_ime_i before=${__kk_ime_a:0:300} after=${__kk_ime_b:0:300}"
            return 1
        fi
    done
    if [[ -n $__KK_IMG_DIFF ]]; then return 1; fi
    if [[ ${3-} == set ]]; then return 0; fi
    __KK_IMG_DIFF="(empty lines or record order only)"
    return 1
}

# kk._img_pre FILE ASSOC — `declare -p` of every variable into FILE, and the
# caller's associative array ASSOC[NAME] = NAME's record (a value's further
# lines appended; empty lines dropped). The state before a load.
kk._img_pre() {
    declare -p > "$1"
    kk._img__parse "$1" "$2"
}
# kk._img__parse FILE ASSOC — kk._img_pre's parse of a `declare -p` text. (A
# full `declare -p` prints bash's dynamic variables — COMP_WORDBREAKS,
# DIRSTACK… — without a value until they are read once: compare a name's
# records only between dumps made the same way.)
kk._img__parse() {
    local -n __kk_imp_o=$2
    local - __kk_imp_l __kk_imp_n="" __kk_imp_z="" IFS=$'\n'
    local -a __kk_imp_a=()
    set -f
    read -r -N 268435456 __kk_imp_z < "$1" || :
    __kk_imp_a=($__kk_imp_z)
    for __kk_imp_l in "${__kk_imp_a[@]}"; do
        if [[ $__kk_imp_l == 'declare -'* ]]; then
            __kk_imp_n=${__kk_imp_l#declare -* }
            __kk_imp_n=${__kk_imp_n%%=*}
            __kk_imp_o[$__kk_imp_n]=$__kk_imp_l
        elif [[ -n $__kk_imp_n ]]; then
            __kk_imp_o[$__kk_imp_n]+=$'\n'$__kk_imp_l
        fi
    done
}

# kk._img_reset PRE VAR... — put each VAR back to its state in the associative
# array PRE (kk._img_pre): unset (a nameref by unset -n), then its record
# declared again (-g, its attributes) when it had one. A readonly VAR cannot
# be put back: it is left alone, listed in __KK_IMG_RO, and the rc is 1.
kk._img_reset() {
    local -n __kk_imt_p=$1
    shift
    local - __kk_imt_v __kk_imt_at __kk_imt_l __kk_imt_fl __kk_imt_rc=0
    set +u
    __KK_IMG_RO=""
    for __kk_imt_v; do
        __kk_imt_at=""
        if declare -p "$__kk_imt_v" >/dev/null 2>&1; then __kk_imt_at=${!__kk_imt_v@a}; fi
        if [[ ! -R $__kk_imt_v && $__kk_imt_at == *r* ]]; then __KK_IMG_RO+="$__kk_imt_v "; __kk_imt_rc=1; continue; fi
        if [[ -R $__kk_imt_v ]]; then unset -n "$__kk_imt_v"; else unset -v "$__kk_imt_v"; fi
        __kk_imt_l=${__kk_imt_p[$__kk_imt_v]-}
        [[ -n $__kk_imt_l ]] || continue
        __kk_imt_fl=${__kk_imt_l#declare -}
        __kk_imt_fl=${__kk_imt_fl%% *}
        __kk_imt_l=${__kk_imt_l#declare -* }
        if [[ $__kk_imt_fl == - ]]; then eval "declare -g $__kk_imt_l"; else eval "declare -g$__kk_imt_fl $__kk_imt_l"; fi
    done
    return "$__kk_imt_rc"
}

# kk._img_hooks — run every hook of __KK_UNIT_SETTINGS in that order through
# kk._image_hook (marked as running), in the caller's options; __KK_IMG_HRC =
# "FN RC" of each hook that returned non-zero.
kk._img_hooks() {
    local __kk_imh_e __kk_imh_fn __kk_imh_h
    __KK_IMG_HRC=()
    for __kk_imh_e in "${__KK_UNIT_SETTINGS[@]}"; do
        __kk_imh_fn=${__kk_imh_e#*"$__KK_SEP"}
        [[ $__kk_imh_fn != : ]] || continue
        __kk_imh_h=0
        kk._image_hook "${__kk_imh_e%%"$__KK_SEP"*}" "$__kk_imh_fn" || __kk_imh_h=$?
        if (( __kk_imh_h != 0 )); then __KK_IMG_HRC+=("$__kk_imh_fn $__kk_imh_h"); fi
    done
    return 0
}

# kk._img_pidvars PID — __KK_IMG_PIDV = " VAR … ": the hook VARs (keys of
# __KK_SETTINGS_VARS) holding PID now (a scalar; not a nameref). A pid-derived
# hook VAR (fv.views' __FV_VW_OWNER) compares equal only in pairs: its value at
# the end of the load is the loader's pid and in a simulation the subshell's.
# kk._img_pidpair PID — in the simulation's subshell, before its dump: each of
# them holding this subshell's $BASHPID gets PID back.
kk._img_pidvars() {
    local - __kk_imq_v __kk_imq_at
    set +u
    __KK_IMG_PIDV=" "
    __KK_IMG_PIDA=()
    for __kk_imq_v in "${!__KK_SETTINGS_VARS[@]}"; do
        __kk_imq_at=""
        if declare -p "$__kk_imq_v" >/dev/null 2>&1; then __kk_imq_at=${!__kk_imq_v@a}; fi
        if [[ ! -R $__kk_imq_v && $__kk_imq_at != *[aA]* && ${!__kk_imq_v-} == "$1" ]]; then
            __KK_IMG_PIDV+="$__kk_imq_v "
            __KK_IMG_PIDA+=("$__kk_imq_v")
        fi
    done
    return 0
}
kk._img_pidpair() {
    local __kk_imq_v
    for __kk_imq_v in "${__KK_IMG_PIDA[@]}"; do
        if [[ ${!__kk_imq_v-} == "$BASHPID" ]]; then printf -v "$__kk_imq_v" '%s' "$1"; fi
    done
    return 0
}

# kk._img__split FILE ARRAY — the caller's ARRAY = FILE's non-empty lines (one
# read -N, a split in memory: mapfile is ~100x slower on the Windows runtimes).
kk._img__split() {
    local - IFS=$'\n' __kk_iml_z=""
    local -n __kk_iml_r=$2
    set -f
    read -r -N 268435456 __kk_iml_z < "$1" || :
    __kk_iml_r=($__kk_iml_z)
}

# kk._img_shell FILE — the shell state a load must not change (an image never
# holds it, §4 / §6.3): sections @trap @alias @umask @options @fattr.
kk._img_shell() {
    {
        printf '@trap\n'; trap -p
        printf '@alias\n'; alias -p
        printf '@umask\n'; umask
        printf '@options\n'; set +o; shopt -p
        printf '@fattr\n'; declare -Fx; declare -Ft
    } > "$1" 2>/dev/null
}

# kk._img_shelldiff A B -> __kk_imx_d: the names of the sections of two
# kk._img_shell texts that differ (' trap alias …'; '' when equal).
kk._img_shelldiff() {
    local __kk_imx_s __kk_imx_a __kk_imx_b
    __kk_imx_d=""
    [[ $1 != "$2" ]] || return 0
    for __kk_imx_s in trap alias umask options fattr; do
        __kk_imx_a=${1#*"@$__kk_imx_s"$'\n'}; __kk_imx_a=${__kk_imx_a%%$'\n'@*}
        __kk_imx_b=${2#*"@$__kk_imx_s"$'\n'}; __kk_imx_b=${__kk_imx_b%%$'\n'@*}
        [[ $__kk_imx_a == "$__kk_imx_b" ]] || __kk_imx_d+=" $__kk_imx_s"
    done
    return 0
}

# ---------------------------------------------------------------------------
# The writer

# kk._img_write ARGS — the miss path (see the header), called by kk.image,
# whose locals it reads (__kk_im_caller, __kk_im_dir, __kk_im_mk, __kk_im_img,
# __kk_im_ref, __kk_im_name, __kk_im_key, __kk_im_reqf, __kk_im_reqk). rc = the
# load's rc. Under VERBOSE_KKLASS=debug a line names the reason when no image
# is written, and one gives the writer's profile.
kk._img_write() {
    local __kk_imw_t="" __kk_imw_rc=0 __kk_imw_why="" __kk_imw_um=022 __kk_imw_nonce="" __kk_imw_rt="" \
          __kk_imw_it="" __kk_imw_ok=0 __kk_imw_cu=0 __kk_imw_cn=0 __kk_imw_pid=$BASHPID __kk_imw_ft0="" \
          __kk_imw_v0f="" __kk_imw_k0="" __kk_imw_sh0="" __kk_imw_nord=0 __kk_imw_nset=0 __kk_imw_used="" \
          __kk_imw_pr="" __kk_imw_opt=$-
    local -a __kk_imw_vn=() __kk_imw_kn=() __kk_imw_fo=() __kk_imw_P=() __kk_imw_tp=()
    local -A __kk_imw_pre=() __kk_imw_f0=() __kk_imw_kb=()
    __kk_imw_tp[0]=$EPOCHREALTIME
    if kk._img__before; then __kk_imw_ok=1; fi
    __kk_imw_tp[1]=$EPOCHREALTIME
    kk._uses "$__kk_im_caller" "$@"
    __kk_imw_rc=$?
    __kk_imw_tp[2]=$EPOCHREALTIME
    kk._img__after
    return "$__kk_imw_rc"
}

# kk._img__before — step 1 (kk._img_write's locals); rc 1 (__kk_imw_why) when
# no image can be written: the load then runs plain.
kk._img__before() {
    # (no IFS local: the records of the caller's IFS are taken here)
    local - __kk_imb_x __kk_imb_z="" __kk_imb_t __kk_imb_nc=0
    local -a __kk_imb_a=() __kk_imb_ks=()
    if [[ $- == *u* ]]; then __kk_imw_cu=1; fi
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_imw_cn=1; __kk_imb_nc=1; shopt -u nocasematch; fi
    set +eux -f
    kk._img__before2 || { if (( __kk_imb_nc )); then shopt -s nocasematch; fi; return 1; }
    if (( __kk_imb_nc )); then shopt -s nocasematch; fi
    return 0
}
kk._img__before2() {
    if (( __kk_im_mk )); then
        ( umask 077 && mkdir -p -- "$__kk_im_dir" ) 2>/dev/null
        kk._image_levels
        if (( __kk_im_mk )) || [[ -n $__kk_im_bad ]]; then
            __kk_imw_why="cannot make the image folder $__kk_im_dir${__kk_im_bad:+ ($__kk_im_bad)}"; return 1
        fi
    fi
    __kk_imw_t=$__kk_im_dir/$__kk_im_name.w$BASHPID.$SRANDOM
    kk._img_shell "$__kk_imw_t.sh0"
    read -r -N 16777216 __kk_imw_sh0 < "$__kk_imw_t.sh0" || :
    __kk_imw_um=${__kk_imw_sh0#*$'@umask\n'}
    __kk_imw_um=${__kk_imw_um%%$'\n'*}
    if [[ -z $__kk_imw_um || $__kk_imw_um == *[!0-7]* ]]; then __kk_imw_why="cannot read the umask"; return 1; fi
    # the reference file, made now (dates mode, §7.6)
    printf -v __kk_imw_nonce '%08x%08x' "$SRANDOM" "$SRANDOM"
    __kk_imw_rt=$__kk_im_ref.tmp.$BASHPID.$SRANDOM
    umask 077
    set -C
    { printf '%s\n' "$__kk_imw_nonce" > "$__kk_imw_rt"; } 2>/dev/null || __kk_imw_why="cannot write $__kk_imw_rt"
    set +C
    umask "$__kk_imw_um"
    if [[ -n $__kk_imw_why ]]; then __kk_imw_rt=""; return 1; fi
    # every variable before (the hook VARs are put back from these records)
    kk._img_pre "$__kk_imw_t.v0" __kk_imw_pre
    for __kk_imb_x in "${!__kk_imw_pre[@]}"; do
        if [[ $__kk_imb_x == __KK_* ]]; then
            [[ $__KK_IMG_REG == *" $__kk_imb_x "* || $__KK_IMG_NEVER == *" $__kk_imb_x "* \
               || $__kk_imb_x == __KK_IMG_* || $__kk_imb_x == __KK_UNIT_USED ]] || __kk_imw_kn+=("$__kk_imb_x")
            continue
        fi
        [[ $__KK_IMG_SKIP == *" $__kk_imb_x "* || $__KK_IMG_NEVER == *" $__kk_imb_x "* || $__kk_imb_x == __kk_* ]] && continue
        __kk_imw_vn+=("$__kk_imb_x")
    done
    if (( ${#__kk_imw_vn[@]} )); then declare -p "${__kk_imw_vn[@]}" > "$__kk_imw_t.v0f" 2>/dev/null; else : > "$__kk_imw_t.v0f"; fi
    read -r -N 268435456 __kk_imw_v0f < "$__kk_imw_t.v0f" || :
    if (( ${#__kk_imw_kn[@]} )); then declare -p "${__kk_imw_kn[@]}" > "$__kk_imw_t.k0" 2>/dev/null; else : > "$__kk_imw_t.k0"; fi
    read -r -N 268435456 __kk_imw_k0 < "$__kk_imw_t.k0" || :
    # the functions before: names and texts
    compgen -A function > "$__kk_imw_t.f0"
    kk._img__split "$__kk_imw_t.f0" __kk_imw_fo
    for __kk_imb_x in "${__kk_imw_fo[@]}"; do __kk_imw_f0[$__kk_imb_x]=1; done
    if (( ${#__kk_imw_fo[@]} )); then declare -f "${__kk_imw_fo[@]}" > "$__kk_imw_t.ft0"; else : > "$__kk_imw_t.ft0"; fi
    read -r -N 268435456 __kk_imw_ft0 < "$__kk_imw_t.ft0" || :
    # kkore's registration tables, element by element (the base list)
    for __kk_imb_t in "${__KK_IMG_REGA[@]}"; do
        eval '__kk_imb_ks=("${!'"$__kk_imb_t"'[@]}")'
        for __kk_imb_x in "${__kk_imb_ks[@]}"; do
            eval '__kk_imw_kb[$__kk_imb_t$__KK_SEP$__kk_imb_x]=${'"$__kk_imb_t"'[$__kk_imb_x]}'
        done
    done
    __kk_imw_used=$__KK_UNIT_USED
    __kk_imw_nord=${#__KK_UNIT_ORDER[@]}
    __kk_imw_nset=${#__KK_UNIT_SETTINGS[@]}
    return 0
}

# kk._img__after — steps 3-5 and the cleanup; never fails.
kk._img__after() {
    local - __kk_ima_nc=0
    set +eux -f
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_ima_nc=1; shopt -u nocasematch; fi
    if (( ! __kk_imw_ok )); then
        :
    elif (( __kk_imw_rc != 0 )); then
        __kk_imw_why="the load failed (rc $__kk_imw_rc)"
    else
        kk._img__build || :
    fi
    # the temp files (one rm): what is left of this writer's
    if [[ -n $__kk_imw_t ]]; then
        local -a __kk_ima_f=()
        local __kk_ima_x
        for __kk_ima_x in sh0 sh1 v0 v0f v1f k0 k1 f0 f1 ft0 ft1 n1 fn end end.pre end.raw sim sim.pre sim.raw diff; do
            __kk_ima_f+=("$__kk_imw_t.$__kk_ima_x")
        done
        [[ -z $__kk_imw_rt ]] || __kk_ima_f+=("$__kk_imw_rt")
        [[ -z $__kk_imw_it ]] || __kk_ima_f+=("$__kk_imw_it")
        command rm -f -- "${__kk_ima_f[@]}" 2>/dev/null
    fi
    if (( __kk_ima_nc )); then shopt -s nocasematch; fi
    if [[ -n $__kk_imw_why ]]; then kk._image_dbg "no image written: $__kk_imw_why"; fi
    if [[ -n $__kk_imw_pr ]]; then kk._image_dbg "writer profile (ms): $__kk_imw_pr"; fi
    return 0
}

# kk._img__ms A B -> __kk_imw_ms: B - A in ms (two EPOCHREALTIME values).
kk._img__ms() {
    local __kk_imm_a=${1/[.,]/} __kk_imm_b=${2/[.,]/}
    __kk_imw_ms=$(( (10#$__kk_imm_b - 10#$__kk_imm_a) / 1000 ))
}

# kk._img__build — the delta, the refusal rules, the simulation, the text, the
# write. rc 1 with __kk_imw_why when no image is written.
kk._img__build() {
    # (no IFS / LC_ALL local here: the simulation's hooks run in the caller's)
    local __kk_imk_x __kk_imk_y __kk_imk_z="" __kk_imk_t __kk_imk_k __kk_imk_v __kk_imk_d __kk_imx_d __kk_imw_ms \
          __kk_imk_sh1="" __kk_imk_kk=""
    local -a __kk_imk_a=() __kk_imk_ks=() __kk_imk_units=() __kk_imk_cls=() __kk_imk_nv=() __kk_imk_ro=() \
          __kk_imk_nf=() __kk_imk_base=() __kk_imk_reg=() __kk_imk_hooks=() __kk_imk_edges=() __kk_imk_files=()
    local -A __kk_imk_nu=() __kk_imk_hv=() __kk_imk_post=() __kk_imk_seen=()
    # the shell state
    kk._img_shell "$__kk_imw_t.sh1"
    read -r -N 16777216 __kk_imk_sh1 < "$__kk_imw_t.sh1" || :
    kk._img_shelldiff "$__kk_imw_sh0" "$__kk_imk_sh1"
    if [[ -n $__kk_imx_d ]]; then __kk_imw_why="the load changed the shell state:$__kk_imx_d"; return 1; fi
    # this call's units, in load order (unchained: every unit registered now)
    for __kk_imk_x in "${__KK_UNIT_ORDER[@]:__kk_imw_nord}"; do
        __kk_imk_x=${__kk_imk_x#*"$__KK_SEP"}
        if ! kk._unit_complete "$__kk_imk_x"; then __kk_imw_why="unit '$__kk_imk_x' is not completely loaded"; return 1; fi
        __kk_imk_units+=("$__kk_imk_x")
        __kk_imk_nu[$__kk_imk_x]=1
    done
    for __kk_imk_x in "${!__KK_UNITS[@]}"; do
        if [[ -z ${__kk_imw_kb[__KK_UNITS$__KK_SEP$__kk_imk_x]+x} && -z ${__kk_imk_nu[$__kk_imk_x]-} ]]; then
            __kk_imw_why="unit '$__kk_imk_x' is registered out of the load order"; return 1
        fi
    done
    if (( ! ${#__kk_imk_units[@]} )); then __kk_imw_why="the load registered no unit"; return 1; fi
    # the hook VARs: never held (the hooks set them on every start)
    for __kk_imk_x in "${!__KK_SETTINGS_VARS[@]}" __kk_ft; do __kk_imk_hv[$__kk_imk_x]=1; done
    # existing variables (kkore's aside): unchanged, or a hook VAR
    if (( ${#__kk_imw_vn[@]} )); then declare -p "${__kk_imw_vn[@]}" > "$__kk_imw_t.v1f" 2>/dev/null; else : > "$__kk_imw_t.v1f"; fi
    read -r -N 268435456 __kk_imk_z < "$__kk_imw_t.v1f" || :
    if [[ $__kk_imk_z != "$__kk_imw_v0f" ]]; then
        local -A __kk_imk_was=()
        kk._img__parse "$__kk_imw_t.v0f" __kk_imk_was
        kk._img__parse "$__kk_imw_t.v1f" __kk_imk_post
        for __kk_imk_x in "${__kk_imw_vn[@]}"; do
            [[ -z ${__kk_imk_hv[$__kk_imk_x]-} ]] || continue
            if [[ ${__kk_imk_post[$__kk_imk_x]-<none>} != "${__kk_imk_was[$__kk_imk_x]-<none>}" ]]; then
                __kk_imw_why="the load changed the existing variable $__kk_imk_x outside the settings hooks (chained deltas: I2b)"
                return 1
            fi
        done
    fi
    if (( ${#__kk_imw_kn[@]} )); then declare -p "${__kk_imw_kn[@]}" > "$__kk_imw_t.k1" 2>/dev/null; else : > "$__kk_imw_t.k1"; fi
    read -r -N 268435456 __kk_imk_kk < "$__kk_imw_t.k1" || :
    if [[ $__kk_imk_kk != "$__kk_imw_k0" ]]; then __kk_imw_why="the load changed a kkore table other than the unit registry"; return 1; fi
    # the variables the load created
    compgen -v > "$__kk_imw_t.n1"
    kk._img__split "$__kk_imw_t.n1" __kk_imk_a
    for __kk_imk_x in "${__kk_imk_a[@]}"; do
        [[ -z ${__kk_imw_pre[$__kk_imk_x]+x} && -z ${__kk_imk_hv[$__kk_imk_x]-} ]] || continue
        [[ $__KK_IMG_SKIP == *" $__kk_imk_x "* || $__KK_IMG_NEVER == *" $__kk_imk_x "* || $__kk_imk_x == __kk_im* \
           || $__kk_imk_x == __KK_IMG_* ]] && continue
        __kk_imk_y=${!__kk_imk_x@a}
        if [[ ! -R $__kk_imk_x && $__kk_imk_y == *x* ]]; then
            __kk_imw_why="the load exported $__kk_imk_x outside the settings hooks"; return 1
        fi
        __kk_imk_nv+=("$__kk_imk_x")
        if [[ $__kk_imk_y == *r* ]]; then __kk_imk_ro+=("$__kk_imk_x"); fi
    done
    # the functions: new ones held, the existing ones unchanged
    compgen -A function > "$__kk_imw_t.f1"
    kk._img__split "$__kk_imw_t.f1" __kk_imk_a
    __kk_imk_y=0
    for __kk_imk_x in "${__kk_imk_a[@]}"; do
        if [[ -n ${__kk_imw_f0[$__kk_imk_x]-} ]]; then __kk_imk_y=$(( __kk_imk_y + 1 )); else __kk_imk_nf+=("$__kk_imk_x"); fi
    done
    if (( __kk_imk_y != ${#__kk_imw_fo[@]} )); then __kk_imw_why="the load removed a function"; return 1; fi
    if (( ${#__kk_imw_fo[@]} )); then declare -f "${__kk_imw_fo[@]}" > "$__kk_imw_t.ft1" 2>/dev/null; else : > "$__kk_imw_t.ft1"; fi
    __kk_imk_z=""
    read -r -N 268435456 __kk_imk_z < "$__kk_imw_t.ft1" || :
    if [[ $__kk_imk_z != "$__kk_imw_ft0" ]]; then __kk_imw_why="the load redefined an existing function (chained deltas: I2b)"; return 1; fi
    # kkore's registration: element deltas; the base list holds each slot's earlier value
    for __kk_imk_t in "${__KK_IMG_REGA[@]}"; do
        eval '__kk_imk_ks=("${!'"$__kk_imk_t"'[@]}")'
        for __kk_imk_k in "${__kk_imk_ks[@]}"; do
            eval '__kk_imk_v=${'"$__kk_imk_t"'[$__kk_imk_k]}'
            __kk_imk_x=$__kk_imk_t$__KK_SEP$__kk_imk_k
            __kk_imk_seen[$__kk_imk_x]=1
            if [[ -z ${__kk_imw_kb[$__kk_imk_x]+x} ]]; then
                __kk_imk_base+=("e$__KK_SEP$__kk_imk_t$__KK_SEP$__kk_imk_k$__KK_SEP-$__KK_SEP")
            elif [[ ${__kk_imw_kb[$__kk_imk_x]} != "$__kk_imk_v" ]]; then
                __kk_imk_base+=("e$__KK_SEP$__kk_imk_t$__KK_SEP$__kk_imk_k$__KK_SEP=$__KK_SEP${__kk_imw_kb[$__kk_imk_x]}")
            else
                continue
            fi
            __kk_imk_reg+=("$__kk_imk_t" "$__kk_imk_k" "$__kk_imk_v")
        done
    done
    for __kk_imk_x in "${!__kk_imw_kb[@]}"; do
        if [[ -z ${__kk_imk_seen[$__kk_imk_x]-} ]]; then
            __kk_imw_why="the load removed the kkore entry ${__kk_imk_x//$__KK_SEP/[}] (chained deltas: I2b)"; return 1
        fi
    done
    # kkore slots a load of these units would write but that predate it (a unit
    # forgotten earlier keeps its namespace; a unit used earlier closed
    # kk.project): an image made now would lack them in a fresh start
    if [[ -n $__kk_imw_used ]]; then
        __kk_imw_why="a unit was used before this load (__KK_UNIT_USED=$__kk_imw_used): no image of a fresh start can be made"; return 1
    fi
    for __kk_imk_x in "${!__kk_imw_kb[@]}"; do
        [[ $__kk_imk_x == __KK_NAMESPACES"$__KK_SEP"* ]] || continue
        __kk_imk_y=${__kk_imw_kb[$__kk_imk_x]%%"$__KK_SEP"*}
        if [[ -n $__kk_imk_y && -n ${__kk_imk_nu[$__kk_imk_y]-} ]]; then
            __kk_imw_why="the namespace ${__kk_imk_x#*"$__KK_SEP"} of unit '$__kk_imk_y' predates this load (a unit forgotten earlier): no image of a fresh start can be made"; return 1
        fi
    done
    if [[ $__KK_UNIT_USED != "$__kk_imw_used" ]]; then
        __kk_imk_base+=("s$__KK_SEP""__KK_UNIT_USED$__KK_SEP$__KK_SEP=$__KK_SEP$__kk_imw_used")
    fi
    # classes, hooks, dependency edges, stamped files
    for __kk_imk_x in "${__kk_imk_units[@]}"; do
        __kk_imk_y=${__KK_UNIT_CLASSES[$__kk_imk_x]-}" "
        while [[ $__kk_imk_y == *[![:space:]]* ]]; do
            __kk_imk_y=${__kk_imk_y# }
            [[ -z ${__kk_imk_y%% *} ]] || __kk_imk_cls+=("${__kk_imk_y%% *}")
            __kk_imk_y=${__kk_imk_y#* }
        done
    done
    __kk_imk_hooks=("${__KK_UNIT_SETTINGS[@]:__kk_imw_nset}")
    for __kk_imk_k in "${!__KK_UNIT_RES[@]}"; do
        __kk_imk_v=${__KK_UNIT_RES[$__kk_imk_k]}
        __kk_imk_x=${__kk_imk_k##*"$__KK_SEP"}
        [[ -n $__kk_imk_v && -n ${__kk_imk_nu[$__kk_imk_x]-} ]] || continue
        for __kk_imk_y in "${__kk_im_reqk[@]}"; do [[ $__kk_imk_y != "$__kk_imk_k" ]] || continue 2; done
        __kk_imk_edges+=("${__kk_imk_k%"$__KK_SEP"*}$__KK_SEP$__kk_imk_x$__KK_SEP$__kk_imk_v")
    done
    __kk_imk_seen=()
    __kk_imk_d=${__KK_UNITS[kuse]%[/\\]*}
    __kk_imk_a=()
    for __kk_imk_x in "${__kk_imk_units[@]}"; do __kk_imk_a+=("${__KK_UNITS[$__kk_imk_x]}"); done
    for __kk_imk_x in "${!__KK_UNIT_FILES[@]}"; do __kk_imk_a+=("$__kk_imk_x"); done
    __kk_imk_a+=("${__KK_UNITS[kbool]}" "$__kk_imk_d/kuse.sh" "$__kk_imk_d/klib.sh" "$__kk_imk_d/kerr.sh" \
                 "$__kk_imk_d/kvar.sh" "$__kk_imk_d/kcfg.sh" "$__kk_imk_d/kimage.sh")
    if [[ -f $KBOOL_HOME/kklass/kklass.sh ]]; then __kk_imk_a+=("$KBOOL_HOME/kklass/kklass.sh"); fi
    for __kk_imk_x in "${__kk_imk_a[@]}"; do
        [[ -z ${__kk_imk_seen[$__kk_imk_x]-} ]] || continue
        __kk_imk_seen[$__kk_imk_x]=1
        if [[ ! -f $__kk_imk_x || ! $__kk_imk_x -ot $__kk_imw_rt ]]; then
            __kk_imw_why="$__kk_imk_x is not older than the load start (a future mtime, or edited during the load)"; return 1
        fi
        __kk_imk_files+=("$__kk_imk_x")
    done
    kk._img__ms "${__kk_imw_tp[0]}" "${__kk_imw_tp[1]}"
    __kk_imw_pr="before $__kk_imw_ms"
    kk._img__ms "${__kk_imw_tp[1]}" "${__kk_imw_tp[2]}"
    __kk_imw_pr+=", load $__kk_imw_ms"
    kk._img__ms "${__kk_imw_tp[2]}" "$EPOCHREALTIME"
    __kk_imw_pr+=", delta $__kk_imw_ms"
    # the simulated image start (§5.2)
    __kk_imk_x=$EPOCHREALTIME
    kk._img__sim || return 1
    kk._img__ms "$__kk_imk_x" "$EPOCHREALTIME"
    __kk_imw_pr+=", simulation $__kk_imw_ms"
    # the text (LC_ALL=C; in a function of its own: the locale its local leaves may warn)
    __kk_imk_x=$EPOCHREALTIME
    kk._img__text 2>/dev/null || return 1
    kk._img__ms "$__kk_imk_x" "$EPOCHREALTIME"
    __kk_imw_pr+=", text $__kk_imw_ms"
    # the write: one printf, then the renames (image first)
    __kk_imk_x=$EPOCHREALTIME
    __kk_imw_it=$__kk_im_img.tmp.$BASHPID.$SRANDOM
    umask 077
    set -C
    __kk_imk_y=0
    { printf '%s' "${__kk_imw_P[@]}" > "$__kk_imw_it"; } 2>/dev/null || __kk_imk_y=1
    set +C
    umask "$__kk_imw_um"
    if (( __kk_imk_y )); then __kk_imw_why="cannot write $__kk_imw_it"; return 1; fi
    if ! command mv -f -- "$__kk_imw_it" "$__kk_im_img" 2>/dev/null; then __kk_imw_why="cannot rename $__kk_imw_it"; return 1; fi
    __kk_imw_it=""
    if ! command mv -f -- "$__kk_imw_rt" "$__kk_im_ref" 2>/dev/null; then __kk_imw_why="cannot rename $__kk_imw_rt"; return 1; fi
    __kk_imw_rt=""
    kk._img__ms "$__kk_imk_x" "$EPOCHREALTIME"
    __kk_imw_pr+=", write $__kk_imw_ms; total"
    kk._img__ms "${__kk_imw_tp[0]}" "$EPOCHREALTIME"
    __kk_imw_pr+=" $__kk_imw_ms"
    kk._image_dbg "wrote $__kk_im_img"
    return 0
}

# kk._img__sim — the simulated image start (§5.2, the subshell form): rc 1 and
# __kk_imw_why naming the first difference.
kk._img__sim() {
    local __kk_imi_d=""
    kk._img_pidvars "$__kk_imw_pid"
    kk._img_state "$__kk_imw_t.end"
    (
        if ! kk._img_reset __kk_imw_pre "${!__KK_SETTINGS_VARS[@]}"; then
            printf 'a settings hook variable is readonly (%s): it cannot be put back' "${__KK_IMG_RO% }" > "$__kk_imw_t.diff"
            exit 1
        fi
        # the hooks in the caller's options (as on a start: errexit ignored)
        if [[ $__kk_imw_opt != *f* ]]; then set +f; fi
        if (( __kk_imw_cu )); then set -u; fi
        if (( __kk_imw_cn )); then shopt -s nocasematch; fi
        kk._img_hooks
        set +u -f
        shopt -u nocasematch
        if (( ${#__KK_IMG_HRC[@]} )); then
            printf 'the settings hook %s failed' "${__KK_IMG_HRC[0]}" > "$__kk_imw_t.diff"
            exit 1
        fi
        kk._img_pidpair "$__kk_imw_pid"
        kk._img_state "$__kk_imw_t.sim"
        if ! kk._img_cmp "$__kk_imw_t.end" "$__kk_imw_t.sim"; then
            printf '%s' "$__KK_IMG_DIFF" > "$__kk_imw_t.diff"
            exit 1
        fi
        exit 0
    ) >/dev/null 2>&1 && return 0
    { read -r -N 4096 __kk_imi_d < "$__kk_imw_t.diff"; } 2>/dev/null || :
    __kk_imw_why="the simulated image start differs: ${__kk_imi_d:-?}"
    return 1
}

# kk._img__arr NAME ARRAY -> __kk_imj_s: `NAME=(%q …)` of the caller's array ARRAY.
kk._img__arr() {
    local -n __kk_imj_r=$2
    if (( ${#__kk_imj_r[@]} )); then
        printf -v __kk_imj_s '%q ' "${__kk_imj_r[@]}"
        __kk_imj_s="$1=(${__kk_imj_s% })"
    else
        __kk_imj_s="$1=()"
    fi
}

# kk._img__vals NAME — NAME's elements as `NAME[%q]=%q` lines, one chunk into
# __kk_imw_P (the keys' and the values' expansions walk one table in one order).
kk._img__vals() {
    local __kk_imz_qk __kk_imz_qv __kk_imz_i __kk_imz_n __kk_imz_c
    local -a __kk_imz_k=() __kk_imz_v=() __kk_imz_z=()
    eval 'printf -v __kk_imz_qk "%q\n" "${!'"$1"'[@]}"; printf -v __kk_imz_qv "%q\n" "${'"$1"'[@]}"'
    __kk_imz_k=($__kk_imz_qk)
    __kk_imz_v=($__kk_imz_qv)
    __kk_imz_n=${#__kk_imz_k[@]}
    for (( __kk_imz_i = 0; __kk_imz_i < __kk_imz_n; __kk_imz_i++ )); do
        __kk_imz_z+=("${__kk_imz_k[__kk_imz_i]}" "${__kk_imz_v[__kk_imz_i]}")
    done
    printf -v __kk_imz_c "$1[%s]=%s\n" "${__kk_imz_z[@]}"
    __kk_imw_P+=("$__kk_imz_c")
}

# kk._img__text — the image text into __kk_imw_P (kk._img__build's lists).
kk._img__text() {
    local LC_ALL=C IFS=$'\n' __kk_imj_s __kk_imj_x __kk_imj_at __kk_imj_fl __kk_imj_l1 __kk_imj_l2 __kk_imj_l3 __kk_imj_l4 \
          __kk_imj_fn="" __kk_imj_cr __kk_imj_c __kk_imj_p
    local -a __kk_imj_kv=() __kk_imj_ch=() __kk_imj_ps=()
    local -A __kk_imj_isro=()
    # the functions, CR-rewritten where this parser drops CR (IMG-D7)
    if (( ${#__kk_imk_nf[@]} )); then
        declare -f "${__kk_imk_nf[@]}" > "$__kk_imw_t.fn" 2>/dev/null
        read -r -N 268435456 __kk_imj_fn < "$__kk_imw_t.fn" || :
    fi
    printf -v __kk_imj_cr '\r'
    if [[ $__kk_imj_fn == *"$__kk_imj_cr"* ]]; then
        eval "__kk_imj_p='$__kk_imj_cr'"
        if [[ -z $__kk_imj_p ]]; then
            if ! declare -F kk._fn_text_cr >/dev/null; then
                __kk_imw_why="a function text holds a CR byte this parser drops, and kklass (kk._fn_text_cr) is not loaded"; return 1
            fi
            # which functions: `declare -f` by 64 names, then one by one in a
            # chunk with a CR (the text itself cannot be cut at function
            # boundaries reliably: a string literal may hold "\n}\n")
            local -a __kk_imj_ok=()
            local __kk_imj_i __kk_imj_f __kk_imj_crt=""
            for (( __kk_imj_i = 0; __kk_imj_i < ${#__kk_imk_nf[@]}; __kk_imj_i += 64 )); do
                __kk_imj_ch=("${__kk_imk_nf[@]:__kk_imj_i:64}")
                declare -f "${__kk_imj_ch[@]}" > "$__kk_imw_t.fn" 2>/dev/null
                __kk_imj_c=""
                read -r -N 268435456 __kk_imj_c < "$__kk_imw_t.fn" || :
                if [[ $__kk_imj_c != *"$__kk_imj_cr"* ]]; then __kk_imj_ok+=("${__kk_imj_ch[@]}"); continue; fi
                for __kk_imj_f in "${__kk_imj_ch[@]}"; do
                    declare -f "$__kk_imj_f" > "$__kk_imw_t.fn" 2>/dev/null
                    __kk_imj_c=""
                    read -r -N 268435456 __kk_imj_c < "$__kk_imw_t.fn" || :
                    if [[ $__kk_imj_c != *"$__kk_imj_cr"* ]]; then __kk_imj_ok+=("$__kk_imj_f"); continue; fi
                    __kk_imj_c=${__kk_imj_c%$'\n'}
                    if ! kk._fn_text_cr __kk_imj_c; then
                        __kk_imw_why="the CR bytes of function $__kk_imj_f cannot be rewritten (kk._fn_text_cr)"; return 1
                    fi
                    __kk_imj_crt+=$__kk_imj_c$'\n'
                done
            done
            __kk_imj_fn=""
            if (( ${#__kk_imj_ok[@]} )); then
                declare -f "${__kk_imj_ok[@]}" > "$__kk_imw_t.fn" 2>/dev/null
                read -r -N 268435456 __kk_imj_fn < "$__kk_imw_t.fn" || :
            fi
            __kk_imj_fn+=$__kk_imj_crt
        fi
    fi
    # the header (lines 1-5)
    printf -v __kk_imj_l1 '__kk_img_key=%q __kk_img_nonce=%q' "$__kk_im_key" "$__kk_imw_nonce"
    kk._img__arr __kk_img_files __kk_imk_files;   __kk_imj_l2=$__kk_imj_s
    kk._img__arr __kk_img_edges __kk_imk_edges;   __kk_imj_l2+=" $__kk_imj_s"
    kk._img__arr __kk_img_reqf __kk_im_reqf;      __kk_imj_l2+=" $__kk_imj_s"
    kk._img__arr __kk_img_units __kk_imk_units;   __kk_imj_l3=$__kk_imj_s
    kk._img__arr __kk_img_classes __kk_imk_cls;   __kk_imj_l3+=" $__kk_imj_s"
    kk._img__arr __kk_img_vars __kk_imk_nv;       __kk_imj_l3+=" $__kk_imj_s"
    kk._img__arr __kk_img_fns __kk_imk_nf;        __kk_imj_l3+=" $__kk_imj_s"
    kk._img__arr __kk_img_ro __kk_imk_ro;         __kk_imj_l3+=" $__kk_imj_s __kk_img_wtime=$EPOCHSECONDS"
    kk._img__arr __kk_img_base __kk_imk_base;     __kk_imj_l4=$__kk_imj_s
    # line 1 carries the byte length of lines 2-5 (all ASCII: %q under LC_ALL=C),
    # so a start reads them with ONE read -N (a line-by-line read of ~150 KB
    # costs ~0.4 s on the MSYS-family runtimes)
    __kk_imj_s=$__kk_imj_l1$'\n'$__kk_imj_l2$'\n'$__kk_imj_l3$'\n'$__kk_imj_l4$'\n'
    __kk_imw_P=("# kbool image v1 ${#__kk_imj_s}"$'\n'"$__kk_imj_s" "$__kk_imj_fn")
    # the variables (declare -g, never -r / -x; arrays element by element);
    # kklass's tables in the final block, then the readonly flags
    for __kk_imj_x in "${__kk_imk_ro[@]}"; do __kk_imj_isro[$__kk_imj_x]=1; done
    for __kk_imj_p in 0 1; do
        for __kk_imj_x in "${__kk_imk_nv[@]}"; do
            if [[ $__kk_imj_x == _KKLASS_* || $__kk_imj_x == __KKLASS_* ]]; then
                (( __kk_imj_p == 1 )) || continue
            else
                (( __kk_imj_p == 0 )) || continue
            fi
            __kk_imj_at=${!__kk_imj_x@a}
            __kk_imj_fl=${__kk_imj_at//[aAnrx]/}
            if [[ -R $__kk_imj_x ]]; then
                eval '__kk_imj_s=${!'"$__kk_imj_x"'}'
                printf -v __kk_imj_s 'declare -gn%s %s=%q\n' "$__kk_imj_fl" "$__kk_imj_x" "$__kk_imj_s"
                __kk_imw_P+=("$__kk_imj_s")
            elif [[ $__kk_imj_at == *[aA]* ]]; then
                __kk_imj_s=a
                [[ $__kk_imj_at != *A* ]] || __kk_imj_s=A
                __kk_imw_P+=("declare -g$__kk_imj_s$__kk_imj_fl $__kk_imj_x=()"$'\n')
                eval '__kk_imj_s=${#'"$__kk_imj_x"'[@]}'
                if (( __kk_imj_s )); then kk._img__vals "$__kk_imj_x"; fi
            elif [[ -z ${!__kk_imj_x+x} ]]; then
                # declared, never assigned: a scalar, or an array (`declare -gA X`)
                eval '__kk_imj_s=${'"$__kk_imj_x"'[@]@a}'
                __kk_imw_P+=("declare -g${__kk_imj_s//[nrx]/}$__kk_imj_fl $__kk_imj_x"$'\n')
            elif [[ -z $__kk_imj_fl ]]; then
                __kk_imj_kv+=("$__kk_imj_x" "${!__kk_imj_x}")
            else
                printf -v __kk_imj_s 'declare -g%s %s=%q\n' "$__kk_imj_fl" "$__kk_imj_x" "${!__kk_imj_x}"
                __kk_imw_P+=("$__kk_imj_s")
            fi
        done
        if (( ${#__kk_imj_kv[@]} )); then
            printf -v __kk_imj_s 'declare -g %s=%q\n' "${__kk_imj_kv[@]}"
            __kk_imw_P+=("$__kk_imj_s")
            __kk_imj_kv=()
        fi
    done
    if (( ${#__kk_imk_ro[@]} )); then
        printf -v __kk_imj_s 'readonly %s\n' "${__kk_imk_ro[@]}"
        __kk_imw_P+=("$__kk_imj_s")
    fi
    # kkore's registration, last
    if (( ${#__kk_imk_reg[@]} )); then
        printf -v __kk_imj_s '%s[%q]=%q\n' "${__kk_imk_reg[@]}"
        __kk_imw_P+=("$__kk_imj_s")
    fi
    if [[ $__KK_UNIT_USED != "$__kk_imw_used" ]]; then
        printf -v __kk_imj_s '__KK_UNIT_USED=%q\n' "$__KK_UNIT_USED"
        __kk_imw_P+=("$__kk_imj_s")
    fi
    kk._img__arr __kk_img_hooks __kk_imk_hooks
    __kk_imw_P+=("$__kk_imj_s"$'\n'"__kk_img_end=$__kk_imw_nonce"$'\n')
    return 0
}

# ---------------------------------------------------------------------------
# The undo of a failed image start (§8.3)

# kk._img_undo — kk._image_hit's header lists (__kk_img_*): drop the listed
# units' registration (and their classes, kklass's hook), forget the listed
# classes, unset the listed functions and the listed variables that are not
# readonly (the readonly ones that landed stay: units guard their readonly
# constants per name), and put every base-list slot back. Then kk.image loads
# the units normally.
kk._img_undo() {
    local - __kk_imu_x __kk_imu_k __kk_imu_n __kk_imu_y
    set +eu
    for __kk_imu_x in "${__kk_img_units[@]}"; do
        if [[ -n ${__KK_UNITS[$__kk_imu_x]+x} && -z ${__KK_UNIT_SYS[$__kk_imu_x]+x} ]]; then kk._unit_drop "$__kk_imu_x"; fi
    done
    if declare -F kk._unit_forget_class >/dev/null; then
        for __kk_imu_x in "${__kk_img_classes[@]}"; do kk._unit_forget_class "$__kk_imu_x"; done
    fi
    for __kk_imu_x in "${__kk_img_vars[@]}"; do
        if [[ -R $__kk_imu_x ]]; then
            unset -n "$__kk_imu_x"
        elif [[ ${!__kk_imu_x@a} != *r* ]]; then
            unset -v "$__kk_imu_x"
        fi
    done
    if (( ${#__kk_img_fns[@]} )); then unset -f "${__kk_img_fns[@]}"; fi
    for __kk_imu_x in "${__kk_img_base[@]}"; do
        __kk_imu_y=${__kk_imu_x%%"$__KK_SEP"*}
        __kk_imu_x=${__kk_imu_x#*"$__KK_SEP"}
        __kk_imu_n=${__kk_imu_x%%"$__KK_SEP"*}
        __kk_imu_x=${__kk_imu_x#*"$__KK_SEP"}
        __kk_imu_k=${__kk_imu_x%%"$__KK_SEP"*}
        __kk_imu_x=${__kk_imu_x#*"$__KK_SEP"}
        [[ $__kk_imu_n == __KK_* && $__kk_imu_n != *[!A-Z_]* ]] || continue
        case $__kk_imu_y${__kk_imu_x:0:1} in
            e-) unset -v "$__kk_imu_n[\$__kk_imu_k]" ;;
            e=) __kk_imu_x=${__kk_imu_x:2}; eval "$__kk_imu_n[\$__kk_imu_k]=\$__kk_imu_x" ;;
            s-) unset -v "$__kk_imu_n" ;;
            s=) printf -v "$__kk_imu_n" '%s' "${__kk_imu_x:2}" ;;
        esac
    done
    return 0
}
