#!/usr/bin/env bash
# kkore/kimage.sh — the load-image writer, pruning, --forget, the undo of a
# failed image start, and THE STATE DUMP (kklass/docs/dev/IMAGE_PLAN.md §5.2,
# §6, §7.4, §8.3; stage I2a: unchained). Part of the unit loader like kuse.sh:
# no unit header. kk.image (kuse.sh) sources it only on a miss, a failed
# start or --forget (kk._image_lib); a test harness (kcl/tests/image_sim.sh)
# sources it for the dump, the compare and the hook replay. Sourcing it again
# redefines the functions. It is a stamped file of every image (§7.1).
#
# Every local here starts with __kk_im (kk.image's own are __kk_im_*), so the
# dump, which lists the variables visible to it, skips them all.
#
# The writer (kk._img_write, the miss path of §6.2):
#   1. before the load: the image folder (made under umask 077 the first time;
#      its trust checked again); in `stat` mode the stat flavour (GNU -c, else
#      BSD -f) over the folder levels, their permission bits checked on the
#      POSIX systems (group- or world-writable: no image); the shell state
#      (traps, aliases, umask, options, function attributes, jobs), the
#      reference file with a fresh nonce (made NOW: a file edited during the
#      load is newer than it), every variable's `declare -p` record (through a
#      temp file, never a pipe — IMAGE_PLAN M12), the function names and
#      texts, kkore's registration tables; right before the load an EXIT trap
#      that removes the temp files if the script ends inside the load (a
#      failing load under `set -e`, an `exit`), the open file descriptors and
#      the hash table;
#   2. kk._uses CALLER [--optional] UNIT... in the caller's options — its rc
#      is kk.image's; then the descriptors and the hash table again, the
#      caller's EXIT trap back;
#   3. the delta: this call's units (registered complete now, not before),
#      their new functions and the variables the load created, the kkore
#      registration entries it added (each with the slot's earlier value or
#      `-` for absent: the base list, checked by every start and put back by
#      the undo), the hooks, the dependency edges, the stamped files and, in
#      `stat` / `hash` mode, their stamps (one stat / cksum). NO IMAGE (a
#      debug line says why) when the load failed (also a failed `--optional`
#      unit: its rc is not 0); changed the shell state (traps, aliases, umask,
#      options, function attributes, a new background job or coprocess); left
#      a file descriptor open or closed one (kklass's pair __kk_ft excepted);
#      exported a variable or a function outside the hooks' VARs; changed,
#      removed or redefined an existing variable / function outside the hooks
#      (kkore's registration tables excepted: those are the base list —
#      chained deltas on other slots are I2b); changed another kkore table;
#      left a unit incomplete; assigned, in a unit file's text, a variable
#      that existed before the load (kk._img__assigned, critic M1); a stamped
#      file is not older than the reference file (a future mtime; or an edit
#      during the load), or, in `stat` mode, its ctime is later than the
#      load's start (later than now: a future ctime, held — M5); a stamped
#      path holds a newline or the US byte; a function text holds a CR byte
#      this parser drops and kklass's kk._fn_text_cr cannot rewrite (IMG-D7);
#      bash < 5.2 and a function text with `&> "$` / `&>"$` (IMG-D9). The
#      dependency edges include the names a lookup did NOT find (a failed
#      `kk.uses --optional`): DIR<US>NAME<US>(empty) (M3). The stamps are
#      taken after the load (the closure is known only then) under the
#      starts' umask;
#   4. the simulated image start (§5.2, no prior set): in a subshell every
#      hook VAR is put back to its state before the load (and the hash table,
#      when the load changed it), every hook runs in __KK_UNIT_SETTINGS order
#      (marked, kk._image_hook; their output is discarded — I1b critic L5),
#      and the full state must equal the end-of-load state (pid-valued hook
#      VARs compare in pairs; the hash table on its own);
#   5. the image text (format v1, §6.1, under LC_ALL=C) written by ONE printf
#      into NAME.tmp.TAG.PID.RANDOM.img (umask 077, noclobber), rc checked;
#      `mv -f` the image, then (dates mode) the reference file to
#      NAME.NONCE.ref. A failed write or rename (a native process holding
#      the image open) is silent: the old image stays;
#   6. a refusal of step 3 / 4 leaves NAME.hold (the reason; §7.5): the next
#      starts of the hour load normally without writing — not for a failed
#      write or rename, an untrusted or uncreatable folder, an edit during the
#      load; --rebuild removes a hold. After a write, pruning (§7.4,
#      kk._img_prune); the temp files, the files pruned and a cleared hold go
#      with ONE rm.
# The writer's files are made under umask 077 (critic L6); the load runs
# under the caller's umask, which is set back afterwards (or the one the load
# set, refused). Never held: kbool.sh's state, hook VARs, __kk_ft, exports,
# the name index and the caller-keyed tables (__KK_UNIT_CAND / _IDX / _IDX_OK
# / _RES / _HIT, __KK_FILE_PWD), __KK_UNIT_PID (pid state: nothing reads it
# for a loaded unit, so an image start leaves it absent), __KK_SETTINGS_RUN,
# the shell-owned and scratch names of __KK_IMG_SKIP, the hash table and
# alias table variables.
#
# The format v1 (order matters for the undo):
#   # kbool image v1 N                               N = the byte length of the header lines below
#   #P<US>WTIME<US>SIZE<US>TAG<US>HOME<US>PRIOR<US>MODE<US>FLAVOUR<US>NONCE<US>RHASH<US>N<US>FILE…
#                                                    the plain line (read without eval: the stamped
#                                                    files for the `stat` bits check, pruning's and
#                                                    --forget's data)
#   __kk_img_key=… __kk_img_nonce=…                 the key (kimghit.sh kk._image_key), the nonce
#   __kk_img_edges=(…) __kk_img_reqf=(…) __kk_img_stamp=… __kk_img_stime=…
#                                                    DIR<US>NAME<US>FILE (FILE empty: not found); the
#                                                    request files; the stamps and their second
#   __kk_img_units=(…) __kk_img_classes=(…) __kk_img_vars=(…) __kk_img_fns=(…) __kk_img_ro=(…) __kk_img_wtime=…
#   __kk_img_base=(…)                                KIND<US>NAME<US>KEY<US>FLAG<US>VALUE
#   <functions>                                      declare -f, CR-rewritten
#   <variables>                                      declare -g…; arrays X=() then X[k]=v; an
#                                                    associative key that is not plain (and has no
#                                                    control byte) through two %q arrays and a loop
#   <final block>                                    kklass tables, then the readonly flags
#   <kkore registration>                             the base list's new values: LAST
#   __kk_img_hooks=(UNIT<US>FN …)
#   __kk_img_end=<the nonce>
# SIZE = the byte count of the file (12 digits); TAG = FNV-1a of $BASH (the
# runtime: pruning judges only its own temps' pids and KBOOL_HOME spellings);
# PRIOR = the prior set (empty until chaining, I2b); FLAVOUR = gnu9 / gnu /
# bsd9 / bsd in `stat` mode (9: nanosecond times), else `-`; NONCE = the
# image's nonce (its NAME.NONCE.ref, dates mode); RHASH = FNV-1a of the
# request (--forget of a request whose 64-character name is another's);
# __kk_img_stime = the second the stamps were taken in (the racy rule of the
# whole-second flavours). I2b adds the chained deltas on non-kkore slots.



declare -g __KK_IMG_SKIP=" _ __kk_ft BASHPID BASH_MONOSECONDS BASH_TRAPSIG BASH_ARGC BASH_ARGV BASH_ARGV0 BASH_COMMAND BASH_LINENO BASH_REMATCH BASH_SOURCE BASH_SUBSHELL EPOCHREALTIME EPOCHSECONDS FUNCNAME HISTCMD LINENO PIPESTATUS RANDOM SECONDS SRANDOM COLUMNS LINES RESULT "
# the writer's kkore classes: held as element deltas (the base list) / never held
declare -ga __KK_IMG_REGA=(__KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_CLASSES __KK_UNIT_FILES
    __KK_UNIT_ORDER __KK_UNIT_SETTINGS __KK_SETTINGS_VARS __KK_NAMESPACES)
