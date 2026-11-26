#!/usr/bin/env bash
# kkore/kuse.sh — the unit loader: kk.unit, kk.uses, kk.namespace, kk.defined, kk.project,
# kk.config.
# Design: kklass/USES_PLAN.md (decisions U1-U44, §7 amendments, header shapes §7.4);
# reference: kkore/README.md.
#
# A UNIT is a file whose first lines — after an optional shebang, blank lines and
# `#` comment lines, all within its first 512 characters — are the two header
# lines (§7.4):
#
#     [[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tlist.sh}../../kbool.sh" || return
#     kk.unit tlist || return $__kk_unit_rc
#
# (a unit outside the kbool tree uses `source "${KBOOL_HOME-}/kbool.sh" || return 2`
# on line 1). Line 1 bootstraps kbool.sh when it is not loaded yet; line 2
# registers the unit, so a repeated plain `source` of the same file is a no-op.
#
#   kk.unit NAME            the header. rc 0 = load the unit now (registered,
#                           KK_UNIT_DIR = its folder); rc 1 = already loaded, skip;
#                           rc 2 = error (printed). $__kk_unit_rc is 0 on a skip and
#                           2 on an error, so `|| return $__kk_unit_rc` makes the
#                           source return 0 or 2.
#   kk.unit --forget NAME   drop a unit's registration (and its classes, through the
#                           kk._unit_forget_class hook kklass defines) so the next
#                           source loads it again. rc 0 / 1 not registered / 2 error
#                           (no name, a system unit kbool.sh loaded, a unit loading now).
#   kk.uses [--optional] ARG...  load units once. ARG with `/`, `\` or ending in `.sh`
#                           is a PATH (relative = relative to the calling file); anything
#                           else is a unit NAME, ALWAYS resolved (U43: except a loaded
#                           kkore / kklass unit, which is never resolved again) — the
#                           calling file's folder (a relative calling file against the
#                           PWD it was loaded from; without a calling file only at an
#                           interactive prompt: $PWD), then the project paths (the merged config
#                           `unitpath`, U1b), then the system paths
#                           (kkore, kklass, kcl/*) — and compared with the unit of that
#                           name already loaded: the same file is a no-op, another file
#                           is an error (owner 2026-10-06). Only files carrying the
#                           header count for a NAME lookup; other files are reachable
#                           by path only. A name no lookup finds but that is loaded
#                           (kuse and kbool, which carry no header) is a no-op.
#                           rc 0 = all loaded (or already loaded); rc != 0 = the first
#                           failure (rc 2 for a loader error, else the unit's own rc).
#                           A failure taints the unit being loaded (U42), unless
#                           --optional: then it is silent and taints nothing.
#   kk.namespace X [Y ...]  declare more function namespaces (X.*) of the calling file,
#                           besides the unit's own name (kk.unit declares that one):
#                           kklass refuses a class or an instance named like a declared
#                           namespace (U22/U40, "Declared namespaces" below). A name
#                           another file declared is shared only from the owner's
#                           folder (U44). rc 0 / 2.
#   kk.defined NAME         rc 0 when NAME is a define of the merged config (U1b),
#                           1 when not, 2 without a name.
#   kk.project PATH|NAME    read a project file (U8-U11, U37): its unit folders,
#                           defines, debug level and .ckk folder take effect. Once,
#                           and before the first kk.uses of a non-system unit.
#   kk.config KEY [OUTVAR]  the merged config value (unitpath, defines, debug, ckkdir).
#   kk.settings FN [VAR...] a unit's settings hook (kklass/docs/dev/IMAGE_PLAN.md §5.2,
#                           IMG-D5): only inside a unit's load, after FN is defined.
#                           Runs FN at once and records it under the unit being loaded
#                           (__KK_UNIT_SETTINGS, load order) with the VARs it sets
#                           (__KK_SETTINGS_VARS; one VAR may be listed by several
#                           units). FN may be `:` (nothing to run, VARs only). rc =
#                           FN's rc; a non-zero rc also taints the unit (U34), so a
#                           plain-sourced unit whose hook failed loads again. rc 2,
#                           printed, nothing recorded or run: outside a unit's load or
#                           in a subshell of it (`$(kk.settings …)`: the record would be
#                           lost); and, the unit tainted like a header error, inside a
#                           running hook, without FN, FN not a function, a VAR not a
#                           name. `kk.unit --forget` (any
#                           drop of the unit) removes its entries. The rules for a
#                           hook function are in "Settings hooks" below.
#   kk.localeDefault        export LC_CTYPE=C.UTF-8 when none of LC_ALL, LC_CTYPE,
#                           LANG is set non-empty; else nothing. rc 0.
#   kk.image [--optional] UNIT...  a load image (kklass/docs/dev/IMAGE_PLAN.md):
#                           as `kk.uses [--optional] UNIT...` (the same units, the
#                           same rc), but when a valid saved image of this load
#                           exists it is sourced instead (then the settings hooks
#                           of its units run, in __KK_UNIT_SETTINGS order) — rc 0;
#                           else a normal load, after which kkore/kimage.sh writes
#                           the image for the next start. Any doubt is a normal
#                           load. --optional goes through the image too (a load
#                           whose optional units all loaded is a plain load's
#                           state); a failed optional unit is kk.uses' quiet rc,
#                           no image, a hold.
#   kk.image --background [--optional] UNIT...  as kk.image, but a miss
#                           does not wait for the writer (owner decision
#                           IMG-D10; bin/fvdlg's start): kk.uses' load at
#                           once (its rc, its units), then a detached
#                           background process — a fresh $BASH running
#                           kkore/kimgbg.sh — writes the image exactly as a
#                           foreground miss would and ENDS BY ITSELF (a few
#                           seconds; a hard limit of 120 s). It runs under
#                           setsid (no terminal), timeout and nice where
#                           found: GNU timeout kills it AND its children at
#                           the limit (their own process group); busybox's
#                           (Alpine) and FreeBSD's signal it alone. Without
#                           a timeout tool (stock macOS) the writer is its
#                           own watchdog ("watch" mode: it runs itself again
#                           in a process substitution and waits on that pipe
#                           with read -t; TERM, then KILL, to that writer
#                           at the limit; its children are not killed as a
#                           group). The caller's $!, job table,
#                           traps and options are untouched; the writer
#                           holds none of its descriptors (0-2 /dev/null:
#                           `x=$(cmd)` returns at once). One writer per
#                           image (its marker NAME.bg next to the image: a
#                           second start meanwhile is a plain load, no
#                           wait); a writer killed or stopped: no damaged
#                           image, a hold of 10 minutes; a writer that
#                           refuses: the foreground writer's hold. No
#                           background writer with units loaded before
#                           (a prior set: a hit still, else a plain
#                           kk.uses). KBOOL_IMAGE=off: no image, no writer.
#                           Details, seams and limits: kkore/kimgbg.sh.
#                           rc 2 with --rebuild / --forget / --path.
#   kk.image --rebuild [--optional] UNIT...  a normal load, then the image
#                           written even when the old one is valid; clears a
#                           hold. rc = the load's.
#   kk.image --forget UNIT...  remove this request's images, .ref, .fnc and .vck files, holds
#                           (every key) and dead temps from the image folder (a
#                           trusted one; also under KBOOL_IMAGE=off). rc 0; 2
#                           without a unit.
#   kk.image --path [UNIT...]  print the image path this start would use
#                           (without units: the folder). rc 0 valid (the folder:
#                           trusted); 1 none, stale, refused, held, not
#                           applicable (nothing printed when there is no path);
#                           2 a usage error (two actions, an unknown option).
#
# Load images (stages I2a, I2b of the plan: an image of a script's first load,
# and chained images on top of units loaded before). Flags, read on every call:
#   KBOOL_IMAGE=off|0       every kk.image is a plain kk.uses.
#   KBOOL_IMAGE_DIR=DIR     the image folder (else, on Linux / macOS / BSD,
#                           $XDG_CACHE_HOME/kbool/image/v1 or ~/.cache/kbool/image/v1;
#                           on Git-bash / MSYS2 / Cygwin $LOCALAPPDATA/…, else
#                           $USERPROFILE/AppData/Local/…, else ~/.cache/…). Root
#                           (EUID 0) uses images only under KBOOL_IMAGE_DIR.
#   KBOOL_IMAGE_CHECK=stat|dates|hash  how a changed file is noticed (the
#                           stamped files: every file of the load, kbool.sh,
#                           kkore, kklass.sh). Default stat on Linux / macOS /
#                           BSD, dates on Git-bash / MSYS2 / Cygwin; another
#                           value -> the default and a debug line. The
#                           EFFECTIVE mode is keyed (switching modes uses another
#                           image), and so is the stat / cksum the start runs
#                           (its path: another tool, another image).
#                           stat:  ONE `stat` per start (GNU -c '%s %.9Y %.9Z
#                                  %i %u %a', else -c with whole seconds, else
#                                  BSD -f '%z %Fm %Fc %i %u %Mp%Lp', else -f with
#                                  whole seconds: the flavour probed by the
#                                  writer, GNU first as kcl TPath does, and kept
#                                  in the image) — size, mtime, ctime, inode,
#                                  owner, mode; on POSIX also refuses a group-
#                                  or world-writable image file and an image
#                                  folder that is world-writable without the
#                                  sticky bit (a group-writable folder is
#                                  accepted: the image and its .ref must be this
#                                  user's, no symbolic link) — the WARNING when
#                                  an image exists, nothing written otherwise.
#                                  The Windows runtimes make modes up: no bits
#                                  checked, no mode stamped there. With whole
#                                  seconds only (or nanosecond times whose
#                                  fractions are all zero: a whole-second
#                                  filesystem), a file whose mtime is the
#                                  second the stamps were taken in is "racy": a
#                                  miss (git's rule); an mtime-keeping change
#                                  inside that second is not seen. A stamped
#                                  file whose ctime is later than now at write
#                                  time: no image, a hold.
#                           dates: no fork — every stamped file older than the
#                                  image's NAME.NONCE.ref (named after the
#                                  image's nonce: two writers at once each have
#                                  their own), made before its load; blind to a
#                                  same-size edit with the old mtime (cp -p, an
#                                  old-dated archive): KBOOL_VERSION is keyed
#                                  for releases. A clock that lags the files'
#                                  (a network KBOOL_HOME) can let a stale image
#                                  hit: use stat or hash there.
#                           hash:  ONE `cksum` per start (content only: touch is
#                                  no change).
#                           stat / cksum not on PATH, or a stat that takes
#                           neither -c nor -f (the writer finds that out and
#                           leaves FOLDER/stat.hold for an hour): runs as dates.
#   KBOOL_IMAGE_CHAIN=on|off  on (the default): an image may sit on top of the
#                           units loaded before kk.image — the prior set P, the
#                           non-system units registered complete, in load order
#                           (__KK_UNIT_ORDER); P's names and files are key rows
#                           (`kk.uses a; kk.image b`, `kk.image b`, another P or
#                           P in another order: four images) and P's files are
#                           stamped. off: any such unit makes kk.image a plain
#                           kk.uses. Another value: on, and a debug line.
# A chained image holds only this call's delta: its units, and its changes to
# slots that existed before — kkore's tables, P's kklass tables and
# registries, scalars (element by element, an element removed too), a
# function of P's it redefined — each with its earlier value (a function: its
# earlier text) in the base list. A start checks the base before sourcing,
# fork-free (bash < 5.3 reads a function's text through the image's NAME.fnc:
# one that is a symbolic link, a folder, another user's or not writable makes
# the start a plain kk.uses and the writer hold, naming it): a slot that
# differs is a plain kk.uses, nothing written; the undo of a failed start puts
# every base slot back. The base list also holds the READ base: every
# variable of P's that this call's unit files name as a word (comments cut) —
# P's load made it, or it came from the environment and P's own files assign
# it (P's load may have defaulted it; the request's own environment names,
# NO_COLOR say, are no P state) — with its state before
# the load (a scalar's value or unset, an indexed array's element count and
# last index, an associative one's count; not bash's own, RESULT, kkore's or
# a hook VAR), so a script that changed such state after the image was made
# (an environment preset of P's default, a list it shortened, a registry key
# it added, a variable a unit copies) gets a plain kk.uses. kklass bumps
# _KKLASS_GEN on every class built or method defined: a load that builds a
# class has it in its base, so a script that changed a P class after the
# image was made (defineMethod) gets a plain kk.uses too. The writer proves
# such an image in ONE fresh process: P loaded by its files as its own load
# leaves it (P's loads run again there: their side effects — files, output —
# repeat once per chained miss), the image applied as a start applies it, the
# state compared with this one (names only this script made are ignored) — so
# an image never depends on what the script changed in P before kk.image (a P
# class changed by defineMethod, a P variable, a class the script built: no
# image, a hold); the M1 probe below runs there too, on top of P. Limit (plan
# R13, documented): an image is valid for P as its own fresh load leaves it
# in the writer's environment, plus the read base — reads through P's
# FUNCTIONS (a unit calling a P function that reads P state), and names the
# word scan cannot see (built by eval or indirection, `${!name}`), are not
# guarded; set KBOOL_IMAGE_CHAIN=off for such a program. A chained load is
# refused (no image, a hold) when it changes the hash table, an exported
# variable, a nameref, a readonly variable, the attributes of a variable or
# removes one, or when an earlier value (or key) of a slot it CHANGES holds a
# CR byte (the base list is one compound array, which the MSYS-family parsers
# read without its CR bytes; a scalar it only READS keeps such a value in its
# %q form, flag q, and is compared as that); a header-less file
# loaded by path before kk.image makes it a plain kk.uses. Holds and pruning
# go by (request, P, mode): the image file name hashes all three, so a hold
# is shared by every script with that key — one whose load is refused (a
# variable it changed in P) holds the same key for a clean one for an hour.
# Not worth an image: a writer whose normal load took less than 1.5 times
# what a start of the image costs (chained: the fresh process's simulated
# start, plus the steps of kk.image before the writer; unchained those steps
# alone) writes none and holds — a near miss (the load at least half that)
# 10 minutes, not an hour: one timing spike — (__KK_IMG_MINLOAD=MS, a test
# seam, sets an absolute floor instead). A script that builds a class of its own BEFORE
# loading P gets no chained image either: P's class tables and kklass's
# _KKLASS_GEN differ from P's own fresh load (no image, a hold).
# Also a plain kk.uses: inside a unit's load or a settings hook, under `set -a`,
# a relative KBOOL_IMAGE_DIR, a folder that cannot be made (its deepest
# existing level not writable: no writer either) or exists unwritable (no
# writer on a miss), no trusted folder (every level from the base down a
# folder this user owns, not a symbolic link or junction; an existing image
# file that fails a check gets ONE WARNING per process), and — on a start — a
# variable the image creates that exists in the caller's view already (a
# readonly one, a caller's local or nameref, a global of another kind, a
# preset, also a bare `local NAME` with neither a value nor an attribute: the
# image would write into it) — ONE `declare -p` over the image's names (on
# bash < 5.3 through the image's NAME.vck, made by the writer: a marker line
# tells a complete read; one that cannot serve means a declare -p per name).
# Limit (chained): a calling function's local that
# shadows a P global which a unit sets with `declare -g` — the normal load
# writes the global, the image's delta line (a plain assignment, sourced in
# the start) writes the local, and the base check reads the local (equal):
# once the function returns, a hit leaves the global as it was. VERBOSE_KKLASS=debug prints a `kbool:
# image: …` line for every reason. An image holds this call's units: their
# functions, the variables they created (readonly flags last; one declared
# without a value — `declare -gA X` — declared again without one), their kklass
# tables and their kkore registration (last, with the earlier value of every
# pre-existing slot it changes: kkore's; chained, P's too), its dependency
# edges (also a dependency NOT found,
# a failed `kk.uses --optional`: found later — a unit file with the header —, the image is stale). Never
# held: kbool.sh's state, settings hook variables (the hooks run again),
# exports, __kk_ft, the name index and caller-keyed tables, __KK_UNIT_PID (pid
# state; absent after an image start, which nothing reads for a loaded unit),
# shell-owned variables, traps, options, aliases, umask, the hash table, jobs,
# descriptors.
# No image (a refusal) when the load fails (a failed --optional unit too);
# changes exports, traps, options, aliases, umask, function attributes
# (exported, traced, readonly), disabled builtins (enable -n), completions,
# the hash table (unless its settings hooks make the change: they run on every
# start), an existing function or (non-kkore) variable outside the hooks
# (unchained; chained, a change becomes a delta, above); sets, when it is absent, a variable that existed before the load (an
# environment preset of a unit's internal `_` default, a caller's variable
# hiding a unit global — the image would lack it): candidates are the
# caller's variables and exported names (not bash's, the environment's,
# kbool's); those that occur as a word in the unit files (comments cut) are
# probed by ONE fresh bash that loads the request without them, with this
# shell's settings (KBOOL_*, exported or not), in its $PWD (a miss costs
# one more load then, only then); a probe that cannot do the same load (no
# result, another rc, other units) is a refusal too; starts a background
# job or a coprocess; leaves a file descriptor open or closes one (kklass's
# pair excepted); a stamped file has a future mtime (or, stat, ctime); a
# function holds a CR byte this parser drops that kklass's kk._fn_text_cr
# cannot rewrite; bash < 5.2 and a function text with `&> "$` (IMG-D9); a
# bash whose declare -f prints `1<> FILE` as `<> FILE` (5.1 and 5.2: it reads back as
# fd 0; probed) and a function text with a ` <> ` that does not read back as
# ` 1<> ` (such a bash prints fd 0 as `0<> FILE`, so the image says ` 1<> `
# for its bare ` <> ` — every function holding one defined again from that
# text must print back as before: a ` <> ` inside a string fails that); a
# plain scalar outside the hooks that holds this shell's pid (pid state
# belongs in a hook VAR: an image would hand every start the writer's pid; a
# readonly or integer one is a constant; held 10 minutes only — a constant
# that equals the pid by chance is gone on the next start); or
# (unchained) a unit was used (or forgotten) before in this shell. Not compared: resource
# limits (ulimit), the directory stack.
# A damaged image is undone and loaded normally — but a flipped byte that
# still parses is not detected, and one in an indexed subscript or an integer
# value can end the caller's script (an arithmetic error inside the source);
# there is no checksum (IMG-D8).
# Holds (FOLDER/NAME.hold, `TIME REASON`): a refusal writes one, and so does
# an image written less than 10 minutes before that is stale again or fails
# on its start (it is undone, then removed). While a hold is younger than an
# hour every start that misses is a plain kk.uses with no write (one -f);
# --rebuild and --forget clear it. Silent (no hold) when the folder cannot be
# made or written, a write or rename fails (a native process holding the
# image: the old image stays), or a stamped file changes during the load. A
# hold that cannot be written is no error, also under `set -e`.
# Pruning, on each write, with ONE rm: images whose KBOOL_HOME is gone (this
# runtime's), older than 30 days or unreadable; the oldest beyond 8 per
# (request, prior set), 16 per request name, 64 or 256 MB per folder; holds
# older than an hour; .ref files not of their image's nonce; temps whose
# writer's pid is gone. A writer's own temps go on every exit path (an EXIT
# trap covers a load that ends the script under `set -e`); all of them under
# umask 077, the load itself under the caller's.
# The config file format and the lookup chain (KBOOL_CONFIG -> project -> user ->
# system -> built-in) are described at the "Configuration" section below.
#
# Identity of a unit = its NAME (the file stem, U33) + `[[ -ef ]]` against the
# registered file (U18'): the same name from another file is an error. A cycle
# (A uses B uses A while A loads) is an error naming the chain; it is detected from
# the bottom-relative index of the unit's `source` frame (C12), no RETURN trap.
#
# Completion (U34). kk.uses knows a unit's rc: a failed load is forgotten, so a
# retry loads it again. A PLAIN `source unit.sh` returns its rc to the caller
# only, so a plain-sourced unit counts as complete once its source frame has
# returned — unless a loader error happened inside its load (a header error, a
# cycle, a unit-name/identity clash; since U42 also ANY failed kk.uses in it that
# is not `--optional`: not found, a bad name, a dependency's own rc): then it is
# marked incomplete, and its next load — a plain source or kk.uses — runs it
# again (U42, owner 2026-10-09; before, kk.uses said "not completely loaded"
# until `kk.unit --forget`). A dependency the unit handles itself is
# `kk.uses --optional dep || fallback`.
# A plain-sourced unit that fails by its own `return N` cannot be told from a
# complete one. A file WITHOUT the header loaded by `kk.uses PATH` is remembered
# by its lexically normalised path (and never by name).
#
# Messages: errors and the argument WARNING go to stderr as `kbool: ...` lines,
# silenced only by VERBOSE_KKLASS=quiet (a loader error is a compile error, not a
# member's rc-1 miss — kcl/README.md 1.2 does not apply to it).
#
# Everything here is fork-free (but kk.image's one stat / cksum in those check
# modes, and its holds written outside the writer). All locals carry the reserved __kk_ prefix: bash
# scopes dynamically, and a unit loaded by kk.uses runs inside kk.uses, so its
# file-scope code would otherwise see (and clobber) the loader's variables (C11).

