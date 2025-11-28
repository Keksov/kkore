#!/bin/bash

# Associative arrays for caching
declare -gA _KK_script_dir_cache
declare -gA _KK_use_cache
declare -gA _KK_use_cache_mtime

kk.getScriptDir() {
    local source_file="${1:-${BASH_SOURCE[1]:-$0}}"
    
    if [[ -n "${_KK_script_dir_cache[$source_file]}" ]]; then
        echo "${_KK_script_dir_cache[$source_file]}"
        return 0
    fi
    
    local result="$(cd "$(dirname "$source_file")" && pwd)"

    _KK_script_dir_cache[$source_file]="$result"
    echo "$result"
}

kk.use() {
    local force=0
    local check_mtime=0
    local filename=""
    
    # Parsing arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=1
                shift
                ;;
            --check-mtime|-m)
                check_mtime=1
                shift
                ;;
            *)
                filename="$1"
                shift
                ;;
        esac
    done
    
    [[ -z "$filename" ]] && { echo "Error: filename required" >&2; return 2; }
    
    local dir=$(kk.getScriptDir "${BASH_SOURCE[0]}")
    local file="${dir}/${filename}"
    
    [[ -f "$file" ]] || { echo "Error: $file not found" >&2; return 2; }
    
    # Force mode - always load
    if [[ $force -eq 1 ]]; then
        _KK_use_cache[$file]=1
        if [[ $check_mtime -eq 1 ]]; then
            local mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
            _KK_use_cache_mtime[$file]="$mtime"
        fi
        echo "$file"
        return 0
    fi
    
    # Mode with modification time check
    if [[ $check_mtime -eq 1 ]]; then
        local mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
        
        # If file changed - load
        if [[ "${_KK_use_cache_mtime[$file]}" != "$mtime" ]]; then
            _KK_use_cache[$file]=1
            _KK_use_cache_mtime[$file]="$mtime"
            echo "$file"
            return 0
        fi
        
        # File not changed
        return 1
    fi
    
    # Normal mode - check only load fact
    if [[ -n "${_KK_use_cache[$file]}" ]]; then
        return 1  # Already loaded
    fi
    
    # Mark as loaded
    _KK_use_cache[$file]=1
    
    echo "$file"
    return 0
}

kk.clearUseCache() {
    _KK_script_dir_cache=()
    _KK_use_cache=()
    _KK_use_cache_mtime=()
}
