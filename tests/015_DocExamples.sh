#!/bin/bash
# DocExamples — the runnable examples of the kbool entry document (README.md in
# the kbool root) and of the kkore reference (kkore/README.md) run as written
# (kklass/USES_PLAN.md phase U5). The marker, the expected-output comments and
# the hermetic run are described in doc_examples.sh (shared with kklass 142,
# which checks the kklass book's chapter "Units and uses").
#
# Why here: kkore is the layer these two documents describe (kbool.sh, the
# loader kk.unit / kk.uses / kk.project / kk.config / kk.defined /
# kk.namespace), the kkore suite already loads ../kbool.sh from the kbool root,
# and the master sweep runs this suite. The kklass book is checked by kklass's
# own suite, so no layer reads the documents of a layer above it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "DocExamples" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/doc_examples.sh"
KDOC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# 1. The checker itself: a sample document whose examples break each rule once
SAMPLE="$_KT_TMPDIR/sample.md"
cat > "$SAMPLE" <<'MD'
Not marked, never run:

```bash
exit 7
```

<!-- doctest -->
```bash
source /path/to/kbool/kbool.sh
echo "$KBOOL_HOME" | grep -c kbool    # => 1
printf '\n'                           # =>
echo end                              # => end
echo "warn" >&2                       # 2> war
```

<!-- doctest -->
```bash
echo two      # => one
```

<!-- doctest -->
```bash
echo "stray" >&2
```

<!-- doctest -->
```bash
echo quiet >&2    # 2> loud
```

<!-- doctest -->
```bash
exit 3
```

<!-- doctest -->
```bash
echo "a documented warning" >&2
echo "an undocumented one" >&2
# 2> documented warning
```

<!-- doctest -->
```text
a marked block that is not bash: not run
```
MD
kt_test_start "the checker: 6 marked bash blocks; a good one passes; a wrong stdout, an unexpected stderr, a missing stderr text, rc != 0 and an undocumented stderr line next to a documented one each fail; unmarked and non-bash blocks are not run [U5]"
out="$_KT_TMPDIR/sample"
rm -rf "$out"
if kdoc_extract "$SAMPLE" "$out"; then n=$RESULT; else n="extract-rc-$?"; fi
verdict=""
why=""
for id in 001 002 003 004 005 006; do
    if [[ -f $out/$id.sh ]] && kdoc_run "$out" "$id"; then verdict+="P"; else verdict+="F"; why+="$id:${KDOC_WHY%%;*}|"; fi
done
if [[ $n == 6 && $verdict == PFFFFF \
      && $why == *"002:stdout differs"* && $why == *"003:unexpected stderr"* \
      && $why == *"004:stderr lacks: [loud]"* && $why == *"005:rc=3"* \
      && $why == *"006:unexpected stderr line(s): [an undocumented one]"* ]]; then
    kt_test_pass "n=$n $verdict"
else
    kt_test_fail "n=$n verdict=$verdict why=$why"
fi

kt_test_start "the checker: an example runs in an empty folder with an empty HOME, no KBOOL_* / BASH_ENV / exported functions from the caller, /etc/kbool hook missing [U5, U41]"
printf '%s\n' '<!-- doctest -->' '```bash' \
    'echo "files=$(ls -A)"                                    # => files=example.sh' \
    'echo "home=$(ls -A "$HOME" | wc -l) cfg=${KBOOL_CONFIG-unset} kh=${KBOOL_HOME-unset} be=${BASH_ENV-unset}"  # => home=0 cfg=unset kh=unset be=unset' \
    'declare -F kdoc_run >/dev/null && echo leaked || echo clean   # => clean' \
    '[[ -e $__KK_CFG_ETC ]] && echo etc || echo noetc          # => noetc' \
    '```' > "$_KT_TMPDIR/iso.md"
rm -rf "$_KT_TMPDIR/iso"
export -f kdoc_run
if KBOOL_CONFIG=/nonexistent KBOOL_HOME=/elsewhere BASH_ENV=/nonexistent kdoc_extract "$_KT_TMPDIR/iso.md" "$_KT_TMPDIR/iso" \
   && KBOOL_CONFIG=/nonexistent KBOOL_HOME=/elsewhere BASH_ENV=/nonexistent kdoc_run "$_KT_TMPDIR/iso" 001; then
    kt_test_pass "isolated"
else
    kt_test_fail "$KDOC_WHY"
fi
export -fn kdoc_run

# ---------------------------------------------------------------------------
# 2. The documents
kdoc_check_file "$KDOC_ROOT/README.md" "README.md" 9
kdoc_check_file "$SCRIPT_DIR/../README.md" "kkore/README.md" 5