# kuse.sh cannot carry the unit header (kk.unit is defined here): kbool.sh sources
# it plainly and registers it as the unit `kuse`. It has NO re-source guard
# variable — an inherited or exported guard (a parent's `set -a`) made a child
# skip its tables, and `__KK_UNITS=()` then created an INDEXED array (critic C2).
# Sourcing it again redefines the functions and repairs the tables.

# The tables. __KK_UNITS is also the loader guard (`${__KK_UNITS[@]@a} == A*`):
# non-empty exactly while kbool.sh is loaded (kbool.sh puts the sentinel [kbool]
# in it; kk.unit and kk.uses refuse to work without it).
#   __KK_UNITS         name -> absolute file, as spelled when registered
#   __KK_UNIT_SRC      name -> the BASH_SOURCE spelling of its source frame
#   __KK_UNIT_BOT      name -> bottom-relative index of that frame (-1: registered by kbool.sh)
#   __KK_UNIT_DONE     name -> 1 once completely loaded
#   __KK_UNIT_FAIL     name -> 1 when a structural load error happened inside its load (U34)
#   __KK_UNIT_SYS      name -> 1 for the units kbool.sh itself loaded (never forgotten)
#   __KK_UNIT_CLASSES  name -> space-separated classes the unit declared (fed by kklass, U2)
#   __KK_UNIT_FILES    normalised path -> 1: header-less files loaded by kk.uses PATH
#   __KK_UNIT_CAND     stem -> newline-terminated candidate files <stem>.sh, in search order
#   __KK_UNIT_IDX      name -> the first HEADERED candidate ('' = none)
#   __KK_UNIT_RES      callerdir<US>name -> what the name resolves to from there ('' = nothing)
#   __KK_UNIT_HIT      callerfile<US>name -> the registered file it matched (kk.uses fast path)
#   __KK_FILE_PWD      relative file spelling -> the PWD it was loaded from (U43): a relative
#                      calling file is resolved against it, not against the current PWD
#   __KK_DEFINES       define name -> 1: the merged `defines` of the config levels (U1b, U31)
#   __KK_CFG           key -> the merged config value (list keys: newline-terminated entries)
#   __KK_CFG_LV        LEVEL/key -> one level's parsed value; LEVEL/key! = that level reset the list
#   __KK_PROJECT       the project file kk.project read ('' = none yet)
#   __KK_UNIT_USED     the first non-system unit used ('' = none): kk.project is refused after it (U37)
#   __KK_CFG_VKW       the VERBOSE_KKLASS value the config itself wrote ('' = none)
#   __KK_NAMESPACES    namespace X (of functions X.*) -> "UNIT<US>FILE" that declared it (U40):
#                      every unit name (kk.unit), every kk.namespace X, the kkore namespaces
#                      (kbool.sh); kklass refuses a class or an instance named like one
#   __KK_UNIT_PROJPATH / __KK_UNIT_SYSPATH  search path entries; `dir/*` = every subfolder
#                      (PROJPATH = the merged config `unitpath`; SYSPATH = kkore, kklass, kcl/*)
#   __KK_LOADED        [on]=1, set by kbool.sh: THIS shell owns the tables (R14). Checked as
#                      `${__KK_LOADED[@]@a} == A` by every entry point before any table
#                      is subscripted by a non-literal key (on a non-assoc table the key
#                      would be evaluated as arithmetic: `d[$(cmd)]` runs cmd)
#   __KK_UNIT_ORDER    INDEXED, dense: the load order of the units (IMAGE_PLAN §7.7), one
#                      element `KIND<US>NAME` per registered unit, oldest first. KIND is
#                      `s` for a system unit (kbool.sh loaded it: __KK_UNIT_SYS) and `u`
#                      for every other unit. It is REGISTRATION order (when a load
#                      began, plan §7.7): a unit is appended when it is registered for a
#                      load — by its header (kk.unit, rc 0) or by kbool.sh
#                      (kk._unit_register, which turns the header's `u` entry of a system
#                      unit into an `s` one) — so a unit appears before the units its
#                      load uses (`kk.uses a` where a uses b: a, b). Replaying the `u`
#                      units in this order BY PATH, `kk.uses "${__KK_UNITS[NAME]}"`,
#                      repeats the same nesting (by name, a unit local to the original
#                      caller's folder would not be found from another file). Every
#                      drop removes the entry (`kk.unit --forget`, a failed or
#                      incomplete load), so a reload is appended at the end again.
#                      While a unit loads, and after a plain-sourced load that was
#                      tainted (U34), its entry is there but the unit is not complete:
#                      a reader keeps only the names kk._unit_complete accepts (quiet,
#                      no side effects). kbool itself (the sentinel) is not in it.
#   __KK_UNIT_PID      name -> $BASHPID of the shell that registered it for its load
#                      (kk.settings refuses a call from a subshell of the load)
#   __KK_UNIT_SETTINGS INDEXED, dense: one element `UNIT<US>FN` per kk.settings call, in
#                      call order (a unit's hooks in its load order; a nested load's
#                      between its parent's). A drop of UNIT removes its elements.
#   __KK_SETTINGS_VARS VAR -> the units that listed VAR in kk.settings, each `UNIT<US>`
#                      (first lister first, no repeats); a drop of UNIT removes it, an
#                      emptied VAR loses its key.
#   __KK_SETTINGS_RUN  while kk.settings runs a hook: `B<US>UNIT<US>FN`, B = the
#                      bottom-relative index of that kk.settings frame in FUNCNAME; ''
#                      otherwise. Counts only while that frame is still on the stack
#                      (kk._settings_hook), so a value left behind by an abnormal exit is
#                      inert. An image start runs the hooks through kk._image_hook,
#                      which sets the same mark for its own frame.
declare -g __KK_SEP=$'\x1f'
kk._unit_tables() {
    local -
    local __kk_t
    set +u
    for __kk_t in __KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_FAIL \
                  __KK_UNIT_SYS __KK_UNIT_CLASSES __KK_UNIT_FILES __KK_UNIT_CAND __KK_UNIT_IDX \
                  __KK_UNIT_RES __KK_UNIT_HIT __KK_DEFINES __KK_CFG __KK_CFG_LV __KK_NAMESPACES __KK_FILE_PWD \
                  __KK_SETTINGS_VARS __KK_UNIT_PID; do
        # keep an ASSIGNED assoc; replace anything else (unset, declared-but-
        # unassigned — whose `${R[@]@a}` reads "A" —, a scalar, an indexed array)
        if [[ ${!__kk_t@a} != *A* ]]; then
            unset "$__kk_t"
            declare -gA "$__kk_t"
            eval "$__kk_t=()"
        fi
    done
    for __kk_t in __KK_UNIT_PROJPATH __KK_UNIT_SYSPATH __KK_UNIT_ORDER __KK_UNIT_SETTINGS; do
        if [[ ${!__kk_t@a} != *a* ]]; then
            unset "$__kk_t"
            declare -ga "$__kk_t"
            eval "$__kk_t=()"
        fi
    done
    if [[ ${__KK_UNIT_IDX_OK-} != [01] ]]; then __KK_UNIT_IDX_OK=0; fi
    : "${__KK_PROJECT=}" "${__KK_UNIT_USED=}" "${__KK_CFG_VKW=}" "${__KK_SETTINGS_RUN=}"
    __kk_unit_rc=0          # the header's `return $__kk_unit_rc`: 0 skip, 2 error
    return 0
}
kk._unit_tables

# ---------------------------------------------------------------------------
# Messages
kk._unit_err() {
    if [[ "${VERBOSE_KKLASS:-}" != quiet ]]; then
        printf 'kbool: error: %s\n' "$*" >&2
    fi
    return 0
}

