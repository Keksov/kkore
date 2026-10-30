#!/usr/bin/env bash
# doc_examples.sh — run the examples a Markdown document marks as runnable, so
# the documentation cannot rot silently (kklass/USES_PLAN.md phase U5). Sourced
# by test files (kkore 015, kklass 142); not a test file — the ktests runner
# picks up NNN_*.sh only.
#
# THE MARKER. A fenced ```bash block whose previous line is exactly
#
#     <!-- doctest -->
#
# is a runnable example (an HTML comment: invisible when the Markdown renders).
# Inside such a block two trailing comments state what it must print:
#
#     echo "$RESULT"          # => apple
#     defineClass kv ""       # 2> Duplicate identifier: 'kv' is a function namespace
#
#   `# => TEXT`  TEXT is the next line of the block's stdout; all `# =>` lines,
#                in order, are its WHOLE stdout (no `# =>` line: no stdout).
#                `# =>` with nothing after it is an empty line.
#   `# 2> TEXT`  TEXT must occur in its stderr (a substring: messages carry
#                absolute paths), and EVERY stderr line must contain one of the
#                block's `# 2>` texts — an unexpected extra message fails the
#                block; no `# 2>` line: stderr must be empty.
# The block must exit 0 — show a failing call as `cmd; echo "rc=$?"  # => rc=2`.
# The literal `/path/to/kbool` is replaced by the real kbool root.
#
# HOW A BLOCK RUNS (U41-style isolation, stricter): written to example.sh in a
# fresh empty folder and run there as `bash example.sh` (the shell running the
# test: $BASH) under `env -i` — only PATH, HOME (an empty folder of its own),
# TMPDIR, LANG=C.UTF-8 and the /etc/kbool test hook (__KK_CFG_ETC, a folder that
# does not exist) — so no developer config, KBOOL_HOME, BASH_ENV, exported
# function or variable reaches it; `timeout` 300 s. Blocks are independent: each
# starts a new shell in a new folder.

# kdoc_extract MD OUT — writes OUT/NNN.sh (the block, root substituted),
# OUT/NNN.out (the expected stdout), OUT/NNN.err (stderr substrings, one per
# line), OUT/NNN.line (the fence's line number in MD). RESULT = the number of
# runnable blocks; rc 1 when MD cannot be read or a marked block is not closed.
kdoc_extract() {
    local md=$1 out=$2 root=${KDOC_ROOT:?KDOC_ROOT (the kbool root) not set}
    local line prev="" n=0 ln=0 in=0 id body exp err text
    local re_out='^(.*[[:space:]])?# =>( (.*))?$' re_err='^(.*[[:space:]])?# 2> (.*)$'
    RESULT=0
    [[ -r $md ]] || return 1
    mkdir -p "$out" || return 1
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        (( ++ln ))
        if (( in )); then
            if [[ $line == '```'* ]]; then
                printf '%s' "$body" > "$out/$id.sh"
                printf '%s' "$exp" > "$out/$id.out"
                printf '%s' "$err" > "$out/$id.err"
                in=0
            else
                body+=${line//\/path\/to\/kbool/$root}$'\n'
                if [[ $line =~ $re_out ]]; then
                    text=${BASH_REMATCH[3]}
                    exp+=$text$'\n'
                fi
                if [[ $line =~ $re_err ]]; then
                    err+=${BASH_REMATCH[2]}$'\n'
                fi
            fi
        elif [[ $line == '```bash' && $prev == '<!-- doctest -->' ]]; then
            (( ++n ))
            printf -v id '%03d' "$n"
            printf '%s\n' "$ln" > "$out/$id.line"
            in=1 body="" exp="" err=""
        fi
        prev=$line
    done < "$md"
    RESULT=$n
    (( ! in ))
}

# kdoc_run OUT ID — run block ID of OUT hermetically. rc 0 = as documented;
# rc 1 = not, with the reason in KDOC_WHY.
kdoc_run() {
    local d=$1/$2.run rc out errt exp p miss=""
    KDOC_WHY=""
    [[ $d == /* || $d == [A-Za-z]:* ]] || d=$PWD/$d     # the run cd's into $d/w
    rm -rf "$d"; mkdir -p "$d/w" "$d/home" "$d/tmp"
    cp "$1/$2.sh" "$d/w/example.sh"
    exp=$(<"$1/$2.out")         # $(<f) and $(cmd) both drop trailing newlines
    out=$(cd "$d/w" && env -i PATH="$PATH" HOME="$d/home" TMPDIR="$d/tmp" LANG=C.UTF-8 \
              __KK_CFG_ETC="$d/etc/kbool" "$KT_TIMEOUT" 300 "$BASH" example.sh 2>"$d/stderr")
    rc=$?
    errt=$(<"$d/stderr")
    if (( rc != 0 )); then KDOC_WHY+="rc=$rc; "; fi
    if [[ $out != "$exp" ]]; then
        KDOC_WHY+="stdout differs: got [${out//$'\n'/|}] want [${exp//$'\n'/|}]; "
    fi
    if [[ -s $1/$2.err ]]; then
        local -a pats=()
        local l ok extra=""
        while IFS= read -r p; do
            [[ -n $p ]] || continue
            pats+=("$p")
            [[ $errt == *"$p"* ]] || miss+=" [$p]"
        done < "$1/$2.err"
        [[ -z $miss ]] || KDOC_WHY+="stderr lacks:$miss; "
        while IFS= read -r l; do                 # every stderr line is documented
            [[ -n $l ]] || continue
            ok=0
            for p in "${pats[@]}"; do [[ $l == *"$p"* ]] && { ok=1; break; }; done
            (( ok )) || extra+=" [$l]"
        done <<< "$errt"
        [[ -z $extra ]] || KDOC_WHY+="unexpected stderr line(s):$extra; "
    elif [[ -n $errt ]]; then
        KDOC_WHY+="unexpected stderr: [${errt//$'\n'/|}]; "
    fi
    if [[ -z $KDOC_WHY ]]; then rm -rf "$d"; return 0; fi
    [[ -z $errt || $KDOC_WHY == *stderr* ]] || KDOC_WHY+="stderr: [${errt//$'\n'/|}]; "
    return 1
}

# kdoc_check_file MD TITLE WANT — the ktests checks of one document: one test
# that it holds exactly WANT runnable examples (a lost marker is caught), then
# one test per example (named by its fence line).
kdoc_check_file() {
    local md=$1 title=$2 want=$3 out i id ln
    out="$_KT_TMPDIR/kdoc_${title//[^A-Za-z0-9]/_}"
    rm -rf "$out"
    kt_test_start "$title: $want runnable examples (<!-- doctest --> blocks), all closed"
    if kdoc_extract "$md" "$out" && [[ $RESULT == "$want" ]]; then
        kt_test_pass "$RESULT"
    else
        kt_test_fail "found ${RESULT:-0}, want $want (or a marked block not closed), in $md"
    fi
    for (( i = 1; i <= RESULT; i++ )); do
        printf -v id '%03d' "$i"
        ln=$(<"$out/$id.line")
        kt_test_start "$title example $i (line $ln) runs as documented"
        if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"; continue; fi
        if kdoc_run "$out" "$id"; then
            kt_test_pass "ok"
        else
            kt_test_fail "${md##*/}:$ln: $KDOC_WHY"
        fi
    done
}
