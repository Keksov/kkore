#!/usr/bin/env bash
# GnuTools — the GNU tool resolver ktool.gnu (kkore/ktool.sh; launch L3.3,
# owner decision OG1 = A of 2026-10-27).
#
# The core is tool-free; the wrapper units (TSed, TAwk, TGrep, TFind, THead,
# TTail) need the GNU tool and find it by NAME: the override KCL_GNU_<FAMILY>,
# then the g-name (gsed, gawk, …), then the plain name — each accepted only
# when its `--version` banner says GNU. On FreeBSD with every GNU package
# installed the wrappers used to run BSD sed (L3_triage §2.1: 577 cases
# skipped on a box that had gsed, ggrep, gfind, ghead and gtail).
#
# Every case runs against FAKE tools in a private folder that is the whole
# PATH: tiny /bin/sh scripts that print a banner and log each call, so the
# test is the same on every platform and the log counts the tool runs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GnuTools" "$SCRIPT_DIR" "$@"

KBOOL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$KBOOL_ROOT/kbool.sh" || exit 2
source "$SCRIPT_DIR/unit_lint.sh"

TMPD="$(kt_fixture_tmpdir)"

# mkfake DIR NAME out|err TEXT — an executable NAME in DIR whose `--version`
# answer is TEXT on stdout (rc 0) or on stderr (rc 1); every call is one line
# `NAME ARGS` in DIR/log.
mkfake() {
    local d=$1 n=$2 how=$3 text=$4 body q="'"
    text=${text//$q/$q\\$q$q}                   # ' -> '\'' inside the single quotes
    mkdir -p "$d"
    if [[ $how == out ]]; then
        body="echo '$text'"
    else
        body="echo '$text' >&2; exit 1"
    fi
    printf '#!/bin/sh\necho "${0##*/} $*" >> "%s/log"\n%s\n' "$d" "$body" > "$d/$n"
    chmod +x "$d/$n"
}

# calls DIR NAME — how many times NAME in DIR ran
calls() {
    local n=0 l
    if [[ -f $1/log ]]; then
        while IFS= read -r l; do
            if [[ $l == "$2 "* ]]; then n=$(( n + 1 )); fi
        done < "$1/log"
    fi
    printf '%s' "$n"
}

# probe FAMILY — `rc=N|RESULT|` of one ktool.gnu call in THIS shell, with the
# ktool.lastError text after the last `|` when rc != 0; anything the call
# itself printed is appended as `|NOISE:…` (there must be none)
probe() {
    local rc=0 r
    ktool.gnu "$1" >"$TMPD/noise" 2>&1 || rc=$?
    r=$RESULT
    RESULT=''
    if (( rc != 0 )); then ktool.lastError; fi
    printf 'rc=%s|%s|%s' "$rc" "$r" "$RESULT"
    if [[ -s $TMPD/noise ]]; then printf '|NOISE:%s' "$(<"$TMPD/noise")"; fi
}

check() {   # GOT WANT
    if [[ "$1" == "$2" ]]; then kt_test_pass "$1"; else kt_test_fail "got [$1] want [$2]"; fi
}

BSD_SED='sed: illegal option -- -'
BB_SED='This is not GNU sed version 4.0'

# ---------------------------------------------------------------------------
kt_test_section "017: loading"

kt_test_start "kbool.sh alone does not load ktool (the core stays tool-free); kk.uses ktool finds kkore/ktool.sh by name"
got="$("$BASH" -c 'source "$1/kbool.sh" || exit 9; declare -F ktool.gnu >/dev/null && echo early; kk.uses ktool; echo "rc=$?"; declare -F ktool.gnu ktool.lastError; [[ ${__KK_UNITS[ktool]} -ef $1/kkore/ktool.sh ]] && echo same' _ "$KBOOL_ROOT" 2>&1)"
check "$got" $'rc=0\nktool.gnu\nktool.lastError\nsame'

kt_test_start "lint: ktool.sh has no file-scope 'local' and no 'declare' without -g (it loads inside kk.uses)"
lint="$(kk_unit_lint "$SCRIPT_DIR/../ktool.sh" 2>&1)"; lrc=$?
check "rc=$lrc ${lint//$'\n'/ | }" "rc=0 "

kk.uses ktool || { kt_test_start "kk.uses ktool"; kt_test_fail "rc=$?"; exit 1; }

# ---------------------------------------------------------------------------
kt_test_section "017: candidates and identities"

D=$TMPD/a; mkfake "$D" gsed out 'gsed (GNU sed) 4.10'; mkfake "$D" sed err "$BSD_SED"
kt_test_start "a GNU g-name wins over a BSD plain name; the plain name is never probed"
got="$(PATH=$D; probe sed; printf '|g=%s p=%s' "$(calls "$D" gsed)" "$(calls "$D" sed)")"
check "$got" "rc=0|$D/gsed||g=1 p=0"

D=$TMPD/b; mkfake "$D" sed err "$BSD_SED"
kt_test_start "a BSD plain name alone is refused: rc 1, RESULT '', the reason names every candidate and the FreeBSD package"
got="$(PATH=$D; OSTYPE=freebsd15.1; probe sed)"
check "$got" "rc=1||no GNU sed: gsed not on PATH; $D/sed is not GNU sed (--version: \"$BSD_SED\"); FreeBSD: pkg install gsed"

D=$TMPD/c; mkfake "$D" sed out "$BB_SED"
kt_test_start "busybox sed ('This is not GNU sed version 4.0') is refused; the musl hint names apk only where /etc/alpine-release exists"
got="$(PATH=$D; OSTYPE=linux-musl; probe sed)"
if [[ -f /etc/alpine-release ]]; then H="Alpine: apk add sed"; else H="install the GNU sed package"; fi
check "$got" "rc=1||no GNU sed: gsed not on PATH; $D/sed is not GNU sed (--version: \"$BB_SED\"); $H"

D=$TMPD/d; mkfake "$D" sed out 'sed (GNU sed) 4.9'
kt_test_start "a GNU plain name is accepted when there is no g-name"
got="$(PATH=$D; probe sed)"
check "$got" "rc=0|$D/sed|"

D=$TMPD/d2; mkfake "$D" sed out "$D/sed (GNU sed) 4.9"
kt_test_start "the msys banner form '/usr/bin/sed (GNU sed) 4.9' (sed run by its path) is GNU — also past 80 characters"
got="$(PATH=$D; probe sed)"
check "$got" "rc=0|$D/sed|"

D=$TMPD/e; mkdir -p "$D"
kt_test_start "none at all: rc 1, 'gsed not on PATH; sed not on PATH', macOS hint"
got="$(PATH=$D; OSTYPE=darwin24; probe sed)"
check "$got" "rc=1||no GNU sed: gsed not on PATH; sed not on PATH; macOS: brew install gnu-sed"

D1=$TMPD/f1; D2=$TMPD/f2; mkfake "$D1" sed err "$BSD_SED"; mkfake "$D2" sed out 'sed (GNU sed) 4.9'
kt_test_start "every PATH folder is searched: a BSD sed first, a GNU sed later on PATH -> the GNU one, each probed once"
got="$(PATH=$D1:$D2; probe sed; printf '|1=%s 2=%s' "$(calls "$D1" sed)" "$(calls "$D2" sed)")"
check "$got" "rc=0|$D2/sed||1=1 2=1"

D=$TMPD/g
mkfake "$D" gawk out 'GNU Awk 5.3.2, API 4.0, PMA Avon 8-g1, (GNU MPFR 4.2.1, GNU MP 6.3.0)'
mkfake "$D" ggrep out 'ggrep (GNU grep) 3.12'
mkfake "$D" gfind out 'find (GNU findutils) 4.11.0'
mkfake "$D" ghead out 'head (GNU coreutils) 9.9'
mkfake "$D" gtail out 'tail (GNU coreutils) 9.9'
mkfake "$D" awk out 'awk version 20250804'
mkfake "$D" grep out 'grep (BSD grep, GNU compatible) 2.6.0-FreeBSD'
kt_test_start "the FreeBSD clean-gnu banners: gawk, ggrep, gfind, ghead, gtail (as measured in kb-freebsd)"
got="$(PATH=$D; for f in awk grep find head tail; do probe $f; printf ' '; done)"
check "$got" "rc=0|$D/gawk| rc=0|$D/ggrep| rc=0|$D/gfind| rc=0|$D/ghead| rc=0|$D/gtail| "

D=$TMPD/h
mkfake "$D" awk out 'awk version 20250804'
mkfake "$D" grep out 'grep (BSD grep, GNU compatible) 2.6.0-FreeBSD'
mkfake "$D" find err 'find: illegal option -- -'
mkfake "$D" head err "head: unrecognized option \`--version'"
mkfake "$D" tail out 'head (GNU coreutils) 9.9'
kt_test_start "refused: BWK awk, BSD grep ('GNU compatible'), BSD find, BSD head, and a GNU head posing as tail"
got="$(PATH=$D; OSTYPE=freebsd15.1; for f in awk grep find head tail; do probe $f; printf '\n'; done)"
check "$got" "rc=1||no GNU awk: gawk not on PATH; $D/awk is not GNU awk (--version: \"awk version 20250804\"); FreeBSD: pkg install gawk
rc=1||no GNU grep: ggrep not on PATH; $D/grep is not GNU grep (--version: \"grep (BSD grep, GNU compatible) 2.6.0-FreeBSD\"); FreeBSD: pkg install gnugrep
rc=1||no GNU find: gfind not on PATH; $D/find is not GNU find (--version: \"find: illegal option -- -\"); FreeBSD: pkg install findutils
rc=1||no GNU head: ghead not on PATH; $D/head is not GNU head (--version: \"head: unrecognized option \`--version'\"); FreeBSD: pkg install coreutils
rc=1||no GNU tail: gtail not on PATH; $D/tail is not GNU tail (--version: \"head (GNU coreutils) 9.9\"); FreeBSD: pkg install coreutils"

# ---------------------------------------------------------------------------
kt_test_section "017: the override KCL_GNU_<FAMILY>"

D=$TMPD/o1; mkfake "$D" gsed out 'gsed (GNU sed) 4.10'
DB=$TMPD/o1bsd; mkfake "$DB" sed err "$BSD_SED"
kt_test_start "an override naming a non-GNU tool is refused with its reason; the GNU gsed on PATH is NOT consulted"
got="$(PATH=$D; KCL_GNU_SED=$DB/sed; OSTYPE=freebsd15.1; probe sed; printf '|g=%s' "$(calls "$D" gsed)")"
check "$got" "rc=1||no GNU sed: KCL_GNU_SED='$DB/sed': $DB/sed is not GNU sed (--version: \"$BSD_SED\"); FreeBSD: pkg install gsed|g=0"

kt_test_start "an override naming no executable file is refused"
got="$(PATH=$D; KCL_GNU_SED=$TMPD/nosuch/sed; OSTYPE=linux-gnu; probe sed)"
check "$got" "rc=1||no GNU sed: KCL_GNU_SED='$TMPD/nosuch/sed' is not an executable file; Debian/Ubuntu: apt install sed; Fedora: dnf install sed"

DG=$TMPD/o2; mkfake "$DG" mysed out 'mysed (GNU sed) 4.9'
kt_test_start "an override naming a GNU tool outside PATH wins over the g-name on PATH"
got="$(PATH=$D; KCL_GNU_SED=$DG/mysed; probe sed; printf '|g=%s' "$(calls "$D" gsed)")"
check "$got" "rc=0|$DG/mysed||g=0"

kt_test_start "a relative override is made absolute against \$PWD"
got="$(cd "$TMPD" && PATH=$D && KCL_GNU_SED=o2/mysed && probe sed)"
check "$got" "rc=0|$TMPD/o2/mysed|"

kt_test_start "an override WITHOUT a slash is a name searched on PATH (KCL_GNU_SED=mysed)"
got="$(PATH=$D:$DG; KCL_GNU_SED=mysed; probe sed)"
check "$got" "rc=0|$DG/mysed|"

kt_test_start "one override per family: KCL_GNU_SED, _AWK, _GREP, _FIND, _HEAD, _TAIL (each read for its own family only)"
got="$(PATH=$TMPD/e; OSTYPE=haiku
       KCL_GNU_SED=/x/s KCL_GNU_AWK=/x/a KCL_GNU_GREP=/x/g KCL_GNU_FIND=/x/f KCL_GNU_HEAD=/x/h KCL_GNU_TAIL=/x/t
       for f in sed awk grep find head tail; do ktool.gnu $f; ktool.lastError; printf '%s\n' "${RESULT%% is not*}"; done)"
check "$got" "no GNU sed: KCL_GNU_SED='/x/s'
no GNU awk: KCL_GNU_AWK='/x/a'
no GNU grep: KCL_GNU_GREP='/x/g'
no GNU find: KCL_GNU_FIND='/x/f'
no GNU head: KCL_GNU_HEAD='/x/h'
no GNU tail: KCL_GNU_TAIL='/x/t'"

kt_test_start "an empty override counts as unset"
got="$(PATH=$D; KCL_GNU_SED=; probe sed)"
check "$got" "rc=0|$D/gsed|"

# ---------------------------------------------------------------------------
kt_test_section "017: the cache"

D=$TMPD/k1; mkfake "$D" gsed out 'gsed (GNU sed) 4.10'
kt_test_start "one --version fork per candidate: a second call in the same shell forks nothing, a \$( ) child of a warm shell neither"
got="$(PATH=$D; probe sed; probe sed; c=$(ktool.gnu sed && printf '%s' "$RESULT"); printf '|child=%s|n=%s' "$c" "$(calls "$D" gsed)")"
check "$got" "rc=0|$D/gsed|rc=0|$D/gsed||child=$D/gsed|n=1"

D=$TMPD/k2; mkfake "$D" gsed out 'gsed (GNU sed) 4.10'
kt_test_start "RESULT mode inside \$( ): the child gets the path, but its cache dies with it — the parent forks once more, then never again"
got="$(PATH=$D
       c=$(ktool.gnu sed && printf '%s' "$RESULT"); printf 'child=%s n=%s|' "$c" "$(calls "$D" gsed)"
       ktool.gnu sed; printf 'parent=%s n=%s|' "$RESULT" "$(calls "$D" gsed)"
       c=$(ktool.gnu sed && printf '%s' "$RESULT"); printf 'child=%s n=%s' "$c" "$(calls "$D" gsed)")"
check "$got" "child=$D/gsed n=1|parent=$D/gsed n=2|child=$D/gsed n=2"

D1=$TMPD/k3; D2=$TMPD/k3b; mkfake "$D1" sed err "$BSD_SED"; mkfake "$D2" gsed out 'gsed (GNU sed) 4.10'
kt_test_start "a failure is cached too; a changed PATH re-resolves without probing a known path again"
got="$(PATH=$D1; probe sed >/dev/null; probe sed >/dev/null; printf 'bsd=%s|' "$(calls "$D1" sed)"
       PATH=$D2:$D1; probe sed; PATH=$D1; ktool.gnu sed; printf '|rc=%s bsd=%s g=%s' "$?" "$(calls "$D1" sed)" "$(calls "$D2" gsed)")"
check "$got" "bsd=1|rc=0|$D2/gsed||rc=1 bsd=1 g=1"

D=$TMPD/k4; mkfake "$D" gsed out 'gsed (GNU sed) 4.10'; DB=$TMPD/k4bsd; mkfake "$DB" sed err "$BSD_SED"
kt_test_start "a changed override re-resolves (and setting it back answers from the known banners)"
got="$(PATH=$D; ktool.gnu sed; printf '%s ' "$RESULT"; KCL_GNU_SED=$DB/sed; ktool.gnu sed; printf 'rc=%s ' "$?"
       KCL_GNU_SED=; ktool.gnu sed; printf '%s g=%s b=%s' "$RESULT" "$(calls "$D" gsed)" "$(calls "$DB" sed)")"
check "$got" "$D/gsed rc=1 $D/gsed g=1 b=1"

# ---------------------------------------------------------------------------
kt_test_section "017: contract"

kt_test_start "unknown families are rc 2 with RESULT '' and a reason ('', SED, 'a b', @, x[1], *, ../sed)"
got=""
for f in '' SED 'a b' @ 'x[1]' '*' ../sed; do
    got+="$(probe "$f")"$'\n'
done
check "$got" "rc=2||ktool.gnu: unknown tool family '' (known: sed awk grep find head tail)
rc=2||ktool.gnu: unknown tool family 'SED' (known: sed awk grep find head tail)
rc=2||ktool.gnu: unknown tool family 'a b' (known: sed awk grep find head tail)
rc=2||ktool.gnu: unknown tool family '@' (known: sed awk grep find head tail)
rc=2||ktool.gnu: unknown tool family 'x[1]' (known: sed awk grep find head tail)
rc=2||ktool.gnu: unknown tool family '*' (known: sed awk grep find head tail)
rc=2||ktool.gnu: unknown tool family '../sed' (known: sed awk grep find head tail)
"

kt_test_start "ktool.lastError is '' before any failure and keeps the last failure across a success"
got="$("$BASH" -c 'source "$1/kbool.sh" || exit 9; kk.uses ktool || exit 8; OSTYPE=haiku
      ktool.lastError; printf "[%s]" "$RESULT"; PATH=$2; ktool.gnu sed; ktool.lastError; printf "[%s]" "$RESULT"
      PATH=$3; ktool.gnu sed; ktool.lastError; printf "[%s]" "$RESULT"
      ktool.gnu nope; ktool.gnu sed; ktool.lastError; printf "[%s]" "$RESULT"' _ "$KBOOL_ROOT" "$TMPD/e" "$TMPD/k1" 2>&1)"
H="FreeBSD: pkg install gsed; macOS: brew install gnu-sed; Alpine: apk add sed; Debian/Ubuntu: apt install sed"
check "$got" "[][no GNU sed: gsed not on PATH; sed not on PATH; $H][no GNU sed: gsed not on PATH; sed not on PATH; $H][ktool.gnu: unknown tool family 'nope' (known: sed awk grep find head tail)]"

kt_test_start "set -eu: a full resolve, a refusal handled with ||, an unknown family and the cached answers run clean"
got="$("$BASH" -c 'set -eu; source "$1/kbool.sh" || exit 9; kk.uses ktool
      PATH=$2; ktool.gnu sed; a=$RESULT; ktool.gnu sed; b=$RESULT
      ktool.gnu awk || r=$?; ktool.gnu awk || s=$?; ktool.gnu bogus || u=$?
      unset KCL_GNU_SED; KCL_GNU_GREP=/nosuch; ktool.gnu grep || v=$?
      echo "ok $a $b $r $s $u $v"' _ "$KBOOL_ROOT" "$TMPD/k1" 2>&1)"
check "$got" "ok $TMPD/k1/gsed $TMPD/k1/gsed 1 1 2 1"

kt_test_start "the platform hints: linux-gnu, cygwin, msys, an unknown OSTYPE"
got=""
for os in linux-gnu cygwin msys haiku; do
    got+="$(PATH=$TMPD/e; OSTYPE=$os; probe tail)"$'\n'
done
check "$got" "rc=1||no GNU tail: gtail not on PATH; tail not on PATH; Debian/Ubuntu: apt install coreutils; Fedora: dnf install coreutils
rc=1||no GNU tail: gtail not on PATH; tail not on PATH; Git for Windows and MSYS2 ship GNU tail in /usr/bin: put it first on PATH
rc=1||no GNU tail: gtail not on PATH; tail not on PATH; Git for Windows and MSYS2 ship GNU tail in /usr/bin: put it first on PATH
rc=1||no GNU tail: gtail not on PATH; tail not on PATH; FreeBSD: pkg install coreutils; macOS: brew install coreutils; Alpine: apk add coreutils; Debian/Ubuntu: apt install coreutils
"

kt_test_start "a caller IFS of ':' and noglob do not change the answer"
got="$(PATH=$TMPD/a; IFS=:; set -f; probe sed)"
check "$got" "rc=0|$TMPD/a/gsed|"

kt_test_start "a banner's control characters are shown as '?', and it is cut at 80 characters"
D=$TMPD/n; mkdir -p "$D"
printf '#!/bin/sh\nprintf "a\\tb\\033c\\r\\n"\n' > "$D/sed"; chmod +x "$D/sed"
L=$TMPD/n2; mkfake "$L" sed out "$(printf 'x%.0s' {1..100})"
got="$(PATH=$D; OSTYPE=darwin; probe sed)"
check "$got" "rc=1||no GNU sed: gsed not on PATH; $D/sed is not GNU sed (--version: \"a?b?c\"); macOS: brew install gnu-sed"
kt_test_start "… and a 100-character banner is cut to 77 characters + '...'"
got="$(PATH=$L; OSTYPE=darwin; probe sed)"
check "$got" "rc=1||no GNU sed: gsed not on PATH; $L/sed is not GNU sed (--version: \"$(printf 'x%.0s' {1..77})...\"); macOS: brew install gnu-sed"

# ---------------------------------------------------------------------------
kt_test_section "017: PATH hygiene, banners, identities (L3.3 round 2)"

# mkraw DIR NAME BODY — a fake whose body after the log line is BODY (sh code)
mkraw() {
    mkdir -p "$1"
    printf '#!/bin/sh\necho "${0##*/} $*" >> "%s/log"\n%s\n' "$1" "$3" > "$1/$2"
    chmod +x "$1/$2"
}

C=$TMPD/cwd; mkfake "$C" gsed out 'gsed (GNU sed) 4.10'; mkfake "$C/rel" gsed out 'gsed (GNU sed) 4.10'
G=$TMPD/r1; mkfake "$G" sed out 'sed (GNU sed) 4.9'
kt_test_start "no cwd hijack: empty, '.', and relative PATH entries are never searched (the GNU gsed in \$PWD and in ./rel is not even run)"
got="$(cd "$C" && PATH=":.:rel:./rel:$G" && probe sed; printf '|cwd=%s rel=%s' "$(calls "$C" gsed)" "$(calls "$C/rel" gsed)")"
check "$got" "rc=0|$G/sed||cwd=0 rel=0"

kt_test_start "… and with only such entries nothing is found"
got="$(cd "$C" && PATH=":.:rel" && OSTYPE=darwin && probe sed)"
check "$got" "rc=1||no GNU sed: gsed not on PATH; sed not on PATH; macOS: brew install gnu-sed"

D1=$TMPD/r2a; mkdir -p "$D1/sed"
D2=$TMPD/r2b; mkdir -p "$D2"; printf 'sed (GNU sed) 4.9\n' > "$D2/sed"; chmod -x "$D2/sed"
D3=$TMPD/r2c; mkfake "$D3" sed out 'sed (GNU sed) 4.9'
kt_test_start "a directory and a non-executable file named sed on PATH are skipped"
got="$(PATH=$D1:$D2:$D3; probe sed; printf '\n'; PATH=$D1:$D2; OSTYPE=darwin; probe sed)"
check "$got" "rc=0|$D3/sed|
rc=1||no GNU sed: gsed not on PATH; sed not on PATH; macOS: brew install gnu-sed"

D=$TMPD/r3
mkraw "$D" grep "echo 'grep: warning: GREP_OPTIONS is deprecated; please use an alias or script' >&2; echo 'grep (GNU grep) 3.11'"
mkfake "$D" sed err 'sed (GNU sed) 4.9'
kt_test_start "the banner is stdout's first line: a stderr warning before it does not hide GNU grep; a banner on stderr only (empty stdout) still counts"
got="$(PATH=$D; probe grep; printf ' '; probe sed)"
check "$got" "rc=0|$D/grep| rc=0|$D/sed|"

D=$TMPD/r4; mkfake "$D" gsed out 'gsed version 1.0, not the GNU one'; mkfake "$D" sed out 'sed (GNU sed) 4.9'
kt_test_start "a non-GNU g-name, then a GNU plain name -> the plain one (both run once)"
got="$(PATH=$D; probe sed; printf '|g=%s p=%s' "$(calls "$D" gsed)" "$(calls "$D" sed)")"
check "$got" "rc=0|$D/sed||g=1 p=1"

D=$TMPD/r5; mkfake "$D" sed err "$BSD_SED"
kt_test_start "a PATH folder listed several times (also with trailing slashes) is searched once: one run, one 'is not GNU'"
got="$(PATH=$D:$D/:$D//:$D; OSTYPE=darwin; probe sed; printf '|n=%s' "$(calls "$D" sed)")"
check "$got" "rc=1||no GNU sed: gsed not on PATH; $D/sed is not GNU sed (--version: \"$BSD_SED\"); macOS: brew install gnu-sed|n=1"

D=$TMPD/r5b; mkfake "$D" gsed out 'gsed (GNU sed) 4.10'
kt_test_start "a trailing slash is dropped from the answer: PATH=DIR/ and PATH=DIR give DIR/gsed and share one banner"
got="$(PATH=$D/; probe sed; PATH=$D; probe sed; printf '|n=%s' "$(calls "$D" gsed)")"
check "$got" "rc=0|$D/gsed|rc=0|$D/gsed||n=1"

D=$TMPD/r6; mkraw "$D" sed 'if [ "$LC_ALL" = C ]; then echo "sed (GNU sed) 4.9"; else echo "LC_ALL=$LC_ALL"; fi'
kt_test_start "the probe runs with LC_ALL=C (the caller exports LC_ALL=POSIX)"
got="$(export LC_ALL=POSIX; PATH=$D; probe sed)"
check "$got" "rc=0|$D/sed|"

CAT=$(type -P cat)       # by path: the fakes run with PATH = their folder only
D=$TMPD/r7; mkraw "$D" sed "x=\$(\"$CAT\"); if [ -z \"\$x\" ]; then echo 'sed (GNU sed) 4.9'; else echo \"stdin: \$x\"; fi"
kt_test_start "the probe's stdin is /dev/null: a candidate that reads stdin sees nothing of the caller's (under timeout; the fake itself does see a stdin it is given)"
ctl="$(timeout -k 2 30 "$D/sed" --version <<< LEAK 2>&1)"
got="$(timeout -k 2 30 "$BASH" -c 'source "$1/kbool.sh" || exit 9; kk.uses ktool || exit 8; PATH=$2; ktool.gnu sed; echo "rc=$? $RESULT"' _ "$KBOOL_ROOT" "$D" <<< LEAK 2>&1)"
check "$ctl|$got" "stdin: LEAK|rc=0 $D/sed"

D=$TMPD/r8; mkfake "$D" head out 'head (uutils coreutils) 0.2.2'; mkfake "$D" tail out 'tail (uutils coreutils) 0.2.2'
kt_test_start "uutils coreutils is refused, and the hint says so and names the Ubuntu switch"
got="$(PATH=$D; OSTYPE=linux-gnu; probe head)"
check "$got" "rc=1||no GNU head: ghead not on PATH; $D/head is not GNU head (--version: \"head (uutils coreutils) 0.2.2\"); uutils coreutils is not accepted (only GNU coreutils is): install GNU coreutils (Ubuntu: the coreutils-from-gnu package)"

kt_test_start "… and the commented one-liner in ktool.sh accepts uutils for head and tail"
UU=""
while IFS= read -r l; do
    if [[ $l == "# __KTOOL_ID[head]+="* ]]; then UU=${l#"# "}; fi
done < "$SCRIPT_DIR/../ktool.sh"
got="$(PATH=$D; eval "$UU"; probe head; printf ' '; probe tail)"
check "[${UU:0:20}] $got" "[__KTOOL_ID[head]+='|] rc=0|$D/head| rc=0|$D/tail|"

D=$TMPD/r9; mkfake "$D" sed out 'GNU sed version 4.2.2'
kt_test_start "old GNU sed: a banner that STARTS with 'GNU sed version ' (4.2.x) is GNU (busybox's 'This is not GNU sed version 4.0' is not, see above)"
got="$(PATH=$D; probe sed)"
check "$got" "rc=0|$D/sed|"

D=$TMPD/r10; mkfake "$D" gnused out 'gnused (GNU sed) 4.9'
kt_test_start "two g-names for one family ('gsed gnused'): tried in order"
got="$(PATH=$D; __KTOOL_GN[sed]='gsed gnused'; probe sed; printf '\n'; PATH=$TMPD/e; OSTYPE=darwin; probe sed)"
check "$got" "rc=0|$D/gnused|
rc=1||no GNU sed: gsed not on PATH; gnused not on PATH; sed not on PATH; macOS: brew install gnu-sed"

kt_test_start "control characters in the override's value are shown as '?' in the reason"
got="$(PATH=$TMPD/e; OSTYPE=darwin; KCL_GNU_SED=$'/x/\033y'; probe sed; printf '\n'; KCL_GNU_SED=$'my\tsed'; probe sed)"
check "$got" "rc=1||no GNU sed: KCL_GNU_SED='/x/?y' is not an executable file; macOS: brew install gnu-sed
rc=1||no GNU sed: KCL_GNU_SED='my?sed': my?sed not on PATH; macOS: brew install gnu-sed"

A=$TMPD/r14a; B=$TMPD/r14b; mkfake "$A/o" mysed out 'mysed (GNU sed) 4.9'; mkfake "$B/o" mysed out 'mysed (GNU sed) 4.9'
kt_test_start "a relative override is cached per \$PWD (cd elsewhere -> resolved again)"
got="$(PATH=$TMPD/e; KCL_GNU_SED=o/mysed; cd "$A"; ktool.gnu sed; printf '%s ' "$RESULT"; cd "$B"; ktool.gnu sed; printf '%s' "$RESULT")"
check "$got" "$A/o/mysed $B/o/mysed"

kt_test_start "no state from the environment: exported __KTOOL_* scalars are dropped at load (fresh associative caches, lastError '')"
got="$(env __KTOOL_ERR=junk __KTOOL_RES=x __KTOOL_BANNER=y __KTOOL_KEY=z __KTOOL_MSG=w __KTOOL_ID=v "$BASH" -c \
      'source "$1/kbool.sh" || exit 9; kk.uses ktool || exit 8; ktool.lastError
       printf "[%s] %s %s [%s]|" "$RESULT" "${__KTOOL_RES@a}" "${#__KTOOL_RES[@]}" "${__KTOOL_ERR@a}"
       PATH=$2; ktool.gnu sed; echo "$? $RESULT"' _ "$KBOOL_ROOT" "$TMPD/a" 2>&1)"
check "$got" "[] A 0 []|0 $TMPD/a/gsed"

kt_test_start "an 'export -f' child without ktool's tables: rc 2, nothing subscripted"
got="$("$BASH" -c 'source "$1/kbool.sh" || exit 9; kk.uses ktool || exit 8
       export -f ktool.gnu ktool._own ktool._san ktool._banner ktool._try ktool._walk ktool._hint
       "$BASH" -c '\''ktool.gnu sed; echo "rc=$? [$RESULT] $__KTOOL_ERR"'\''' _ "$KBOOL_ROOT" 2>&1)"
check "$got" "rc=2 [] ktool.gnu: ktool is not loaded in this shell (kk.uses ktool)"

# ---------------------------------------------------------------------------
kt_test_section "017: the banner mechanism (L3.3 round 3)"

BIG=$TMPD/big.txt; printf '%01048576d\n' 0 > "$BIG"          # 1 MiB of zeros
BLANK=$TMPD/blank.txt; printf '%1048576s\n' '' > "$BLANK"    # 1 MiB of spaces
D=$TMPD/r15; mkraw "$D" sed "echo 'sed (GNU sed) 4.9'; \"$CAT\" \"$BIG\"; \"$CAT\" \"$BIG\" >&2"
D2=$TMPD/r15b; mkraw "$D2" grep "\"$CAT\" \"$BLANK\" \"$BLANK\"; echo 'grep (GNU grep) 3.11' >&2; \"$CAT\" \"$BIG\" >&2"
kt_test_start "a banner followed by 1 MiB on stdout and 1 MiB on stderr, and 2 MiB of blank stdout before a stderr banner, resolve in well under a second each (linear split; under timeout)"
got="$(timeout -k 2 120 "$BASH" -c 'source "$1/kbool.sh" || exit 9; kk.uses ktool || exit 8; PATH=$2:$3
       for f in sed grep; do s=$EPOCHREALTIME; ktool.gnu $f; rc=$?; e=$EPOCHREALTIME
           printf "%s rc=%s %s %s\n" $f $rc "$RESULT" $(( (${e//[.,]/} - ${s//[.,]/}) / 1000 )); done' _ "$KBOOL_ROOT" "$D" "$D2" 2>&1)"
ms1=${got#sed rc=0 $D/sed }; ms1=${ms1%%$'\n'*}; ms2=${got##*$D2/grep }
if [[ "$got" == "sed rc=0 $D/sed "*$'\n'"grep rc=0 $D2/grep "* && $ms1 =~ ^[0-9]+$ && $ms2 =~ ^[0-9]+$ ]] \
   && (( ms1 < 2000 && ms2 < 2000 )); then
    kt_test_pass "sed ${ms1} ms, grep ${ms2} ms"
else
    kt_test_fail "[${got//$'\n'/ | }]"
fi

D=$TMPD/r16; mkraw "$D" sed "printf 'sed (GNU sed) 4.9\\000x\\n'; printf 'warn\\000y\\n' >&2"
D2=$TMPD/r16b; mkraw "$D2" grep "printf 'grep (GNU grep) 3.11\\000\\n' >&2"
kt_test_start "NUL bytes on the tool's stdout and stderr: bash's 'ignored null byte' warning never reaches the caller, the banner is still read"
got="$(PATH=$D:$D2; probe sed; printf ' '; probe grep)"
check "$got" "rc=0|$D/sed| rc=0|$D2/grep|"

D=$TMPD/r17; mkfake "$D" find out 'find (uutils findutils) 0.7.0'
kt_test_start "a uutils findutils find is refused with the ordinary hint (the coreutils-from-gnu hint is for head/tail only)"
got="$(PATH=$D; OSTYPE=linux-gnu; probe find)"
check "$got" "rc=1||no GNU find: gfind not on PATH; $D/find is not GNU find (--version: \"find (uutils findutils) 0.7.0\"); Debian/Ubuntu: apt install findutils; Fedora: dnf install findutils"

D=$TMPD/r18; mkraw "$D" sed "printf '   \\n\\t\\n  \\r\\n  GNU sed version 4.2.2\\n'"
D2=$TMPD/r18b; mkraw "$D2" grep "printf ' \\n\\t\\n'; echo 'grep (GNU grep) 3.11' >&2"
kt_test_start "blank and whitespace-only lines before the banner are skipped and its leading blanks dropped (so '^GNU sed version' still matches); a whitespace-only stdout falls back to stderr"
got="$(PATH=$D:$D2; probe sed; printf ' '; probe grep)"
check "$got" "rc=0|$D/sed| rc=0|$D2/grep|"

kt_test_log "017_GnuTools.sh completed"