kk._unit_warn() {
    if [[ "${VERBOSE_KKLASS:-}" != quiet ]]; then
        printf 'kbool: WARNING: %s\n' "$*" >&2
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Paths (lexical only — no cd, no fork)

# kk._unit_lexnorm PATH -> __kk_n: absolute, `/`-separated, `.`, `..` and `//`
# folded; `C:\x` and `C:/x` become `/c/x`. Lexical, so it does not resolve
# symlinks: used for messages, KBOOL_HOME (validated with -ef) and the keys of
# header-less files, never as a unit's identity (U18'). (A PATH normal
# already — absolute, no `\`, `//`, `.` or `..` segment, no trailing `/` —
# is the answer as it is: one test instead of the segment loop, ~0.15 ms a
# path; load images normalise every prior unit's file on each start, I2b F6.)
kk._unit_lexnorm() {
    if [[ $1 == /?* && $1 != *[\\]* && $1 != *//* && $1 != */ && $1 != */./* && $1 != */../* && $1 != */. && $1 != */.. ]]; then
        __kk_n=$1
        return 0
    fi
    local __kk_p="${1//\\//}" __kk_s __kk_o=""
    if [[ $__kk_p == [A-Za-z]:* ]]; then
        __kk_s=${__kk_p:0:1}
        __kk_p="/${__kk_s,}/${__kk_p:2}"
    fi
    if [[ $__kk_p != /* ]]; then
        __kk_p="$PWD/$__kk_p"
    fi
    __kk_p+=/
    while [[ -n $__kk_p ]]; do
        __kk_s=${__kk_p%%/*}
        __kk_p=${__kk_p#*/}
        case $__kk_s in
            ''|.) ;;
            ..) __kk_o=${__kk_o%/*} ;;
            *) __kk_o+=/$__kk_s ;;
        esac
    done
    __kk_n=${__kk_o:-/}
}

# kk._unit_dir FILE -> __kk_d: the folder of FILE as spelled, made absolute
# against PWD (a no-slash `tlist.sh` -> $PWD).
kk._unit_dir() {
    case $1 in
        */*|*\\*)
            __kk_d=${1%[/\\]*}
            if [[ -z $__kk_d ]]; then __kk_d=/; fi
            ;;
        *) __kk_d=. ;;
    esac
    if [[ $__kk_d == . ]]; then
        __kk_d=$PWD
    elif [[ $__kk_d != /* && $__kk_d != [A-Za-z]:* ]]; then
        __kk_d=$PWD/$__kk_d
    fi
}

# kk._unit_has_header FILE STEM — rc 0 when FILE carries the unit header for STEM:
# within its first 512 characters, skipping blank lines and `#` lines (a shebang,
# a comment block), the first or second remaining line is `kk.unit STEM` followed
# by nothing, a blank or `;|&` (leading blanks and a CR ignored; a line cut by the
# 512-character limit does not count). A missing/unreadable FILE is rc 1.
# ONE `read -N` per file, no fork: a line-by-line `read` costs ~2.5x as much on
# MSYS (it reads in small chunks and seeks back) — P5 measurement in the ledger.
kk._unit_has_header() {
    local __kk_h="" __kk_l __kk_i=0
    IFS= read -r -N 512 __kk_h 2>/dev/null <"$1" || :     # rc 1 at EOF (a short file) is normal
    [[ $__kk_h == *"kk.unit $2"* ]] || return 1    # one scan rejects most non-units
    if (( ${#__kk_h} >= 512 )); then
        [[ $__kk_h == *$'\n'* ]] || return 1
        __kk_h=${__kk_h%$'\n'*}$'\n'               # drop the cut last line
    fi
    while [[ -n $__kk_h ]]; do
        __kk_l=${__kk_h%%$'\n'*}
        if [[ $__kk_h == *$'\n'* ]]; then __kk_h=${__kk_h#*$'\n'}; else __kk_h=""; fi
        __kk_l=${__kk_l%$'\r'}
        __kk_l=${__kk_l#"${__kk_l%%[![:space:]]*}"}
        [[ -z $__kk_l || $__kk_l == '#'* ]] && continue
        if [[ $__kk_l == "kk.unit $2" || $__kk_l == "kk.unit $2"[[:space:]\;\|\&]* ]]; then
            return 0
        fi
        (( ++__kk_i < 2 )) || return 1
    done
    return 1
}

# ---------------------------------------------------------------------------
# Registry state

# kk._unit_check NAME MIN — the state of a REGISTERED unit not marked done.
# MIN is the lowest frame index, in THIS function's view, that counts as an outer
# load (kk._unit passes 4: 0 = here, 1 = kk._unit, 2 = kk.unit, 3 = the header's own file;
# kk._uses passes 3: 0 = here, 1 = kk._uses, 2 = kk.uses, 3 = the calling file,
# which counts — a unit using itself is a cycle).
#   rc 0: the unit's source frame has returned and no error was seen while it
#         loaded -> it is complete (a plain-sourced unit is marked done lazily, here);
#   rc 2: its frame is still on the stack (cycle); printed;
#   rc 3: its load has ended but was tainted (U34: a structural error, or since
#         U42 any failed non-optional kk.uses inside it): NOT complete — silent;
#         the caller drops the registration and loads the unit again (U42).
kk._unit_check() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14, U1b R2)
    [[ ${2-} == [0-9]* && ${2-} != *[!0-9]* ]] || return 2   # MIN reaches (( ))
    local __kk_b=${__KK_UNIT_BOT[$1]--1} __kk_n=${#BASH_SOURCE[@]} __kk_k __kk_j __kk_s __kk_c=""
    if (( __kk_b >= 0 )); then
        __kk_k=$(( __kk_n - 1 - __kk_b ))
        if (( __kk_k >= $2 && __kk_k < __kk_n )) \
           && [[ ${FUNCNAME[__kk_k]-} == source && ${BASH_SOURCE[__kk_k]-} == "${__KK_UNIT_SRC[$1]-}" ]]; then
            for (( __kk_j = __kk_k; __kk_j >= $2; __kk_j-- )); do
                if [[ ${FUNCNAME[__kk_j]-} == source ]]; then
                    __kk_s=${BASH_SOURCE[__kk_j]##*[/\\]}
                    __kk_s=${__kk_s%.sh}
                    if [[ -n $__kk_s && -n ${__KK_UNITS[$__kk_s]+x} ]]; then
                        __kk_c+="$__kk_s -> "
                    fi
                fi
            done
            kk._unit_err "circular unit reference: ${__kk_c}$1"
            return 2
        fi
    fi
    if [[ -n ${__KK_UNIT_FAIL[$1]+x} ]]; then
        return 3        # its load ended incompletely: the caller loads it again (U42)
    fi
    __KK_UNIT_DONE[$1]=1
    return 0
}

# kk._unit_taint MIN — a load error happened (a header error, a cycle, a
# unit-name/identity clash; since U42 any failed non-optional kk.uses): mark the
# innermost unit still being loaded (a `source` frame at index >= MIN in this
# function's view whose registration matches it) as not completely loaded (U34):
# its next load runs it again (U42). kk.uses checks a unit it loaded right after
# its source; this is what catches a PLAIN-sourced one.
kk._unit_taint() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14, U1b R2)
    [[ ${1-} == [0-9]* && ${1-} != *[!0-9]* ]] || return 2   # MIN reaches (( ))
    local __kk_j __kk_s __kk_n=${#BASH_SOURCE[@]}
    for (( __kk_j = $1; __kk_j < __kk_n; __kk_j++ )); do
        [[ ${FUNCNAME[__kk_j]-} == source ]] || continue
        __kk_s=${BASH_SOURCE[__kk_j]##*[/\\]}
        __kk_s=${__kk_s%.sh}
        if [[ -n $__kk_s && -n ${__KK_UNITS[$__kk_s]+x} && -z ${__KK_UNIT_DONE[$__kk_s]+x} \
              && ${__KK_UNIT_SRC[$__kk_s]-} == "${BASH_SOURCE[__kk_j]}" \
              && ${__KK_UNIT_BOT[$__kk_s]--1} == $(( __kk_n - 1 - __kk_j )) ]]; then
            __KK_UNIT_FAIL[$__kk_s]=1
            return 0
        fi
    done
    return 0
}

# kk._unit_loading OUT — OUT (a literal name: RESULT, or a caller's __kk_ local)
# = the name of the innermost unit being loaded right now (rc 0), or '' (rc 1):
# the innermost `source` frame whose file is a registered, not yet complete unit
# registered at exactly that frame. The one stack walk kk._unit_current and
# kk.settings share; it reads no table but the four below and writes only OUT.
kk._unit_loading() {
    if [[ ${__KK_LOADED[@]@a} != A ]]; then printf -v "$1" %s ""; return 2; fi   # R14
    local __kk_lw_j __kk_lw_s __kk_lw_n=${#BASH_SOURCE[@]}
    for (( __kk_lw_j = 1; __kk_lw_j < __kk_lw_n; __kk_lw_j++ )); do
        [[ ${FUNCNAME[__kk_lw_j]-} == source ]] || continue
        __kk_lw_s=${BASH_SOURCE[__kk_lw_j]##*[/\\]}
        __kk_lw_s=${__kk_lw_s%.sh}
        if [[ -n $__kk_lw_s && -n ${__KK_UNITS[$__kk_lw_s]+x} && -z ${__KK_UNIT_DONE[$__kk_lw_s]+x} \
              && ${__KK_UNIT_SRC[$__kk_lw_s]-} == "${BASH_SOURCE[__kk_lw_j]}" \
              && ${__KK_UNIT_BOT[$__kk_lw_s]--1} == $(( __kk_lw_n - 1 - __kk_lw_j )) ]]; then
            printf -v "$1" '%s' "$__kk_lw_s"
            return 0
        fi
    done
    printf -v "$1" '%s' ""
    return 1
}

# kk._unit_current -> RESULT: the name of the innermost unit being loaded right
# now (rc 0), or '' (rc 1). The hook kklass uses to file a class under its unit (U2).
kk._unit_current() {
    RESULT=""
    [[ ${__KK_LOADED[@]@a} == A ]] || return 1     # no registry of this shell (R14)
    kk._unit_loading RESULT
}

# kk._unit_complete NAME — rc 0 when the registered unit NAME is completely
# loaded: marked done, or (a plain-sourced load, marked lazily) not tainted and
# its `source` frame no longer on the stack. rc 1 otherwise (not registered,
# loading now, tainted), rc 2 without a registry. Quiet and without side effects
# (kk._unit_check, which also marks done, prints a cycle while a unit loads):
# the filter for a reader of __KK_UNIT_ORDER.
kk._unit_complete() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    [[ -n ${1-} && -n ${__KK_UNITS[$1]+x} ]] || return 1
    [[ -z ${__KK_UNIT_DONE[$1]+x} ]] || return 0
    [[ -z ${__KK_UNIT_FAIL[$1]+x} ]] || return 1
    local __kk_b=${__KK_UNIT_BOT[$1]--1} __kk_n=${#BASH_SOURCE[@]} __kk_k
    [[ $__kk_b == [0-9]* && $__kk_b != *[!0-9]* ]] || return 0
    __kk_k=$(( __kk_n - 1 - __kk_b ))
    if (( __kk_k >= 1 && __kk_k < __kk_n )) \
       && [[ ${FUNCNAME[__kk_k]-} == source && ${BASH_SOURCE[__kk_k]-} == "${__KK_UNIT_SRC[$1]-}" ]]; then
        return 1
    fi
    return 0
}

# kk._unit_register NAME FILE — register NAME as completely loaded from FILE
# (kbool.sh, for the system units it sources plainly).
kk._unit_register() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14, U1b R2)
    local __kk_l=$(( ${#__KK_UNIT_ORDER[@]} - 1 ))
    if [[ -z ${__KK_UNITS[$1]+x} ]]; then
        __KK_UNITS[$1]=$2
        __KK_UNIT_SRC[$1]=$2
        __KK_UNIT_BOT[$1]=-1
        __KK_UNIT_ORDER+=("s$__KK_SEP$1")
    elif (( __kk_l >= 0 )) && [[ ${__KK_UNIT_ORDER[__kk_l]} == "u$__KK_SEP$1" ]]; then
        __KK_UNIT_ORDER[__kk_l]="s$__KK_SEP$1"    # its header's `u` entry (uses U3), last
    else
        kk._unit_order_del "$1"
        __KK_UNIT_ORDER+=("s$__KK_SEP$1")
    fi
    __KK_UNIT_DONE[$1]=1
    __KK_UNIT_SYS[$1]=1
    unset '__KK_UNIT_FAIL[$1]'
}

# kk._unit_order_del NAME — remove NAME's entry from __KK_UNIT_ORDER (kept dense).
# Exact names also under nocasematch (`ca` is not `CA`).
kk._unit_order_del() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    local __kk_e __kk_nc=0
    local -a __kk_o=()
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_nc=1; shopt -u nocasematch; fi
    for __kk_e in "${__KK_UNIT_ORDER[@]}"; do
        [[ ${__kk_e#*"$__KK_SEP"} == "$1" ]] || __kk_o+=("$__kk_e")
    done
    if (( __kk_nc )); then shopt -s nocasematch; fi
    __KK_UNIT_ORDER=("${__kk_o[@]}")
}

# kk._unit_core NAME — rc 0 when the REGISTERED unit NAME is a system unit
# (kbool.sh loaded it) or lives directly in a non-glob system path folder (kkore,
# kklass): U43 — such a name is never resolved again, so a file of that name in
# the caller's folder (or the PWD) cannot take its place. rc 1 otherwise.
kk._unit_core() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    [[ -n ${__KK_UNITS[${1:-.}]+x} ]] || return 1
    [[ -z ${__KK_UNIT_SYS[$1]+x} ]] || return 0
    local __kk_e __kk_n __kk_x
    kk._unit_lexnorm "${__KK_UNITS[$1]%[/\\]*}"
    __kk_x=$__kk_n
    for __kk_e in "${__KK_UNIT_SYSPATH[@]}"; do
        [[ $__kk_e != */\* ]] || continue
        kk._unit_lexnorm "$__kk_e"
        [[ $__kk_n != "$__kk_x" ]] || return 0
    done
    return 1
}

# kk._unit_caller_dir FILE -> __kk_d: the folder of a calling FILE (U43). An
# absolute FILE: its folder. A RELATIVE spelling is taken against the PWD
# recorded when that file was loaded (kk.unit; kbool.sh for the files on the
# stack at its boot — a script that cd's after loading kbool keeps its folder),
# else against the PWD at its first kk.uses (recorded then).
kk._unit_caller_dir() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    if [[ $1 == /* || $1 == [A-Za-z]:* ]]; then
        kk._unit_dir "$1"
        return 0
    fi
    if [[ -z ${__KK_FILE_PWD[$1]+x} ]]; then __KK_FILE_PWD[$1]=$PWD; fi
    case $1 in
        */*|*\\*) __kk_d=${__KK_FILE_PWD[$1]}/${1%[/\\]*} ;;
        *) __kk_d=${__KK_FILE_PWD[$1]} ;;
    esac
    return 0
}

