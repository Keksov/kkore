#!/bin/bash
# The config reader, the config lookup chain, kk.project and kk.config
# (kklass/USES_PLAN.md U5/U29/U30/U38, U7/U7', U8-U11, U31, U37, U2'; phase U1b).
# Every scenario runs in a FRESH bash against the throw-away kbool tree of
# unit_fixture.sh. Hermetic: uf_run points HOME at a fixture folder, unsets
# USERPROFILE / ProgramData / PROGRAMDATA / KBOOL_CONFIG and replaces /etc/kbool
# by the fixture folder in __KK_CFG_ETC — no real ~/.kbool, /etc/kbool or
# %ProgramData%\kbool is ever read or created.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ConfigProject" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/unit_fixture.sh"
UF_FX="$_KT_TMPDIR/fx"
uf_build "$UF_FX" || { kt_test_start "fixture"; kt_test_fail "uf_build failed"; exit 1; }
FX="$UF_FX"
F="$FX"

# show.sh: one line with the merged config as kk.config reports it, the debug
# level and the project search path
cat > "$FX/show.sh" <<'EOF'
kk.config debug; __d="$RESULT:$?"
kk.config ckkdir; __c="$RESULT:$?"
kk.config unitpath; __u="${RESULT//$'\n'/,}:$?"
kk.config defines; __f="${RESULT//$'\n'/,}:$?"
__p=""; for __x in "${__KK_UNIT_PROJPATH[@]}"; do __p+="$__x,"; done
echo "debug=$__d ckk=$__c up=$__u def=$__f vk=${VERBOSE_KKLASS-unset} pp=$__p"
EOF

# every scenario starts from a clean set of config folders
cfg_clean() { rm -rf "$F/home" "$F/etc" "$F/w" "$F/pd" "$F/pd2" "$F/c" "$F/p"; }

# ---------------------------------------------------------------------------
# The reader (U7, U7'): comments, blank lines, CRLF, trim, repeat-to-append lists,
# relative paths against the file's own folder
cfg_clean
mkdir -p "$F/c/1"
printf '%s\r\n' '# a comment' '   # an indented comment' '' '  debug   =   debug  ' 'ckkdir = cache=dir' \
    'unitpath = lib' 'unitpath=../shared/*' 'defines = A  B' $'defines =\tC' > "$F/c/1/kb.conf"
uf_run 'export KBOOL_CONFIG="$FX/c/1/kb.conf"; source "$FX/kbool.sh"; echo "r=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "r=0"$'\n'"debug=debug:0 ckk=$F/c/1/cache=dir:0 up=$F/c/1/lib,$F/c/shared/*:0 def=A,B,C:0 vk=debug pp=$F/c/1/lib,$F/c/shared/*," ]]
uf_check "reader: # lines, blanks, CRLF, trim, value after the FIRST '=', list keys repeat to append, paths relative to the file (lexical) [U7, U7']" $?

cfg_clean
uf_cfg "$F/c/2/kb.conf" 'debug = quiet' 'debug = debug' 'ckkdir = /abs/x # not a comment' 'ckkdir = /abs/y # not a comment'
uf_run 'export KBOOL_CONFIG="$FX/c/2/kb.conf"; source "$FX/kbool.sh"; source "$FX/show.sh"'
[[ "$UF_OUT" == "debug=debug:0 ckk=/abs/y # not a comment:0 up=:1 def=:1 vk=debug pp=" ]]
uf_check "reader: a scalar key repeated in one file — the last line wins; '#' inside a value is data; absolute paths as written [U7']" $?

cfg_clean
uf_cfg "$F/c/3/kb.conf" '# c' 'just words' 'unit_path = x' '= nokey' 'debug = loud' 'defines = OK 9bad' 'ckkdir = c'
uf_run 'export KBOOL_CONFIG="$FX/c/3/kb.conf"; source "$FX/kbool.sh"; echo "r=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "kbool: WARNING: $F/c/3/kb.conf:2: not a 'key = value' line; ignored"$'\n'"kbool: WARNING: $F/c/3/kb.conf:3: unknown key 'unit_path'; ignored"$'\n'"kbool: WARNING: $F/c/3/kb.conf:4: not a 'key = value' line; ignored"$'\n'"kbool: WARNING: $F/c/3/kb.conf:5: debug 'loud' is not quiet, default or debug; ignored"$'\n'"kbool: WARNING: $F/c/3/kb.conf:6: not a define name, ignored: '9bad'"$'\n'"r=0"$'\n'"debug=:1 ckk=$F/c/3/c:0 up=:1 def=OK:0 vk=unset pp=" ]]
uf_check "reader: a line without '=', an empty key, an unknown key, a bad debug level, a bad define -> one WARNING each with file:line, skipped; the rest applies [U7]" $?

uf_run 'export KBOOL_CONFIG="$FX/c/3/kb.conf" VERBOSE_KKLASS=quiet; source "$FX/kbool.sh"; echo "r=$?"'
[[ "$UF_OUT" == "r=0" ]]
uf_check "reader: the WARNINGs are silenced by VERBOSE_KKLASS=quiet" $?