declare -g __KK_IMG_REG=" __KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_CLASSES __KK_UNIT_FILES __KK_UNIT_ORDER __KK_UNIT_SETTINGS __KK_SETTINGS_VARS __KK_NAMESPACES "
declare -g __KK_IMG_NEVER=" DIRSTACK GROUPS OLDPWD __KK_UNIT_CAND __KK_UNIT_IDX __KK_UNIT_IDX_OK __KK_UNIT_RES __KK_UNIT_HIT __KK_FILE_PWD __KK_UNIT_PID __KK_SETTINGS_RUN __kk_unit_rc BASH_CMDS BASH_ALIASES "
# bash's own variables and the environment's usual ones: units assign them
# in their functions (`local IFS=`, `PATH=`, `REPLY=`), so they are no
# candidates of kk._img__assigned (M1); LC_* by pattern there
declare -g __KK_IMG_BASHV=" BASH BASHOPTS BASHPID BASH_ALIASES BASH_ARGC BASH_ARGV BASH_ARGV0 BASH_CMDS BASH_COMMAND BASH_COMPAT BASH_ENV BASH_EXECUTION_STRING BASH_LINENO BASH_LOADABLES_PATH BASH_MONOSECONDS BASH_REMATCH BASH_SOURCE BASH_SUBSHELL BASH_TRAPSIG BASH_VERSINFO BASH_VERSION BASH_XTRACEFD CDPATH CHILD_MAX COLUMNS COMPREPLY COMP_CWORD COMP_KEY COMP_LINE COMP_POINT COMP_TYPE COMP_WORDBREAKS COMP_WORDS COPROC DIRSTACK EMACS ENV EPOCHREALTIME EPOCHSECONDS EUID EXECIGNORE FCEDIT FIGNORE FUNCNAME FUNCNEST GLOBIGNORE GLOBSORT GROUPS HISTCMD HISTCONTROL HISTFILE HISTFILESIZE HISTIGNORE HISTSIZE HISTTIMEFORMAT HOME HOSTFILE HOSTNAME HOSTTYPE IFS IGNOREEOF INPUTRC INSIDE_EMACS LANG LANGUAGE LINENO LINES LOGNAME MACHTYPE MAIL MAILCHECK MAILPATH MAPFILE OLDPWD OPTARG OPTERR OPTIND OSTYPE PATH PIPESTATUS POSIXLY_CORRECT PPID PROMPT_COMMAND PROMPT_DIRTRIM PS0 PS1 PS2 PS3 PS4 PWD RANDOM READLINE_ARGUMENT READLINE_LINE READLINE_MARK READLINE_POINT REPLY RESULT SECONDS SHELL SHELLOPTS SHLVL SRANDOM TEMP TERM TIMEFORMAT TMOUT TMP TMPDIR TZ UID USER "
# the bytes of an associative key written as it is into a subscript (kk._img__vals)
declare -g __KK_IMG_PLAIN="A-Za-z0-9_./:,+=-"
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
# holds it, §4 / §6.3): sections @trap @alias @umask @options @fattr
# (exported, traced, readonly functions) @enable (`enable -n`: disabled
# builtins) @complete (`complete -p`) @jobs (`jobs -p`: the pids of the
# background jobs — a coprocess is one too). Not covered (documented): the
# resource limits (ulimit) and the directory stack (pushd / DIRSTACK).
kk._img_shell() {
    # (the redirection inside the 2>/dev/null: an unwritable folder is silent)
    { {
        printf '@trap\n'; trap -p
        printf '@alias\n'; alias -p
        printf '@umask\n'; umask
        printf '@options\n'; set +o; shopt -p
        printf '@fattr\n'; declare -Fx; declare -Ft; declare -Fr
        printf '@enable\n'; enable -n
        printf '@complete\n'; complete -p
        printf '@jobs\n'; jobs -p
    } > "$1"; } 2>/dev/null || :
}

