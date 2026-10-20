#!/usr/bin/env bash
# unit_lint.sh — a reusable lint for unit files (uses phase U3; found_in_U1a,
# critic C11; review R8). Not a test file: the runner only picks up NNN_*.sh.
# Source it from any suite (kkore, kklass, kcl) and call:
#
#   kk_unit_lint FILE...   prints `FILE:LINE: TEXT` for every FILE-SCOPE
#                          `local`, and every file-scope `declare` / `typeset`
#                          without -g (and without -f / -F / -p, which declare
#                          nothing); rc 0 = clean, rc 1 = findings, rc 2 = a
#                          FILE that cannot be read.
#
# Why: a unit loaded by kk.uses runs INSIDE kk._uses, and the system units and
# kuse.sh run inside kbool.sh's boot function, so such a line declares a LOCAL
# of the loader — the variable vanishes when the load returns (and a `local`
# outside any function is an error in a plain source).
#
# One awk pass per call (one process). Each line is scanned character by
# character outside here-documents: single / double quotes (also across lines),
# backslash escapes, `#` comments, `$(( ))` / `(( ))` arithmetic (so `z<<y` is
# no here-document) and here-documents (`<<WORD`, `<<-WORD`, quoted WORD) are
# tracked, and the quoted text is dropped from the "code" of the line. A
# function body is everything between the `{` or `(` that follows a header
# `NAME()` / `function NAME` and its matching `}` / `)` — wherever on the line
# that closing token is (`echo x; }`, a one-liner). On the code of a line outside
# every body, a declaration is the word local / declare / typeset at a command
# position (line start, after ; & | ( { ! or then / else / do), optionally
# preceded by `!`, `time`, `builtin`, `command` and NAME=VALUE assignments.
# Not seen: a declaration inside `eval '...'` (it is a string).

kk_unit_lint() {
    local __f __rc=0
    for __f; do
        if [[ ! -r $__f || -d $__f ]]; then
            printf '%s: cannot be read\n' "$__f"
            __rc=2
        fi
    done
    (( __rc == 0 )) || return 2
    (( $# )) || return 0
    LC_ALL=C awk '
    function flush_decl(code,   n, i, w, words, cmd, opts, k) {
        # split the code into statements at ; & | ( { and check each one
        n = split(code, stm, /[;&|({]/)
        for (i = 1; i <= n; i++) {
            nw = split(stm[i], words, /[ \t]+/)
            k = 1
            while (k <= nw && words[k] == "") k++
            # then / else / do / ! / time / builtin / command / NAME=VALUE prefixes
            while (k <= nw && (words[k] == "then" || words[k] == "else" || words[k] == "do" || words[k] == "!" \
                   || words[k] == "time" || words[k] == "builtin" || words[k] == "command" \
                   || words[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) k++
            if (k > nw) continue
            cmd = words[k]
            if (cmd != "local" && cmd != "declare" && cmd != "typeset") continue
            opts = ""
            for (k++; k <= nw; k++) {
                if (words[k] == "") continue
                if (words[k] == "--") break
                if (words[k] !~ /^[-+]/) break
                opts = opts substr(words[k], 2)
            }
            if (cmd == "local" || opts !~ /[gfFp]/) return 1
        }
        return 0
    }
    FNR == 1 { sq = 0; dq = 0; hd = ""; hdt = 0; depth = 0; pend = 0; btype = ""; arith = 0 }
    {
        line = $0
        sub(/\r$/, "", line)
        if (hd != "") {
            t = line
            if (hdt) sub(/^\t+/, "", t)
            if (t == hd) hd = ""
            next
        }
        startdepth = depth
        code = ""
        L = length(line)
        newhd = ""; newhdt = 0
        for (i = 1; i <= L; i++) {
            c = substr(line, i, 1)
            if (sq) { if (c == "\047") sq = 0; continue }
            if (dq) {
                if (c == "\\") { i++; continue }
                if (c == "\"") dq = 0
                continue
            }
            if (c == "\\") { i++; code = code " "; continue }
            if (c == "\047") { sq = 1; code = code " "; continue }
            if (c == "\"") { dq = 1; code = code " "; continue }
            if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;&|(]/)) break
            two = substr(line, i, 2)
            if (two == "((") { arith++; code = code "(("; i++; continue }
            if (two == "))" && arith > 0) { arith--; code = code "))"; i++; continue }
            if (two == "<<" && arith == 0 && substr(line, i + 2, 1) != "<") {
                rest = substr(line, i + 2)
                t = 0
                if (substr(rest, 1, 1) == "-") { t = 1; rest = substr(rest, 2) }
                sub(/^[ \t]*/, "", rest)
                sub(/^["\047]/, "", rest)
                if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) { newhd = substr(rest, 1, RLENGTH); newhdt = t }
                code = code "<<"; i++; continue
            }
            # function bodies: the token after a header opens one
            prev = (i == 1) ? " " : substr(line, i - 1, 1)
            nxt = substr(line, i + 1, 1)
            if (c == "{" && (prev ~ /[ \t;&|(]/ || i == 1) && (nxt == "" || nxt ~ /[ \t]/)) {
                if (pend && depth == 0) { depth = 1; btype = "{"; pend = 0 }
                else if (depth > 0 && btype == "{") depth++
            } else if (c == "}" && (prev ~ /[ \t;&]/ || i == 1) && (nxt == "" || nxt ~ /[ \t;&|)<>]/)) {
                if (depth > 0 && btype == "{") depth--
            } else if (c == "(" && arith == 0) {
                if (pend && depth == 0 && substr(line, i, 2) != "()") { depth = 1; btype = "("; pend = 0 }
                else if (depth > 0 && btype == "(") depth++
            } else if (c == ")" && arith == 0) {
                if (depth > 0 && btype == "(") depth--
            }
            code = code c
        }
        if (newhd != "") { hd = newhd; hdt = newhdt }
        # a function header on this line (outside any body): the next { or ( opens it
        if (startdepth == 0 && !sq && !dq) {
            hdr = code
            if (hdr ~ /^[ \t]*(function[ \t]+[A-Za-z_][A-Za-z0-9_.:@-]*([ \t]*\(\))?|[A-Za-z_][A-Za-z0-9_.:@-]*[ \t]*\(\))[ \t]*([{(].*)?$/) {
                # the body token may already have been on this line (handled above
                # only when pend was set): re-scan the header line for it
                if (depth == 0) {
                    pend = 1
                    h = hdr
                    sub(/^[ \t]*(function[ \t]+[A-Za-z_][A-Za-z0-9_.:@-]*([ \t]*\(\))?|[A-Za-z_][A-Za-z0-9_.:@-]*[ \t]*\(\))[ \t]*/, "", h)
                    if (h != "") {
                        # count the body on the header line itself
                        b = substr(h, 1, 1)
                        if (b == "{" || b == "(") {
                            pend = 0; btype = b; depth = 0
                            for (j = 1; j <= length(h); j++) {
                                cj = substr(h, j, 1)
                                if (b == "{" && cj == "{") depth++
                                else if (b == "{" && cj == "}") depth--
                                else if (b == "(" && cj == "(") depth++
                                else if (b == "(" && cj == ")") depth--
                            }
                            if (depth < 0) depth = 0
                        }
                    }
                }
                next
            }
        }
        if (startdepth == 0 && depth == 0 && !pend && code != "") {
            if (flush_decl(code)) {
                t = line
                sub(/^[ \t]+/, "", t)
                printf "%s:%d: %s\n", FILENAME, FNR, t
                found = 1
            }
        }
    }
    END { exit found ? 1 : 0 }
    ' "$@"
}
