#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%ktool.sh}../kbool.sh" || return
kk.unit ktool || return $__kk_unit_rc
# ktool.sh — kkore unit: the GNU tool resolver (launch L3.3, owner decision
# OG1 = A, 2026-10-27). NOT a system unit: kbool.sh does not load it, the core
# stays tool-free; a unit that drives a GNU tool says `kk.uses ktool` (the
# system path $KBOOL_HOME/kkore finds it).
#
#   ktool.gnu FAMILY     RESULT = the absolute path of a GNU build of FAMILY
#                        rc 0 found; rc 1 none (RESULT=''); rc 2 unknown FAMILY
#                        (or ktool is not loaded in this shell)
#   ktool.lastError      RESULT = why the last failing ktool.gnu failed
#
# FAMILY is one of `sed awk grep find head tail` (the tables below; a new
# family is one row in each). For each family the candidates are, in order:
#   1. the override KCL_GNU_<FAMILY> (KCL_GNU_SED, KCL_GNU_AWK, ...) when it is
#      set and non-empty — then it is the ONLY candidate: a path (a word with a
#      `/`; a relative one is taken against $PWD) must be an executable file, a
#      name is searched on PATH; a wrong override is refused, never skipped
#      (the thttpserver KCL_NC rule);
#   2. the g-name(s) (gsed, gawk, ggrep, gfind, ghead, gtail) in every PATH
#      folder, in PATH order;
#   3. the plain name (sed, awk, ...) in every PATH folder, in PATH order.
# Only ABSOLUTE PATH folders are searched: an empty entry, `.` and every
# relative folder are skipped (no cwd hijack — bash would run `./gsed` from an
# untrusted cwd for `PATH=/usr/bin:`, this resolver never answers it). Folders
# are compared without trailing slashes and each is searched once.
#
# A candidate is accepted only when its `--version` banner carries the
# family's GNU identity (__KTOOL_ID). The banner is the first non-blank line of
# the tool's STDOUT (leading blanks dropped); only when stdout is all blank,
# the same of its stderr (a GNU grep that warns about GREP_OPTIONS on stderr
# first is still GNU grep).
# Measured banners (launch L3.3): `sed (GNU sed) 4.9` — `/usr/bin/sed (GNU
# sed) 4.9` when run by its path on msys, `gsed (GNU sed) 4.10` on FreeBSD;
# `GNU sed version 4.2.2` (sed 4.2.x: RHEL/CentOS 7, SLES 12); `GNU Awk 5.4.1,
# API 4.1, …`; `grep (GNU grep) 3.0`, `ggrep (GNU grep) 3.12`; `find (GNU
# findutils) 4.11.0` (also as gfind); `head (GNU coreutils) 9.9` (also as
# ghead). Refused: busybox (`This is not GNU sed version 4.0`, `awk:
# unrecognized option: -`), BSD (`sed: illegal option -- -`, `grep (BSD grep,
# GNU compatible) 2.6.0`, `awk version 20250804`), uutils coreutils (`head
# (uutils coreutils) 0.2.2`, Ubuntu 25.10+; owner decision pending — the hint
# says so, and accepting it is one commented line below the tables).
#
# Cost. One run of each candidate per process (its banner is cached in
# __KTOOL_BANNER; a cold probe costs two shell forks — the second execs the
# tool — so stdout and stderr come back apart), and a family's answer is cached in __KTOOL_RES under a key made
# of the override's value and $PATH (+ $PWD for a relative override): while
# they do not change, a repeated call is a few string compares — no fork, no
# PATH walk. A changed PATH or override re-resolves (without running a tool
# already probed). A failure is cached the same way.
#
# Subshells. The caches are plain globals: a `( … )` / `$( … )` child inherits
# a warm cache (no fork there), but what a child resolves dies with it. Call
# `ktool.gnu FAMILY` once in the caller's own shell (RESULT mode) to fill the
# cache there; `p=$(ktool.gnu sed && printf '%s' "$RESULT")` works, and forks
# again in the next child when the parent never resolved.
#
# Contract: nothing is ever printed (the caller reports, e.g. through
# kk.debug, and its tests SKIP with the text of ktool.lastError); set -u and
# set -e clean; every global is __KTOOL_*, every local __ktool_*. No state is
# taken from the environment: the tables and caches are associative arrays of
# THIS shell (bash never exports an array), declared fresh at load unless they
# already are (a `kk.unit --forget ktool` + re-source keeps the caches), and
# ktool.gnu refuses to subscript them in a shell where they are not (an
# `export -f` child): on a non-associative table a path-derived key would be
# evaluated as arithmetic.