# kk._img_shelldiff A B -> __kk_imx_d: the names of the sections of two
# kk._img_shell texts that differ (' trap alias …'; '' when equal). @jobs
# differs only by a job B has and A had not (a job of the caller's that
# ended during the load is no change of the load's).
kk._img_shelldiff() {
    local __kk_imx_s __kk_imx_a __kk_imx_b __kk_imx_l
    __kk_imx_d=""
    [[ $1 != "$2" ]] || return 0
    for __kk_imx_s in trap alias umask options fattr enable complete jobs; do
        # (a newline in front of each section's text: an empty section is
        # cut right — I2a-1 named an empty `trap` with a changed `alias`)
        __kk_imx_a=$'\n'${1#*"@$__kk_imx_s"$'\n'}; __kk_imx_a=${__kk_imx_a%%$'\n'@*}
        __kk_imx_b=$'\n'${2#*"@$__kk_imx_s"$'\n'}; __kk_imx_b=${__kk_imx_b%%$'\n'@*}
        [[ $__kk_imx_a != "$__kk_imx_b" ]] || continue
        if [[ $__kk_imx_s == jobs ]]; then
            [[ $1 == *$'\n@jobs\n'* ]] || __kk_imx_a=""
            [[ $2 == *$'\n@jobs\n'* ]] || __kk_imx_b=""
            for __kk_imx_l in ${__kk_imx_b//$'\n'/ }; do
                [[ $'\n'$__kk_imx_a$'\n' == *$'\n'"$__kk_imx_l"$'\n'* ]] || { __kk_imx_d+=" jobs"; break; }
            done
            continue
        fi
        __kk_imx_d+=" $__kk_imx_s"
    done
    return 0
}

# ---------------------------------------------------------------------------
# Small helpers of the writer, pruning and --forget

# kk._img_glob DIR ARRAY — the caller's ARRAY = the entries of DIR (one glob,
# fork-free; nullglob on, failglob / nocaseglob / GLOBIGNORE off for it).
kk._img_glob() {
    local - GLOBIGNORE= __kk_imy_o=$BASHOPTS
    local -n __kk_imy_r=$2
    set +f
    shopt -s nullglob
    shopt -u failglob nocaseglob
    __kk_imy_r=("$1"/*)
    [[ :$__kk_imy_o: == *:nullglob:* ]] || shopt -u nullglob
    [[ :$__kk_imy_o: != *:failglob:* ]] || shopt -s failglob
    [[ :$__kk_imy_o: != *:nocaseglob:* ]] || shopt -s nocaseglob
    return 0
}

# kk._img_fds VAR — VAR = " N N … ": the open file descriptors of this shell,
# fork-free: the entries of /proc/$BASHPID/fd (Linux, Cygwin, MSYS2, Git-bash:
# one glob, well under a millisecond; the glob's own directory descriptor is
# listed too, the same in two snapshots), else 0..255 probed by a `>&N`
# duplication each (macOS / BSD; ~256 redirections). The writer compares a
# snapshot before and after the load (§6.3: fds other than kklass's pair).
kk._img_fds() {
    local - __kk_imf_x __kk_imf_s=" " __kk_imf_n
    local -a __kk_imf_a=()
    set +eu
    if [[ -d /proc/$BASHPID/fd ]]; then
        kk._img_glob "/proc/$BASHPID/fd" __kk_imf_a
        for __kk_imf_x in "${__kk_imf_a[@]}"; do
            __kk_imf_x=${__kk_imf_x##*/}
            [[ -z $__kk_imf_x || $__kk_imf_x == *[!0-9]* ]] || __kk_imf_s+="$__kk_imf_x "
        done
    else
        for (( __kk_imf_n = 0; __kk_imf_n < 256; __kk_imf_n++ )); do
            { : >&$__kk_imf_n; } 2>/dev/null && __kk_imf_s+="$__kk_imf_n "    # (unquoted: a number; IMG-D9)
        done
    fi
    printf -v "$1" '%s' "$__kk_imf_s"
}

# kk._img__fdcheck — kk._img__build's descriptor rule over the two snapshots
# __kk_imw_fd0 / _fd1: rc 1 (__kk_imw_why) when the load left one open that
# is not kklass's pair (__kk_ft) or closed one. Its own IFS (the snapshots
# are blank-separated: the caller's IFS may be anything — critic L1).
kk._img__fdcheck() {
    local IFS=' ' __kk_imd_x __kk_imd_y=" "
    if [[ ${__kk_ft[0]+${__kk_ft@a}} == a* && ${__kk_ft[0]} == "$BASHPID" ]]; then
        __kk_imd_y+="${__kk_ft[1]} ${__kk_ft[2]} ${__kk_ft[6]} "
    fi
    for __kk_imd_x in $__kk_imw_fd1; do
        [[ $__kk_imw_fd0 == *" $__kk_imd_x "* || $__kk_imd_y == *" $__kk_imd_x "* ]] && continue
        __kk_imw_why="the load left the file descriptor $__kk_imd_x open"; return 1
    done
    for __kk_imd_x in $__kk_imw_fd0; do
        [[ $__kk_imw_fd1 == *" $__kk_imd_x "* ]] && continue
        __kk_imw_why="the load closed the file descriptor $__kk_imd_x"; return 1
    done
    return 0
}

# kk._img_now — __kk_imw_now = the time now, in seconds (a function, so a
# test can move "now" back: a ctime in the future cannot be made portably).
kk._img_now() { __kk_imw_now=$EPOCHSECONDS; }

# kk._img__assigned — critic M1: rc 1 (__kk_imw_why) when a variable that
# existed before the load (__kk_imw_vn: not kkore's, not bash's of
# __KK_IMG_BASHV, not LC_*, not a hook VAR) is an assignment target in the
# texts of this call's unit files. Such a variable is pre-existing and may
# look unchanged — an environment preset of a unit's internal self-default
# (`: "${__X:=d}"`, D6), or a caller's local hiding the unit's global — so
# the writer would leave it out and every image start would lack it. The
# textual forms scanned (one regex per candidate that occurs in the texts):
#   NAME=  NAME+=  NAME[…]=  NAME[…]+=      (not after a name character, $ . {)
#   ${NAME:=…}  ${NAME=…}
#   declare / local / readonly / typeset … NAME   (on the same command)
# Scanned are the file-scope lines only — a line that starts at column 0 and
# is no comment (function bodies are indented by kbool's style; texts are not
# parsed, so a file-scope statement indented inside an `if` is not seen, and
# a one-line function at column 0 is). bash's and the environment's usual
# names, KBOOL_* and VERBOSE_KKLASS (keyed) are no candidates.
kk._img__assigned() {
    local - __kk_ima_t="" __kk_ima_c __kk_ima_u __kk_ima_n __kk_ima_r __kk_ima_nl=$'\n' IFS=$'\n'
    local -a __kk_ima_l=()
    set -f
    # only the file-scope statements: lines that start at column 0 and are no
    # comment (function bodies are indented; a one-line function at column 0
    # counts) — each line not of that form becomes empty in one expansion
    for __kk_ima_u in "${__kk_imk_units[@]}"; do
        __kk_ima_c=""
        { read -r -N 268435456 __kk_ima_c < "${__KK_UNITS[$__kk_ima_u]}"; } 2>/dev/null || :
        __kk_ima_l=($__kk_ima_c)
        printf -v __kk_ima_c '%s\n' "${__kk_ima_l[@]/#[[:space:]#]*/}"
        __kk_ima_t+=$__kk_ima_c
    done
    for __kk_ima_n in "${__kk_imw_vn[@]}"; do
        [[ -n $__kk_ima_n && $__kk_ima_n != *[!A-Za-z0-9_]* && $__kk_ima_n != [0-9]* ]] || continue   # (`local -` lists as -)
        [[ -z ${__kk_imk_hv[$__kk_ima_n]-} && $__KK_IMG_BASHV != *" $__kk_ima_n "* && $__kk_ima_n != LC_* \
           && $__kk_ima_n != KBOOL_* && $__kk_ima_n != VERBOSE_KKLASS ]] || continue
        [[ $__kk_ima_t == *"$__kk_ima_n"* ]] || continue
        __kk_ima_r='(^|[^A-Za-z0-9_$.{])'"$__kk_ima_n"'(\[[^]]*\])?\+?=|\$\{'"$__kk_ima_n"':?=|(declare|local|readonly|typeset)[^;&|'"$__kk_ima_nl"']*[[:space:]]'"$__kk_ima_n"'([[:space:];=]|$)'
        if [[ $__kk_ima_t =~ $__kk_ima_r ]]; then
            __kk_imw_why="the variable $__kk_ima_n existed before the load and a unit file assigns it (a preset or a caller's local would hide the unit's own value from the image)"
            return 1
        fi
    done
    return 0
}

# kk._img__hcopy ASSOC — the caller's ASSOC = the hash table (BASH_CMDS).
kk._img__hcopy() {
    local -n __kk_imh_r=$1
    local __kk_imh_k
    __kk_imh_r=()
    for __kk_imh_k in "${!BASH_CMDS[@]}"; do __kk_imh_r[$__kk_imh_k]=${BASH_CMDS[$__kk_imh_k]}; done
    return 0
}

# kk._img__hdiff A B -> __kk_imw_hd: the first name whose hash-table entry
# differs between the associative arrays A and B ('' when equal).
kk._img__hdiff() {
    local -n __kk_imh_a=$1 __kk_imh_b=$2
    local __kk_imh_k
    __kk_imw_hd=""
    for __kk_imh_k in "${!__kk_imh_b[@]}"; do
        [[ ${__kk_imh_a[$__kk_imh_k]-$'\1'} == "${__kk_imh_b[$__kk_imh_k]}" ]] || { __kk_imw_hd=$__kk_imh_k; return 0; }
    done
    for __kk_imh_k in "${!__kk_imh_a[@]}"; do
        [[ -n ${__kk_imh_b[$__kk_imh_k]+x} ]] || { __kk_imw_hd=$__kk_imh_k; return 0; }
    done
    return 0
}

# kk._img_oldbash — rc 0 on a bash older than 5.2 (IMG-D9: its `declare -f`
# prints `>&"$fd"` as `&> "$fd"`, which parses back as another redirection).
# A function, so a test can pretend an old bash.
kk._img_oldbash() {
    (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2) ))
}

# kk._img__trapset / kk._img__trapback — the writer's EXIT trap around the
# load: it removes the writer's temp files when the script ends inside the
# load (a failing load under the caller's `set -e`, an `exit` in a unit), then
# runs the caller's own EXIT trap. trapback puts the caller's trap back — only
# when the load left the writer's trap in place (a load that set its own is
# left so, and refused: the shell state differs).
kk._img__trapset() {
    local - __kk_imt_x=""
    local -a __kk_imt_a=()
    set +eu        # (under the caller's set -e a failed write here must not end the script: M2)
    { trap -p EXIT > "$__kk_imw_t.tr0"; } 2>/dev/null || :
    { read -r -N 1048576 __kk_imt_x < "$__kk_imw_t.tr0"; } 2>/dev/null || :
    if [[ $__kk_imt_x == 'trap -- '* ]]; then
        eval "__kk_imt_a=($__kk_imt_x)"
        __kk_imw_tro=${__kk_imt_a[2]-}
        __kk_imw_trs=1
    fi
    printf -v __kk_imt_x '%q ' "$__kk_imw_t".{sh0,v0,v0f,k0,f0,ft0,ref,tr0,tr1}
    __kk_imw_trap="command rm -f -- ${__kk_imt_x% } 2>/dev/null"
    if (( __kk_imw_trs )); then __kk_imw_trap+=$'\n'$__kk_imw_tro; fi
    trap -- "$__kk_imw_trap" EXIT
    { trap -p EXIT > "$__kk_imw_t.tr1"; } 2>/dev/null || :
    { read -r -N 1048576 __kk_imw_trp < "$__kk_imw_t.tr1"; } 2>/dev/null || :
    return 0
}
kk._img__trapback() {
    local - __kk_imt_x=""
    set +eu        # (under the caller's set -e a failed write here must not end the script: M2)
    { trap -p EXIT > "$__kk_imw_t.tr1"; } 2>/dev/null || :
    { read -r -N 1048576 __kk_imt_x < "$__kk_imw_t.tr1"; } 2>/dev/null || :
    [[ $__kk_imt_x == "$__kk_imw_trp" ]] || return 0
    if (( __kk_imw_trs )); then trap -- "$__kk_imw_tro" EXIT; else trap - EXIT; fi
    return 0
}

# ---------------------------------------------------------------------------
# The writer

# kk._img_write — the miss path (see the header), called by kk.image, whose
# locals it reads (__kk_im_caller, __kk_im_args, __kk_im_act, __kk_im_dir,
# __kk_im_mk, __kk_im_img, __kk_im_ref, __kk_im_name, __kk_im_key,
# __kk_im_mode, __kk_im_reqf, __kk_im_reqk) — and changes when its `stat`
# takes neither -c nor -f (the mode becomes `dates`: the key and the names
# again). rc = the load's rc. Under VERBOSE_KKLASS=debug a line names the
# reason when no image is written, and one gives the writer's profile.
kk._img_write() {
    local __kk_imw_t="" __kk_imw_rc=0 __kk_imw_why="" __kk_imw_nohold="" __kk_imw_um="" __kk_imw_um1="" __kk_imw_nonce="" \
          __kk_imw_it="" __kk_imw_ok=0 __kk_imw_cu=0 __kk_imw_cn=0 __kk_imw_pid=$BASHPID __kk_imw_ft0="" \
          __kk_imw_v0f="" __kk_imw_k0="" __kk_imw_sh0="" __kk_imw_nord=0 __kk_imw_nset=0 __kk_imw_used="" \
          __kk_imw_pr="" __kk_imw_opt=$- __kk_imw_tag="" __kk_imw_fl="" __kk_imw_t0=0 __kk_imw_fd0="" \
          __kk_imw_fd1="" __kk_imw_trap="" __kk_imw_trp="" __kk_imw_tro="" __kk_imw_trs=0 __kk_imw_hd="" \
          __kk_imw_wrote=0 __kk_imw_rt="" __kk_imw_now=0
    local -a __kk_imw_vn=() __kk_imw_kn=() __kk_imw_fo=() __kk_imw_P=() __kk_imw_tp=()
    local -A __kk_imw_pre=() __kk_imw_f0=() __kk_imw_kb=() __kk_imw_hc0=() __kk_imw_hc1=()
    __kk_imw_tp[0]=$EPOCHREALTIME
    if kk._img__before; then __kk_imw_ok=1; fi
    __kk_imw_tp[1]=$EPOCHREALTIME
    # next to the load: the EXIT trap, the descriptors, the hash table; the
    # load runs under the caller's umask, the writer's files under 077 (L6)
    if (( __kk_imw_ok )); then
        kk._img__trapset; kk._img_fds __kk_imw_fd0; kk._img__hcopy __kk_imw_hc0
        umask "$__kk_imw_um"
    fi
    kk._uses "$__kk_im_caller" "${__kk_im_args[@]}"
    __kk_imw_rc=$?
    if (( __kk_imw_ok )); then
        kk._img__hcopy __kk_imw_hc1; kk._img_fds __kk_imw_fd1; kk._img__trapback
        kk._img__sh1                             # (the shell state the load left, its umask too)
        { read -r -N 16777216 __kk_imw_um1 < "$__kk_imw_t.sh1"; } 2>/dev/null || :
        __kk_imw_um1=${__kk_imw_um1#*$'@umask\n'}
        __kk_imw_um1=${__kk_imw_um1%%$'\n'*}
        [[ -n $__kk_imw_um1 && $__kk_imw_um1 != *[!0-7]* ]] || __kk_imw_um1=$__kk_imw_um
        umask 077
    fi
    __kk_imw_tp[2]=$EPOCHREALTIME
    kk._img__after
    # the umask the load left (the caller's, unless the load changed it)
    if (( __kk_imw_ok )); then umask "$__kk_imw_um1"; fi
    return "$__kk_imw_rc"
}

# kk._img__sh1 — the shell state right after the load into NAME…sh1, taken
# in the same option context as sh0 (kk._img__before: set +eux -f,
# nocasematch off), so only the load's changes differ.
kk._img__sh1() {
    local - __kk_ims_nc=0
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_ims_nc=1; shopt -u nocasematch; fi
    set +eux -f
    kk._img_shell "$__kk_imw_t.sh1"
    if (( __kk_ims_nc )); then shopt -s nocasematch; fi
    return 0
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
    kk._img__before2 || { if (( __kk_imb_nc )); then shopt -s nocasematch; fi; [[ -z $__kk_imw_um ]] || umask "$__kk_imw_um"; return 1; }
    if (( __kk_imb_nc )); then shopt -s nocasematch; fi
    return 0
}
kk._img__before2() {
    if (( __kk_im_mk )); then
        ( umask 077 && mkdir -p -- "$__kk_im_dir" ) 2>/dev/null
        kk._image_levels
        if (( __kk_im_mk )) || [[ -n $__kk_im_bad ]]; then
            __kk_imw_why="cannot make the image folder $__kk_im_dir${__kk_im_bad:+ ($__kk_im_bad)}"; __kk_imw_nohold=1; return 1
        fi
    elif [[ -n $__kk_im_bad ]]; then
        __kk_imw_why="untrusted folder: $__kk_im_bad"; __kk_imw_nohold=1; return 1
    fi
    # `stat` mode: the flavour (GNU -c, else BSD -f, as kcl TPath probes) over
    # the folder levels — whose permission bits count here (§8.1)
    if [[ $__kk_im_mode == stat ]]; then kk._img__probe || return 1; fi
    # the temp files: NAME.tmp.TAG.PID.RANDOM.KIND (TAG names this bash, so
    # that pruning judges only the pids of its own runtime with kill -0)
    kk._image_hash "$BASH" __kk_imw_tag
    __kk_imw_t=$__kk_im_dir/$__kk_im_name.tmp.$__kk_imw_tag.$BASHPID.$SRANDOM
    # the first file written: a folder this user cannot write in (POSIX
    # modes) ends the writer here, silently (IMG-D3)
    kk._img_shell "$__kk_imw_t.sh0"
    if [[ ! -f $__kk_imw_t.sh0 ]]; then
        __kk_imw_why="cannot write in the image folder $__kk_im_dir"; __kk_imw_nohold=1; __kk_imw_t=""; return 1
    fi
    read -r -N 16777216 __kk_imw_sh0 < "$__kk_imw_t.sh0" || :
    __kk_imw_um=${__kk_imw_sh0#*$'@umask\n'}
    __kk_imw_um=${__kk_imw_um%%$'\n'*}
    if [[ -z $__kk_imw_um || $__kk_imw_um == *[!0-7]* ]]; then __kk_imw_why="cannot read the umask"; __kk_imw_nohold=1; return 1; fi
    # the reference file, made now: a stamped file must be older than it after
    # the load (every mode: an edit during the load, a future mtime); in
    # `dates` mode it becomes NAME.ref, the start's reference (§7.6)
    printf -v __kk_imw_nonce '%08x%08x' "$SRANDOM" "$SRANDOM"
    __kk_imw_rt=$__kk_imw_t.ref
    kk._img_now; __kk_imw_t0=$__kk_imw_now     # (the load's start; "now" a test seam, kk._img_now)
    umask 077
    set -C
    { printf '%s\n' "$__kk_imw_nonce" > "$__kk_imw_rt"; } 2>/dev/null || __kk_imw_why="cannot write $__kk_imw_rt"
    set +C
    # (the writer's own files — the dumps of every variable, the function
    # texts — under umask 077 from here on; the caller's umask is set back for
    # the load itself, kk._img_write; critic L6)
    if [[ -n $__kk_imw_why ]]; then __kk_imw_nohold=1; return 1; fi
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

# kk._img__probe — `stat` mode: __kk_imw_fl = the first flavour of gnu9,
# gnu, bsd9, bsd (kk._image_stamp: stat -c with nanosecond times, -c, -f with
# nanoseconds, -f) whose output over the folder levels is right (one fork on
# GNU coreutils >= 8.32; up to four on a BSD stat — misses only), their
# permission bits checked where they count (rc 1: an untrusted folder, no
# hold). A stat that takes neither: the mode becomes `dates` (keyed: the key
# and the names again, kk._image_key) and FOLDER/stat.hold tells the starts
# of the next hour so (kk._image_prep).
kk._img__probe() {
    local __kk_imo_f
    local -a __kk_imo_l=() __kk_imo_a=()
    if (( __kk_im_modes )); then kk._image__levels __kk_imo_l; else __kk_imo_l=("$__kk_im_dir"); fi
    for __kk_imo_f in gnu9 gnu bsd9 bsd; do
        kk._image_stamp "$__kk_imo_f" "${__kk_imo_l[@]}" || continue
        __kk_imw_fl=$__kk_imo_f
        if (( __kk_im_modes )); then
            kk._image_lines "$__kk_im_so" __kk_imo_a
            if ! kk._image_wbits "${__kk_imo_a[@]}"; then
                __kk_imw_why="untrusted folder: $__kk_im_why"; __kk_imw_nohold=1; return 1
            fi
        fi
        return 0
    done
    kk._image_dbg "KBOOL_IMAGE_CHECK=stat: the stat on PATH takes neither -c nor -f; using dates (stat.hold)"
    kk._image_hold "the stat on PATH takes neither -c nor -f" "" "$__kk_im_dir/stat.hold"
    __kk_im_mode=dates __kk_im_modes=0
    kk._image_key
    return 0
}

# kk._img__after — steps 3-5, the hold, pruning and the cleanup (ONE rm);
# never fails.
kk._img__after() {
    local - __kk_ima_nc=0 __kk_ima_x __kk_ima_h __kk_ima_held=""
    local -a __kk_ima_f=()
    set +eux -f
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_ima_nc=1; shopt -u nocasematch; fi
    if (( ! __kk_imw_ok )); then
        :
    elif (( __kk_imw_rc != 0 )); then
        __kk_imw_why="the load failed (rc $__kk_imw_rc)"
    else
        kk._img__build || :
    fi
    # a hold: the same start would refuse again (§7.5); --rebuild clears one
    # (the name: a `stat` that does not work made it the `dates` one)
    __kk_ima_h=$__kk_im_dir/$__kk_im_name.hold
    if [[ -n $__kk_imw_why && -z $__kk_imw_nohold && -n $__kk_imw_t ]]; then
        kk._image_hold "$__kk_imw_why" "$__kk_imw_um"
        __kk_ima_held=$__kk_ima_h
    elif [[ $__kk_im_act == rebuild && -f $__kk_ima_h && ! -L $__kk_ima_h ]]; then
        __kk_ima_f+=("$__kk_ima_h")
    fi
    if (( __kk_imw_wrote )); then kk._img_prune; fi
    # the temp files: what is left of this writer's
    if [[ -n $__kk_imw_t ]]; then
        for __kk_ima_x in sh0 sh1 v0 v0f v1f k0 k1 f0 f1 ft0 ft1 n1 fn end end.pre end.raw sim sim.pre sim.raw diff \
                          ref img tr0 tr1; do
            __kk_ima_f+=("$__kk_imw_t.$__kk_ima_x")
        done
    fi
    if (( ${#__kk_ima_f[@]} )); then command rm -f -- "${__kk_ima_f[@]}" 2>/dev/null; fi
    if (( __kk_ima_nc )); then shopt -s nocasematch; fi
    if [[ -n $__kk_imw_why ]]; then kk._image_dbg "no image written: $__kk_imw_why"; fi
    if [[ -n $__kk_ima_held ]]; then kk._image_dbg "held for an hour: $__kk_ima_held"; fi
    if [[ -n $__kk_imw_pr ]]; then kk._image_dbg "writer profile (ms): $__kk_imw_pr"; fi
    return 0
}

# kk._img__ms A B -> __kk_imw_ms: B - A in ms (two EPOCHREALTIME values).
kk._img__ms() {
    local __kk_imm_a=${1/[.,]/} __kk_imm_b=${2/[.,]/}
    __kk_imw_ms=$(( (10#$__kk_imm_b - 10#$__kk_imm_a) / 1000 ))
}

# kk._img__build — the delta, the refusal rules, the simulation, the text, the
# write. rc 1 with __kk_imw_why when no image is written (__kk_imw_nohold set
# when the next start may well succeed: an edit during the load, a failed
# write or rename).
kk._img__build() {
    # (no IFS / LC_ALL local here: the simulation's hooks run in the caller's)
    local __kk_imk_x __kk_imk_y __kk_imk_z="" __kk_imk_t __kk_imk_k __kk_imk_v __kk_imk_d __kk_imx_d __kk_imw_ms \
          __kk_imk_sh1="" __kk_imk_kk="" __kk_imk_stamp="" __kk_imk_stime=0 __kk_imk_home="" __kk_n
    local -a __kk_imk_a=() __kk_imk_ks=() __kk_imk_units=() __kk_imk_cls=() __kk_imk_nv=() __kk_imk_ro=() \
          __kk_imk_nf=() __kk_imk_base=() __kk_imk_reg=() __kk_imk_hooks=() __kk_imk_edges=() __kk_imk_files=()
    local -A __kk_imk_nu=() __kk_imk_hv=() __kk_imk_post=() __kk_imk_seen=()
    # the shell state (traps, aliases, umask, options, function attributes, jobs)
    # (sh1 was written by kk._img_write right after the load)
    read -r -N 16777216 __kk_imk_sh1 < "$__kk_imw_t.sh1" || :
    kk._img_shelldiff "$__kk_imw_sh0" "$__kk_imk_sh1"
    if [[ -n $__kk_imx_d ]]; then __kk_imw_why="the load changed the shell state:$__kk_imx_d"; return 1; fi
    # the descriptors: none opened or closed but kklass's pair (__kk_ft, §4)
    kk._img__fdcheck || return 1
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
    # a pre-existing variable a unit file assigns (it may look unchanged: M1)
    kk._img__assigned || return 1
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
        [[ -n $__kk_imk_v && -n ${__kk_imk_nu[$__kk_imk_x]-} ]] || [[ -z $__kk_imk_v ]] || continue      # (empty: found nothing, M3)
        for __kk_imk_y in "${__kk_im_reqk[@]}"; do [[ $__kk_imk_y != "$__kk_imk_k" ]] || continue 2; done
        __kk_imk_edges+=("${__kk_imk_k%"$__KK_SEP"*}$__KK_SEP$__kk_imk_x$__KK_SEP$__kk_imk_v")
    done
    __kk_imk_seen=()
    __kk_imk_d=${__KK_UNITS[kuse]%[/\\]*}
    __kk_imk_a=()
    for __kk_imk_x in "${__kk_imk_units[@]}"; do __kk_imk_a+=("${__KK_UNITS[$__kk_imk_x]}"); done
    for __kk_imk_x in "${!__KK_UNIT_FILES[@]}"; do __kk_imk_a+=("$__kk_imk_x"); done
    __kk_imk_a+=("${__KK_UNITS[kbool]}" "$__kk_imk_d/kuse.sh" "$__kk_imk_d/klib.sh" "$__kk_imk_d/kerr.sh" \
                 "$__kk_imk_d/kvar.sh" "$__kk_imk_d/kcfg.sh" "$__kk_imk_d/kimghit.sh" "$__kk_imk_d/kimage.sh")
    if [[ -f $KBOOL_HOME/kklass/kklass.sh ]]; then __kk_imk_a+=("$KBOOL_HOME/kklass/kklass.sh"); fi
    kk._unit_lexnorm "$KBOOL_HOME"
    __kk_imk_home=$__kk_n
    if [[ $__kk_imk_home == *[$'\n'"$__KK_SEP"]* ]]; then
        __kk_imw_why="KBOOL_HOME holds a newline or the US byte (the plain header line cannot)"; return 1
    fi
    for __kk_imk_x in "${__kk_imk_a[@]}"; do
        [[ -z ${__kk_imk_seen[$__kk_imk_x]-} ]] || continue
        __kk_imk_seen[$__kk_imk_x]=1
        if [[ $__kk_imk_x == *[$'\n'"$__KK_SEP"]* ]]; then
            __kk_imw_why="the path of $__kk_imk_x holds a newline or the US byte (the plain header line cannot)"; return 1
        fi
        if [[ ! -f $__kk_imk_x ]]; then __kk_imw_why="$__kk_imk_x is missing after the load"; __kk_imw_nohold=1; return 1; fi
        # newer than the reference made before the load: newer than the shell
        # state file written after it too = a future mtime (a hold); else an
        # edit during the load (the next start writes)
        if [[ ! $__kk_imk_x -ot $__kk_imw_rt ]]; then
            if [[ $__kk_imk_x -nt $__kk_imw_t.sh1 ]]; then
                __kk_imw_why="$__kk_imk_x has a future mtime"
            else
                __kk_imw_why="$__kk_imk_x changed during the load"; __kk_imw_nohold=1
            fi
            return 1
        fi
        __kk_imk_files+=("$__kk_imk_x")
    done
    # the stamps of `stat` / `hash` mode, after the load (the closure is known
    # only now); `stat` also refuses a file whose ctime is later than the
    # load's start (an mtime-keeping change during the load, to the second)
    case $__kk_im_mode in
        stat|hash)
            __kk_imk_t=$__kk_imw_fl
            [[ $__kk_im_mode == stat ]] || __kk_imk_t=hash
            __kk_imk_stime=$EPOCHSECONDS        # (the racy rule of the whole-second flavours, kimghit.sh)
            # (under the umask the starts have, not the writer's 077: a runtime
            # that makes modes up uses it)
            umask "$__kk_imw_um1"
            kk._image_stamp "$__kk_imk_t" "${__kk_imk_files[@]}"
            __kk_imk_y=$?
            umask 077
            if (( __kk_imk_y )); then
                __kk_imw_why="$__kk_imk_t failed over the stamped files"; __kk_imw_nohold=1; return 1
            fi
            __kk_imk_stamp=$__kk_im_so
            if [[ $__kk_im_mode == stat ]]; then
                kk._image_lines "$__kk_imk_stamp" __kk_imk_ks
                for (( __kk_imk_k = 0; __kk_imk_k < ${#__kk_imk_files[@]}; __kk_imk_k++ )); do
                    __kk_imk_v=${__kk_imk_ks[__kk_imk_k]#* * }
                    __kk_imk_v=${__kk_imk_v%% *}
                    __kk_imk_v=${__kk_imk_v%%.*}          # (gnu9 / bsd9: the whole seconds)
                    if [[ -z $__kk_imk_v || $__kk_imk_v == *[!0-9]* ]] || (( 10#$__kk_imk_v > __kk_imw_t0 )); then
                        kk._img_now
                        if [[ -n $__kk_imk_v && $__kk_imk_v != *[!0-9]* ]] && (( 10#$__kk_imk_v > __kk_imw_now )); then
                            __kk_imw_why="${__kk_imk_files[__kk_imk_k]} has a future ctime ($__kk_imk_v; now $__kk_imw_now)"; return 1     # (a hold: critic M5)
                        fi
                        __kk_imw_why="${__kk_imk_files[__kk_imk_k]} changed during the load (its ctime ${__kk_imk_v:-?})"
                        __kk_imw_nohold=1; return 1
                    fi
                done
            fi ;;
    esac
    # the hash table: a change the hooks do not repeat is refused by the simulation
    kk._img__hdiff __kk_imw_hc0 __kk_imw_hc1
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
    # the write: one printf, then the renames (image first; the reference in
    # `dates` mode only). A failed rename (a native process holding the image
    # open) is silent: the temp goes, the old image stays.
    __kk_imk_x=$EPOCHREALTIME
    __kk_imw_it=$__kk_imw_t.img
    umask 077
    set -C
    __kk_imk_y=0
    { printf '%s' "${__kk_imw_P[@]}" > "$__kk_imw_it"; } 2>/dev/null || __kk_imk_y=1
    set +C
    umask "$__kk_imw_um"
    if (( __kk_imk_y )); then __kk_imw_why="cannot write $__kk_imw_it"; __kk_imw_nohold=1; return 1; fi
    if ! command mv -f -- "$__kk_imw_it" "$__kk_im_img" 2>/dev/null; then
        __kk_imw_why="cannot rename $__kk_imw_it"; __kk_imw_nohold=1; return 1
    fi
    if [[ $__kk_im_mode == dates ]]; then
        __kk_im_ref=$__kk_im_dir/$__kk_im_name.$__kk_imw_nonce.ref      # (named after the nonce: L3)
        if ! command mv -f -- "$__kk_imw_rt" "$__kk_im_ref" 2>/dev/null; then
            __kk_imw_why="cannot rename $__kk_imw_rt"; __kk_imw_nohold=1; return 1
        fi
    fi
    __kk_imw_wrote=1
    kk._img__ms "$__kk_imk_x" "$EPOCHREALTIME"
    __kk_imw_pr+=", write $__kk_imw_ms; total"
    kk._img__ms "${__kk_imw_tp[0]}" "$EPOCHREALTIME"
    __kk_imw_pr+=" $__kk_imw_ms"
    kk._image_dbg "wrote $__kk_im_img"
    return 0
}

# kk._img__sim — the simulated image start (§5.2, the subshell form): rc 1 and
# __kk_imw_why naming the first difference. The hash table is compared on its
# own (the writer's own commands hash after the load): when the load changed
# it, the subshell puts the table of before the load back, and the hooks must
# make it the table of after the load.
kk._img__sim() {
    local __kk_imi_d="" __kk_imi_k
    local -a __KK_IMG_XV=("${__KK_IMG_XV[@]}" BASH_CMDS)
    kk._img_pidvars "$__kk_imw_pid"
    kk._img_state "$__kk_imw_t.end"
    (
        if ! kk._img_reset __kk_imw_pre "${!__KK_SETTINGS_VARS[@]}"; then
            printf 'a settings hook variable is readonly (%s): it cannot be put back' "${__KK_IMG_RO% }" > "$__kk_imw_t.diff"
            exit 1
        fi
        if [[ -n $__kk_imw_hd ]]; then
            hash -r
            for __kk_imi_k in "${!__kk_imw_hc0[@]}"; do BASH_CMDS[$__kk_imi_k]=${__kk_imw_hc0[$__kk_imi_k]}; done
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
        if [[ -n $__kk_imw_hd ]]; then
            local -A __kk_imi_h=()
            kk._img__hcopy __kk_imi_h
            kk._img__hdiff __kk_imi_h __kk_imw_hc1
            if [[ -n $__kk_imw_hd ]]; then
                printf 'the load changed the hash table (%s) outside the settings hooks' "$__kk_imw_hd" > "$__kk_imw_t.diff"
                exit 1
            fi
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

# kk._img__vals NAME [ATTRS] — NAME's elements as `NAME[%q]=%q` lines, one
# chunk into __kk_imw_P (the keys' and the values' expansions walk one table
# in one order). An associative array's key whose %q form is not plain
# (__KK_IMG_PLAIN) is never written into a subscript: bash 5.1 reads
# `X[@]=v` as an assignment to every element (an error, the whole table lost
# on an image start: fv.mouse's __FV_MS_ORD, CI run 45467673135), and quoted
# or escaped subscripts parse differently between versions. Those keys and
# their values go into two indexed arrays (%q elements, which every bash
# reads alike) and a loop assigns `NAME[${__kk_img_k[i]}]=${__kk_img_v[i]}`:
# a subscript that is one expansion, taken as the key.
kk._img__vals() {
    local __kk_imz_qk __kk_imz_qv __kk_imz_i __kk_imz_n __kk_imz_c
    local -a __kk_imz_k=() __kk_imz_v=() __kk_imz_z=() __kk_imz_uk=() __kk_imz_uv=() __kk_imz_r=()
    eval 'printf -v __kk_imz_qk "%q\n" "${!'"$1"'[@]}"; printf -v __kk_imz_qv "%q\n" "${'"$1"'[@]}"'
    __kk_imz_k=($__kk_imz_qk)
    __kk_imz_v=($__kk_imz_qv)
    __kk_imz_n=${#__kk_imz_k[@]}
    if [[ ${2-} == *A* ]]; then eval '__kk_imz_r=("${!'"$1"'[@]}")'; fi
    for (( __kk_imz_i = 0; __kk_imz_i < __kk_imz_n; __kk_imz_i++ )); do
        if [[ ${2-} == *A* && ${__kk_imz_k[__kk_imz_i]} == *[!$__KK_IMG_PLAIN]* ]] \
           && kk._img__loopkey "${__kk_imz_r[__kk_imz_i]}"; then
            __kk_imz_uk+=("${__kk_imz_k[__kk_imz_i]}")
            __kk_imz_uv+=("${__kk_imz_v[__kk_imz_i]}")
        else
            __kk_imz_z+=("${__kk_imz_k[__kk_imz_i]}" "${__kk_imz_v[__kk_imz_i]}")
        fi
    done
    if (( ${#__kk_imz_z[@]} )); then
        printf -v __kk_imz_c "$1[%s]=%s\n" "${__kk_imz_z[@]}"
        __kk_imw_P+=("$__kk_imz_c")
    fi
    if (( ${#__kk_imz_uk[@]} )); then
        kk._img__loop "$1" "${__kk_imz_uk[*]}" "${__kk_imz_uv[*]}"
    fi
}

# kk._img__loopkey RAWKEY — rc 0 when a key that is not plain takes the loop
# form: unless it holds a control byte (0x01-0x1F, 0x7F). Those stay in the
# literal `X[$'\r']=v` form, which every bash reads: in the loop form the
# MSYS2 / Git-bash parser drops a CR of the expanded subscript ("bad array
# subscript", and the rest of the loop is lost — fv.keyboard's __FV_KB_CTRL).
kk._img__loopkey() {
    [[ ${1//[[:cntrl:]]/} == "$1" ]]
}

# kk._img__loop NAME QKEYS QVALS — the loop form of kk._img__vals into
# __kk_imw_P: QKEYS / QVALS = the %q forms, newline-separated.
kk._img__loop() {
    local __kk_imz_a=${2//$'\n'/ } __kk_imz_b=${3//$'\n'/ }
    __kk_imw_P+=("__kk_img_k=($__kk_imz_a) __kk_img_v=($__kk_imz_b)"$'\n'"for __kk_img_i in \"\${!__kk_img_k[@]}\"; do $1[\${__kk_img_k[__kk_img_i]}]=\${__kk_img_v[__kk_img_i]}; done"$'\n')
}

# kk._img__text — the image text into __kk_imw_P (kk._img__build's lists).
kk._img__text() {
    local LC_ALL=C IFS=$'\n' __kk_imj_s __kk_imj_x __kk_imj_at __kk_imj_fl __kk_imj_l0 __kk_imj_l1 __kk_imj_l2 \
          __kk_imj_l3 __kk_imj_l4 __kk_imj_fn="" __kk_imj_cr __kk_imj_c __kk_imj_p __kk_imj_w=$EPOCHSECONDS __kk_imj_n=0
    local -a __kk_imj_kv=() __kk_imj_ch=() __kk_imj_ps=()
    local -A __kk_imj_isro=()
    # the functions, CR-rewritten where this parser drops CR (IMG-D7)
    if (( ${#__kk_imk_nf[@]} )); then
        declare -f "${__kk_imk_nf[@]}" > "$__kk_imw_t.fn" 2>/dev/null
        read -r -N 268435456 __kk_imj_fn < "$__kk_imw_t.fn" || :
    fi
    # bash < 5.2 prints `>&"$fd"` as `&> "$fd"` (IMG-D9): no image of such a text
    if kk._img_oldbash && [[ $__kk_imj_fn == *'&> "$'* || $__kk_imj_fn == *'&>"$'* ]]; then
        __kk_imw_why="bash $BASH_VERSION (< 5.2) and a function text with &> \"\$ (IMG-D9)"; return 1
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
    # the header: the plain line (read without eval: wtime, size — 12 digits,
    # filled in last —, the runtime tag, KBOOL_HOME, the prior set, the mode,
    # the stat flavour, the stamped files), then the lines that run
    __kk_imj_l0="#P$__KK_SEP$__kk_imj_w$__KK_SEP""000000000000$__KK_SEP$__kk_imw_tag$__KK_SEP$__kk_imk_home$__KK_SEP"
    __kk_imj_l0+="$__KK_SEP$__kk_im_mode$__KK_SEP${__kk_imw_fl:--}$__KK_SEP$__kk_imw_nonce$__KK_SEP$__kk_im_rh$__KK_SEP${#__kk_imk_files[@]}"
    for __kk_imj_x in "${__kk_imk_files[@]}"; do __kk_imj_l0+=$__KK_SEP$__kk_imj_x; done
    printf -v __kk_imj_l1 '__kk_img_key=%q __kk_img_nonce=%q' "$__kk_im_key" "$__kk_imw_nonce"
    kk._img__arr __kk_img_edges __kk_imk_edges;   __kk_imj_l2=$__kk_imj_s
    kk._img__arr __kk_img_reqf __kk_im_reqf;      __kk_imj_l2+=" $__kk_imj_s"
    printf -v __kk_imj_s '__kk_img_stamp=%q __kk_img_stime=%s' "$__kk_imk_stamp" "$__kk_imk_stime"; __kk_imj_l2+=" $__kk_imj_s"
    kk._img__arr __kk_img_units __kk_imk_units;   __kk_imj_l3=$__kk_imj_s
    kk._img__arr __kk_img_classes __kk_imk_cls;   __kk_imj_l3+=" $__kk_imj_s"
    kk._img__arr __kk_img_vars __kk_imk_nv;       __kk_imj_l3+=" $__kk_imj_s"
    kk._img__arr __kk_img_fns __kk_imk_nf;        __kk_imj_l3+=" $__kk_imj_s"
    kk._img__arr __kk_img_ro __kk_imk_ro;         __kk_imj_l3+=" $__kk_imj_s __kk_img_wtime=$__kk_imj_w"
    kk._img__arr __kk_img_base __kk_imk_base;     __kk_imj_l4=$__kk_imj_s
    # line 1 carries the byte length of the lines after it (all ASCII but the
    # paths of the plain line, measured in bytes under LC_ALL=C), so a start
    # reads them with ONE read -N (a line-by-line read of ~150 KB costs ~0.4 s
    # on the MSYS-family runtimes)
    __kk_imj_s=$__kk_imj_l0$'\n'$__kk_imj_l1$'\n'$__kk_imj_l2$'\n'$__kk_imj_l3$'\n'$__kk_imj_l4$'\n'
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
                if (( __kk_imj_s )); then kk._img__vals "$__kk_imj_x" "$__kk_imj_at"; fi
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
    # (a key that is not plain: kk._img__vals' loop form)
    __kk_imj_ch=()
    for (( __kk_imj_p = 0; __kk_imj_p < ${#__kk_imk_reg[@]}; __kk_imj_p += 3 )); do
        printf -v __kk_imj_c '%q' "${__kk_imk_reg[__kk_imj_p+1]}"
        if [[ $__kk_imj_c == *[!$__KK_IMG_PLAIN]* ]] && kk._img__loopkey "${__kk_imk_reg[__kk_imj_p+1]}"; then
            printf -v __kk_imj_s '%q' "${__kk_imk_reg[__kk_imj_p+2]}"
            kk._img__loop "${__kk_imk_reg[__kk_imj_p]}" "$__kk_imj_c" "$__kk_imj_s"
        else
            __kk_imj_ch+=("${__kk_imk_reg[@]:__kk_imj_p:3}")
        fi
    done
    if (( ${#__kk_imj_ch[@]} )); then
        printf -v __kk_imj_s '%s[%q]=%q\n' "${__kk_imj_ch[@]}"
        __kk_imw_P+=("$__kk_imj_s")
    fi
    if [[ $__KK_UNIT_USED != "$__kk_imw_used" ]]; then
        printf -v __kk_imj_s '__KK_UNIT_USED=%q\n' "$__KK_UNIT_USED"
        __kk_imw_P+=("$__kk_imj_s")
    fi
    kk._img__arr __kk_img_hooks __kk_imk_hooks
    __kk_imw_P+=("$__kk_imj_s"$'\n'"__kk_img_end=$__kk_imw_nonce"$'\n')
    # the size field: the byte count of the whole text (pruning's 256 MB cap)
    for __kk_imj_x in "${__kk_imw_P[@]}"; do __kk_imj_n=$(( __kk_imj_n + ${#__kk_imj_x} )); done
    printf -v __kk_imj_s '%012d' "$__kk_imj_n"
    __kk_imw_P[0]=${__kk_imw_P[0]/"$__KK_SEP$__kk_imj_w$__KK_SEP"000000000000"$__KK_SEP"/"$__KK_SEP$__kk_imj_w$__KK_SEP$__kk_imj_s$__KK_SEP"}
    return 0
}

# ---------------------------------------------------------------------------
# Pruning (§7.4) and --forget

# kk._img_prune — after a write, the files of the image folder to remove,
# appended to the caller's rm list __kk_ima_f (kk._img__after removes all
# with ONE rm). Images (their plain header line read: two `read`s each, no
# eval) whose KBOOL_HOME no longer exists (only images of this runtime: the
# folder may be shared by several, whose spellings differ), older than 30
# days, unreadable; then the oldest beyond 8 per (request, prior set), beyond
# 16 per request name, beyond __KK_IMG_MAXN (64) or __KK_IMG_MAXB bytes (256
# MB) in the folder — never the image just written; the reference files and
# holds of removed images; holds older than an hour; temps of this runtime
# whose pid is gone (kill -0). __KK_IMG_MAXN / __KK_IMG_MAXB are for tests.
kk._img_prune() {
    local __kk_imp_x __kk_imp_n __kk_imp_l1 __kk_imp_l2 __kk_imp_i __kk_imp_o __kk_imp_t __kk_imp_r \
          __kk_imp_now=$EPOCHSECONDS __kk_imp_tot=0 __kk_imp_maxn=${__KK_IMG_MAXN:-64} __kk_imp_maxb=${__KK_IMG_MAXB:-268435456}
    local -a __kk_imp_e=() __kk_imp_p=() __kk_imp_w=() __kk_imp_s=() __kk_imp_g=() __kk_imp_q=() __kk_imp_a=() \
          __kk_imp_d=() __kk_imp_refs=() __kk_im_pl=() __kk_img_files=()
    local -A __kk_imp_gone=() __kk_imp_nc=()
    [[ -n $__kk_imp_maxn && $__kk_imp_maxn != *[!0-9]* ]] || __kk_imp_maxn=64
    [[ -n $__kk_imp_maxb && $__kk_imp_maxb != *[!0-9]* ]] || __kk_imp_maxb=268435456
    kk._img_glob "$__kk_im_dir" __kk_imp_e
    for __kk_imp_x in "${__kk_imp_e[@]}"; do
        __kk_imp_n=${__kk_imp_x##*/}
        [[ -f $__kk_imp_x && ! -L $__kk_imp_x ]] || continue
        case $__kk_imp_n in
            *.tmp.*)
                __kk_imp_r=${__kk_imp_n#*.tmp.}
                __kk_imp_t=${__kk_imp_r%%.*}
                __kk_imp_r=${__kk_imp_r#*.}
                __kk_imp_r=${__kk_imp_r%%.*}
                [[ $__kk_imp_t == "$__kk_imw_tag" && -n $__kk_imp_r && $__kk_imp_r != *[!0-9]* \
                   && $__kk_imp_x != "$__kk_imw_t".* ]] || continue
                kill -0 "$__kk_imp_r" 2>/dev/null || __kk_ima_f+=("$__kk_imp_x") ;;
            *.img)
                __kk_imp_l1="" __kk_imp_l2=""
                { IFS= read -r __kk_imp_l1 && IFS= read -r __kk_imp_l2; } < "$__kk_imp_x" 2>/dev/null
                if [[ $__kk_imp_l1 != "# kbool image v1 "* ]] || ! kk._image_pline "$__kk_imp_l2" \
                   || [[ ${__kk_im_pl[1]} == *[!0-9]* || -z ${__kk_im_pl[1]} ]]; then
                    if [[ $__kk_imp_x != "$__kk_im_img" ]]; then __kk_ima_f+=("$__kk_imp_x"); __kk_imp_gone[$__kk_imp_x]=1; fi
                    continue
                fi
                if [[ $__kk_imp_x != "$__kk_im_img" ]]; then
                    if [[ ${__kk_im_pl[2]} == "$__kk_imw_tag" && ! -d ${__kk_im_pl[3]} ]] \
                       || (( __kk_imp_now - 10#${__kk_im_pl[0]} > 2592000 )); then
                        __kk_ima_f+=("$__kk_imp_x"); __kk_imp_gone[$__kk_imp_x]=1
                        continue
                    fi
                fi
                __kk_imp_r=${__kk_imp_n%-????????.img}
                __kk_imp_p+=("$__kk_imp_x")
                __kk_imp_w+=("$(( 10#${__kk_im_pl[0]} ))")
                __kk_imp_s+=("$(( 10#${__kk_im_pl[1]} ))")
                __kk_imp_q+=("$__kk_imp_r")
                __kk_imp_nc[$__kk_imp_x]=${__kk_im_pl[7]}
                __kk_imp_g+=("$__kk_imp_r$__KK_SEP${__kk_im_pl[4]}")
                __kk_imp_a+=(all)
                __kk_imp_d+=(0) ;;
            *.hold)
                kk._image_hfile "$__kk_imp_x" || __kk_ima_f+=("$__kk_imp_x") ;;
            *.ref)
                __kk_imp_refs+=("$__kk_imp_x") ;;
        esac
    done
    kk._img__cap __kk_imp_g 8
    kk._img__cap __kk_imp_q 16
    kk._img__cap __kk_imp_a "$__kk_imp_maxn"
    for (( __kk_imp_i = 0; __kk_imp_i < ${#__kk_imp_p[@]}; __kk_imp_i++ )); do
        (( __kk_imp_d[__kk_imp_i] )) || __kk_imp_tot=$(( __kk_imp_tot + __kk_imp_s[__kk_imp_i] ))
    done
    while (( __kk_imp_tot > __kk_imp_maxb )); do
        __kk_imp_o=-1
        for (( __kk_imp_i = 0; __kk_imp_i < ${#__kk_imp_p[@]}; __kk_imp_i++ )); do
            (( ! __kk_imp_d[__kk_imp_i] )) && [[ ${__kk_imp_p[__kk_imp_i]} != "$__kk_im_img" ]] || continue
            (( __kk_imp_o < 0 || __kk_imp_w[__kk_imp_i] < __kk_imp_w[__kk_imp_o] )) && __kk_imp_o=$__kk_imp_i
        done
        (( __kk_imp_o >= 0 )) || break
        __kk_imp_d[__kk_imp_o]=1
        __kk_imp_tot=$(( __kk_imp_tot - __kk_imp_s[__kk_imp_o] ))
    done
    for (( __kk_imp_i = 0; __kk_imp_i < ${#__kk_imp_p[@]}; __kk_imp_i++ )); do
        (( __kk_imp_d[__kk_imp_i] )) || continue
        __kk_ima_f+=("${__kk_imp_p[__kk_imp_i]}")
        __kk_imp_gone[${__kk_imp_p[__kk_imp_i]}]=1
    done
    for __kk_imp_x in "${!__kk_imp_gone[@]}"; do
        __kk_imp_x=${__kk_imp_x%.img}.hold
        [[ ! -f $__kk_imp_x ]] || __kk_ima_f+=("$__kk_imp_x")
    done
    for __kk_imp_x in "${__kk_imp_refs[@]}"; do
        __kk_imp_r=${__kk_imp_x%.ref}                   # NAME.NONCE.ref: kept only as its image's own
        __kk_imp_t=${__kk_imp_r##*.}
        __kk_imp_n=${__kk_imp_r%.*}.img
        [[ ${__kk_imp_r##*/} == *.* && -f $__kk_imp_n && -z ${__kk_imp_gone[$__kk_imp_n]-} && ${__kk_imp_nc[$__kk_imp_n]-} == "$__kk_imp_t" ]] || __kk_ima_f+=("$__kk_imp_x")
    done
    return 0
}

# kk._img__cap KEYS CAP — kk._img_prune's caps: mark (__kk_imp_d) the oldest
# images (__kk_imp_w) of every group of equal KEYS (an array parallel to
# __kk_imp_p) beyond CAP members; never the image just written.
kk._img__cap() {
    local -n __kk_imc_k=$1
    local -A __kk_imc_n=()
    local __kk_imc_i __kk_imc_o __kk_imc_g __kk_imc_c
    for (( __kk_imc_i = 0; __kk_imc_i < ${#__kk_imp_p[@]}; __kk_imc_i++ )); do
        (( __kk_imp_d[__kk_imc_i] )) && continue
        __kk_imc_g=${__kk_imc_k[__kk_imc_i]}
        __kk_imc_n[$__kk_imc_g]=$(( ${__kk_imc_n[$__kk_imc_g]:-0} + 1 ))
    done
    for __kk_imc_g in "${!__kk_imc_n[@]}"; do
        __kk_imc_c=${__kk_imc_n[$__kk_imc_g]}
        while (( __kk_imc_c > $2 )); do
            __kk_imc_o=-1
            for (( __kk_imc_i = 0; __kk_imc_i < ${#__kk_imp_p[@]}; __kk_imc_i++ )); do
                (( ! __kk_imp_d[__kk_imc_i] )) && [[ ${__kk_imc_k[__kk_imc_i]} == "$__kk_imc_g" \
                    && ${__kk_imp_p[__kk_imc_i]} != "$__kk_im_img" ]] || continue
                (( __kk_imc_o < 0 || __kk_imp_w[__kk_imc_i] < __kk_imp_w[__kk_imc_o] )) && __kk_imc_o=$__kk_imc_i
            done
            (( __kk_imc_o >= 0 )) || break
            __kk_imp_d[__kk_imc_o]=1
            __kk_imc_c=$(( __kk_imc_c - 1 ))
        done
    done
    return 0
}

# kk._img__forgetmine IMG — rc 0 when IMG exists and its plain line's request
# hash is this request's (__kk_im_rh). Two reads, no eval.
kk._img__forgetmine() {
    local __kk_imy_1="" __kk_imy_2=""
    local -a __kk_im_pl=() __kk_img_files=()
    [[ -f $1 ]] || return 1
    { IFS= read -r __kk_imy_1 && IFS= read -r __kk_imy_2; } < "$1" 2>/dev/null
    kk._image_pline "$__kk_imy_2" && [[ ${__kk_im_pl[8]} == "$__kk_im_rh" ]]
}

# kk._img_forget — kk.image --forget UNIT...: remove this request's images,
# reference files and holds of every key from the image folder (the request
# name of kk._image_reqname; the folder of kk._image_dir, only when trusted),
# and its temps of this runtime whose pid is gone. ONE rm. rc 0.
kk._img_forget() {
    local - __kk_imy_x __kk_imy_n __kk_imy_p __kk_imy_t __kk_imy_tag="" __kk_imy_nc=0 \
          __kk_imy_h='[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'
    local -a __kk_imy_e=() __kk_imy_f=()
    set +eu
    if [[ -n $__kk_im_bad ]]; then kk._image_dbg "--forget: untrusted folder: $__kk_im_bad; nothing deleted"; return 0; fi
    if [[ ! -d $__kk_im_dir ]]; then kk._image_dbg "--forget: no image folder $__kk_im_dir"; return 0; fi
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_imy_nc=1; shopt -u nocasematch; fi
    kk._image_hash "$BASH" __kk_imy_tag
    kk._img_glob "$__kk_im_dir" __kk_imy_e
    for __kk_imy_x in "${__kk_imy_e[@]}"; do
        __kk_imy_n=${__kk_imy_x##*/}
        [[ $__kk_imy_n == "$__kk_im_rn"-* ]] || continue
        __kk_imy_p=${__kk_imy_n#"$__kk_im_rn"-}
        # (the pattern of 8 hex digits, then .img / .NONCE.ref / .hold / .tmp.).
        # A request name cut at 64 characters may be another request's: then
        # an image goes only when its plain line's request hash is this
        # request's, and a .ref / .hold only next to such an image (critic L8)
        if [[ $__kk_imy_p == $__kk_imy_h.img ]]; then
            if (( ${#__kk_im_rn} >= 64 )) && ! kk._img__forgetmine "$__kk_imy_x"; then continue; fi
            __kk_imy_f+=("$__kk_imy_x")
        elif [[ $__kk_imy_p == $__kk_imy_h.*ref || $__kk_imy_p == $__kk_imy_h.hold ]]; then
            if (( ${#__kk_im_rn} >= 64 )) && ! kk._img__forgetmine "$__kk_im_dir/$__kk_im_rn-${__kk_imy_p:0:8}.img"; then continue; fi
            __kk_imy_f+=("$__kk_imy_x")
        elif [[ $__kk_imy_p == $__kk_imy_h.tmp.* ]]; then
            __kk_imy_p=${__kk_imy_p#*.tmp.}
            __kk_imy_t=${__kk_imy_p%%.*}
            __kk_imy_p=${__kk_imy_p#*.}
            __kk_imy_p=${__kk_imy_p%%.*}
            [[ $__kk_imy_t == "$__kk_imy_tag" && -n $__kk_imy_p && $__kk_imy_p != *[!0-9]* ]] || continue
            kill -0 "$__kk_imy_p" 2>/dev/null || __kk_imy_f+=("$__kk_imy_x")
        fi
    done
    if (( __kk_imy_nc )); then shopt -s nocasematch; fi
    if (( ${#__kk_imy_f[@]} )); then command rm -f -- "${__kk_imy_f[@]}" 2>/dev/null; fi
    kk._image_dbg "--forget: ${#__kk_imy_f[@]} file(s) of '$__kk_im_rn' removed from $__kk_im_dir"
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