cfg_clean
mkdir -p "$F/c/4/winlib" "$F/c/4/sub/lib2"
uf_user "$F/c/4/winlib/wu.sh" wu 'WU_LOADS=$(( ${WU_LOADS:-0} + 1 ))'
uf_user "$F/c/4/sub/lib2/wv.sh" wv 'WV_LOADS=$(( ${WV_LOADS:-0} + 1 ))'
uf_win "$F/c/4/winlib"; W4LIB=$UF_WIN
uf_win "$F/c/4/ck"; W4CK=$UF_WIN
uf_cfg "$F/c/4/kb.conf" "unitpath = $W4LIB" 'unitpath = sub\lib2' "ckkdir = $W4CK"
uf_run 'export KBOOL_CONFIG="$FX/c/4/kb.conf"; source "$FX/kbool.sh"; kk.uses wu wv; echo "u=$? $WU_LOADS$WV_LOADS"; source "$FX/show.sh"'
W4LIBS=${W4LIB//\\//}; W4CKS=${W4CK//\\//}
[[ "$UF_OUT" == "u=0 11"$'\n'"debug=:1 ckk=$W4CKS:0 up=$W4LIBS,$F/c/4/sub/lib2:0 def=:1 vk=unset pp=$W4LIBS,$F/c/4/sub/lib2," ]]
uf_check "reader: an absolute C:\\ path keeps its drive spelling with '\\' -> '/', a relative path with '\\' joins the file's folder; kk.uses finds units there (no cygpath) [U7', C16, R1]" $?

mkdir -p "$F/c/4/pkgs/pk1"
uf_user "$F/c/4/pkgs/pk1/pk1.sh" pk1 'PK1_LOADS=1'
uf_win "$F/c/4/pkgs"; W4PK=$UF_WIN
uf_cfg "$F/c/4/pk.conf" "unitpath = $W4PK\\*"
uf_run 'export KBOOL_CONFIG="$FX/c/4/pk.conf"; source "$FX/kbool.sh"; kk.uses pk1; echo "u=$? L=$PK1_LOADS"; kk.config unitpath; echo "$RESULT"'
[[ "$UF_OUT" == "u=0 L=1"$'\n'"${W4PK//\\//}/*" ]]
uf_check "reader: an absolute 'C:\\...\\pkgs\\*' entry is the every-subfolder form 'C:/.../pkgs/*' (was a literal folder '*') [U13, R1]" $?

uf_win "$F/c/4/kb.conf"
uf_run "export KBOOL_CONFIG='$UF_WIN'; source \"\$FX/kbool.sh\"; kk.uses wv; echo \"u=\$? \$WV_LOADS\"; kk.config unitpath; echo \"\${RESULT//\$'\\n'/,}\""
[[ "$UF_OUT" == "u=0 1"$'\n'"$W4LIBS,C:/${F:3}/c/4/sub/lib2" ]]
uf_check "KBOOL_CONFIG given as C:\\...: relative entries join its folder (separators folded to /), the unit is found" $?

cfg_clean
uf_cfg "$F/home/.kbool/config" 'unitpath = u1' 'defines = U'
uf_cfg "$F/c/5/kb.conf" 'unitpath = e1' 'unitpath =' 'unitpath = e2' 'defines = X' 'defines =' 'defines = E'
uf_run 'export KBOOL_CONFIG="$FX/c/5/kb.conf"; source "$FX/kbool.sh"; source "$FX/show.sh"; kk.defined U; echo "U=$?"'
[[ "$UF_OUT" == "debug=:1 ckk=:1 up=$F/c/5/e2:0 def=E:0 vk=unset pp=$F/c/5/e2,"$'\n'"U=1" ]]
uf_check "an EMPTY list value resets the list: the entries above it in the file and every weaker level's [U7', U1b merge rule]" $?

# ---------------------------------------------------------------------------
# KBOOL_CONFIG failures (P3: kbool.sh rc != 0, guard off)
cfg_clean
P3_PROBE='source "$FX/kbool.sh"; r=$?; [[ ${__KK_UNITS[@]@a} == A* ]] && g=on || g=off; echo "r=$r guard=$g home=${KBOOL_HOME-unset}"'
uf_run "export KBOOL_CONFIG=\"\$FX/c/none.conf\"; $P3_PROBE"
[[ "$UF_OUT" == *"KBOOL_CONFIG"*"$F/c/none.conf"*$'\n'"r=2 guard=off home=unset" ]]
uf_check "KBOOL_CONFIG names a missing file -> kbool.sh rc 2 naming it, guard off, KBOOL_HOME unset [P3, U38]" $?

mkdir -p "$F/c/adir"
uf_run "export KBOOL_CONFIG=\"\$FX/c/adir\"; $P3_PROBE"
[[ "$UF_OUT" == *"r=2 guard=off home=unset" ]]
uf_check "KBOOL_CONFIG names a folder -> rc 2, guard off [P3]" $?

uf_run "export KBOOL_CONFIG=; $P3_PROBE; source \"\$FX/show.sh\""
[[ "$UF_OUT" == "r=0 guard=on home=$F"$'\n'"debug=:1 ckk=:1 up=:1 def=:1 vk=unset pp=" ]]
uf_check "an empty KBOOL_CONFIG counts as unset; no config anywhere -> built-in defaults, silent [U4]" $?

# ---------------------------------------------------------------------------
# The chain (U5/U29/U30/U38): user = ~/.kbool else $USERPROFILE/.kbool;
# system = /etc/kbool else $ProgramData/kbool
cfg_clean
uf_cfg "$F/home/.kbool/config" 'defines = HOMEDEF'
uf_cfg "$F/w/.kbool/config" 'defines = WINDEF'
uf_win "$F/w"; WUP=$UF_WIN
uf_run "export USERPROFILE='$WUP'; source \"\$FX/kbool.sh\"; kk.config defines; echo \"d=\$RESULT\""
[[ "$UF_OUT" == "d=HOMEDEF" ]]
uf_check "user level: ~/.kbool/config is read, \$USERPROFILE/.kbool/config is NOT when ~ has one (first found) [U29]" $?

rm -f "$F/home/.kbool/config"
uf_run "export USERPROFILE='$WUP'; source \"\$FX/kbool.sh\"; kk.config defines; echo \"d=\$RESULT\""
[[ "$UF_OUT" == "d=WINDEF" ]]
uf_check "user level: no ~/.kbool/config -> \$USERPROFILE/.kbool/config (a C:\\ value as written) [U6, U29]" $?

uf_run 'export HOME=; set -x; source "$FX/kbool.sh"; set +x; echo "r=$?"'
[[ "$UF_OUT" == *"r=0" && "$UF_OUT" != *".kbool/config"* ]]
uf_check "HOME empty and USERPROFILE unset: no user config path is probed at all (never /.kbool) [C16]" $?

cfg_clean
uf_cfg "$F/etc/kbool/config" 'defines = ETCDEF'
uf_cfg "$F/pd/kbool/config" 'defines = PDDEF'
uf_cfg "$F/pd2/kbool/config" 'defines = WRONG'
uf_win "$F/pd"; WPD=$UF_WIN
uf_run "export ProgramData='$WPD' PROGRAMDATA=\"\$FX/pd2\"; source \"\$FX/kbool.sh\"; kk.config defines; echo \"d=\$RESULT\""
[[ "$UF_OUT" == "d=ETCDEF" ]]
uf_check "system level: /etc/kbool/config is read, \$ProgramData/kbool/config is NOT when /etc has one (first found) [U30]" $?

rm -f "$F/etc/kbool/config"
uf_run "export ProgramData='$WPD' PROGRAMDATA=\"\$FX/pd2\"; source \"\$FX/kbool.sh\"; kk.config defines; echo \"d=\$RESULT\""
[[ "$UF_OUT" == "d=PDDEF" ]]
uf_check "system level: no /etc/kbool/config -> \$ProgramData/kbool/config; \$PROGRAMDATA is never read [U30, C16]" $?

uf_run "export PROGRAMDATA=\"\$FX/pd2\"; source \"\$FX/kbool.sh\"; kk.config defines; echo \"d=[\$RESULT] r=\$?\""
[[ "$UF_OUT" == "d=[] r=1" ]]
uf_check "system level: ProgramData unset -> nothing read (no root-relative /kbool/config probe) [C16]" $?

# precedence: scalars — the strongest level that sets the key wins;
# lists — stronger levels' entries first, then weaker ones
cfg_clean
uf_cfg "$F/etc/kbool/config" 'ckkdir = sys' 'debug = quiet' 'unitpath = s1' 'defines = S'
uf_cfg "$F/home/.kbool/config" 'ckkdir = usr' 'unitpath = u1' 'defines = U S'
uf_cfg "$F/p/a/project.conf" 'ckkdir = prj' 'unitpath = p1' 'defines = P' 'debug = debug'
uf_cfg "$F/c/e.conf" 'unitpath = e1' 'defines = E'
uf_run 'source "$FX/kbool.sh"; source "$FX/show.sh"; kk.project "$FX/p/a/project.conf"; echo "p=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "debug=quiet:0 ckk=$F/home/.kbool/usr:0 up=$F/home/.kbool/u1,$F/etc/kbool/s1:0 def=U,S:0 vk=quiet pp=$F/home/.kbool/u1,$F/etc/kbool/s1,"$'\n'"p=0"$'\n'"debug=debug:0 ckk=$F/p/a/prj:0 up=$F/p/a/p1,$F/home/.kbool/u1,$F/etc/kbool/s1:0 def=P,U,S:0 vk=debug pp=$F/p/a/p1,$F/home/.kbool/u1,$F/etc/kbool/s1," ]]
uf_check "precedence: user over system at load; project over user after kk.project; lists stronger-first, defines merged without duplicates [U5]" $?

uf_cfg "$F/c/e.conf" 'unitpath = e1' 'defines = E' 'ckkdir = env'
uf_run 'export KBOOL_CONFIG="$FX/c/e.conf"; source "$FX/kbool.sh"; source "$FX/show.sh"; kk.project "$FX/p/a/project.conf"; source "$FX/show.sh"'
[[ "$UF_OUT" == "debug=quiet:0 ckk=$F/c/env:0 up=$F/c/e1,$F/home/.kbool/u1,$F/etc/kbool/s1:0 def=E,U,S:0 vk=quiet pp=$F/c/e1,$F/home/.kbool/u1,$F/etc/kbool/s1,"$'\n'"debug=debug:0 ckk=$F/c/env:0 up=$F/c/e1,$F/p/a/p1,$F/home/.kbool/u1,$F/etc/kbool/s1:0 def=E,P,U,S:0 vk=debug pp=$F/c/e1,$F/p/a/p1,$F/home/.kbool/u1,$F/etc/kbool/s1," ]]
uf_check "precedence: KBOOL_CONFIG is the strongest level, also over the project [U5, U38]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses klib; echo "${__KK_UNIT_SYSPATH[*]}"'
[[ "$UF_OUT" == "$F/kkore $F/kklass $F/kcl/*" ]]
uf_check "the built-in system paths stay after every config level (config unitpath feeds the project path list only) [U4, U14]" $?

# ---------------------------------------------------------------------------
# U38: KBOOL_HOME = where the loaded kbool lives; a preset elsewhere -> one WARNING
cfg_clean
uf_run 'export KBOOL_HOME=/elsewhere; source "$FX/kbool.sh"; echo "r=$? home=$KBOOL_HOME"'
[[ "$UF_OUT" == "kbool: WARNING: KBOOL_HOME=/elsewhere is ignored: kbool is loaded from $F"$'\n'"r=0 home=$F" ]]
uf_check "a preset KBOOL_HOME naming another folder: one WARNING, KBOOL_HOME = kbool.sh's folder [U38]" $?

uf_run 'export KBOOL_HOME="$FX/kcl/.."; source "$FX/kbool.sh"; echo "r=$? home=$KBOOL_HOME"; export KBOOL_HOME=; source "$FX/kbool.sh"; echo ok'
[[ "$UF_OUT" == "r=0 home=$F"$'\n'"ok" ]]
uf_check "a preset KBOOL_HOME naming the same folder in another spelling: silent [U38]" $?

uf_run 'export KBOOL_HOME=; source "$FX/kbool.sh"; echo "r=$? home=$KBOOL_HOME"'
[[ "$UF_OUT" == "r=0 home=$F" ]]
uf_check "an empty preset KBOOL_HOME is silent [U38]" $?

uf_run 'export VERBOSE_KKLASS=quiet KBOOL_HOME=/elsewhere; source "$FX/kbool.sh"; echo "r=$? home=$KBOOL_HOME"'
[[ "$UF_OUT" == "r=0 home=$F" ]]
uf_check "VERBOSE_KKLASS=quiet silences the U38 WARNING" $?

# ---------------------------------------------------------------------------
# kk.project PATH|NAME (U8, U9, U37, U2')
cfg_clean
uf_cfg "$F/p/a/project.conf" 'unitpath = lib' 'ckkdir = .ckk' 'defines = PROJ' 'debug = debug'
uf_user "$F/p/a/lib/pu.sh" pu 'PU_LOADS=$(( ${PU_LOADS:-0} + 1 ))'
uf_run 'source "$FX/kbool.sh"; kk.defined PROJ; d0=$?; kk.project "$FX/p/a/project.conf"; echo "p=$? d0=$d0"; kk.uses pu; echo "u=$? L=$PU_LOADS"; kk.defined PROJ; echo "d=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "p=0 d0=1"$'\n'"u=0 L=1"$'\n'"d=0"$'\n'"debug=debug:0 ckk=$F/p/a/.ckk:0 up=$F/p/a/lib:0 def=PROJ:0 vk=debug pp=$F/p/a/lib," ]]
uf_check "kk.project PATH: unit paths and ckkdir relative to the project file; kk.uses finds project units; defines; debug level applied [U8, U9, U11]" $?

cfg_clean
uf_cfg "$F/home/.kbool/myproj/project.conf" 'unitpath = lib' 'defines = MYPROJ'
uf_user "$F/home/.kbool/myproj/lib/pn.sh" pn 'PN_LOADS=1'
uf_cfg "$F/w/.kbool/wproj/project.conf" 'unitpath = lib'
uf_user "$F/w/.kbool/wproj/lib/wn.sh" wn 'WN_LOADS=1'
uf_win "$F/w"; WUP=$UF_WIN
uf_run 'source "$FX/kbool.sh"; kk.project myproj; echo "p=$?"; kk.uses pn; echo "u=$? L=$PN_LOADS"; kk.defined MYPROJ; echo "d=$?"'
[[ "$UF_OUT" == "p=0"$'\n'"u=0 L=1"$'\n'"d=0" ]]
uf_check "kk.project NAME -> ~/.kbool/NAME/project.conf [U8]" $?

uf_run "export USERPROFILE='$WUP'; source \"\$FX/kbool.sh\"; kk.project wproj; echo \"p=\$?\"; kk.uses wn; echo \"u=\$? L=\$WN_LOADS\"; kk.config unitpath; echo \"\$RESULT\""
[[ "$UF_OUT" == "p=0"$'\n'"u=0 L=1"$'\n'"C:/${F:3}/w/.kbool/wproj/lib" ]]
uf_check "kk.project NAME: not under ~ -> \$USERPROFILE/.kbool/NAME/project.conf (C:\\ folder, relative paths join it) [U6, U29]" $?

uf_run "export USERPROFILE='$WUP'; source \"\$FX/kbool.sh\"; kk.project nosuch; echo \"p=\$?\"; kk.project myproj; echo \"p2=\$?\""
[[ "$UF_OUT" == *"nosuch"*"$F/home/.kbool/nosuch/project.conf"*"$WUP"*$'\n'"p=2"$'\n'"p2=0" ]]
uf_check "kk.project NAME not found: rc 2 naming the places searched; nothing set, a retry works" $?

uf_run 'source "$FX/kbool.sh"; kk.project "$FX/p/none.conf"; echo "p=$?"; kk.project; echo "p0=$?"; kk.project a b; echo "p2=$?"; kk.project ..; echo "pdd=$?"; kk.project "$FX/p"; echo "pdir=$?"; echo "proj=[$__KK_PROJECT]"; source "$FX/show.sh"'
[[ "$UF_OUT" == *"p=2"*"p0=2"*"p2=2"*"pdd=2"*"pdir=2"$'\n'"proj=[]"$'\n'"debug=:1 ckk=:1 up=:1 def=:1 vk=unset pp=" ]]
uf_check "kk.project: a missing file, no argument, two arguments, '..', a folder -> rc 2" $?

cfg_clean
uf_cfg "$F/p/a/project.conf" 'unitpath = lib' 'defines = PROJ'
uf_user "$F/p/a/lib/pu.sh" pu 'PU_LOADS=$(( ${PU_LOADS:-0} + 1 ))'
uf_cfg "$F/p/b/project.conf" 'defines = B'
uf_run 'source "$FX/kbool.sh"; kk.uses a; kk.project "$FX/p/a/project.conf"; echo "p=$? L=${PU_LOADS:-0}"; kk.defined PROJ; echo "d=$?"'
[[ "$UF_OUT" == *"kk.project"*"'a'"*$'\n'"p=2 L=0"$'\n'"d=1" ]]
uf_check "kk.project after a kk.uses of a non-system unit -> rc 2 naming it, no project applied [U37]" $?

uf_run 'source "$FX/kbool.sh"; source "$FX/kcl/a/a.sh"; kk.project "$FX/p/a/project.conf"; echo "p=$? proj=[$__KK_PROJECT]"; source "$FX/show.sh"'
[[ "$UF_OUT" == *"'a'"*$'\n'"p=2 proj=[]"$'\n'"debug=:1 ckk=:1 up=:1 def=:1 vk=unset pp=" ]]
uf_check "kk.project after a PLAIN-sourced unit -> rc 2 (it could have read the defines already) [U37]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses nosuchunit 2>/dev/null; kk.project "$FX/p/a/project.conf" 2>/dev/null; echo "p=$? proj=[$__KK_PROJECT]"; source "$FX/show.sh"'
[[ "$UF_OUT" == "p=2 proj=[]"$'\n'"debug=:1 ckk=:1 up=:1 def=:1 vk=unset pp=" ]]
uf_check "kk.project after a FAILED kk.uses of a non-system name -> rc 2 [U37]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses klib kerr kvar kcfg kuse; kk.project "$FX/p/a/project.conf"; echo "p=$?"; kk.uses pu; echo "u=$? L=$PU_LOADS"'
[[ "$UF_OUT" == "p=0"$'\n'"u=0 L=1" ]]
uf_check "kk.uses of system units before kk.project is allowed [U37]" $?

uf_run 'source "$FX/kbool.sh"; kk.project "$FX/p/a/project.conf"; kk.project "$FX/p/b/project.conf"; echo "p=$?"; kk.defined B; echo "B=$?"'
[[ "$UF_OUT" == *"$F/p/a/project.conf"*$'\n'"p=2"$'\n'"B=1" ]]
uf_check "a second kk.project with ANOTHER file -> rc 2 naming the project already set, nothing applied [U37, R9c]" $?

uf_run 'source "$FX/kbool.sh"; kk.project "$FX/p/a/project.conf"; kk.uses pu; kk.project "$FX/p/a/project.conf"; echo "same=$?"; cd "$FX/p"; kk.project ./a/../a/project.conf; echo "spelled=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "same=0"$'\n'"spelled=0"$'\n'"debug=:1 ckk=:1 up=$F/p/a/lib:0 def=PROJ:0 vk=unset pp=$F/p/a/lib," ]]
uf_check "a second kk.project with the SAME file (any spelling, -ef), even after a unit was used -> rc 0 no-op, like kk.uses [R9c, owner]" $?

uf_run 'source "$FX/kbool.sh"; kk.uses klib; kk._unit_find pu "$PWD"; echo "f=$? ok=$__KK_UNIT_IDX_OK"; kk.project "$FX/p/a/project.conf"; echo "ok=$__KK_UNIT_IDX_OK res=${#__KK_UNIT_RES[@]} hit=${#__KK_UNIT_HIT[@]}"; kk.uses pu; echo "u=$? L=$PU_LOADS"'
[[ "$UF_OUT" == "f=1 ok=1"$'\n'"ok=0 res=0 hit=0"$'\n'"u=0 L=1" ]]
uf_check "kk.project invalidates the name index and the resolution caches: a name missed before is found after [P6, U16]" $?

uf_cfg "$F/p/c/proj.conf" 'unitpath = lib'
uf_user "$F/p/c/lib/pc.sh" pc 'PC_LOADS=1'
printf '%s\n' 'source "$FX/kbool.sh" || exit 9' 'kk.project proj.conf; echo "p1=$?"' 'kk.uses pc; echo "u=$? L=$PC_LOADS"' > "$F/p/c/main.sh"
printf '%s\n' 'source "$FX/kbool.sh" || exit 9' 'kk.project ./c/proj.conf; echo "p2=$?"' > "$F/p/main2.sh"
uf_run 'export FX; cd /; "$BASH" "$FX/p/c/main.sh"; "$BASH" "$FX/p/main2.sh"'
[[ "$UF_OUT" == "p1=0"$'\n'"u=0 L=1"$'\n'"p2=0" ]]
uf_check "kk.project with a relative path (incl. a no-slash NAME.conf) is relative to the CALLING file's folder, like kk.uses [U12]" $?

# debug level: the config writes VERBOSE_KKLASS only when nobody else set it
cfg_clean
uf_cfg "$F/home/.kbool/config" 'debug = quiet'
uf_cfg "$F/p/a/project.conf" 'debug = debug'
uf_cfg "$F/p/d/project.conf" 'debug = default'
uf_run 'source "$FX/kbool.sh"; echo "v0=${VERBOSE_KKLASS-unset}"; kk.project "$FX/p/a/project.conf"; echo "v1=${VERBOSE_KKLASS-unset}"'
[[ "$UF_OUT" == "v0=quiet"$'\n'"v1=debug" ]]
uf_check "debug level: the user config's level applies at load, the project's on kk.project [U11]" $?

uf_run 'source "$FX/kbool.sh"; kk.project "$FX/p/d/project.conf"; echo "v=${VERBOSE_KKLASS-unset}"'
[[ "$UF_OUT" == "v=unset" ]]
uf_check "debug = default in the project undoes the user config's level (VERBOSE_KKLASS unset again)" $?

uf_run 'export VERBOSE_KKLASS=; source "$FX/kbool.sh"; kk.project "$FX/p/a/project.conf"; echo "v=[${VERBOSE_KKLASS-unset}]"'
[[ "$UF_OUT" == "v=[]" ]]
uf_check "debug level: a VERBOSE_KKLASS preset in the environment (even empty) is never overwritten" $?

uf_run 'source "$FX/kbool.sh"; VERBOSE_KKLASS=debug; kk.project "$FX/p/d/project.conf"; echo "v=${VERBOSE_KKLASS-unset}"'
[[ "$UF_OUT" == "v=debug" ]]
uf_check "debug level: VERBOSE_KKLASS set by the script after the load is never overwritten" $?

cfg_clean
uf_cfg "$F/p/a/project.conf" 'unitpath = lib' 'bogus line' 'colour = red'
uf_run 'source "$FX/kbool.sh"; kk.project "$FX/p/a/project.conf"; echo "p=$?"'
[[ "$UF_OUT" == "kbool: WARNING: $F/p/a/project.conf:2: not a 'key = value' line; ignored"$'\n'"kbool: WARNING: $F/p/a/project.conf:3: unknown key 'colour'; ignored"$'\n'"p=0" ]]
uf_check "kk.project: malformed / unknown lines in the project file -> WARNING with file:line, rc 0" $?

# shell state: set -eu, nocasematch, a caller's set -f / globbing
cfg_clean
uf_cfg "$F/home/.kbool/config" 'UNITPATH = up' 'defines = Lower' 'unitpath = u*'
uf_cfg "$F/p/a/project.conf" 'unitpath = lib' 'defines = PROJ'
uf_user "$F/p/a/lib/pu.sh" pu 'PU_LOADS=1'
uf_run 'set -eu; shopt -s nocasematch; source "$FX/kbool.sh"; kk.project "$FX/p/a/project.conf"; kk.uses pu; kk.config ckkdir || echo "ck=$?"; kk.defined LOWER || echo "LOWER=$?"; kk.defined PROJ; kk.config unitpath; echo "${RESULT//$'"'"'\n'"'"'/,}"; shopt -q nocasematch && echo nc-on; echo end'
[[ "$UF_OUT" == "kbool: WARNING: $F/home/.kbool/config:1: unknown key 'UNITPATH'; ignored"$'\n'"ck=1"$'\n'"LOWER=1"$'\n'"$F/p/a/lib,$F/home/.kbool/u*"$'\n'"nc-on"$'\n'"end" ]]
uf_check "set -eu + nocasematch: keys and defines stay case-sensitive, the caller's nocasematch is back, no abort; '*' in a value is data [§1.4]" $?

uf_cfg "$F/home/.kbool/config" 'unitpath = u*' 'defines = A B'
uf_run 'source "$FX/kbool.sh"; [[ $- == *f* ]] || echo f-off; x=("$FX"/kbool.s?); echo "glob=${#x[@]}"; kk.config defines; echo "${RESULT//$'"'"'\n'"'"'/,}"'
[[ "$UF_OUT" == "f-off"$'\n'"glob=1"$'\n'"A,B" ]]
uf_check "the config read's set -f (no globbing of '*' values) does not leak to the caller" $?

uf_run 'set -f; source "$FX/kbool.sh"; [[ $- == *f* ]] && echo f-kept'
[[ "$UF_OUT" == "f-kept" ]]
uf_check "a caller's own set -f survives the config read" $?

cfg_clean
uf_cfg "$F/c/1/kb.conf" 'unitpath = lib' 'ckkdir = ../ck'
uf_run 'cd "$FX/c/1"; export KBOOL_CONFIG=kb.conf; source "$FX/kbool.sh"; cd /; kk.config unitpath; echo "$RESULT"; kk.config ckkdir; echo "$RESULT"'
[[ "$UF_OUT" == "$F/c/1/lib"$'\n'"$F/c/ck" ]]
uf_check "a relative KBOOL_CONFIG is taken from \$PWD at load; its relative paths are absolute afterwards" $?

# ---------------------------------------------------------------------------
# kk.config KEY [OUTVAR] (kcl §1.1, §1.2, §1.7)
cfg_clean
uf_cfg "$F/c/k.conf" 'unitpath = l1' 'unitpath = l 2' 'ckkdir = /ck'
uf_run 'export KBOOL_CONFIG="$FX/c/k.conf"; source "$FX/kbool.sh"
declare -a arr=(old); kk.config unitpath arr; echo "1 r=$? R=$RESULT n=${#arr[@]} [${arr[0]}] [${arr[1]}]"
declare -a de=(old); kk.config defines de; echo "2 r=$? R=[$RESULT] n=${#de[@]}"
kk.config ckkdir arr; echo "3 r=$?"
kk.config unitpath 1bad; echo "4 r=$?"; kk.config unitpath __kk_x; echo "5 r=$?"; kk.config unitpath RESULT; echo "6 r=$?"
kk.config nosuchkey; echo "7 r=$? R=[$RESULT]"; kk.config; echo "8 r=$?"
x=$(kk.config ckkdir); echo "9 [$x]"; y=$(kk.config unitpath); echo "10 [${y//$'"'"'\n'"'"'/|}]"
kk.config debug; echo "11 r=$? R=[$RESULT]"
declare -A h=([k]=v); kk.config unitpath h; echo "12 r=$? h=${h[k]-gone}"
declare -ra ro=(x); kk.config unitpath ro; echo "13 r=$? ro=${ro[0]}"
shopt -s nocasematch; kk.config DEBUG; echo "14 r=$?"; kk.config CKKDIR; echo "15 r=$?"; shopt -q nocasematch && echo "16 nc-on"; shopt -u nocasematch
kk.defined A B; echo "17 r=$?"'
[[ "$UF_OUT" == "1 r=0 R=2 n=2 [$F/c/l1] [$F/c/l 2]"$'\n'"2 r=1 R=[] n=0"$'\n'"3 r=2"$'\n'"4 r=2"$'\n'"5 r=2"$'\n'"6 r=2"$'\n'"7 r=2 R=[]"$'\n'"8 r=2"$'\n'"9 [/ck]"$'\n'"10 [$F/c/l1|$F/c/l 2]"$'\n'"11 r=1 R=[]"$'\n'"12 r=2 h=v"$'\n'"13 r=2 ro=x"$'\n'"14 r=2"$'\n'"15 r=2"$'\n'"16 nc-on"$'\n'"17 r=2" ]]
uf_check "kk.config: OUTVAR array + count; empty list rc 1; OUTVAR on a scalar, a bad / reserved / assoc / readonly OUTVAR, an unknown or no key (also under nocasematch), kk.defined with two names -> rc 2, silent; \$( ) prints; unset scalar rc 1 [§1.1, §1.6, §1.7, R8]" $?

# ---------------------------------------------------------------------------
# R14 probes for the new entry points: a set -a child and an export -f child
# (functions inherited, assoc tables not) and injection-shaped arguments
cfg_clean
uf_cfg "$F/p/a/project.conf" 'unitpath = lib' 'ckkdir = ck' 'defines = PROJ'
uf_user "$F/p/a/lib/pu.sh" pu 'PU_LOADS=$(( ${PU_LOADS:-0} + 1 ))'
mkdir -p "$F/cwd"; rm -f "$F/cwd/PWN"
CHILD='kk.config "x[\$(touch PWN)]"; echo c=$?; kk.defined "y[\$(touch PWN)]"; echo d=$?; kk.project "$FX/p/a/project.conf"; echo p=$?; kk.uses pu; echo u=$? L=$PU_LOADS; kk.config ckkdir; echo "ck=$RESULT"; kk.defined PROJ; echo d2=$?; kk.config "x[\$(touch PWN)]" 2>/dev/null; echo c2=$?'
uf_run "export FX; cd \"\$FX/cwd\"; set -a; source \"\$FX/kbool.sh\"; set +a; \"\$BASH\" -c '$CHILD'"
[[ "$UF_OUT" == *"c=2"$'\n'*"d=2"$'\n'"p=0"$'\n'"u=0 L=1"$'\n'"ck=$F/p/a/ck"$'\n'"d2=0"$'\n'"c2=2" && "$UF_OUT" != *"syntax error"* && "$UF_OUT" != *"operand"* && ! -e "$F/cwd/PWN" ]]
uf_check "set -a parent, exec'd child: kk.config / kk.defined refuse (rc 2) without evaluating the key, kk.project bootstraps and works [R14]" $?

rm -f "$F/cwd/PWN"
uf_run "export FX; cd \"\$FX/cwd\"; source \"\$FX/kbool.sh\"; export -f \$(compgen -A function); \"\$BASH\" -c '$CHILD'"
[[ "$UF_OUT" == *"c=2"$'\n'*"d=2"$'\n'"p=0"$'\n'"u=0 L=1"$'\n'"ck=$F/p/a/ck"$'\n'"d2=0"$'\n'"c2=2" && "$UF_OUT" != *"syntax error"* && "$UF_OUT" != *"operand"* && ! -e "$F/cwd/PWN" ]]
uf_check "every function exported (no set -a): the same — no table subscripted before the ownership check [R14]" $?

# every internal function that subscripts a table, called DIRECTLY in a
# registry-less child (both ways a child inherits the functions), with
# hostile arguments and level-named env variables holding $( )
INTERNALS='H="x[\$(touch PWN)]"; export user="a[\$(touch PWN)]" env="b[\$(touch PWN)]" system=c project=d
kk._cfg_merge; printf "m=%s " $?; kk._cfg_apply; printf "a=%s " $?; kk._cfg_read "$FX/p/a/project.conf" "$H"; printf "r=%s " $?; kk._cfg_boot; printf "b=%s " $?
kk._unit_register "$H" /f; printf "reg=%s " $?; kk._unit_check "$H" 3; printf "chk=%s " $?; kk._unit_taint 0; printf "tnt=%s " $?
kk._unit_drop "$H"; printf "drp=%s " $?; kk._unit_find "$H" /c/x; printf "fnd=%s " $?; kk._unit_forget "$H"; printf "fgt=%s " $?
kk._unit_index_build; printf "idx=%s " $?; source "$FX/inj/x[\$(touch PWN)].sh"; echo'
mkdir -p "$F/inj"; printf '%s\n' 'kk._unit_taint 0; printf "stem=%s" $?' > "$F/inj/x[\$(touch PWN)].sh"
for mode in 'source "$FX/kbool.sh"; export -f $(compgen -A function)' 'set -a; source "$FX/kbool.sh"; set +a'; do
    rm -f "$F/cwd/PWN"
    printf '%s\n' "$INTERNALS" > "$F/internals.sh"
    uf_run "export FX; cd \"\$FX/cwd\"; $mode; unset KBOOL_HOME; \"\$BASH\" \"\$FX/internals.sh\""
    [[ "$UF_OUT" == "m=2 a=2 r=2 b=2 reg=2 chk=2 tnt=2 drp=2 fnd=2 fgt=2 idx=2 stem=2" && ! -e "$F/cwd/PWN" ]]
    uf_check "internal kk._cfg_* and kk._unit_* functions in a registry-less child (${mode#*; }): rc 2 before any subscript, nothing evaluated (also a file named 'x[\$(touch PWN)].sh') [R14, R2]" $?
done

rm -f "$F/cwd/PWN"
uf_run 'cd "$FX/cwd"; source "$FX/kbool.sh"; kk.project "z[\$(touch PWN)]"; echo "p=$?"; kk.config "x[\$(touch PWN)]"; echo "c=$?"; kk.config unitpath "a[\$(touch PWN)]"; echo "o=$?"'
[[ "$UF_OUT" == *"p=2"$'\n'"c=2"$'\n'"o=2" && ! -e "$F/cwd/PWN" ]]
uf_check "injection-shaped kk.project NAME / kk.config KEY / OUTVAR in the normal shell: rc 2, nothing executed [R14]" $?
rm -f "$F/cwd/PWN"

# ---------------------------------------------------------------------------
# U1b review round 1 (R3-R5, R7, R9, R10)

# R3: encodings
cfg_clean
mkdir -p "$F/c"
printf '\xEF\xBB\xBFdefines = BOMDEF\nunitpath = lib\n' > "$F/c/bom.conf"
uf_run 'export KBOOL_CONFIG="$FX/c/bom.conf"; source "$FX/kbool.sh"; echo "r=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "r=0"$'\n'"debug=:1 ckk=:1 up=$F/c/lib:0 def=BOMDEF:0 vk=unset pp=$F/c/lib," ]]
uf_check "a UTF-8 BOM before the first key is skipped [R3]" $?

printf '\xFF\xFEd\0e\0f\0i\0n\0e\0s\0 \0=\0 \0A\0\r\0\n\0' > "$F/c/u16le.conf"
printf '\xFE\xFF\0d\0e\0f\0i\0n\0e\0s\0 \0=\0 \0A\0\n' > "$F/c/u16be.conf"
printf 'defines = A\0B\nunitpath = x\n' > "$F/c/nul.conf"
for f in u16le u16be nul; do
    uf_run "export KBOOL_CONFIG=\"\$FX/c/$f.conf\"; source \"\$FX/kbool.sh\"; echo \"r=\$?\"; source \"\$FX/show.sh\""
    [[ "$UF_OUT" == "kbool: WARNING: $F/c/$f.conf: UTF-16 or binary content (a NUL byte) is not supported - save it as UTF-8; the file is ignored"$'\n'"r=0"$'\n'"debug=:1 ckk=:1 up=:1 def=:1 vk=unset pp=" ]]
    uf_check "a $f file: ONE clear WARNING, the whole file ignored (no garbled keys, no silently joined values) [R3]" $?
done

printf 'defines = A\rdefines = B\runitpath = lib\r' > "$F/c/cronly.conf"
uf_run 'export KBOOL_CONFIG="$FX/c/cronly.conf"; source "$FX/kbool.sh"; echo "r=$?"; kk.config defines; echo "d=[$RESULT]"'
[[ "$UF_OUT" == "kbool: WARNING: $F/c/cronly.conf: CR-only line ends are not supported - save it with LF or CRLF line ends; the file is ignored"$'\n'"r=0"$'\n'"d=[]" ]]
uf_check "a file with CR but no LF line ends: one WARNING, ignored [R3]" $?

: > "$F/c/empty.conf"
printf '\r\n\r\n' > "$F/c/crlfonly.conf"
uf_run 'export KBOOL_CONFIG="$FX/c/empty.conf"; source "$FX/kbool.sh"; echo "r=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "r=0"$'\n'"debug=:1 ckk=:1 up=:1 def=:1 vk=unset pp=" ]]
uf_check "an EMPTY KBOOL_CONFIG file: rc 0, silent, nothing applied [R10]" $?
uf_run 'export KBOOL_CONFIG="$FX/c/crlfonly.conf"; source "$FX/kbool.sh"; echo "r=$?"; source "$FX/show.sh"'
[[ "$UF_OUT" == "r=0"$'\n'"debug=:1 ckk=:1 up=:1 def=:1 vk=unset pp=" ]]
uf_check "a KBOOL_CONFIG of blank CRLF lines only: rc 0, silent, nothing applied [R10]" $?

uf_cfg "$F/c/utf.conf" 'defines = café' 'defines = OK Été'
for loc in C.UTF-8 en_US.UTF-8; do
    uf_run "export LC_ALL=$loc KBOOL_CONFIG=\"\$FX/c/utf.conf\"; source \"\$FX/kbool.sh\"; kk.config defines; echo \"d=\$RESULT\""
    [[ "$UF_OUT" == "kbool: WARNING: $F/c/utf.conf:1: not a define name, ignored: 'café'"$'\n'"kbool: WARNING: $F/c/utf.conf:2: not a define name, ignored: 'Été'"$'\n'"d=OK" ]]
    uf_check "a non-ASCII define is not a name under $loc (locale ranges cannot widen [A-Za-z]) [R3, kcl 1.6]" $?
done

# R4: limits — a line over 4096 characters, a file over 64 KiB
{ printf 'defines = A\n'; printf 'defines = %4100s\n' X; printf 'defines = C\n'; } > "$F/c/longline.conf"
uf_run 'export KBOOL_CONFIG="$FX/c/longline.conf"; source "$FX/kbool.sh"; echo "r=$?"; kk.config defines; echo "${RESULT//$'"'"'\n'"'"'/,}"'
[[ "$UF_OUT" == "kbool: WARNING: $F/c/longline.conf:2: longer than 4096 characters; ignored"$'\n'"r=0"$'\n'"A,C" ]]
uf_check "a line longer than 4096 characters: WARNING with file:line, skipped; the lines around it apply [R4]" $?

{ printf 'defines = FIRST\n'; for (( i = 0; i < 1100; i++ )); do printf '# %060d\n' "$i"; done; printf 'defines = LATE\n'; } > "$F/c/big.conf"
uf_run 'export KBOOL_CONFIG="$FX/c/big.conf"; source "$FX/kbool.sh"; echo "r=$?"; kk.defined FIRST; echo "first=$?"; kk.defined LATE; echo "late=$?"'
[[ "$UF_OUT" == "kbool: WARNING: $F/c/big.conf: longer than 64 KiB; the rest is ignored"$'\n'"r=0"$'\n'"first=0"$'\n'"late=1" ]]
uf_check "a file over 64 KiB: WARNING, read up to the limit (the cut last line dropped) [R4]" $?

# R5: a relative KBOOL_CONFIG is made absolute for children started elsewhere
cfg_clean
mkdir -p "$F/c/sub"
uf_cfg "$F/c/rel.conf" 'defines = REL'
uf_run 'cd "$FX/c"; export KBOOL_CONFIG=rel.conf; source "$FX/kbool.sh"; echo "parent=$? cfg=$KBOOL_CONFIG"; cd sub; "$BASH" -c "source \"\$FX/kbool.sh\"; echo child=\$?; kk.defined REL; echo rel=\$?"'
[[ "$UF_OUT" == "parent=0 cfg=$F/c/rel.conf"$'\n'"child=0"$'\n'"rel=0" ]]
uf_check "a relative KBOOL_CONFIG: exported absolute after the read; a child in another folder loads it (rc 0) [R5]" $?

# R7a: under set -a the config-written VERBOSE_KKLASS is not exported
cfg_clean
uf_cfg "$F/home/.kbool/config" 'debug = quiet'
uf_cfg "$F/p/a/project.conf" 'debug = debug'
uf_run 'set -a; source "$FX/kbool.sh"; set +a; echo "parent=$VERBOSE_KKLASS"; "$BASH" -c "echo env=\${VERBOSE_KKLASS-unset}; source \"\$FX/kbool.sh\"; kk.project \"\$FX/p/a/project.conf\"; echo child=\$VERBOSE_KKLASS"'
[[ "$UF_OUT" == "parent=quiet"$'\n'"env=unset"$'\n'"child=debug" ]]
uf_check "set -a parent: the config-written VERBOSE_KKLASS stays unexported; the child's project level applies [R7]" $?

# R9a: a system unit named by its PATH behaves like its name
cfg_clean
uf_cfg "$F/p/a/project.conf" 'unitpath = lib' 'defines = PROJ'
uf_user "$F/p/a/lib/pu.sh" pu 'PU_LOADS=$(( ${PU_LOADS:-0} + 1 ))'
uf_run 'source "$FX/kbool.sh"; kk.uses "$KBOOL_HOME/kkore/klib.sh" "$FX/kcl/../kkore/kvar.sh"; echo "u=$? files=${#__KK_UNIT_FILES[@]}"; kk.project "$FX/p/a/project.conf"; echo "p=$?"'
[[ "$UF_OUT" == "u=0 files=0"$'\n'"p=0" ]]
uf_check "kk.uses of a system unit by PATH (any spelling): a no-op that leaves kk.project open, like the name [R9a, U37]" $?

# R9b (owner U39): an empty list value cuts the weaker ENVIRONMENT levels, never the project
cfg_clean
uf_cfg "$F/etc/kbool/config" 'unitpath = s1' 'defines = S'
uf_cfg "$F/home/.kbool/config" 'unitpath = u1' 'defines = U'
uf_cfg "$F/c/e.conf" 'unitpath = e0' 'unitpath =' 'unitpath = e1' 'defines =' 'defines = E'
uf_cfg "$F/p/a/project.conf" 'unitpath = p1' 'defines = P'
uf_cfg "$F/p/r/project.conf" 'unitpath = p0' 'unitpath =' 'unitpath = p1' 'defines =' 'defines = R'
uf_run 'export KBOOL_CONFIG="$FX/c/e.conf"; source "$FX/kbool.sh"; source "$FX/show.sh"; kk.project "$FX/p/a/project.conf"; source "$FX/show.sh"'
[[ "$UF_OUT" == "debug=:1 ckk=:1 up=$F/c/e1:0 def=E:0 vk=unset pp=$F/c/e1,"$'\n'"debug=:1 ckk=:1 up=$F/c/e1,$F/p/a/p1:0 def=E,P:0 vk=unset pp=$F/c/e1,$F/p/a/p1," ]]
uf_check "an empty list value in KBOOL_CONFIG cuts user + system and its own earlier lines, but NOT the project's lists [R9b, U39]" $?

uf_run 'source "$FX/kbool.sh"; source "$FX/show.sh"; kk.project "$FX/p/r/project.conf"; source "$FX/show.sh"'
[[ "$UF_OUT" == "debug=:1 ckk=:1 up=$F/home/.kbool/u1,$F/etc/kbool/s1:0 def=U,S:0 vk=unset pp=$F/home/.kbool/u1,$F/etc/kbool/s1,"$'\n'"debug=:1 ckk=:1 up=$F/p/r/p1:0 def=R:0 vk=unset pp=$F/p/r/p1," ]]
uf_check "an empty list value in the PROJECT resets the inherited user + system lists (and its own earlier lines) [R9b, U39]" $?

uf_run 'export KBOOL_CONFIG="$FX/c/e.conf"; source "$FX/kbool.sh"; kk.project "$FX/p/r/project.conf"; source "$FX/show.sh"'
[[ "$UF_OUT" == "debug=:1 ckk=:1 up=$F/c/e1,$F/p/r/p1:0 def=E,R:0 vk=unset pp=$F/c/e1,$F/p/r/p1," ]]
uf_check "a project reset never cuts the stronger KBOOL_CONFIG entries [R9b, U39]" $?

# R10: hostile content, hostile / spaced project folders, trailing backslashes,
# kk.project from a unit's file scope and from a $( ) subshell
cfg_clean
mkdir -p "$F/cwd"; rm -f "$F/cwd/PWN"
uf_cfg "$F/c/hostile.conf" \
    'k$(touch PWN) = 1' \
    'unitpath = lib/$(touch PWN)/`touch PWN`/[x]/@y/*' \
    'ckkdir = /ck/$(touch PWN)`touch PWN`[a]*@' \
    'defines = OK a[$(touch PWN)] `touch PWN` * @x x[1]' \
    'debug = $(touch PWN)'
uf_run 'cd "$FX/cwd"; export KBOOL_CONFIG="$FX/c/hostile.conf"; source "$FX/kbool.sh"; echo "r=$?"; kk.config ckkdir; echo "ck=$RESULT"; kk.config unitpath; echo "up=$RESULT"; kk.config defines; echo "def=$RESULT"; kk.uses nosuch 2>/dev/null; echo "u=$?"'
[[ "$UF_OUT" == "kbool: WARNING: $F/c/hostile.conf:1: unknown key 'k\$(touch PWN)'; ignored"$'\n'"kbool: WARNING: $F/c/hostile.conf:4: not a define name, ignored: 'a[\$(touch' 'PWN)]' '\`touch' 'PWN\`' '*' '@x' 'x[1]'"$'\n'"kbool: WARNING: $F/c/hostile.conf:5: debug '\$(touch PWN)' is not quiet, default or debug; ignored"$'\n'"r=0"$'\n'"ck=/ck/\$(touch PWN)\`touch PWN\`[a]*@"$'\n'"up=$F/c/lib/\$(touch PWN)/\`touch PWN\`/[x]/@y/*"$'\n'"def=OK"$'\n'"u=2" && ! -e "$F/cwd/PWN" ]]
uf_check "hostile config content (\$( ), backticks, [ ], *, @ in keys, values, defines, debug): data only, WARNINGs name it, nothing executed or globbed [R10]" $?

rm -f "$F/cwd/PWN"
HP="$F/p/d[\$(touch PWN)] \`touch PWN\`"
uf_cfg "$HP/project.conf" 'unitpath = lib' 'defines = HOSTILEP'
uf_user "$HP/lib/hu.sh" hu 'HU_LOADS=1'
uf_cfg "$F/p/my proj/project.conf" 'unitpath = my lib' 'ckkdir = .c k'
uf_user "$F/p/my proj/my lib/sp.sh" sp 'SP_LOADS=1'
uf_run 'cd "$FX/cwd"; source "$FX/kbool.sh"; kk.project "$FX/p/d[\$(touch PWN)] \`touch PWN\`/project.conf"; echo "p=$?"; kk.uses hu; echo "u=$? L=$HU_LOADS"; kk.defined HOSTILEP; echo "d=$?"'
[[ "$UF_OUT" == "p=0"$'\n'"u=0 L=1"$'\n'"d=0" && ! -e "$F/cwd/PWN" ]]
uf_check "a project in a folder named 'd[\$(touch PWN)] \`touch PWN\`': applied, its unit found, nothing executed [R10]" $?
uf_run 'source "$FX/kbool.sh"; kk.project "$FX/p/my proj/project.conf"; echo "p=$?"; kk.uses sp; echo "u=$? L=$SP_LOADS"; kk.config ckkdir; echo "$RESULT"'
[[ "$UF_OUT" == "p=0"$'\n'"u=0 L=1"$'\n'"$F/p/my proj/.c k" ]]
uf_check "a project folder and values with spaces [R10]" $?
rm -f "$F/cwd/PWN"

cfg_clean
uf_cfg "$F/w/.kbool/config" 'defines = WINDEF'
uf_cfg "$F/pd/kbool/config" 'defines = PDDEF'
uf_win "$F/w"; WUP=$UF_WIN
uf_win "$F/pd"; WPD=$UF_WIN
uf_run "export USERPROFILE='$WUP\\' ProgramData='$WPD\\'; source \"\$FX/kbool.sh\"; kk.config defines; echo \"d=\${RESULT//\$'\\n'/,}\""
[[ "$UF_OUT" == "d=WINDEF,PDDEF" ]]
uf_check "USERPROFILE and ProgramData with a trailing backslash: both configs found [R10, C16]" $?

cfg_clean
uf_cfg "$F/p/a/project.conf" 'defines = PROJ'
uf_user "$F/p/up/up.sh" up 'kk.project "$FX/p/a/project.conf"; UP_P=$?'
uf_run 'source "$FX/kbool.sh"; kk.uses "$FX/p/up/up.sh"; echo "u=$? UP_P=$UP_P"; kk.defined PROJ; echo "d=$?"'
[[ "$UF_OUT" == *"too late, unit '$F/p/up/up.sh'"*$'\n'"u=0 UP_P=2"$'\n'"d=1" ]]
uf_check "kk.project from a unit's file scope -> rc 2 (the unit itself is in use) [R10, U37]" $?

uf_run 'source "$FX/kbool.sh"; x=$(kk.project "$FX/p/a/project.conf"; echo "in=$?"); echo "$x"; kk.defined PROJ; echo "d0=$?"; kk.project "$FX/p/a/project.conf"; echo "parent=$?"; kk.defined PROJ; echo "d=$?"'
[[ "$UF_OUT" == "in=0"$'\n'"d0=1"$'\n'"parent=0"$'\n'"d=0" ]]
uf_check "kk.project inside \$( ) changes only the subshell; the parent may still call it [R10]" $?

kt_test_log "011_ConfigProject.sh completed"