# kk._unit_drop NAME — forget a unit: its classes first (the kklass hook), then
# every registry entry. No checks.
kk._unit_drop() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14, U1b R2)
    local __kk_l="${__KK_UNIT_CLASSES[$1]-} " __kk_c
    if [[ $__kk_l != " " ]] && declare -F kk._unit_forget_class >/dev/null; then
        while [[ -n ${__kk_l// /} ]]; do
            __kk_c=${__kk_l%% *}
            __kk_l=${__kk_l#* }
            if [[ -n $__kk_c ]]; then kk._unit_forget_class "$__kk_c"; fi
        done
    fi
    unset '__KK_UNITS[$1]' '__KK_UNIT_SRC[$1]' '__KK_UNIT_BOT[$1]' '__KK_UNIT_DONE[$1]' \
          '__KK_UNIT_FAIL[$1]' '__KK_UNIT_CLASSES[$1]' '__KK_UNIT_PID[$1]'
    kk._unit_order_del "$1"
    if (( ${#__KK_UNIT_SETTINGS[@]} )); then kk._settings_drop "$1"; fi
}

# kk._unit_reset — empty every registry table (kbool.sh: a fresh start, and the
# cleanup of a failed start): unset + a fresh declaration, so a table that is
# not an assoc any more (an inherited scalar, an indexed array) cannot survive.
# Defines and search paths go too.
kk._unit_reset() {
    unset __KK_UNITS __KK_UNIT_SRC __KK_UNIT_BOT __KK_UNIT_DONE __KK_UNIT_FAIL __KK_UNIT_SYS \
          __KK_UNIT_CLASSES __KK_UNIT_FILES __KK_UNIT_CAND __KK_UNIT_IDX __KK_UNIT_RES \
          __KK_UNIT_HIT __KK_DEFINES __KK_UNIT_PROJPATH __KK_UNIT_SYSPATH __KK_UNIT_IDX_OK \
          __KK_LOADED __KK_CFG __KK_CFG_LV __KK_NAMESPACES __KK_FILE_PWD __KK_PROJECT __KK_UNIT_USED __KK_CFG_VKW \
          __KK_UNIT_ORDER __KK_UNIT_SETTINGS __KK_SETTINGS_VARS __KK_UNIT_PID __KK_SETTINGS_RUN
    kk._unit_tables
}

# ---------------------------------------------------------------------------
# The unit -> classes registry (P4). kklass (U2) files every class it builds
# under kk._unit_current and defines kk._unit_forget_class CLASS, which
# `kk.unit --forget` calls for each of them.

# kk._unit_add_class UNIT CLASS — rc 0 (a repeat is a no-op), rc 2 on an empty argument.
kk._unit_add_class() {
    [[ -n ${1-} && -n ${2-} ]] || return 2
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2     # no registry of this shell (R14)
    case " ${__KK_UNIT_CLASSES[$1]-} " in
        *" $2 "*) return 0 ;;
    esac
    __KK_UNIT_CLASSES[$1]+="${__KK_UNIT_CLASSES[$1]:+ }$2"
    return 0
}

# kk._unit_classes UNIT -> RESULT: the space-separated classes of UNIT ('' when none).
kk._unit_classes() {
    RESULT=""
    [[ ${__KK_LOADED[@]@a} == A ]] || return 0     # no registry of this shell (R14)
    RESULT="${__KK_UNIT_CLASSES[${1:-.}]-}"
    return 0
}

# ---------------------------------------------------------------------------
# Declared namespaces (uses U2b, U22 as amended by U40, owner 2026-10-08).
# A namespace is the X of functions X.* a library defines (kk.uses, kv.new,
# tawk.run). A class or an instance named X would replace or delete them, so
# kklass refuses a class or an instance whose name is a DECLARED namespace —
# declared, because listing bash's function table costs O(functions) after any
# definition (measured ~quadratic: 2k 9 ms, 8k 150 ms, 16k 0.9 s, 24k 2.8 s), so
# nothing on a declaration or `.new` path lists functions. Declared are:
#   * every unit's own name (kk.unit NAME — a unit `tlist` owns tlist.*);
#   * every `kk.namespace X ...` (a unit, or any file, owning more prefixes:
#     thttpserver's ths, tcustomapplication's tca);
#   * the kkore namespaces kk kl ke kv kc (kbool.sh; kklass also records kk kl
#     ke kv and its own kkp in its table, so they are taken without kbool too).
# A plain library that neither has a unit header nor calls kk.namespace is NOT
# protected (the documented gap, U40). Several files may share one namespace
# (the first declaration names the owner) — only files in the OWNER'S FOLDER
# (U44, owner 2026-10-14: a package, the thttpserver files sharing ths); a
# file elsewhere, a file-less caller, or a unit NAMED like it from another
# folder is refused (a unit so named in the owner's folder shares it), and a
# class-named namespace is never shared with a file but its class's own. A
# class may take the name of its own unit's / file's namespace (kcl's
# `class dateutils` in dateutils.sh).
# The other direction (U22: "a unit loaded AFTER a class of the same name is
# caught at load"): kk.unit NAME and kk.namespace X refuse (rc 2) a name that is
# already a built class or a live instance — through kklass's hook
# kk._name_in_use when kklass is loaded.

# kk._ns_declare X UNIT FILE — record namespace X (first owner wins) and tell
# kklass (its hook kk._namespace_add) when it is loaded. X is an identifier.
kk._ns_declare() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    [[ -z ${__KK_NAMESPACES[$1]+x} ]] || return 0
    __KK_NAMESPACES[$1]="$2$__KK_SEP$3"
    if declare -F kk._namespace_add >/dev/null; then kk._namespace_add "$1" "$2" "$3"; fi
    return 0
}

# kk._ns_free X FILE WHAT — rc 0 when X may become a namespace declared from
# FILE; rc 2 (printed) when kklass says X is a built class (declared elsewhere)
# or a live instance. WHAT names the caller for the message.
kk._ns_free() {
    declare -F kk._name_in_use >/dev/null || return 0
    kk._name_in_use "$1" "$2" || return 0
    kk._unit_err "$3: '$1' is already $RESULT; a unit name and a kk.namespace name are function namespaces and may not be a class or an instance (U22)"
    return 2
}

# kk._ns_share X FILE WHAT — X is ALREADY declared (U44, owner 2026-10-14):
# rc 0 when FILE may share it — FILE is the owner's file (a repeat, a reload),
# or a file in the owner's FOLDER (a package: thttpmessage, thttprouter and
# thttpserver share ths) and X is not a class declared in another file; rc 2
# (printed) otherwise: a file in another folder, a file-less caller (a prompt,
# `bash -c`) sharing another's namespace, a class-named namespace (kcl's
# `class dateutils`) claimed by any file but its class's own. WHAT names the
# caller for the message.
kk._ns_share() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    local __kk_o=${__KK_NAMESPACES[$1]-} __kk_of __kk_ou __kk_n __kk_d1 __kk_d2
    __kk_ou=${__kk_o%%"$__KK_SEP"*}
    __kk_of=${__kk_o#*"$__KK_SEP"}
    if [[ $2 == "$__kk_of" ]] || [[ -n $2 && -n $__kk_of && $2 -ef $__kk_of ]]; then return 0; fi
    __kk_d1=${2%[/\\]*} __kk_d2=${__kk_of%[/\\]*}     # the two folders
    if [[ -n $2 && -n $__kk_of && $__kk_d1 -ef $__kk_d2 ]]; then
        kk._ns_free "$1" "$2" "$3" || return 2
        return 0
    fi
    if [[ -n $__kk_of ]]; then kk._unit_lexnorm "$__kk_of"; else __kk_n="no file"; fi
    kk._unit_err "$3: '$1' is already the function namespace of ${__kk_ou:+unit $__kk_ou }($__kk_n); only a file in that folder may share it (U44)"
    return 2
}

# kk.namespace X [Y ...] — declare more function namespaces of the calling file
# (owner: the unit being loaded, if any). rc 0; rc 2 (printed) for no name, a
# name that is not an identifier, a name that is already a class or a live
# instance, a name another file declared unless that file is in this file's
# folder (U44, kk._ns_share), or when kbool.sh is not loaded in this shell. A
# repeat is a no-op.
# Every rc-2 error with kbool loaded is a structural load error (U34/U42, U4-G1
# R1): it taints the unit being loaded (frame 2 = the caller's source frame from
# kk._unit_taint's view), so a plain-sourced unit whose kk.namespace failed is
# not counted complete — its next source or kk.uses runs it again.
kk.namespace() {
    if [[ ${__KK_LOADED[@]@a} != A ]]; then
        printf 'kbool: error: kk.namespace %s: kbool.sh is not loaded\n' "$*" >&2
        return 2
    fi
    local __kk_x __kk_file=${BASH_SOURCE[1]-} __kk_u=""
    if (( $# == 0 )); then
        kk._unit_err "kk.namespace: no namespace named"
        kk._unit_taint 2
        return 2
    fi
    for __kk_x; do
        if ! kk._is_ident "$__kk_x"; then
            kk._unit_err "kk.namespace: '$__kk_x' is not a namespace name (letters, digits, _)"
            kk._unit_taint 2
            return 2
        fi
    done
    case $__kk_file in
        ''|main|environment) __kk_file="" ;;
        /*|[A-Za-z]:*) ;;
        *) __kk_file=$PWD/$__kk_file ;;
    esac
    if kk._unit_current; then __kk_u=$RESULT; fi
    for __kk_x; do
        if [[ -z ${__KK_NAMESPACES[$__kk_x]+x} ]]; then
            if ! kk._ns_free "$__kk_x" "$__kk_file" "kk.namespace $__kk_x"; then
                kk._unit_taint 2
                return 2
            fi
        elif ! kk._ns_share "$__kk_x" "$__kk_file" "kk.namespace $__kk_x"; then
            kk._unit_taint 2
            return 2
        fi
        kk._ns_declare "$__kk_x" "$__kk_u" "$__kk_file"
    done
    return 0
}

# ---------------------------------------------------------------------------
# Settings hooks (kklass/docs/dev/IMAGE_PLAN.md §5, IMG-D5). A unit's load-time
# statements whose result can differ between two starts — environment reads,
# caller presets of public names, locale, PATH probes, pids and fds — live in a
# function the unit passes to kk.settings, with the variables that function
# sets. Today kk.settings just runs it; the recorded hooks let a later load
# image (kk.image, IMAGE_PLAN §9) run them again on every start.
#
#     myunit._settings() {
#         : "${MYUNIT_WIDTH:=80}"
#         kk.localeDefault
#         return 0
#     }
#     kk.settings myunit._settings MYUNIT_WIDTH LC_CTYPE || return
#
# Writing a hook (the image runs it again on every start, outside the load):
#   * it is a FUNCTION, so a plain `declare X` / `declare -A M` inside it makes a
#     local that is gone when it returns: write `declare -g` / `declare -gA`
#     (a plain assignment or `: "${X:=d}"` is global already);
#   * end it with `return 0`, or make sure its last command cannot fail: its rc
#     is kk.settings' rc, and `[[ -n ${X-} ]] && Y=1` as the last line returns 1
#     whenever X is unset — which fails the load under `kk.settings FN || return`
#     (a lint, I1's kcl/tests/001, can check that the last line of every
#     function passed to kk.settings is `return 0` or an assignment);
#   * no `kk.uses`, no `source` of a unit and no `kk.settings` inside it: a hook
#     must not load units — only its unit's load does. Refused with rc 2 and a
#     message (the unit tainted): kk.settings, and a kk.uses / source that would
#     LOAD a unit; a kk.uses or re-source of a unit already loaded stays the
#     usual no-op (rc 0), so a helper that does `kk.uses dep` defensively works;
#   * no load-only context: KK_UNIT_DIR, the load's positional parameters, the
#     loader's state are not there when an image start runs it — copy what it
#     needs at file scope (`MYUNIT_DIR=$KK_UNIT_DIR`) and read the copy;
#   * it must be safe to run again (idempotent): an append to a registry checks
#     for its entry first, a default uses `:=`, nothing is counted twice;
#   * hooks run again in __KK_UNIT_SETTINGS order — the order the kk.settings
#     calls ran — NOT in unit order (__KK_UNIT_ORDER lists a unit when its load
#     starts: tfind before the tutil it loads). A hook that appends to another
#     unit's registry therefore comes after that unit's: call kk.settings
#     after the `kk.uses` of the registry's owner (tfind's hook after `kk.uses
#     tutil`, whose hook declares TUTIL_OUT_PREFIXES), and list the registry
#     too (I1b critic M2; kcl's lint R7 checks it).

# kk._settings_hook MIN — rc 0 while a kk.settings frame (or kk._image_hook's:
# the hooks of an image start) at index >= MIN in this function's view is
# running its hook (__KK_SETTINGS_RUN, and that frame still on the stack); then
# __kk_hk (a caller's local) = "FN of unit 'U'". rc 1 else.
kk._settings_hook() {
    local __kk_r=${__KK_SETTINGS_RUN-} __kk_b __kk_k
    [[ -n $__kk_r ]] || return 1
    __kk_b=${__kk_r%%"$__KK_SEP"*}
    [[ $__kk_b == [0-9]* && $__kk_b != *[!0-9]* ]] || return 1
    __kk_k=$(( ${#FUNCNAME[@]} - 1 - __kk_b ))
    (( __kk_k >= $1 )) && [[ ${FUNCNAME[__kk_k]-} == kk.settings || ${FUNCNAME[__kk_k]-} == kk._image_hook ]] || return 1
    __kk_r=${__kk_r#*"$__KK_SEP"}
    __kk_hk="${__kk_r#*"$__KK_SEP"} of unit '${__kk_r%%"$__KK_SEP"*}'"
    return 0
}

# kk.settings FN [VAR...] — see the header. Fork-free; the unit being loaded is
# found by kk._unit_loading (the caller's RESULT is not touched).
kk.settings() {
    if [[ ${__KK_LOADED[@]@a} != A ]]; then
        printf 'kbool: error: kk.settings %s: kbool.sh is not loaded\n' "$*" >&2
        return 2
    fi
    local __kk_fn=${1-} __kk_u="" __kk_v __kk_hk="" __kk_nc=0 __kk_rc
    if ! kk._unit_loading __kk_u; then
        kk._unit_err "kk.settings ${__kk_fn}: not inside a unit's load (call it in the unit file, after the function is defined)"
        return 2
    fi
    if [[ ${__KK_UNIT_PID[$__kk_u]-} != "$BASHPID" ]]; then
        kk._unit_err "kk.settings ${__kk_fn}: called in a subshell of the load of unit '$__kk_u' (\$( ), a pipe, ( )): nothing would be recorded"
        return 2
    fi
    if [[ -n ${__KK_SETTINGS_RUN-} ]] && kk._settings_hook 2; then
        kk._unit_err "kk.settings ${__kk_fn}: called inside the settings hook $__kk_hk; a hook may not call kk.settings (in unit '$__kk_u')"
        kk._unit_taint 2
        return 2
    fi
    if (( $# == 0 )) || [[ -z $__kk_fn ]]; then
        kk._unit_err "kk.settings: usage 'kk.settings FN [VAR...] || return' (in unit '$__kk_u')"
        kk._unit_taint 2
        return 2
    fi
    if [[ $__kk_fn != : ]] && ! declare -F -- "$__kk_fn" >/dev/null; then
        kk._unit_err "kk.settings: '$__kk_fn' is not a function (define it before kk.settings; in unit '$__kk_u')"
        kk._unit_taint 2
        return 2
    fi
    for __kk_v in "${@:2}"; do
        if ! kk._is_ident "$__kk_v"; then
            kk._unit_err "kk.settings $__kk_fn: '$__kk_v' is not a variable name (letters, digits, _; in unit '$__kk_u')"
            kk._unit_taint 2
            return 2
        fi
    done
    __KK_UNIT_SETTINGS+=("$__kk_u$__KK_SEP$__kk_fn")
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_nc=1; shopt -u nocasematch; fi
    for __kk_v in "${@:2}"; do
        case ${__KK_SETTINGS_VARS[$__kk_v]-} in
            "$__kk_u$__KK_SEP"*|*"$__KK_SEP$__kk_u$__KK_SEP"*) ;;
            *) __KK_SETTINGS_VARS[$__kk_v]+=$__kk_u$__KK_SEP ;;
        esac
    done
    if (( __kk_nc )); then shopt -s nocasematch; fi
    # the hook runs marked (M1: no kk.settings / unit load inside it); the mark
    # is cleared on every return of FN and is inert once this frame is gone
    __KK_SETTINGS_RUN="$(( ${#FUNCNAME[@]} - 1 ))$__KK_SEP$__kk_u$__KK_SEP$__kk_fn"
    "$__kk_fn"
    __kk_rc=$?
    __KK_SETTINGS_RUN=""
    # a failed hook leaves the unit incomplete (U34): a plain-sourced unit that
    # ignored the rc, or returned it, loads again next time
    if (( __kk_rc != 0 )); then kk._unit_taint 2; fi
    return "$__kk_rc"
}

# kk._settings_drop UNIT — remove UNIT's kk.settings records (kk._unit_drop).
# Exact names also under nocasematch.
kk._settings_drop() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    local __kk_e __kk_k __kk_l __kk_hit=0 __kk_nc=0
    local -a __kk_o=()
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_nc=1; shopt -u nocasematch; fi
    for __kk_e in "${__KK_UNIT_SETTINGS[@]}"; do
        if [[ ${__kk_e%%"$__KK_SEP"*} == "$1" ]]; then
            __kk_hit=1
        else
            __kk_o+=("$__kk_e")
        fi
    done
    if (( __kk_hit )); then
        __KK_UNIT_SETTINGS=("${__kk_o[@]}")
        for __kk_k in "${!__KK_SETTINGS_VARS[@]}"; do
            __kk_l=$__KK_SEP${__KK_SETTINGS_VARS[$__kk_k]}
            __kk_l=${__kk_l/"$__KK_SEP$1$__KK_SEP"/$__KK_SEP}
            __kk_l=${__kk_l#"$__KK_SEP"}
            if [[ -n $__kk_l ]]; then
                __KK_SETTINGS_VARS[$__kk_k]=$__kk_l
            else
                unset '__KK_SETTINGS_VARS[$__kk_k]'
            fi
        done
    fi
    if (( __kk_nc )); then shopt -s nocasematch; fi
    return 0
}

# kk.localeDefault — the kcl locale default (IMAGE_PLAN §5.2): no locale set at
# all -> LC_CTYPE=C.UTF-8, exported (the units' byte/character semantics); any
# non-empty LC_ALL, LC_CTYPE or LANG is left as it is. rc 0. For a unit's hook.
kk.localeDefault() {
    [[ -n ${LC_ALL:-}${LC_CTYPE:-}${LANG:-} ]] || export LC_CTYPE=C.UTF-8
    return 0
}

# ---------------------------------------------------------------------------
# The name index (U13', U16, P5/P6), lazy at two levels:
#  * the CANDIDATE map (stem -> files named <stem>.sh, in search order) is built
#    by one glob per path entry at the first name not found in the caller's
#    folder — never in kbool.sh; project paths first, then the system paths; an
#    entry ending in `/*` means every subfolder of it;
#  * a file's header is read only when its stem is looked up, and the answer is
#    cached per name in __KK_UNIT_IDX (a miss as ''), for the shell session (U16).
# The result equals a full index of HEADERED files with first-match-wins (U13',
# U15), but the first lookup costs one glob + one file read instead of reading
# every candidate (kcl/*: 79 .sh files after U4, 32 of them kcl/tests, 29 of
# them units in 26 folders; P5 was measured at 48 files, see the U1a ledger).
# kk.project (U1b) sets __KK_UNIT_IDX_OK=0; the next lookup rebuilds both maps.
kk._unit_index_build() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14, U1b R2)
    local __kk_e __kk_f __kk_s __kk_nf=0 __kk_fg=0 __kk_ng=0
    local -a __kk_g
    local GLOBIGNORE        # a caller's GLOBIGNORE='*' would empty the index (C10);
    unset GLOBIGNORE        # the caller's value comes back when this function returns
    __KK_UNIT_IDX=()
    __KK_UNIT_CAND=()
    __KK_UNIT_RES=()        # resolutions depend on the search path: start over
    __KK_UNIT_HIT=()
    if [[ $- == *f* ]]; then __kk_nf=1; set +f; fi
    if [[ :$BASHOPTS: == *:failglob:* ]]; then __kk_fg=1; shopt -u failglob; fi
    if [[ :$BASHOPTS: != *:nullglob:* ]]; then __kk_ng=1; shopt -s nullglob; fi
    for __kk_e in "${__KK_UNIT_PROJPATH[@]}" "${__KK_UNIT_SYSPATH[@]}"; do
        if [[ $__kk_e == */\* ]]; then
            __kk_g=("${__kk_e%/\*}"/*/*.sh)
        else
            __kk_g=("$__kk_e"/*.sh)
        fi
        for __kk_f in "${__kk_g[@]}"; do
            __kk_s=${__kk_f##*/}
            __kk_s=${__kk_s%.sh}
            __KK_UNIT_CAND[$__kk_s]+="$__kk_f"$'\n'
        done
    done
    if (( __kk_ng )); then shopt -u nullglob; fi
    if (( __kk_fg )); then shopt -s failglob; fi
    if (( __kk_nf )); then set -f; fi
    __KK_UNIT_IDX_OK=1
    return 0
}

# kk._unit_find NAME DIR -> __kk_found: DIR/NAME.sh when it carries the header,
# else the first HEADERED candidate named NAME.sh on the search path. rc 1 when
# NAME is not a unit anywhere.
kk._unit_find() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14, U1b R2)
    local __kk_l __kk_f
    # an empty DIR: no caller-folder step (U43: no calling file, not at a prompt)
    if [[ -n ${2-} ]] && kk._unit_has_header "$2/$1.sh" "$1"; then
        __kk_found=$2/$1.sh
        return 0
    fi
    if (( ! __KK_UNIT_IDX_OK )); then kk._unit_index_build; fi
    if [[ -z ${__KK_UNIT_IDX[$1]+x} ]]; then
        __KK_UNIT_IDX[$1]=""
        __kk_l=${__KK_UNIT_CAND[$1]-}
        while [[ -n $__kk_l ]]; do
            __kk_f=${__kk_l%%$'\n'*}
            __kk_l=${__kk_l#*$'\n'}
            if kk._unit_has_header "$__kk_f" "$1"; then
                __KK_UNIT_IDX[$1]=$__kk_f
                break
            fi
        done
    fi
    __kk_found=${__KK_UNIT_IDX[$1]}
    [[ -n $__kk_found ]]
}

# ---------------------------------------------------------------------------
# kk.unit NAME | kk.unit --forget NAME
kk.unit() {
    # Fast path — the no-op re-source of a loaded unit by the spelling it was
    # registered with (absolute), sourced without arguments: one test, no locals.
    # Ownership first (R14): no table is subscripted unless it is this shell's.
    if [[ $# == 1 && ${__KK_LOADED[@]@a} == A && -n ${__KK_UNIT_DONE[${1:-.}]+x} && ${FUNCNAME[1]-} == source \
          && ${BASH_SOURCE[1]-} == "${__KK_UNITS[$1]}" \
          && ${BASH_ARGC[0]-} == 1 && ${BASH_ARGV[0]-} == "${BASH_SOURCE[1]}" ]]; then
        __kk_unit_rc=0
        return 1
    fi
    kk._unit "$@"
}

# kk._unit — kk.unit past its fast path (kklass round 5 / P14, finding K7):
# bash copies a function's body on every call, so the skip path above pays
# only for this short wrapper (re-source 5.2 ~436 -> ~378 us, critic r5a C8).
# ONE FRAME DEEPER than kk.unit — every stack index here is kk.unit's + 1:
# BASH_SOURCE[2] / FUNCNAME[2] are the unit's `source` frame, kk._unit_taint
# and kk._unit_check take MIN 4, __KK_UNIT_BOT is #BASH_SOURCE - 3, and under
# extdebug the source's BASH_ARGC entry is [2] (kk._unit's and kk.unit's own
# arguments come first: BASH_ARGV offset BASH_ARGC[0] + BASH_ARGC[1]).
# kkore test 016 covers the extdebug indices.
kk._unit() {
    if [[ ${__KK_LOADED[@]@a} != A ]]; then
        __kk_unit_rc=2
        printf 'kbool: error: kk.unit %s: kbool.sh is not loaded (line 1 of a unit header loads it)\n' "$*" >&2
        return 2
    fi
    if [[ ${1-} == --forget ]]; then
        kk._unit_forget "${2-}"
        return
    fi
    local __kk_name=${1-} __kk_src=${BASH_SOURCE[2]-} __kk_stem __kk_a __kk_p __kk_d __kk_n __kk_m \
          __kk_ai=0 __kk_vo=0 __kk_id=0 __kk_hk=""
    __kk_unit_rc=2
    if [[ ${FUNCNAME[2]-} != source || -z $__kk_src ]]; then
        kk._unit_err "kk.unit ${__kk_name}: not the header of a unit file (it must be loaded by source or kk.uses)"
        return 2
    fi
    if (( $# != 1 )) || [[ -z $__kk_name ]]; then
        kk._unit_err "kk.unit: usage 'kk.unit NAME || return \$__kk_unit_rc' (in '$__kk_src')"
        kk._unit_taint 4
        return 2
    fi
    __kk_stem=${__kk_src##*[/\\]}
    __kk_stem=${__kk_stem%.sh}
    if [[ $__kk_name != "$__kk_stem" ]]; then
        kk._unit_err "unit header 'kk.unit $__kk_name' does not match the file name '${__kk_src##*[/\\]}' (a unit's name is its file stem)"
        kk._unit_taint 4
        return 2
    fi
    # P8: units take no arguments. A `source FILE` without arguments pushes FILE on
    # BASH_ARGV with BASH_ARGC 1 (evalfile.c). With arguments the top entry is never
    # that: bash pushes the arguments (at top level they even stay on BASH_ARGV
    # afterwards) or nothing. Under extdebug kk.unit's and kk._unit's frames come first. The
    # one false negative: `source FILE FILE` (one argument equal to the file's path).
    if [[ $BASHOPTS == *extdebug* ]]; then
        __kk_ai=2
        __kk_vo=$(( ${BASH_ARGC[0]-0} + ${BASH_ARGC[1]-0} ))
    fi
    if [[ ${BASH_ARGC[__kk_ai]-} != 1 || ${BASH_ARGV[__kk_vo]-} != "$__kk_src" ]]; then
        kk._unit_warn "unit '$__kk_name' called with arguments; units take none ($__kk_src)"
    fi
    if [[ $__kk_src == /* || $__kk_src == [A-Za-z]:* ]]; then
        __kk_a=$__kk_src
    else
        __kk_a=$PWD/$__kk_src
    fi
    if [[ -n ${__KK_UNITS[$__kk_name]+x} ]]; then
        __kk_p=${__KK_UNITS[$__kk_name]}
        if [[ $__kk_p != "$__kk_a" && ! $__kk_p -ef $__kk_a ]]; then
            kk._unit_lexnorm "$__kk_p"
            __kk_m=$__kk_n
            kk._unit_lexnorm "$__kk_a"
            kk._unit_err "unit '$__kk_name' is already loaded from '$__kk_m'; refusing '$__kk_n' (unit names are unique)"
            kk._unit_taint 4
            return 2
        fi
        __kk_m=0
        if [[ -z ${__KK_UNIT_DONE[$__kk_name]+x} ]]; then kk._unit_check "$__kk_name" 4 || __kk_m=$?; fi
        if (( __kk_m == 2 )); then
            kk._unit_taint 4
            return 2
        fi
        if (( __kk_m == 0 )); then
            __kk_unit_rc=0
            return 1
        fi
        # rc 3: an earlier load of this file ended incompletely (U34/U42) —
        # forget it (its classes too) and load it again below
        kk._unit_drop "$__kk_name"
    fi
    # M1: a settings hook must not load units (a no-op re-source above is fine)
    if [[ -n ${__KK_SETTINGS_RUN-} ]] && kk._settings_hook 1; then
        kk._unit_err "kk.unit $__kk_name: a settings hook may not load units (inside the hook $__kk_hk; in '$__kk_src')"
        kk._unit_taint 4
        return 2
    fi
    # a unit loaded (by any means) before kk.project could have read the defines
    # and resolved names without the project: kk.project is refused from now on (U37)
    # U22/U40: a unit's name is a function namespace — it may not be a built
    # class or a live instance (checked before anything is registered).
    # kk._is_ident lives in klib, a system unit whose OWN header runs before its
    # body (uses U3): until kbool.sh has marked klib loaded, the name is not
    # declared here — kbool.sh declares every system unit's name after the boot.
    if [[ -n ${__KK_UNIT_DONE[klib]+x} ]] && kk._is_ident "$__kk_name"; then __kk_id=1; fi
    if (( __kk_id )) && [[ -z ${__KK_NAMESPACES[$__kk_name]+x} ]] \
       && ! kk._ns_free "$__kk_name" "$__kk_a" "unit header 'kk.unit $__kk_name' in '$__kk_src'"; then
        kk._unit_taint 4
        return 2
    fi
    # U44: a unit NAMED like a namespace another file declared shares it — only
    # from the owner's folder (a unit `ths` elsewhere would define ths.*)
    if (( __kk_id )) && [[ -n ${__KK_NAMESPACES[$__kk_name]+x} ]] \
       && ! kk._ns_share "$__kk_name" "$__kk_a" "unit header 'kk.unit $__kk_name' in '$__kk_src'"; then
        kk._unit_taint 4
        return 2
    fi
    if [[ -z $__KK_UNIT_USED ]]; then __KK_UNIT_USED=$__kk_name; fi
    __KK_UNITS[$__kk_name]=$__kk_a
    __KK_UNIT_SRC[$__kk_name]=$__kk_src
    # U43: a relative spelling is resolved later against the PWD of this load
    if [[ $__kk_src != "$__kk_a" ]]; then __KK_FILE_PWD[$__kk_src]=$PWD; fi
    __KK_UNIT_BOT[$__kk_name]=$(( ${#BASH_SOURCE[@]} - 3 ))
    unset '__KK_UNIT_DONE[$__kk_name]' '__KK_UNIT_FAIL[$__kk_name]'
    # the load order (IMAGE_PLAN §7.7): not registered until here, or dropped
    # above, so the name has no entry yet — appended at the end
    __KK_UNIT_ORDER+=("u$__KK_SEP$__kk_name")
    __KK_UNIT_PID[$__kk_name]=$BASHPID     # kk.settings: no record from a subshell
    if (( __kk_id )); then kk._ns_declare "$__kk_name" "$__kk_name" "$__kk_a"; fi
    kk._unit_dir "$__kk_src"
    KK_UNIT_DIR=$__kk_d
    __kk_unit_rc=0
    return 0
}

# kk._unit_forget NAME — `kk.unit --forget NAME` (U24', P4).
kk._unit_forget() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14, U1b R2)
    local __kk_b __kk_k __kk_n=${#BASH_SOURCE[@]}
    if [[ -z $1 ]]; then
        kk._unit_err "kk.unit --forget: no unit named"
        return 2
    fi
    [[ -n ${__KK_UNITS[$1]+x} ]] || return 1
    if [[ -n ${__KK_UNIT_SYS[$1]+x} ]]; then
        kk._unit_err "kk.unit --forget $1: a system unit loaded by kbool.sh cannot be forgotten"
        return 2
    fi
    if [[ -z ${__KK_UNIT_DONE[$1]+x} ]]; then
        __kk_b=${__KK_UNIT_BOT[$1]--1}
        __kk_k=$(( __kk_n - 1 - __kk_b ))
        if (( __kk_b >= 0 && __kk_k >= 1 && __kk_k < __kk_n )) \
           && [[ ${FUNCNAME[__kk_k]-} == source && ${BASH_SOURCE[__kk_k]-} == "${__KK_UNIT_SRC[$1]-}" ]]; then
            kk._unit_err "kk.unit --forget $1: the unit is being loaded right now"
            return 2
        fi
    fi
    kk._unit_drop "$1"
    return 0
}

# ---------------------------------------------------------------------------
# kk.uses ARG...
kk.uses() {
    # Fast path (C8): every argument is a NAME this calling file already resolved
    # to the unit now registered and complete — one assoc test per argument, no
    # `set --`, no caller-dir work. OWNERSHIP FIRST (R14): only when the registry
    # is this shell's assoc tables is any table subscripted by a non-literal key.
    if [[ ${__KK_LOADED[@]@a} == A && ${BASH_SOURCE[1]-} == /* ]]; then
        if (( $# == 1 )) && [[ -n ${__KK_UNIT_DONE[${1:-.}]+x} \
              && ${__KK_UNIT_HIT[${BASH_SOURCE[1]}$__KK_SEP$1]-} == "${__KK_UNITS[$1]}" ]]; then
            return 0
        fi
        if (( $# > 1 )); then
            local __kk_q
            for __kk_q; do
                [[ -n ${__KK_UNIT_DONE[${__kk_q:-.}]+x} \
                   && ${__KK_UNIT_HIT[${BASH_SOURCE[1]}$__KK_SEP$__kk_q]-} == "${__KK_UNITS[$__kk_q]}" ]] || break
                __kk_q=$__KK_SEP     # marks "all passed" when the loop ends here
            done
            [[ $__kk_q != "$__KK_SEP" ]] || return 0
        fi
    elif [[ ${__KK_LOADED[@]@a} != A ]]; then
        # a child bash that inherited kk.uses (exported functions) but not the
        # registry (arrays are never exported): kbool.sh from KBOOL_HOME first (C7)
        [[ -z ${KBOOL_HOME-} || ! -f ${KBOOL_HOME-}/kbool.sh ]] || source "$KBOOL_HOME/kbool.sh" || return
        [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.uses %s: kbool.sh is not loaded\n' "$*" >&2; return 2; }
    fi
    # bash copies a function's whole body on every call (execute_function), so the
    # work lives in kk._uses and this wrapper stays small (C8: copying the old
    # one-piece kk.uses was ~70 us of its ~85 us already-loaded cost).
    kk._uses "${BASH_SOURCE[1]-}" "$@"
}

# kk._uses CALLER [--optional] ARG... — kk.uses' body. CALLER = the calling file
# (BASH_SOURCE[1] of kk.uses, '' at a prompt / at the top level of bash -c,
# bash -s or a pipe). Frame indices seen from here are one deeper than from
# kk.uses: the caller's frame is 3 for kk._unit_check / kk._unit_taint.
# U42 (owner 2026-10-09): every failure — not found, a bad name, the unit's own
# rc != 0, a structural error, a unit whose own load was left incomplete —
# taints the unit being loaded around this call (U34), so its next load (a
# plain source or kk.uses) runs it again instead of counting it complete.
# `--optional` (leading) marks the dependencies optional: a failure neither
# taints nor prints the loader's not-found / load-failed message; the rc still
# reports it (`kk.uses --optional extra || fallback`).
kk._uses() {
    # an exported kk._uses called on its own in a registry-less child (R14)
    [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.uses: kbool.sh is not loaded\n' >&2; return 2; }
    local __kk_caller=$1 __kk_opt=0
    shift
    while [[ ${1-} == --optional ]]; do
        __kk_opt=1
        shift
    done
    local -a __kk_args=("$@")
    local __kk_a __kk_f __kk_nm __kk_cdir="" __kk_pdir __kk_d __kk_n __kk_k __kk_rc __kk_sv __kk_svset __kk_hl \
          __kk_found __kk_m __kk_p __kk_key __kk_hk=""
    set --
    if (( ${#__kk_args[@]} == 0 )); then
        kk._unit_err "kk.uses: no unit named"
        (( __kk_opt )) || kk._unit_taint 3
        return 2
    fi
    # the calling file's folder (U12; U14 as amended by U43): a relative PATH is
    # relative to it ($PWD without a calling file); a NAME is looked up there
    # first — without a calling file only at an interactive prompt ($PWD), never
    # from bash -c / bash -s / a pipe; a relative calling file is taken against
    # the PWD it was loaded from (kk._unit_caller_dir)
    case $__kk_caller in
        ''|main|environment)
            __kk_pdir=$PWD
            if [[ $- == *i* ]]; then __kk_cdir=$PWD; fi
            ;;
        *)
            kk._unit_caller_dir "$__kk_caller"
            __kk_cdir=$__kk_d
            __kk_pdir=$__kk_d
            ;;
    esac
    for __kk_a in "${__kk_args[@]}"; do
        __kk_hl=0
        if [[ $__kk_a == */* || $__kk_a == *\\* || $__kk_a == *.sh ]]; then
            # a PATH
            if [[ $__kk_a == /* || $__kk_a == [A-Za-z]:* ]]; then
                __kk_f=$__kk_a
            else
                __kk_f=$__kk_pdir/$__kk_a
            fi
            __kk_nm=${__kk_f##*[/\\]}
            __kk_nm=${__kk_nm%.sh}
            # a unit kbool.sh loaded, named by its path, is that unit: a no-op like
            # its name, and it does not close kk.project (U37, U1b R9a)
            if [[ -n ${__KK_UNIT_SYS[${__kk_nm:-.}]+x} ]] \
               && [[ ${__KK_UNITS[$__kk_nm]-} == "$__kk_f" || ${__KK_UNITS[$__kk_nm]-} -ef $__kk_f ]]; then
                continue
            fi
            # U37: the first use of a non-system unit (found or not, failing or
            # not) closes kk.project
            if [[ -z $__KK_UNIT_USED ]]; then __KK_UNIT_USED=$__kk_a; fi
            if [[ ! -f $__kk_f ]]; then
                if (( ! __kk_opt )); then
                    kk._unit_err "kk.uses: unit file '$__kk_a' not found (relative to '$__kk_pdir')"
                    kk._unit_taint 3
                fi
                return 2
            fi
            if kk._unit_has_header "$__kk_f" "$__kk_nm"; then
                if [[ -n ${__KK_UNITS[$__kk_nm]+x} ]]; then
                    if [[ ${__KK_UNITS[$__kk_nm]} == "$__kk_f" || ${__KK_UNITS[$__kk_nm]} -ef $__kk_f ]]; then
                        __kk_m=0
                        if [[ -z ${__KK_UNIT_DONE[$__kk_nm]+x} ]]; then kk._unit_check "$__kk_nm" 3 || __kk_m=$?; fi
                        (( __kk_m != 0 )) || continue
                        if (( __kk_m == 2 )); then
                            (( __kk_opt )) || kk._unit_taint 3
                            return 2
                        fi
                        kk._unit_drop "$__kk_nm"     # rc 3: its load ended incomplete -> again (U42)
                    else
                        kk._unit_lexnorm "${__KK_UNITS[$__kk_nm]}"
                        __kk_m=$__kk_n
                        kk._unit_lexnorm "$__kk_f"
                        kk._unit_err "unit '$__kk_nm' is already loaded from '$__kk_m'; refusing '$__kk_n' (unit names are unique)"
                        (( __kk_opt )) || kk._unit_taint 3
                        return 2
                    fi
                fi
            else
                # a file without the header: tracked by its normalised path
                __kk_hl=1
                kk._unit_lexnorm "$__kk_f"
                __kk_k=$__kk_n
                if [[ -n ${__KK_UNIT_FILES[$__kk_k]+x} ]]; then
                    continue
                fi
            fi
        else
            # a unit NAME: resolved from this caller, then compared with the unit
            # of that name already loaded (owner 2026-10-06, "найти и сравнить").
            # U37: a name kbool.sh did not load closes kk.project, found or not
            if [[ -z $__KK_UNIT_USED && -z ${__KK_UNIT_SYS[${__kk_a:-.}]+x} ]]; then
                __KK_UNIT_USED=$__kk_a
            fi
            if [[ -z $__kk_a || $__kk_a == *[[:space:]*?\[]* ]]; then
                kk._unit_err "kk.uses: '$__kk_a' is not a unit name"
                (( __kk_opt )) || kk._unit_taint 3
                return 2
            fi
            __kk_f=""
            if kk._unit_core "$__kk_a"; then
                # U43: a loaded system unit (kkore, kklass) is never resolved again —
                # a file of that name in the caller's folder cannot take its place
                __kk_p=${__KK_UNITS[$__kk_a]}
            else
                __kk_key=$__kk_cdir$__KK_SEP$__kk_a
                if [[ -z ${__KK_UNIT_RES[$__kk_key]+x} ]]; then
                    if kk._unit_find "$__kk_a" "$__kk_cdir"; then
                        __KK_UNIT_RES[$__kk_key]=$__kk_found
                    else
                        __KK_UNIT_RES[$__kk_key]=""
                    fi
                fi
                __kk_f=${__KK_UNIT_RES[$__kk_key]}
                __kk_p=${__KK_UNITS[$__kk_a]-}
                if [[ -n $__kk_p && -n $__kk_f && $__kk_f != "$__kk_p" && ! $__kk_f -ef $__kk_p ]]; then
                    kk._unit_lexnorm "$__kk_p"
                    __kk_m=$__kk_n
                    kk._unit_lexnorm "$__kk_f"
                    kk._unit_err "unit '$__kk_a' is already loaded from '$__kk_m'; here it resolves to '$__kk_n' (unit names are unique)"
                    (( __kk_opt )) || kk._unit_taint 3
                    return 2
                fi
            fi
            if [[ -n ${__KK_UNITS[$__kk_a]+x} ]]; then
                # the same file — or a loaded unit no lookup finds (kuse, kbool,
                # a unit loaded by path from outside the search path)
                __kk_m=0
                if [[ -z ${__KK_UNIT_DONE[$__kk_a]+x} ]]; then kk._unit_check "$__kk_a" 3 || __kk_m=$?; fi
                if (( __kk_m == 0 )); then
                    if [[ $__kk_caller == /* ]]; then
                        __KK_UNIT_HIT[$__kk_caller$__KK_SEP$__kk_a]=$__kk_p
                    fi
                    continue
                fi
                if (( __kk_m == 2 )); then
                    (( __kk_opt )) || kk._unit_taint 3
                    return 2
                fi
                kk._unit_drop "$__kk_a"         # rc 3: its load ended incomplete -> again (U42)
                [[ -n $__kk_f ]] || __kk_f=$__kk_p
            fi
            if [[ -z $__kk_f ]]; then
                if (( ! __kk_opt )); then
                    kk._unit_err "kk.uses: unit '$__kk_a' not found (searched ${__kk_cdir:+"'$__kk_cdir', "}the project and the system paths; a file without the header 'kk.unit $__kk_a' is loaded by path only)"
                    kk._unit_taint 3
                fi
                return 2
            fi
            __kk_nm=$__kk_a
        fi
        # M1: a settings hook must not load units (its unit's load does that)
        if [[ -n ${__KK_SETTINGS_RUN-} ]] && kk._settings_hook 1; then
            kk._unit_err "kk.uses $__kk_a: a settings hook may not load units (inside the hook $__kk_hk)"
            (( __kk_opt )) || kk._unit_taint 3
            return 2
        fi
        # load it: no arguments (C10), plain `source` (C11), KK_UNIT_DIR kept (C19)
        __kk_svset=${KK_UNIT_DIR+1}
        __kk_sv=${KK_UNIT_DIR-}
        source "$__kk_f"
        __kk_rc=$?
        if [[ -n $__kk_svset ]]; then
            KK_UNIT_DIR=$__kk_sv
        else
            unset KK_UNIT_DIR
        fi
        __kk_unit_rc=0
        if (( __kk_rc != 0 )); then
            # forget a failed load, so a retry loads it again (C12); the calling
            # unit is tainted (U42) unless the dependency is optional
            if [[ ${__KK_UNITS[$__kk_nm]-} == "$__kk_f" && -z ${__KK_UNIT_DONE[$__kk_nm]+x} ]]; then
                kk._unit_drop "$__kk_nm"
            fi
            if (( ! __kk_opt )); then
                kk._unit_err "kk.uses: loading unit '$__kk_nm' failed (rc=$__kk_rc)"
                kk._unit_taint 3
            fi
            return "$__kk_rc"
        fi
        if [[ ${__KK_UNITS[$__kk_nm]-} == "$__kk_f" ]]; then
            if [[ -n ${__KK_UNIT_FAIL[$__kk_nm]+x} ]]; then
                # rc 0, but a failed dependency or a structural error inside its
                # load left it incomplete (U34/U42): not loaded
                kk._unit_drop "$__kk_nm"
                if (( ! __kk_opt )); then
                    kk._unit_err "kk.uses: unit '$__kk_nm' is not completely loaded: a dependency or a structural error failed inside its load"
                    kk._unit_taint 3
                fi
                return 2
            fi
            __KK_UNIT_DONE[$__kk_nm]=1
            if [[ $__kk_hl == 0 && $__kk_a != *[/\\]* && $__kk_a != *.sh && $__kk_caller == /* ]]; then
                __KK_UNIT_HIT[$__kk_caller$__KK_SEP$__kk_a]=$__kk_f
            fi
        elif (( __kk_hl )); then
            __KK_UNIT_FILES[$__kk_k]=1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Load images (kklass/docs/dev/IMAGE_PLAN.md; the header's "Load images").
# Only the entry lives here (its options; KBOOL_IMAGE=off without sourcing
# anything): the hit path — prep, key, trust, header, stamps, holds — is
# kkore/kimghit.sh, sourced on every image start (fork-free, one more parse:
# a `source kbool.sh` does not pay for it, critic M6); the writer, the undo,
# pruning, --forget and the state dump are kkore/kimage.sh, sourced only on
# a miss, a failed start or --forget (kk._image_lib). Locals: __kk_im_* in
# kk.image (the helpers of both files write them), the image header's
# __kk_img_* in kk._image_hit, which sources the image; every name on the
# stack while kimage.sh dumps the state starts with __kk_im. Chained images
# (I2b): the prior set in kimghit.sh kk._image_prior, the deltas and the
# fresh-process simulation in kimage.sh. The background writer of --background
# (IMG-D10, I5): kkore/kimgbg.sh, sourced on such a miss (kk._image_bglib).

# kk.image [--rebuild | --forget | --path | --background] [--optional] [UNIT...] — see the header.
kk.image() {
    if [[ ${__KK_LOADED[@]@a} != A ]]; then
        [[ -z ${KBOOL_HOME-} || ! -f ${KBOOL_HOME-}/kbool.sh ]] || source "$KBOOL_HOME/kbool.sh" || return
        [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.image %s: kbool.sh is not loaded\n' "$*" >&2; return 2; }
    fi
    local __kk_im_t0=$EPOCHREALTIME __kk_im_caller=${BASH_SOURCE[1]-} __kk_im_why="" __kk_im_mode=dates __kk_im_euid=0 __kk_im_dir="" \
          __kk_im_mk=0 __kk_im_bad="" __kk_im_lv="" __kk_im_ml="" __kk_im_img="" __kk_im_ref="" __kk_im_key="" \
          __kk_im_name="" __kk_im_h="" __kk_im_cdir="" __kk_im_req="" __kk_im_rn="" __kk_im_rh="" __kk_im_files="" \
          __kk_im_fam=- __kk_im_act="" __kk_im_from="" __kk_im_wt="" __kk_im_stale=0 __kk_im_modes=0 \
          __kk_im_so="" __kk_im_hr="" __kk_im_rc=0 __kk_im_o=0 __kk_im_tool="" __kk_im_pn="" __kk_im_prior="" __kk_im_ph="" __kk_im_bg=""
    # (the background writer, kimgbg.sh kk._imgbg_run, calls kk.image as the
    # caller's file would: the caller from its dynamic local, and the writer's
    # path instead of a start; a kk.image nested in a unit's load sees its own)
    if [[ -n ${__kk_imbg_w-} ]]; then __kk_im_caller=$__kk_imbg_caller __kk_im_bg=w; fi
    local __kk_imbg_w=""
    local -a __kk_im_reqf=() __kk_im_reqk=() __kk_im_args=() __kk_im_pf=()
    while [[ ${1-} == --* ]]; do
        case $1 in
            --rebuild|--forget|--path)
                if [[ -n $__kk_im_act || $__kk_im_bg == 1 ]]; then kk._unit_err "kk.image $1: only one of --rebuild, --forget, --path, --background"; return 2; fi
                __kk_im_act=${1#--} ;;
            --background)
                if [[ -n $__kk_im_act ]]; then kk._unit_err "kk.image $1: only one of --rebuild, --forget, --path, --background"; return 2; fi
                [[ $__kk_im_bg == w ]] || __kk_im_bg=1 ;;
            --optional) __kk_im_o=1 ;;
            *)  if [[ -n $__kk_im_act ]]; then kk._unit_err "kk.image --$__kk_im_act: unknown option '$1'"; return 2; fi
                break ;;
        esac
        shift
    done
    if [[ $__kk_im_act == forget ]] && (( ! $# )); then kk._unit_err "kk.image --forget: no unit named"; return 2; fi
    if (( __kk_im_o )); then __kk_im_args=(--optional "$@"); else __kk_im_args=("$@"); fi
    for __kk_im_why; do __kk_im_req+=$__kk_im_why$__KK_SEP; done
    __kk_im_why=""
    if [[ $__kk_im_act != forget ]]; then
        case ${KBOOL_IMAGE-} in
            off|0) __kk_im_why="KBOOL_IMAGE=$KBOOL_IMAGE" ;;
        esac
    fi
    if [[ -z $__kk_im_why ]] && ! kk._image_hitlib; then __kk_im_why="kkore/kimghit.sh cannot be loaded"; fi
    if [[ -z $__kk_im_why ]]; then
        kk._image_run "$@"
        return
    fi
    case $__kk_im_act in
        path)   kk._image_dbg "--path: $__kk_im_why"; return 1 ;;
        forget) kk._image_dbg "--forget: $__kk_im_why; nothing deleted"; return 0 ;;
    esac
    kk._image_dbg "$__kk_im_why; a normal load (kk.uses ${__kk_im_args[*]})"
    kk._uses "$__kk_im_caller" "${__kk_im_args[@]}"
}

# kk._image_dbg MSG — the `kbool: image: MSG` line, under VERBOSE_KKLASS=debug only.
kk._image_dbg() {
    if [[ ${VERBOSE_KKLASS:-} == debug ]]; then printf 'kbool: image: %s\n' "$*" >&2; fi
    return 0
}

# kk._image_hitlib — source kkore/kimghit.sh (next to this file) unless
# loaded; kk._image_lib — kimghit.sh, then kkore/kimage.sh; kk._image_bglib —
# kimghit.sh, then kkore/kimgbg.sh (a --background miss). rc 1 when one
# fails. (A function defined by the file tells it is loaded; sourcing either
# again redefines its functions.)
kk._image_hitlib() {
    if declare -F kk._image_run >/dev/null; then return 0; fi
    local __kk_il_f=${__KK_UNITS[kuse]-}
    __kk_il_f=${__kk_il_f%[/\\]*}/kimghit.sh
    [[ -f $__kk_il_f ]] || return 1
    source "$__kk_il_f" || return 1
    declare -F kk._image_run >/dev/null
}
kk._image_bglib() {
    kk._image_hitlib || return 1
    if declare -F kk._imgbg_fore >/dev/null; then return 0; fi
    local __kk_il_f=${__KK_UNITS[kuse]-}
    __kk_il_f=${__kk_il_f%[/\\]*}/kimgbg.sh
    [[ -f $__kk_il_f ]] || return 1
    source "$__kk_il_f" || return 1
    declare -F kk._imgbg_fore >/dev/null
}
kk._image_lib() {
    kk._image_hitlib || return 1
    if declare -F kk._img_write >/dev/null; then return 0; fi
    local __kk_il_f=${__KK_UNITS[kuse]-}
    __kk_il_f=${__kk_il_f%[/\\]*}/kimage.sh
    [[ -f $__kk_il_f ]] || return 1
    source "$__kk_il_f" || return 1
    declare -F kk._img_write >/dev/null
}

# kk._image_hook UNIT FN — run the settings hook FN of UNIT marked as running
# (__KK_SETTINGS_RUN with this frame, kk._settings_hook): inside it kk.settings,
# kk.uses and kk.unit refuse to load units, as under kk.settings (I1a L9). rc =
# FN's rc. Used by the image start, the writer's simulation and kcl's harness.
kk._image_hook() {
    local __kk_ih_rc
    __KK_SETTINGS_RUN="$(( ${#FUNCNAME[@]} - 1 ))$__KK_SEP$1$__KK_SEP$2"
    "$2"
    __kk_ih_rc=$?
    __KK_SETTINGS_RUN=""
    return "$__kk_ih_rc"
}

# ---------------------------------------------------------------------------
# Configuration (U1b): the `key = value` reader, the lookup chain, kk.project,
# kk.config. Fork-free like the rest of this file.
#
# FILE FORMAT (U7, U7'). UTF-8 text (a leading UTF-8 BOM is skipped), LF or
# CRLF line ends. One `key = value` per line: the key is the text before the
# FIRST `=`, the value the text after it, both trimmed. A line whose first
# non-blank character is `#` is a comment; blank lines are skipped; CRs are
# dropped. Nothing is evaluated: no quoting, no escapes, no `~` or `$VAR`
# expansion, and a `#` inside a value is data. Keys:
#
#   unitpath = FOLDER     LIST — every line appends one folder (`dir/*` = every
#                         subfolder); kk.uses NAME searches them, in order, after
#                         the calling file's folder and before the system paths
#   defines  = A B ...    LIST — space-separated names; every line appends (kk.defined)
#   debug    = LEVEL      quiet | default | debug -> VERBOSE_KKLASS (kcl/README.md 1.2)
#   ckkdir   = FOLDER     the .ckk cache folder — stored for kklass (U2/U3): kk.config ckkdir
#
# A scalar key repeated in one file: the last line wins. An EMPTY value of a
# list key resets the list (see LEVELS for how far). In every FOLDER `\` becomes
# `/` (so `C:\x\units\*` is the every-subfolder form `C:/x/units/*`); a relative
# one is joined to the config file's own folder and `.`/`..` are folded
# lexically (no cd: symlinks are not resolved); an absolute one (`/x`, `C:\x`,
# `\\srv\x`) keeps its drive / root spelling — no cygpath (C16).
# A line without `=` or with an empty key, a line longer than 4096 characters,
# an unknown key, a debug level that is not one of the three and a define that
# is not a name (ASCII [A-Za-z_][A-Za-z0-9_]*, case-sensitive) each print one
# `kbool: WARNING: FILE:LINE: ...` line and are skipped; the rest of the file
# applies. An unknown key warns rather than passing silently because a misspelt
# key (`unit_path`) would otherwise do nothing without a trace; it is not an
# error, so a config shared by two kbool versions still loads in the older one.
# A WHOLE FILE is skipped with one WARNING when it is UTF-16 (a FF FE / FE FF
# BOM — what Windows PowerShell 5's `>` writes) or holds any NUL byte (binary),
# or when it has CR but no LF line ends (classic Mac). Only the first 64 KiB of
# a file are read (WARNING; the cut last line is dropped): the reader's time
# grows faster than linearly with the line length, and these two limits keep
# the worst case far below a second.
#
# LEVELS (U5 as amended by U29/U30/U38), strongest first:
#   env      $KBOOL_CONFIG, a config file path (set but missing / unreadable:
#            kbool.sh fails with rc 2 — P3). A relative one is made absolute
#            ($PWD at load) after the read, so a child shell in another folder
#            reads the same file
#   project  the file kk.project read
#   user     ~/.kbool/config, else $USERPROFILE/.kbool/config (only when
#            USERPROFILE is non-empty — never a root-relative /.kbool)
#   system   /etc/kbool/config, else $ProgramData/kbool/config (the Windows
#            variable is spelled ProgramData; only when non-empty)
#   built-in no defines, no debug level, no ckkdir, no project folders; the system
#            paths kkore, kklass, kcl/* are always searched last (U4)
# "else" = first found (`-f`). Combining: a SCALAR key takes the value of the
# strongest level that sets it (an empty value counts: it sets the key to
# nothing there); a LIST key takes the entries of every level, strongest level
# first, each level in file order, without duplicates — so a project's folders
# are searched before the user's and those before the system config's. An
# EMPTY list value (U39, owner 2026-10-07) drops the entries above it in its
# own file and every weaker ENVIRONMENT level's (user, system) — never the
# project's: the project's lists always apply, and the project resets the
# inherited user/system entries with its own empty value. env, user and system
# are read when kbool.sh loads; kk.project reads its file and merges again.
#
# The debug level writes VERBOSE_KKLASS only when nobody else set it: it must
# be unset, or still hold the value the config itself wrote. A VERBOSE_KKLASS
# from the environment (even an empty one) or set by the script always wins —
# with one limitation: a script that assigns exactly the value the config wrote
# cannot be told from the config's own value, so a later kk.project may change
# it. The config's value is never exported (also under `set -a`): a child
# shell reads the config levels itself.
#
# The system folder /etc/kbool can be replaced through __KK_CFG_ETC (a test
# hook for hermetic tests; not an API).

# kk._cfg_fold PATH -> __kk_n: `\` -> `/`, then `.`, `..` and `//` folded
# lexically; a `C:` prefix and a leading UNC `//` are kept.
kk._cfg_fold() {
    local __kk_p=${1//\\//} __kk_pre="" __kk_s __kk_o=""
    if [[ $__kk_p == [A-Za-z]:* ]]; then
        __kk_pre=${__kk_p:0:2}
        __kk_p=${__kk_p:2}
    elif [[ $__kk_p == //* ]]; then
        __kk_pre=/
    fi
    __kk_p+=/
    while [[ -n $__kk_p ]]; do
        __kk_s=${__kk_p%%/*}
        __kk_p=${__kk_p#*/}
        case $__kk_s in
            ''|.) ;;
            ..) __kk_o=${__kk_o%/*} ;;
            *) __kk_o+=/$__kk_s ;;
        esac
    done
    __kk_n=$__kk_pre${__kk_o:-/}
}

# kk._cfg_path VALUE BASE -> __kk_n: an absolute VALUE (`/x`, `\x`, `C:...`)
# with `\` -> `/` and nothing else changed; a relative one is BASE/VALUE with
# `\` -> `/` and VALUE's `.`/`..` segments applied to BASE. BASE is a folder
# already folded by kk._cfg_read: `/`-separated, no `.`/`..`/`//`, no trailing
# `/` ('' = the root).
kk._cfg_path() {
    case $1 in
        /*|\\*|[A-Za-z]:*) __kk_n=${1//\\//}; return 0 ;;
        *\\*|.|..|./*|../*|*/.|*/..|*/./*|*/../*|*//*) ;;
        *) __kk_n=$2/${1%/}; return 0 ;;     # the common case: nothing to fold
    esac
    local __kk_b=$2 __kk_p=${1//\\//}/ __kk_s
    while [[ -n $__kk_p ]]; do
        __kk_s=${__kk_p%%/*}
        __kk_p=${__kk_p#*/}
        case $__kk_s in
            ''|.) ;;
            ..) if [[ $__kk_b == */* ]]; then __kk_b=${__kk_b%/*}; fi ;;
            *) __kk_b+=/$__kk_s ;;
        esac
    done
    __kk_n=${__kk_b:-/}
}

# kk._cfg_read FILE LEVEL — parse FILE into the LEVEL slot of __KK_CFG_LV,
# replacing what that level held. rc 0 (malformed lines, or a whole file
# refused as UTF-16 / binary / CR-only, only WARN); rc 2 (printed) when FILE
# cannot be read. Callers own the registry (R14) and have tested `-f`.
kk._cfg_read() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # no registry of this shell (R14)
    local - __kk_file=$1 __kk_lv=$2 __kk_all="" __kk_l __kk_k __kk_v __kk_w __kk_no=0 \
          __kk_d __kk_n __kk_nc=0 __kk_rc=0 __kk_cut=0 __kk_up="" __kk_upr="" __kk_df="" __kk_dfr="" \
          __kk_dbg="" __kk_dbgs="" __kk_ck="" __kk_cks="" IFS
    local -a __kk_ls __kk_ws
    unset '__KK_CFG_LV[$__kk_lv/unitpath]' '__KK_CFG_LV[$__kk_lv/unitpath!]' \
          '__KK_CFG_LV[$__kk_lv/defines]' '__KK_CFG_LV[$__kk_lv/defines!]' \
          '__KK_CFG_LV[$__kk_lv/debug]' '__KK_CFG_LV[$__kk_lv/ckkdir]'
    # One read of at most 64 KiB, no fork, NUL as the delimiter: `read -N` would
    # drop NUL bytes silently (`A\0B` became the define AB), so this read stops
    # at the first NUL instead — rc 0 with fewer characters than asked = a NUL.
    # It reads byte by byte on MSYS (~1.2 us per byte; 64 KiB ~80 ms); a
    # 10-line file costs ~0.2 ms more than `read -N`. A stat costs 150-200 us,
    # so `-r` is asked only when the read returned nothing.
    IFS= read -r -d '' -n 65536 __kk_all 2>/dev/null <"$__kk_file" || __kk_rc=$?
    if (( __kk_rc != 0 )) && [[ -z $__kk_all ]] && [[ ! -f $__kk_file || ! -r $__kk_file ]]; then
        kk._unit_err "cannot read the config file '$__kk_file'"
        return 2
    fi
    if (( __kk_rc == 0 && ${#__kk_all} < 65536 )) \
       || [[ $__kk_all == $'\xff\xfe'* || $__kk_all == $'\xfe\xff'* ]]; then
        kk._unit_warn "$__kk_file: UTF-16 or binary content (a NUL byte) is not supported - save it as UTF-8; the file is ignored"
        return 0
    fi
    if (( __kk_rc == 0 )); then
        kk._unit_warn "$__kk_file: longer than 64 KiB; the rest is ignored"
        __kk_cut=1                               # the cut last line goes below
    fi
    # a UTF-8 BOM: tested as a prefix, then cut by its length in THIS locale (1
    # character under UTF-8, 3 bytes under C) — `${all#$'\xef\xbb\xbf'}` costs
    # ~450 ms on a 64 KiB value on MSYS
    if [[ $__kk_all == $'\xef\xbb\xbf'* ]]; then
        __kk_w=$'\xef\xbb\xbf'
        __kk_all=${__kk_all:${#__kk_w}}
    fi
    if [[ $__kk_all == *$'\r'* && $__kk_all != *$'\n'* ]]; then
        kk._unit_warn "$__kk_file: CR-only line ends are not supported - save it with LF or CRLF line ends; the file is ignored"
        return 0
    fi
    # the base for relative paths: the file's folder, folded once
    kk._unit_dir "$__kk_file"
    __kk_d=${__kk_d//\\//}
    case $__kk_d in
        *//*|*/.|*/./*|*/..|*/../*) kk._cfg_fold "$__kk_d"; __kk_d=$__kk_n ;;
    esac
    __kk_d=${__kk_d%/}
    # key and define names match exactly (case-sensitive); no globbing below
    if [[ $BASHOPTS == *nocasematch* ]]; then __kk_nc=1; shopt -u nocasematch; fi
    set -f
    # lines by ONE word split on newlines; an empty line would vanish (IFS
    # whitespace), so it becomes `#` first — line numbers stay exact. CRs go in
    # one pass (a CR inside a line is never meaningful here).
    __kk_all=${__kk_all//$'\r'/}
    if [[ $__kk_all == $'\n'* ]]; then __kk_all="#$__kk_all"; fi
    __kk_all=${__kk_all//$'\n\n'/$'\n#\n'}
    __kk_all=${__kk_all//$'\n\n'/$'\n#\n'}
    IFS=$'\n'
    __kk_ls=($__kk_all)
    unset IFS                    # the default splitting, for `defines` below
    if (( __kk_cut && ${#__kk_ls[@]} )); then unset '__kk_ls[-1]'; fi
    # Every statement costs 5-10 us on MSYS, so the loop keeps the usual line
    # (`key = value`, one define per line) to about a dozen; values accumulate
    # in locals and reach __KK_CFG_LV once, after the loop.
    for __kk_l in "${__kk_ls[@]}"; do
        __kk_no=$(( __kk_no + 1 ))
        case $__kk_l in
            ''|'#'*) continue ;;
        esac
        if (( ${#__kk_l} > 4096 )); then
            kk._unit_warn "$__kk_file:$__kk_no: longer than 4096 characters; ignored"
            continue
        fi
        if [[ $__kk_l == [[:space:]]* ]]; then
            __kk_l=${__kk_l#"${__kk_l%%[![:space:]]*}"}
            case $__kk_l in
                ''|'#'*) continue ;;
            esac
        fi
        __kk_k=${__kk_l%%=*}
        if [[ $__kk_k == "$__kk_l" ]]; then          # no `=`
            kk._unit_warn "$__kk_file:$__kk_no: not a 'key = value' line; ignored"
            continue
        fi
        __kk_k=${__kk_k%"${__kk_k##*[![:space:]]}"}
        __kk_v=${__kk_l#*=}
        __kk_v=${__kk_v#"${__kk_v%%[![:space:]]*}"}
        if [[ $__kk_v == *[[:space:]] ]]; then __kk_v=${__kk_v%"${__kk_v##*[![:space:]]}"}; fi
        case $__kk_k in
            defines)
                if [[ -n $__kk_v && $__kk_v != *[!A-Za-z0-9_]* && $__kk_v != [0-9]* && $__kk_v != *[![:ascii:]]* ]]; then
                    __kk_df+=$__kk_v$'\n'                   # one name: the usual line
                elif [[ -z $__kk_v ]]; then
                    __kk_df=""
                    __kk_dfr=1
                elif [[ $__kk_v != *[!A-Za-z0-9_[:space:]]* && " $__kk_v" != *[[:space:]][0-9]* \
                     && $__kk_v != *[![:ascii:]]* ]]; then
                    __kk_ws=($__kk_v)                       # all names: one append
                    printf -v __kk_w '%s\n' "${__kk_ws[@]}"
                    __kk_df+=$__kk_w
                else
                    # mixed: one WARNING per line names every word that is not
                    # a name (a pathological line holds ~2000 of them)
                    __kk_ws=($__kk_v)                       # set -f: no globbing
                    __kk_n=""
                    for __kk_w in "${__kk_ws[@]}"; do
                        if [[ $__kk_w == [!A-Za-z_]* || $__kk_w == *[!A-Za-z0-9_]* || $__kk_w == *[![:ascii:]]* ]]; then
                            __kk_n+=" '$__kk_w'"
                        else
                            __kk_df+=$__kk_w$'\n'
                        fi
                    done
                    if [[ -n $__kk_n ]]; then kk._unit_warn "$__kk_file:$__kk_no: not a define name, ignored:$__kk_n"; fi
                fi
                ;;
            unitpath)
                if [[ -z $__kk_v ]]; then
                    __kk_up=""
                    __kk_upr=1
                else
                    kk._cfg_path "$__kk_v" "$__kk_d"
                    __kk_up+=$__kk_n$'\n'
                fi
                ;;
            debug)
                case $__kk_v in
                    ''|quiet|default|debug) __kk_dbg=$__kk_v; __kk_dbgs=1 ;;
                    *) kk._unit_warn "$__kk_file:$__kk_no: debug '$__kk_v' is not quiet, default or debug; ignored" ;;
                esac
                ;;
            ckkdir)
                if [[ -n $__kk_v ]]; then
                    kk._cfg_path "$__kk_v" "$__kk_d"
                    __kk_v=$__kk_n
                fi
                __kk_ck=$__kk_v
                __kk_cks=1
                ;;
            '')
                kk._unit_warn "$__kk_file:$__kk_no: not a 'key = value' line; ignored"
                ;;
            *)
                kk._unit_warn "$__kk_file:$__kk_no: unknown key '$__kk_k'; ignored"
                ;;
        esac
    done
    if [[ -n $__kk_up || -n $__kk_upr ]]; then __KK_CFG_LV[$__kk_lv/unitpath]=$__kk_up; fi
    if [[ -n $__kk_upr ]]; then __KK_CFG_LV[$__kk_lv/unitpath!]=1; fi
    if [[ -n $__kk_df || -n $__kk_dfr ]]; then __KK_CFG_LV[$__kk_lv/defines]=$__kk_df; fi
    if [[ -n $__kk_dfr ]]; then __KK_CFG_LV[$__kk_lv/defines!]=1; fi
    if [[ -n $__kk_dbgs ]]; then __KK_CFG_LV[$__kk_lv/debug]=$__kk_dbg; fi
    if [[ -n $__kk_cks ]]; then __KK_CFG_LV[$__kk_lv/ckkdir]=$__kk_ck; fi
    if (( __kk_nc )); then shopt -s nocasematch; fi
    return 0
}

# kk._cfg_merge — rebuild __KK_CFG from the levels (the rule above).
kk._cfg_merge() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # (R14)
    local - __kk_k __kk_lv __kk_l __kk_e __kk_o __kk_cut IFS
    local -a __kk_es
    local -A __kk_seen
    __KK_CFG=()
    for __kk_k in debug ckkdir; do
        for __kk_lv in env project user system; do
            if [[ -n ${__KK_CFG_LV[$__kk_lv/$__kk_k]+x} ]]; then
                __KK_CFG[$__kk_k]=${__KK_CFG_LV[$__kk_lv/$__kk_k]}
                break
            fi
        done
    done
    set -f
    for __kk_k in unitpath defines; do
        __kk_l=""
        __kk_cut=0
        for __kk_lv in env project user system; do
            # an empty list value cuts the weaker ENVIRONMENT levels, never the
            # project (U39)
            if (( __kk_cut )) && [[ $__kk_lv != project ]]; then continue; fi
            __kk_l+=${__KK_CFG_LV[$__kk_lv/$__kk_k]-}
            if [[ -n ${__KK_CFG_LV[$__kk_lv/$__kk_k!]+x} ]]; then __kk_cut=1; fi
        done
        __kk_seen=()
        __kk_o=""
        IFS=$'\n'
        __kk_es=($__kk_l)
        unset IFS
        for __kk_e in "${__kk_es[@]}"; do
            if [[ -z ${__kk_seen[$__kk_e]+x} ]]; then
                __kk_seen[$__kk_e]=1
                __kk_o+=$__kk_e$'\n'
            fi
        done
        __KK_CFG[$__kk_k]=$__kk_o
    done
}

# kk._cfg_apply — make the merged config effective: the project search path,
# the defines, the debug level; the name index and the resolution caches start
# over (P6, U16).
kk._cfg_apply() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # (R14)
    local - __kk_v=${__KK_CFG[debug]-} __kk_e IFS
    local -a __kk_es
    set -f
    IFS=$'\n'
    __KK_UNIT_PROJPATH=(${__KK_CFG[unitpath]-})
    __kk_es=(${__KK_CFG[defines]-})
    unset IFS
    __KK_DEFINES=()
    for __kk_e in "${__kk_es[@]}"; do
        __KK_DEFINES[$__kk_e]=1
    done
    __KK_UNIT_IDX_OK=0
    __KK_UNIT_RES=()
    __KK_UNIT_HIT=()
    # VERBOSE_KKLASS: only when unset, or still what the config wrote last time
    if [[ -z ${VERBOSE_KKLASS+x} || ( -n $__KK_CFG_VKW && $VERBOSE_KKLASS == "$__KK_CFG_VKW" ) ]]; then
        case $__kk_v in
            quiet|debug)
                VERBOSE_KKLASS=$__kk_v
                __KK_CFG_VKW=$__kk_v
                # under `set -a` the assignment exported it, and a child would
                # take it for an environment value it must not overwrite (R7)
                if [[ $- == *a* ]]; then export -n VERBOSE_KKLASS; fi
                ;;
            *)
                if [[ -n $__KK_CFG_VKW ]]; then unset VERBOSE_KKLASS; fi
                __KK_CFG_VKW=""
                ;;
        esac
    fi
    return 0
}

# kk._cfg_userfile REL -> __kk_found: ~/.kbool/REL, else $USERPROFILE/.kbool/REL
# (first found; an empty HOME / USERPROFILE is never probed). rc 1 when neither.
kk._cfg_userfile() {
    __kk_found=""
    if [[ -n ${HOME-} && -f $HOME/.kbool/$1 ]]; then
        __kk_found=$HOME/.kbool/$1
    elif [[ -n ${USERPROFILE-} && -f $USERPROFILE/.kbool/$1 ]]; then
        __kk_found=$USERPROFILE/.kbool/$1
    fi
    [[ -n $__kk_found ]]
}

# kk._cfg_boot — kbool.sh, after the system units: read the system, user and
# KBOOL_CONFIG levels, merge, apply. rc 2 (printed, nothing applied) when
# KBOOL_CONFIG names no file or a config file cannot be read (P3).
kk._cfg_boot() {
    [[ ${__KK_LOADED[@]@a} == A ]] || return 2       # (R14)
    local __kk_f __kk_found __kk_n
    __KK_CFG_LV=()
    __KK_CFG=()
    __kk_f=${__KK_CFG_ETC:-/etc/kbool}/config
    if [[ -f $__kk_f ]]; then
        kk._cfg_read "$__kk_f" system || return 2
    elif [[ -n ${ProgramData-} && -f $ProgramData/kbool/config ]]; then
        kk._cfg_read "$ProgramData/kbool/config" system || return 2
    fi
    if kk._cfg_userfile config; then
        kk._cfg_read "$__kk_found" user || return 2
    fi
    if [[ -n ${KBOOL_CONFIG-} ]]; then
        if [[ ! -f $KBOOL_CONFIG ]]; then
            kk._unit_err "KBOOL_CONFIG names no config file: '$KBOOL_CONFIG'"
            return 2
        fi
        kk._cfg_read "$KBOOL_CONFIG" env || return 2
        # a relative KBOOL_CONFIG is relative to THIS shell's folder: made
        # absolute, a child shell (which inherits it) started elsewhere — or a
        # unit header bootstrapping kbool.sh there — reads the same file (R5)
        case $KBOOL_CONFIG in
            /*|\\*|[A-Za-z]:*) ;;
            *) kk._cfg_fold "$PWD/$KBOOL_CONFIG"; KBOOL_CONFIG=$__kk_n ;;
        esac
    fi
    # nothing read (no config anywhere): the tables are already the built-in state
    if (( ${#__KK_CFG_LV[@]} )); then
        kk._cfg_merge
        kk._cfg_apply
    fi
    return 0
}

# ---------------------------------------------------------------------------
# kk.project PATH|NAME — read a project file (U8, U9, U11, U37, U2').
#   PATH (contains `/` or `\`, or ends in `.conf`): the project file; a relative
#        PATH is relative to the CALLING file's folder (a prompt: $PWD), like kk.uses
#   NAME: ~/.kbool/NAME/project.conf, else $USERPROFILE/.kbool/NAME/project.conf
# Paths inside the file are relative to its own folder. Its keys are the config
# keys above; it is the second-strongest level (only KBOOL_CONFIG beats it).
# rc 0 = applied: the project folders feed kk.uses NAME (the name index and the
# resolution caches start over), the defines feed kk.defined, the debug level
# and ckkdir take effect. kk.project runs once per shell: a later call naming
# the SAME file (`-ef`, any spelling) is an rc-0 no-op, like kk.uses (owner
# 2026-10-07). rc 2 (printed; nothing applied, a later call may try again):
# usage, not found, unreadable, another project already set, or a non-system
# unit already used (U37: kk.project must come before the first kk.uses of a
# non-system unit, and before any unit is sourced).
kk.project() {
    if [[ ${__KK_LOADED[@]@a} != A ]]; then
        # a child bash that inherited the functions but not the registry (R8, R14)
        [[ -z ${KBOOL_HOME-} || ! -f ${KBOOL_HOME-}/kbool.sh ]] || source "$KBOOL_HOME/kbool.sh" || return
        [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.project %s: kbool.sh is not loaded\n' "$*" >&2; return 2; }
    fi
    local __kk_a=${1-} __kk_f __kk_d __kk_n __kk_found __kk_m
    if (( $# != 1 )) || [[ -z $__kk_a ]]; then
        kk._unit_err "kk.project: usage 'kk.project PATH|NAME'"
        return 2
    fi
    if [[ $__kk_a == *[/\\]* || $__kk_a == *.conf ]]; then
        if [[ $__kk_a == /* || $__kk_a == \\* || $__kk_a == [A-Za-z]:* ]]; then
            __kk_f=$__kk_a
        else
            if [[ -n ${BASH_SOURCE[1]-} ]]; then
                kk._unit_dir "${BASH_SOURCE[1]}"
            else
                __kk_d=$PWD
            fi
            __kk_f=$__kk_d/$__kk_a
        fi
        if [[ ! -f $__kk_f ]]; then
            kk._unit_err "kk.project: project file '$__kk_f' not found"
            return 2
        fi
    else
        if [[ $__kk_a == . || $__kk_a == .. ]]; then
            kk._unit_err "kk.project: '$__kk_a' is not a project name"
            return 2
        fi
        if ! kk._cfg_userfile "$__kk_a/project.conf"; then
            __kk_m=""
            if [[ -n ${HOME-} ]]; then __kk_m+="'$HOME/.kbool/$__kk_a/project.conf'"; fi
            if [[ -n ${USERPROFILE-} ]]; then __kk_m+="${__kk_m:+, }'$USERPROFILE/.kbool/$__kk_a/project.conf'"; fi
            kk._unit_err "kk.project: project '$__kk_a' not found (searched ${__kk_m:-nothing: HOME and USERPROFILE are empty})"
            return 2
        fi
        __kk_f=$__kk_found
    fi
    if [[ -n $__KK_PROJECT ]]; then
        if [[ $__kk_f == "$__KK_PROJECT" || $__kk_f -ef $__KK_PROJECT ]]; then
            return 0
        fi
        kk._unit_err "kk.project $__kk_a: a project is already set ('$__KK_PROJECT'); kk.project runs once"
        return 2
    fi
    if [[ -n $__KK_UNIT_USED ]]; then
        kk._unit_err "kk.project $__kk_a: too late, unit '$__KK_UNIT_USED' is already in use (kk.project must come before the first kk.uses of a non-system unit)"
        return 2
    fi
    kk._cfg_read "$__kk_f" project || return 2
    __KK_PROJECT=$__kk_f
    kk._cfg_merge
    kk._cfg_apply
    return 0
}

# ---------------------------------------------------------------------------
# kk.config KEY [OUTVAR] — the merged configuration, for the other layers
# (kcl/README.md 1.1, 1.2, 1.6, 1.7).
#   scalar KEY (debug, ckkdir): RESULT = the value; rc 1 + RESULT='' when no
#        level sets it (or sets it empty). Inside $( ) the value is printed.
#   list KEY (unitpath, defines) without OUTVAR: RESULT = the entries joined by
#        newlines (printed inside $( )); with OUTVAR: the caller's indexed array
#        OUTVAR gets the entries and RESULT their count. rc 1 + RESULT=''
#        (OUTVAR emptied) when the list is empty.
#   rc 2 (silent; the reason under VERBOSE_KKLASS=debug): no or an unknown KEY
#        (keys match exactly, also under nocasematch), an OUTVAR for a scalar
#        key, a bad or reserved OUTVAR (kk._outName), an OUTVAR that is an
#        associative or a readonly variable, more arguments; kbool.sh not
#        loaded in this shell (printed).
kk.config() {
    if [[ a == A && $BASHOPTS == *nocasematch* ]]; then    # exact keys (kcl 1.6)
        shopt -u nocasematch
        kk.config "$@"
        local __kk_rc=$?
        shopt -s nocasematch
        return "$__kk_rc"
    fi
    RESULT=""
    if [[ ${__KK_LOADED[@]@a} != A ]]; then      # no registry of this shell (R14)
        printf 'kbool: error: kk.config %s: kbool.sh is not loaded\n' "${1-}" >&2
        return 2
    fi
    local __kk_k=${1-} __kk_v __kk_at
    case $__kk_k in
        debug|ckkdir)
            if (( $# != 1 )); then
                kk.debug "kk.config $__kk_k: a scalar key takes no OUTVAR"
                return 2
            fi
            RESULT=${__KK_CFG[$__kk_k]-}
            [[ -n $RESULT ]] || return 1
            if (( BASH_SUBSHELL > 0 )); then printf '%s' "$RESULT"; fi
            return 0
            ;;
        unitpath|defines) ;;
        *)
            kk.debug "kk.config: unknown key '$__kk_k' (unitpath, defines, debug, ckkdir)"
            return 2
            ;;
    esac
    __kk_v=${__KK_CFG[$__kk_k]-}
    if (( $# == 1 )); then
        [[ -n $__kk_v ]] || return 1
        RESULT=${__kk_v%$'\n'}
        if (( BASH_SUBSHELL > 0 )); then printf '%s' "$RESULT"; fi
        return 0
    fi
    if (( $# != 2 )) || ! kk._outName "$2"; then
        kk.debug "kk.config $__kk_k: '${2-}' is not a usable output array name"
        return 2
    fi
    # an associative or readonly OUTVAR would take the entries as keys (rc 0)
    # or fail with a bash diagnostic: refused before the nameref is bound
    local -
    set +u
    __kk_at="$2[@]"
    __kk_at=${!__kk_at@a}
    if [[ $__kk_at == *[Ar]* ]]; then
        kk.debug "kk.config $__kk_k: '$2' is an associative or readonly variable"
        return 2
    fi
    local -n __kk_o=$2
    __kk_o=()
    while [[ -n $__kk_v ]]; do
        __kk_o+=("${__kk_v%%$'\n'*}")
        __kk_v=${__kk_v#*$'\n'}
    done
    (( ${#__kk_o[@]} )) || return 1
    RESULT=${#__kk_o[@]}
    return 0
}

# ---------------------------------------------------------------------------
# kk.defined NAME — a define of the merged config (U31): rc 0 defined, 1 not,
# 2 no name / more than one argument / kbool.sh not loaded in this shell.
# Case-sensitive.
kk.defined() {
    [[ -n ${1-} ]] || return 2
    [[ ${__KK_LOADED[@]@a} == A ]] || { printf 'kbool: error: kk.defined %s: kbool.sh is not loaded\n' "$1" >&2; return 2; }
    (( $# == 1 )) || return 2
    [[ -n ${__KK_DEFINES[$1]+x} ]]
}