# ktool._own NAME — rc 0 when NAME is an associative array of this shell.
ktool._own() {
    local -                         # nounset off for this frame only
    set +u
    local -n __ktool_r=$1
    [[ ${__ktool_r@a} == *A* ]]
}

# ---- the family table (re-declared at every load) -----------------------------
# __KTOOL_FAMS the families, in the order a refusal lists them
# __KTOOL_ENV  the override variable (absent: the family has no override);
#              spelled out, not `${f^^}`, which is locale-dependent (tr_TR: İ)
# __KTOOL_GN   the g-name(s), space separated ('' or absent: none)
# __KTOOL_ID   the GNU identity: `|`-separated fragments, one must be in the
#              banner; a fragment starting with `^` must START the banner
# __KTOOL_PKG  the package names: FreeBSD pkg | macOS brew | apk/apt/dnf
#              (absent: the hint only says `install GNU FAMILY`)
unset -v __KTOOL_FAMS __KTOOL_ENV __KTOOL_GN __KTOOL_ID __KTOOL_PKG
declare -ga __KTOOL_FAMS=( sed awk grep find head tail )
declare -gA __KTOOL_ENV=(
    [sed]=KCL_GNU_SED  [awk]=KCL_GNU_AWK  [grep]=KCL_GNU_GREP
    [find]=KCL_GNU_FIND  [head]=KCL_GNU_HEAD  [tail]=KCL_GNU_TAIL
)
declare -gA __KTOOL_GN=(  [sed]=gsed  [awk]=gawk  [grep]=ggrep  [find]=gfind  [head]=ghead  [tail]=gtail )
declare -gA __KTOOL_ID=(
    [sed]='(GNU sed) |^GNU sed version '  [awk]='GNU Awk '
    [grep]='(GNU grep) '               [find]='find (GNU findutils) '
    [head]='head (GNU coreutils) '     [tail]='tail (GNU coreutils) '
)
# uutils coreutils (Ubuntu 25.10+) is REFUSED until the owner decides; to accept it, uncomment:
# __KTOOL_ID[head]+='|head (uutils coreutils) '; __KTOOL_ID[tail]+='|tail (uutils coreutils) '
declare -gA __KTOOL_PKG=(
    [sed]='gsed|gnu-sed|sed'           [awk]='gawk|gawk|gawk'
    [grep]='gnugrep|grep|grep'         [find]='findutils|findutils|findutils'
    [head]='coreutils|coreutils|coreutils'  [tail]='coreutils|coreutils|coreutils'
)

# ---- the caches (kept across a `kk.unit --forget ktool` + re-source) ---------
# __KTOOL_BANNER [abs path] = its banner (sanitised, see ktool._banner)
# __KTOOL_RES    [family]   = the resolved path, '' = none
# __KTOOL_KEY    [family]   = override + PATH (+ PWD) the answer belongs to
# __KTOOL_MSG    [family]   = the failure message, '' on success
# __KTOOL_ERR               = the last failure message
if ! { ktool._own __KTOOL_BANNER && ktool._own __KTOOL_RES && ktool._own __KTOOL_KEY \
       && ktool._own __KTOOL_MSG; }; then
    unset -v __KTOOL_BANNER __KTOOL_RES __KTOOL_KEY __KTOOL_MSG __KTOOL_ERR
    declare -gA __KTOOL_BANNER=() __KTOOL_RES=() __KTOOL_KEY=() __KTOOL_MSG=()
    declare -g __KTOOL_ERR=''
fi

