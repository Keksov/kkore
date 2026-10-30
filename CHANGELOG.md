# Changelog — kkore

> Draft (launch L6.7): reviewed before the first release (L8).

kkore holds the system units of kbool: the unit loader (`kk.unit`, `kk.uses`,
`kk.project`, `kk.config`, `kk.defined`, `kk.namespace`), output and argument
helpers, the error trap, frames and unique names, a key/value store, and the GNU
tool resolver `ktool`. There is no tag or release yet; this file groups the
whole history by phase, newest first. The reference is [README.md](README.md).
Commit hashes in parentheses point at the change for readers who want the diff.

## Unreleased — first public release (draft)

### Launch: portability, CI and the bash 5.1 floor (2026-10-20 .. 2026-10-30, launch L0-L5)

* **Bash 5.1 is the floor**: `kc.exists`, `kc.delete` and `kv.free` no longer
  double-expand subscripts (a 5.1 failure); special-key tests and a static check
  (018) keep it that way (9d21c81).
* **`ktool`**, the GNU tool resolver (`ktool.gnu FAMILY`, `ktool.lastError`):
  units that wrap `grep`, `sed`, `gawk`, `find`, `head` or `tail` get an absolute
  path to a real GNU tool, including the `g`-prefixed names on FreeBSD, or a
  reason why none is usable (aa318a4). It accepts uutils `head` and `tail` from
  0.2.2 and refuses older ones with a version hint (83e750b). Loaded on demand with
  `kk.uses ktool`, not by `kbool.sh`.
* Windows-only cases of test 011 are "not applicable" passes elsewhere and follow
  the real drive letter on CI; test 014 writes `bash -i` stderr to a file, not a
  pipe (FreeBSD); test 007's perf contract is the best of up to three runs.
* Tests call `"$KT_TIMEOUT"` and SKIP when neither `timeout` nor `gtimeout` exists.
* All files are LF; every script starts with `#!/usr/bin/env bash` and has its exec
  bit; comma-locale-safe `EPOCHREALTIME` splits in tests 006/007.
* Test 015 no longer depends on the clone's folder name; CI workflow that runs the
  13-row kbool matrix with this commit as kkore (ca183f4); `CONTRIBUTING.md`.
* MIT `LICENSE` added; internal plans moved to `docs/dev/`.

### `kk.uses` and the unit loader (2026-10-06 .. 2026-10-17, uses U1-U5)

* **`kk.unit` / `kk.uses` / `kk.defined`** (U1a): a Pascal-like unit directive.
  `kk.uses tlist` loads a unit by name from a search path, once, and reports a
  unit that failed to load.
* **Configuration**: a config chain read at load, `kk.project` and `kk.config`
  (U1b).
* **Declared namespaces** with `kk.namespace`; a unit name that is taken is refused
  (U2b). A refused `kk.namespace` taints the loading unit, and a declared namespace
  is shared only within its owner's folder (U4 review, U44).
* The system units `kuse klib kerr kvar kcfg` carry unit headers; a failed
  dependency taints the dependent unit; lookup is cwd-safe (U3).
* A fast path for re-loading an already loaded unit (`kk.unit` calls `kk._unit`
  only the first time, about 19 percent cheaper) (K7).
* Single-quoted `unset` of variable subscripts (U2a review).
* A doc-example checker and the `kuse` API reference in the README (U5).
* `kk.class --forget` warns about live instances.

### Shared helpers and strict identifiers (2026-09-06 .. 2026-10-05)

* `kk.isInt` and `kk.isNum`: shared numeric guards used across kcl; sourcing is
  safe under `set -u` (7532cad).
* `kk.debug` and `kk._outName`: the shared diagnostic switch and output-name
  validator (kcl review P9); `kk.warn` writes warnings to stderr and is silenced
  by `VERBOSE_KKLASS=quiet`.
* A locale-exact identifier rule shared by `kk._is_ident`, `kk._outName`,
  `kk._setOut` and `kc.alias`: no locale switch, and exact under every locale,
  `globasciiranges` and `nocasematch` combination (c5f8181). Names such as `ı`,
  `İ` or `Ａ` now answer rc 2 without a bash diagnostic.
* Fork-free clock in the `kv.new` batch timing test.

### Hardening (2026-07-08)

* A hardening and optimisation pass over the core, and a fix so `kerr.sh` does not
  leak a global `SCRIPT_DIR` (5fb403a, 5b54035).

### Foundations (2025-11-28 .. 2026-06-01)

* First version: library helpers, variable management (`kv.*`), configuration
  management (`kc.*`) with edge-case tests, error handling split into its own
  module with input validation, and frame management for nested calls.
* An option to exit on error, and script-directory resolution fixed.
* The test runner became a thin wrapper over the ktests framework.
