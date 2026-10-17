# kkore — the kbool system units

kkore is the bottom layer of kbool: the units `kbool.sh` always loads, in this
order — `kuse` (the unit loader), `klib`, `kerr`, `kvar`, `kcfg`. They are
registered as loaded **system units**: `kk.uses klib` is a no-op, they are never
forgotten and never resolved again by name. Load them by loading kbool:

```bash
source /path/to/kbool/kbool.sh || exit
```

The entry document — quick start, header shapes, the configuration chain, how
to run the tests — is the [kbool README](../README.md). This page is the
reference of the loader's public functions (section 1), the rules they keep
(2–4), the security notes (5) and the limitations (6). The design, with every
decision and its reasons, is [kklass/USES_PLAN.md](../kklass/USES_PLAN.md);
the code comments of [`kuse.sh`](kuse.sh) are the fine print.

| unit | defines | |
|---|---|---|
| `kuse` | `kk.unit`, `kk.uses`, `kk.namespace`, `kk.project`, `kk.config`, `kk.defined` | section 1 |
| `klib` | `kl.write`, `kl.writeln`, `kl.errln`, `kl.getTopCaller`; the guards `kk.isInt`, `kk.isNum`, `kk._outName`, `kk._is_ident`; `kk.debug`, `kk.warn` | contract: [kcl/README.md §1.2, §1.5, §1.7](../kcl/README.md#1-the-kcl-contract) |
| `kerr` | the ERR trap and error reporting: `ke.setTrap`, `ke.onError`, `ke.setError`, `ke.hasError`, `ke.reportError`, `ke.enableErrorReport`, `ke.errorsReportingOff`, `ke.exitOnErrorOn/Off` | the trap is set by an explicit `ke.setTrap` (units take no arguments) |
| `kvar` | `kv.new` (unique names), the frame stack `kv.framePush/Pop/Current/Instance/Class`, `kv.set/get/free` | used by kklass's dispatch |
| `kcfg` | a key/value store: `kc.set/get/exists/delete/keys/clear`, `kc.setTrue/setFalse/isTrue/isFalse`, `kc.alias` | not the kbool configuration (that is `kk.config`) |

Declared function namespaces of kkore (no class or instance may take them):
`kk kl ke kv kc` and the unit names `kuse klib kerr kvar kcfg`.

---

## 1. The loader API (`kuse.sh`)

Conventions as in [kcl/README.md §1](../kcl/README.md#1-the-kcl-contract): a
value comes back in `RESULT`, a list into a caller array (`OUTVAR`); rc 0 /
1 / 2. One difference: a **loader error is printed** (`kbool: error: …` on
stderr, silenced only by `VERBOSE_KKLASS=quiet`) — it is a compile error of the
program, not a member's rc-1 miss. Every function here is fork-free, and all
of them refuse to work (rc 2, printed) in a shell where `kbool.sh` is not
loaded — except `kk.uses` and `kk.project`, which load `$KBOOL_HOME/kbool.sh`
first when it exists (a child bash that inherited the functions).

### `kk.unit NAME` — the unit header

    kk.unit NAME || return $__kk_unit_rc        # line 2 of every unit

| rc | meaning | `$__kk_unit_rc` | the `source` returns |
|---|---|---|---|
| 0 | load the unit now: it is registered, `KK_UNIT_DIR` = its folder, `NAME` declared as a namespace | 0 | the unit's own rc |
| 1 | already loaded (or a complete earlier load): skip | 0 | 0 |
| 2 | error, printed: NAME is not the file stem, a usage error, the same NAME loaded from another file, a cycle, NAME is a built class / a live instance / another folder's namespace, not called from a sourced file | 2 | 2 |

An rc-2 header error also **taints** the unit around it (section 2.4). With
arguments (`source unit.sh x`) it prints `kbool: WARNING: unit 'NAME' called
with arguments; units take none` and goes on.

### `kk.unit --forget NAME` — the development hatch

Drops NAME's registration and the sites of the classes it declared, so the next
`source` / `kk.uses` loads it again and rebuilds them. Live instances of the old
classes are not touched. rc 0 forgotten; rc 1 NAME is not registered; rc 2
(printed) no name, a system unit, or the unit is being loaded right now. A
unit's declared namespace stays (the reload re-declares it from the same file).

### `kk.uses [--optional] ARG...` — load units once

* **ARG** with `/` or `\`, or ending in `.sh`, is a **PATH**: relative to the
  folder of the calling file (`$PWD` when there is none). Anything else is a
  **NAME** (no blanks, `*`, `?`, `[`).
* **rc 0**: every ARG is loaded or was already. Otherwise the **first failure**
  stops the list: rc 2 for a loader error (printed: not found, not a name, a
  cycle, a name clash, a dependency's incomplete load), else the unit's own
  non-zero rc (`kbool: error: kk.uses: loading unit 'X' failed (rc=N)`).
* A failed load is **forgotten** (a retry loads it again) and **taints** the
  unit whose load called `kk.uses` (section 2.4).
* **`--optional`** (leading, applies to every ARG): a failure prints nothing
  and taints nothing; the rc still reports it.
* Each unit is sourced with **no positional arguments** and `KK_UNIT_DIR` is
  restored afterwards. A loaded NAME costs ~30 µs (a cached hit per calling
  file), a no-op `source` of a loaded unit ~0.2 ms; the first NAME lookup of a
  shell builds the name index (one glob per search folder, 4–6 ms with kcl).

### `kk.namespace X [Y ...]` — more function namespaces

Declares `X.*` (and `Y.*` …) as function namespaces of the calling file; the
unit being loaded, if any, is their owner. kklass then refuses a class or an
instance named X. rc 0 (a repeat is a no-op). rc 2 (printed; the unit being
loaded is tainted): no name, not an identifier, X is a built class or a live
instance, X is already declared by a file in **another folder** (U44: only a
package — files of one folder — may share a namespace; a namespace named like a
class is never shared but with that class's own file), kbool not loaded.

### `kk.project PATH|NAME` — the project level

PATH (contains `/` or `\`, or ends in `.conf`): the project file — relative to
the calling file's folder (`$PWD` at a prompt). NAME:
`~/.kbool/NAME/project.conf`, else `$USERPROFILE/.kbool/NAME/project.conf`. rc 0:
read, merged as the second-strongest level and applied (the name index and the
resolution caches start over). rc 0 too, doing nothing: the same file again (any
spelling, `-ef`). rc 2 (printed; nothing applied, a later call may try again):
usage, not found, unreadable, another project already set, or **too late** — a
non-system unit was already used (`kk.uses`, found or not, `--optional` too) or
sourced. The system units are only `kuse klib kerr kvar kcfg`; `kklass` and
every kcl unit are non-system. There is no automatic project-file discovery.

### `kk.config KEY [OUTVAR]` — the merged configuration

| KEY | without OUTVAR | with OUTVAR |
|---|---|---|
| `debug`, `ckkdir` (scalars) | `RESULT` = the value; rc 1 + `RESULT=''` when unset or empty | rc 2 |
| `unitpath`, `defines` (lists) | `RESULT` = the entries joined by newlines; rc 1 + `RESULT=''` when empty | the caller's indexed array OUTVAR gets the entries, `RESULT` = their count; rc 1 + `RESULT=''` + OUTVAR emptied when empty |

Inside `$( )` the value is printed. rc 2, silent (the reason under
`VERBOSE_KKLASS=debug`): no or an unknown KEY (exact match, also under
`nocasematch`), extra arguments, a bad, reserved, associative or readonly
OUTVAR. `unitpath` lists the config levels' folders only (absolute, folded); the
system paths are not in it.

### `kk.defined NAME` — a define

rc 0 NAME is in the merged `defines`; rc 1 not; rc 2 no name or more than one
argument (and, printed, kbool not loaded). Case-sensitive. Use it in an
ordinary `if` — there is no conditional-loading syntax.

### Variables

| name | |
|---|---|
| `KBOOL_HOME` | exported by `kbool.sh`: the folder it was loaded from (a preset naming another folder is overwritten with a WARNING) |
| `KBOOL_CONFIG` | read: the strongest config file; a relative value is made absolute after the read |
| `KK_UNIT_DIR` | while a unit loads: its folder as sourced, made absolute (not normalised) — the way a unit finds its own data files. Outside a load its value is meaningless (it stays at the last unit plain-sourced, or is restored by `kk.uses`). Read it at file scope **before** plain-sourcing anything (a plain nested source leaves it at that file's folder; `kk.uses` restores it); code that needs the folder at run time keeps a copy (`MATH_DIR=$KK_UNIT_DIR`) |
| `__kk_unit_rc` | the header's return value (above) |
| `VERBOSE_KKLASS` | `quiet` silences loader messages; `debug` shows the silent rc-2 reasons; the config's `debug` key sets it only when nobody else did |

<!-- doctest -->
```bash
mk() {  # mk FILE NAME BODY — a unit with the user header
    printf '%s\n' '#!/bin/bash' \
        '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
        "kk.unit $2 || return \$__kk_unit_rc" "$3" > "$1"
}
mkdir -p lib
mk lib/alpha.sh alpha 'echo "alpha: dir=${KK_UNIT_DIR##*/}"'
mk lib/wrong.sh right ''
source /path/to/kbool/kbool.sh || exit
kk.uses lib/alpha.sh; echo "rc=$?"           # => alpha: dir=lib
                                             # => rc=0
source lib/alpha.sh; echo "rc=$?"            # => rc=0
kk.uses lib/wrong.sh; echo "rc=$?"           # => rc=2
# 2> unit header 'kk.unit right' does not match the file name 'wrong.sh'
# 2> kbool: error: kk.uses: loading unit 'wrong' failed (rc=2)
kk.unit --forget alpha; echo "rc=$?"         # => rc=0
kk.unit --forget alpha; echo "rc=$?"         # => rc=1
kk.unit alpha; echo "rc=$?"                  # => rc=2
# 2> kk.unit alpha: not the header of a unit file
```

---

## 2. Units: the rules

### 2.1 The header and its placement

The two header lines must be the first lines that are neither blank nor `#`
lines — a shebang and a comment block may come first — and must end within the
file's first **512 characters**: the name index reads one 512-character block
per candidate file, without a fork. Shapes:

```bash
# inside the kbool tree: ONE relative path, to kbool.sh (../ in kkore and kklass, ../../ in kcl)
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tlist.sh}../../kbool.sh" || return
kk.unit tlist || return $__kk_unit_rc
```

```bash
# outside the tree: through KBOOL_HOME (rc 2 when neither kbool nor KBOOL_HOME is there)
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit myunit || return $__kk_unit_rc
```

Line 1 is the loader guard: `__KK_UNITS` is an associative array with an
element exactly while kbool is loaded in this shell (set -u safe, no fork, not
fooled by an exported scalar). `kuse.sh` itself has no header — `kbool.sh`
sources it plainly and registers it.

### 2.2 Identity

A unit's name is its file stem (`kk.unit` with another name is rc 2). The name
is **unique** in a shell: the registry maps NAME → the file it was loaded from,
and the same file in any spelling (`C:\x`, `C:/x`, `/c/x`, `a/../b`, a symlink)
is recognised with `[[ -ef ]]`. The same NAME from another file is rc 2 —
whether the second file is sourced, named by path, or what `kk.uses NAME`
resolves to from some caller. Among HEADERED files of one name on the search
path the first one wins, silently.

### 2.3 Lookup of a NAME

1. the calling file's folder — a relative calling file is taken against the
   `$PWD` it was loaded from (a script that `cd`s keeps its folder). Without a
   calling file (a prompt, `bash -c`, `bash -s`, a pipe): only at an
   **interactive prompt** (`$-` has `i`), as `$PWD`;
2. the `unitpath` folders of the merged configuration, strongest level first;
3. the system paths `$KBOOL_HOME/kkore`, `$KBOOL_HOME/kklass`, `$KBOOL_HOME/kcl/*`.

A folder entry `dir/*` means every subfolder of `dir`, each probed for
`NAME.sh`. Only a file whose header names it (`kk.unit NAME`) counts. A loaded
kkore or kklass unit is never resolved again — a headered `klib.sh` in the
caller's folder or in `$PWD` is ignored (a name NOT loaded yet is found in the
caller's folder first). A loaded unit no lookup finds (loaded by path
from elsewhere) is a no-op by NAME. Resolutions are cached per (calling folder,
NAME) for the shell session; `kk.project` empties the caches.

<!-- doctest -->
```bash
printf '%s\n' '#!/bin/bash' \
    '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
    'kk.unit near || return $__kk_unit_rc' 'echo "near: loaded"' > near.sh
printf '%s\n' '#!/bin/bash' \
    '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
    'kk.unit klib || return $__kk_unit_rc' 'echo "a fake klib"' > klib.sh   # a headered decoy
source /path/to/kbool/kbool.sh || exit
kk.uses klib; echo "klib: rc=$?"             # => klib: rc=0
bash -c 'source "$KBOOL_HOME/kbool.sh"; kk.uses near; echo "bash -c: rc=$?"'   # => bash -c: rc=2
# 2> kk.uses: unit 'near' not found
cd /
kk.uses near; echo "script after cd: rc=$?"  # => near: loaded
                                             # => script after cd: rc=0
```

### 2.4 Loaded once; complete or not

`kk.uses` knows a unit's rc: a non-zero source forgets the unit. A **plain**
`source` returns its rc to its caller only, so a plain-sourced unit counts as
complete once its `source` frame has returned — unless a loader error happened
inside its load: a header error, a cycle, a name clash, a refused
`kk.namespace`, a kklass *Duplicate identifier*, or any failed `kk.uses` that is
not `--optional`. That **taints** the innermost unit being loaded, and its next
load — a plain `source` or `kk.uses` — runs it again (`kk.uses` of a tainted unit
that returned 0 is rc 2: `unit 'X' is not completely loaded`). A plain-sourced
unit that fails by its own `return N` cannot be told from a complete one.

A **cycle** (A uses B uses A while A loads) is rc 2 naming the chain:
`kbool: error: circular unit reference: a -> b -> a`.

A file **without** the header loaded by `kk.uses PATH` is remembered by its
lexically normalised path (never by name): a second `kk.uses` of it is a no-op,
a plain `source` re-runs it.

<!-- doctest -->
```bash
mk() { printf '%s\n' '#!/bin/bash' \
        '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
        "kk.unit $1 || return \$__kk_unit_rc" "$2" > "$1.sh"; }
mk ca 'kk.uses cb || return'
mk cb 'kk.uses ca || return'
mk half 'echo "half: runs"; kk.uses absent || return'
printf 'echo "plain: runs"\n' > plain.sh
source /path/to/kbool/kbool.sh || exit
kk.uses ca; echo "rc=$?"           # => rc=2
# 2> kbool: error: circular unit reference: ca -> cb -> ca
# 2> kk.uses: loading unit 'cb' failed
# 2> kk.uses: loading unit 'ca' failed
# 2> kk.uses: unit 'absent' not found
source ./half.sh; echo "rc=$?"     # => half: runs
                                   # => rc=2
source ./half.sh; echo "rc=$?"     # => half: runs
                                   # => rc=2
kk.uses ./plain.sh ./plain.sh      # => plain: runs
```

### 2.5 Child shells

Bash never exports an array, so a child `bash` — even one that inherited the
loader functions through `set -a` or `export -f` — starts with an **empty
registry** and loads its units again (harmless: same files, same sites).
`kk.uses` and `kk.project` there source `$KBOOL_HOME/kbool.sh` first;
`kk.config`, `kk.defined` and `kk.namespace` are rc 2. A `( … )` / `$( … )`
subshell shares the parent's registry.

---

## 3. Registry and ownership

* **Units** — NAME → file; the file's PWD for relative spellings; done /
  tainted / system flags; NAME → the classes it declared (fed by kklass, so
  `--forget` can drop them).
* **Declared namespaces** — X → the unit and file that declared it first
  (first owner wins). Declared are: every unit's own name (`kk.unit`), every
  `kk.namespace X`, and kkore's `kk kl ke kv kc`; kklass adds its own `kkp`
  and records `kk kl ke kv` itself, so they are taken also without kbool.
  kklass refuses a class or an instance named like any of them with ONE table
  lookup — nothing lists bash's function table (that costs O(functions) after
  any definition, ~quadratic). The other direction holds too: `kk.unit NAME`
  and `kk.namespace X` refuse a NAME / X that already is a built class or a live
  instance (kklass's hook). A namespace's own unit/file may declare a class of
  that name (kcl's `class dateutils` in `dateutils.sh`).
* **Sharing** — a declared namespace may be declared again only from the
  owner's file or a file in the owner's **folder** (a package: thttpserver's
  three files share `ths`; a unit *named* like the namespace counts as such a
  file); a file elsewhere, a file-less caller (a prompt, `bash -c`) or a unit
  named like it from another folder is refused (rc 2).
* **Hooks for kklass** (internal): `kk._unit_current` (the unit being loaded),
  `kk._unit_add_class`, `kk._unit_forget_class` (kklass defines it; `--forget`
  calls it), `kk._namespace_add` / `kk._name_in_use` (kklass's taken-names table).

<!-- doctest -->
```bash
mk() { mkdir -p "${1%/*}"; printf '%s\n' '#!/bin/bash' \
        '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
        "kk.unit $2 || return \$__kk_unit_rc" "$3" > "$1"; }
mk pkg/pa.sh pa 'kk.namespace pk || return; pk.one() { :; }'
mk pkg/pb.sh pb 'kk.namespace pk || return; pk.two() { :; }'
mk other/po.sh po 'kk.namespace pk || return'
source /path/to/kbool/kbool.sh || exit
kk.uses pkg/pa.sh pkg/pb.sh; echo "package: rc=$?"   # => package: rc=0
kk.uses other/po.sh; echo "foreign: rc=$?"           # => foreign: rc=2
# 2> 'pk' is already the function namespace of unit pa
# 2> only a file in that folder may share it
# 2> kk.uses: loading unit 'po' failed
kk.namespace kv; echo "kkore's: rc=$?"               # => kkore's: rc=2
```

---

## 4. Configuration file reference

Levels and the merge rule: [kbool README, Configuration](../README.md#configuration).
The reader (`kk._cfg_read`) is fork-free and executes nothing:

* UTF-8; a leading UTF-8 BOM is skipped; LF or CRLF (every CR is dropped). A
  file that is UTF-16 (a `FF FE` / `FE FF` start — PowerShell 5's `>`), holds a
  NUL byte, or has CR-only line ends is ignored with ONE WARNING.
* One `key = value` per line: the key is the text before the first `=`, the
  value the text after it, both trimmed. `#` lines are comments; a `#` inside a
  value is data. No quoting, escapes, `~` or `$VAR`.
* Keys `unitpath` (list of folders), `defines` (list; ASCII names
  `[A-Za-z_][A-Za-z0-9_]*`, case-sensitive), `debug` (`quiet` | `default` |
  `debug`; empty = default), `ckkdir` (folder). A list key repeats to append; an
  empty list value resets (see the merge rule); a scalar's last line wins.
* Folders: every `\` becomes `/` (`C:\x\units\*` is the every-subfolder form); a
  relative one is joined to the config file's folder and `.`/`..` folded
  lexically (symlinks are not resolved); an absolute one keeps its drive / root
  spelling (no cygpath).
* A line without `=` or with an empty key, an unknown key, a bad debug level, a
  define that is not a name (the other names on the line are kept), a line over
  4096 characters: `kbool: WARNING: FILE:LINE: …`, the line skipped. Only the
  first 64 KiB of a file are read (WARNING; the cut last line dropped). Worst
  case under the limits: ≤ 0.26 s per file; a usual 10-line file ~1 ms.
* `debug` writes `VERBOSE_KKLASS` only when it is unset or still holds the value
  the config itself wrote; it is never exported. Limitation: a script that
  assigns exactly the value the config wrote cannot be told from it.
* `/etc/kbool` can be replaced through `__KK_CFG_ETC` — a hook for hermetic
  tests (the ktests runner uses it), not an API.

<!-- doctest -->
```bash
mkdir -p "$HOME/.kbool/demo/units"
cat > "$HOME/.kbool/demo/project.conf" <<'EOF'
unitpath = units
defines  = DEMO TRACE
EOF
source /path/to/kbool/kbool.sh || exit
kk.config defines; echo "rc=$?"                  # => rc=1
kk.project demo || exit
kk.config defines list; echo "$RESULT: ${list[*]}"   # => 2: DEMO TRACE
kk.config unitpath; echo "${RESULT#"$HOME"/}"    # => .kbool/demo/units
kk.defined TRACE; echo "TRACE: rc=$?"            # => TRACE: rc=0
kk.defined NOPE; echo "NOPE: rc=$?"              # => NOPE: rc=1
kk.defined; echo "none: rc=$?"                   # => none: rc=2
kk.config colour; echo "unknown key: rc=$?"      # => unknown key: rc=2
```

---

## 5. Security notes

* **No environment-supplied state.** The registry is a set of associative
  arrays, and bash never exports an array, so no environment variable can
  pre-fill it. `kbool.sh` marks the tables as this shell's with a one-element
  associative array (`__KK_LOADED`); every entry point checks it **before** it
  subscripts a table by a caller-, path- or name-derived key — on a table that
  is not an associative array bash would evaluate the key as arithmetic
  (`d[$(cmd)]` would run `cmd`). A child with inherited exported functions
  therefore sees no registry and starts its own (section 2.5). `kbool.sh`
  starts every boot from freshly declared tables (unset, then declared).
* **Hostile names and paths are data.** Unit names are file stems compared as
  strings and with `-ef`; namespace names must be identifiers; `kk.uses` refuses
  a NAME with blanks or glob characters; array elements are unset with
  single-quoted subscripts (`unset 'T[$k]'`), so `$(…)` inside a key is never
  expanded a second time. The tests run every entry point in an `export -f`
  child and a `set -a` child with `x[$(touch PWN)]` arguments, file names and
  level-named variables: no command runs.
* **No cwd hijack.** A NAME is looked up in the calling file's folder, never in
  `$PWD` for a non-interactive caller without a file (`bash -c`, `bash -s`, a
  pipe); a LOADED kkore / kklass unit is never re-resolved. This is not a
  general guarantee: for a name not loaded yet the calling file's folder comes
  first (first match, silently) — a script whose folder holds a headered
  `kklass.sh` loads it on its first `kk.uses kklass`. Keep unit names unique on
  your search path.
* **Config files are data**: nothing is evaluated or expanded; size, line
  length and encoding are capped (section 4).
* **What is trusted**: `KBOOL_HOME` in a shell that has no kbool yet — a user
  unit's header and `kk.uses` / `kk.project` in a registry-less child source
  `$KBOOL_HOME/kbool.sh` (as much trust as `PATH`); `KBOOL_CONFIG` and
  `__KK_CFG_ETC` (where the config is read from); the unit files on your
  search path. Units run with the caller's privileges, like any `source`.

---

## 6. Limitations

* **No reload.** `kk.unit --forget` / `kk.class --forget` are development
  hatches: live instances of a forgotten class keep their old functions, and
  their names lose the taken-name protection (`kk.class --forget` warns).
* **Unprotected plain libraries.** A library with neither a unit header nor a
  `kk.namespace` line declares nothing: `source libns.sh; T.new libns` still
  replaces its `libns.*` functions. Give it a header or one `kk.namespace` line.
* **A plain-sourced unit that fails by its own `return N`** counts as complete
  (section 2.4); load it with `kk.uses`, which sees the rc.
* **`KK_UNIT_DIR` after a plain nested `source`** points at that file's folder
  (section 1, Variables).
* **A copy of an in-tree unit outside its folder** cannot bootstrap kbool (its
  relative line 1 misses `kbool.sh`: the source fails) and clashes by name with
  the original (`already loaded from …`). Put the folder on `unitpath`, or give
  the copy the user header and its own name.
* **The argument WARNING** misses one case: `source FILE FILE` (a single
  argument equal to the file's own path).
* **`kk.project` once**, before the first non-system unit (anything but `kuse
  klib kerr kvar kcfg`); a project file is
  never re-read.
* A unit runs inside `kk.uses` (and the boot inside a function): file-scope
  `local` / `declare` without `-g` would become the loader's locals — the unit
  lint (`kkore/tests/unit_lint.sh`) rejects them.

---

## 7. Tests

`bash kkore/tests/tests.sh` (threaded; `--mode single` sequential). The loader:
004 (frame / use / error trap), 009 (units and uses), 010 (kbool.sh), 011
(config and kk.project), 012 (declared namespaces), 013 (system unit headers +
lint), 014 (failed dependencies, lookup without a cwd hijack), 015 (the runnable
examples of this page and of the kbool README). Shared helpers, not test files:
`unit_fixture.sh` (a private kbool tree + a hermetic `uf_run`), `unit_lint.sh`,
`doc_examples.sh` (the `<!-- doctest -->` runner).