# ktool._san TEXT — the caller's __ktool_s = TEXT fit for a message: CRs
# dropped, other control characters as `?`, at most MAX (default 200)
# characters (`...` marks the cut). Banners, PATH folders and the override's
# value all pass through it.
ktool._san() {
    local __ktool_m=${2:-200}
    __ktool_s=${1//$'\r'/}
    __ktool_s=${__ktool_s//[[:cntrl:]]/?}
    if (( ${#__ktool_s} > __ktool_m )); then
        __ktool_s="${__ktool_s:0:__ktool_m-3}..."
    fi
}

# ktool._banner PATH — fill __KTOOL_BANNER[PATH] once per process. The tool
# runs once, with LC_ALL=C and stdin from /dev/null (no candidate waits for
# input; one that never exits, or leaves a child holding its stdout, blocks
# the probe — there is no timeout, by design). Two shell forks: the outer
# `$( )` subshell, and the inner one, which `exec`s the tool. The tool's
# stdout goes straight to the outer capture, its stderr to the inner one; the
# outer subshell appends that stderr and its length as 10 digits, so the two
# come apart by plain slicing — LINEAR in the output's size (a `${x%%SEP*}`
# split is quadratic in bash: 22 s on 1 MB), and correct whatever bytes the
# tool prints. The slicing runs under a function-local LC_ALL=C (bytes, the
# same unit `${#}` counted in the subshell). bash's own "ignored null byte"
# warning (a NUL in either stream) is sent to /dev/null, never to the caller.
# The banner is the first line of stdout that is not blank, its leading
# blanks dropped — or, when stdout is all blank, the same of stderr; only the
# first 4096 bytes of either stream are looked at (bounds every pattern
# operation below). Sanitised by ktool._san, uncut (the identity is matched on
# the whole line; a refusal shows 80 characters).
ktool._banner() {
    local __ktool_p=$1 __ktool_x __ktool_o __ktool_e __ktool_n __ktool_s
    if [[ -n ${__KTOOL_BANNER[$__ktool_p]+x} ]]; then
        return 0
    fi
    local LC_ALL=C
    { __ktool_x=$(
        exec 3>&1
        __ktool_e=$(LC_ALL=C exec "$__ktool_p" --version </dev/null 2>&1 >&3 3>&-) || :
        printf '%s%010d' "$__ktool_e" "${#__ktool_e}"
      ); } 2>/dev/null || :
    __ktool_n=${__ktool_x: -10}
    __ktool_o='' __ktool_e=''
    if [[ ${#__ktool_n} == 10 && $__ktool_n != *[!0-9]* ]]; then
        __ktool_n=$(( 10#$__ktool_n ))
        if (( __ktool_n <= ${#__ktool_x} - 10 )); then
            __ktool_e=${__ktool_x:${#__ktool_x}-10-__ktool_n:__ktool_n}
            __ktool_o=${__ktool_x:0:${#__ktool_x}-10-__ktool_n}
        fi
    fi
    __ktool_o=${__ktool_o:0:4096}
    if [[ $__ktool_o != *[![:space:]]* ]]; then
        __ktool_o=${__ktool_e:0:4096}
    fi
    __ktool_o=${__ktool_o//$'\r'/}
    __ktool_o=${__ktool_o#"${__ktool_o%%[![:space:]]*}"}
    ktool._san "${__ktool_o%%$'\n'*}" 4096
    __KTOOL_BANNER[$__ktool_p]=$__ktool_s
}

# ktool._try PATH — rc 0 when PATH is a GNU build of the caller's family
# (__ktool_f), else rc 1 with the reason appended to the caller's __ktool_why
# (and the caller's __ktool_uu set when a head/tail banner is uutils coreutils').
ktool._try() {
    local __ktool_p=$1 __ktool_b __ktool_l __ktool_a __ktool_s
    ktool._banner "$__ktool_p"
    __ktool_b=${__KTOOL_BANNER[$__ktool_p]}
    __ktool_l="${__KTOOL_ID[$__ktool_f]}|"
    while [[ -n $__ktool_l ]]; do
        __ktool_a=${__ktool_l%%|*}
        __ktool_l=${__ktool_l#*|}
        if [[ -z $__ktool_a ]]; then
            continue
        elif [[ $__ktool_a == ^* ]]; then
            if [[ $__ktool_b == "${__ktool_a#^}"* ]]; then
                return 0
            fi
        elif [[ $__ktool_b == *"$__ktool_a"* ]]; then
            return 0
        fi
    done
    if [[ ( $__ktool_f == head || $__ktool_f == tail ) && $__ktool_b == *"(uutils coreutils)"* ]]; then
        __ktool_uu=1
    fi
    ktool._san "$__ktool_b" 80
    __ktool_b=$__ktool_s
    ktool._san "$__ktool_p"
    __ktool_why+="; $__ktool_s is not GNU $__ktool_f (--version: \"${__ktool_b:-no answer}\")"
    return 1
}

# ktool._walk NAME — try NAME in every absolute PATH folder, in order, each
# folder once (trailing slashes dropped). rc 0 with __ktool_c = the first GNU
# one; rc 1 otherwise, the misses added to __ktool_why (`NAME not on PATH` when
# no folder has an executable regular file NAME).
ktool._walk() {
    local __ktool_n=$1 __ktool_r="$PATH:" __ktool_d __ktool_q __ktool_seen=0 __ktool_s
    local -A __ktool_ds=()
    while [[ -n $__ktool_r ]]; do
        __ktool_d=${__ktool_r%%:*}
        __ktool_r=${__ktool_r#*:}
        while [[ $__ktool_d == ?*/ ]]; do
            __ktool_d=${__ktool_d%/}
        done
        if [[ $__ktool_d != /* || -n ${__ktool_ds[$__ktool_d]+x} ]]; then
            continue                    # '', '.', relative: never; a repeat: once
        fi
        __ktool_ds[$__ktool_d]=1
        __ktool_q=${__ktool_d%/}/$__ktool_n
        if [[ -f $__ktool_q && -x $__ktool_q ]]; then
            __ktool_seen=1
            if ktool._try "$__ktool_q"; then
                __ktool_c=$__ktool_q
                return 0
            fi
        fi
    done
    if (( ! __ktool_seen )); then
        ktool._san "$__ktool_n"
        __ktool_why+="; $__ktool_s not on PATH"
    fi
    return 1
}

# ktool._hint — the caller's __ktool_hint = how to get GNU FAMILY here
# ($OSTYPE and /etc/alpine-release, no fork). After a uutils refusal (the
# caller's __ktool_uu) it says that instead.
ktool._hint() {
    local __ktool_pk=${__KTOOL_PKG[$__ktool_f]-} __ktool_pf __ktool_pb __ktool_pl
    if [[ $__ktool_uu == 1 ]]; then
        __ktool_hint="uutils coreutils is not accepted (only GNU coreutils is): install GNU coreutils (Ubuntu: the coreutils-from-gnu package)"
        return 0
    fi
    if [[ $__ktool_pk != *'|'*'|'* ]]; then
        __ktool_hint="install GNU $__ktool_f"
        return 0
    fi
    __ktool_pf=${__ktool_pk%%|*}
    __ktool_pl=${__ktool_pk##*|}
    __ktool_pb=${__ktool_pk#*|}
    __ktool_pb=${__ktool_pb%%|*}
    case ${OSTYPE:-} in
        freebsd*)      __ktool_hint="FreeBSD: pkg install $__ktool_pf" ;;
        darwin*)       __ktool_hint="macOS: brew install $__ktool_pb" ;;
        linux-musl*)
            if [[ -f /etc/alpine-release ]]; then
                __ktool_hint="Alpine: apk add $__ktool_pl"
            else
                __ktool_hint="install the GNU $__ktool_pl package"
            fi
            ;;
        linux*)        __ktool_hint="Debian/Ubuntu: apt install $__ktool_pl; Fedora: dnf install $__ktool_pl" ;;
        cygwin*|msys*) __ktool_hint="Git for Windows and MSYS2 ship GNU $__ktool_f in /usr/bin: put it first on PATH" ;;
        *)             __ktool_hint="FreeBSD: pkg install $__ktool_pf; macOS: brew install $__ktool_pb; Alpine: apk add $__ktool_pl; Debian/Ubuntu: apt install $__ktool_pl" ;;
    esac
}

# ktool.gnu FAMILY — see the header. RESULT = the absolute path (rc 0) or ''
# (rc 1: no GNU build; rc 2: FAMILY is not in the table, or ktool's tables
# are not this shell's). On rc 1 / 2 the reason is ktool.lastError's: `no GNU
# sed: gsed not on PATH; /usr/bin/sed is not GNU sed (--version: "sed: illegal
# option -- -"); FreeBSD: pkg install gsed`.
ktool.gnu() {   # FAMILY
    local __ktool_f=${1-} __ktool_v __ktool_o __ktool_k __ktool_c='' __ktool_why='' __ktool_hint \
          __ktool_g __ktool_uu=0 __ktool_s
    local IFS=' '                      # the g-name list is split below
    RESULT=''
    if [[ ${__KTOOL_ID[@]@a} != A* ]]; then
        __KTOOL_ERR="ktool.gnu: ktool is not loaded in this shell (kk.uses ktool)"
        return 2
    fi
    case $__ktool_f in
        ''|*[!a-z0-9_]*) __ktool_f='' ;;
    esac
    if [[ -z $__ktool_f || -z ${__KTOOL_ID[$__ktool_f]+x} ]]; then
        ktool._san "${1-}"
        __KTOOL_ERR="ktool.gnu: unknown tool family '$__ktool_s' (known: ${__KTOOL_FAMS[*]})"
        return 2
    fi
    __ktool_v=${__KTOOL_ENV[$__ktool_f]-}
    __ktool_o=''
    if [[ -n $__ktool_v ]]; then
        __ktool_o=${!__ktool_v-}
    fi
    __ktool_k=${#__ktool_o}:$__ktool_o:$PATH
    if [[ $__ktool_o == */* && $__ktool_o != /* && $__ktool_o != [A-Za-z]:* ]]; then
        __ktool_k+=:$PWD                 # a relative override depends on the cwd
    fi
    if [[ -n ${__KTOOL_KEY[$__ktool_f]+x} && ${__KTOOL_KEY[$__ktool_f]} == "$__ktool_k" ]]; then
        RESULT=${__KTOOL_RES[$__ktool_f]}
        if [[ -n $RESULT ]]; then
            return 0
        fi
        __KTOOL_ERR=${__KTOOL_MSG[$__ktool_f]}
        return 1
    fi
    if [[ -n $__ktool_o ]]; then
        if [[ $__ktool_o == */* ]]; then
            __ktool_c=$__ktool_o
            if [[ $__ktool_c != /* && $__ktool_c != [A-Za-z]:* ]]; then
                __ktool_c=$PWD/$__ktool_c
            fi
            if [[ ! -f $__ktool_c || ! -x $__ktool_c ]]; then
                __ktool_why="; is not an executable file"
                __ktool_c=''
            elif ! ktool._try "$__ktool_c"; then
                __ktool_c=''
            fi
        elif ! ktool._walk "$__ktool_o"; then
            __ktool_c=''
        fi
        if [[ -z $__ktool_c ]]; then
            ktool._san "$__ktool_o"
            if [[ $__ktool_why == "; is not an executable file" ]]; then
                __ktool_why="; $__ktool_v='$__ktool_s' is not an executable file"
            else
                __ktool_why="; $__ktool_v='$__ktool_s': ${__ktool_why#; }"
            fi
        fi
    else
        for __ktool_g in ${__KTOOL_GN[$__ktool_f]-} "$__ktool_f"; do
            if ktool._walk "$__ktool_g"; then
                break
            fi
            __ktool_c=''
        done
    fi
    __KTOOL_KEY[$__ktool_f]=$__ktool_k
    __KTOOL_RES[$__ktool_f]=$__ktool_c
    if [[ -n $__ktool_c ]]; then
        __KTOOL_MSG[$__ktool_f]=''
        RESULT=$__ktool_c
        return 0
    fi
    ktool._hint
    __KTOOL_MSG[$__ktool_f]="no GNU $__ktool_f: ${__ktool_why#; }; $__ktool_hint"
    __KTOOL_ERR=${__KTOOL_MSG[$__ktool_f]}
    return 1
}

# ktool.lastError — RESULT = the reason of the last ktool.gnu that failed
# (rc 1 or 2) in this shell; '' when none failed yet. rc 0.
ktool.lastError() {
    RESULT=$__KTOOL_ERR
    return 0
}
