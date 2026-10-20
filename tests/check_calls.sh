#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export LEC_LOG_DIR="${LEC_LOG_DIR:-$(mktemp -d)}"
source lib/debug.sh
source lib/common.sh
source lib/core.sh
source lib/io.sh
source lib/utils.sh
source lib/network.sh
source lib/update.sh
source lib/menu.sh
for m in modules/*.sh; do source "$m"; done

allowlist=" _summary_row hex_md5 "

ids="$(grep -hoE '\b[a-z_][a-z0-9_]*_[a-z0-9_]+\b' main.sh install.sh lib/*.sh modules/*.sh | sort -u)"

entry_defs=" $(grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' main.sh install.sh | sed -E 's/[[:space:]]*\(\)$//' | tr '\n' ' ') "

declared_arrays="$(grep -hoE '^declare -[a-zA-Z]+[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' lib/*.sh modules/*.sh main.sh install.sh 2>/dev/null | awk '{print $NF}' | sort -u)"

broken_declares=""
for name in $declared_arrays; do
    if ! declare -p "$name" >/dev/null 2>&1; then
        broken_declares+="$name "
    fi
done

unresolved=""
for id in $ids; do
    [[ "$allowlist" == *" $id "* ]] && continue
    [[ "$entry_defs" == *" $id "* ]] && continue
    if declare -F "$id" >/dev/null 2>&1; then
        continue
    fi
    if command -v "$id" >/dev/null 2>&1; then
        continue
    fi
    if ! grep -qE "(^[[:space:]]*|[;&|]|\$\()[[:space:]]*!?[[:space:]]*${id}([[:space:];|&]|\$)|\b(if|then|else|elif|do)[[:space:]]+!?[[:space:]]*${id}([[:space:];|&]|\$)" \
        main.sh install.sh lib/*.sh modules/*.sh 2>/dev/null; then
        continue
    fi
    if grep -qE "(^|[;&|])[[:space:]]*${id}[[:space:]]*=|^[[:space:]]*${id}[[:space:]]*=" \
        main.sh install.sh lib/*.sh modules/*.sh 2>/dev/null; then
        continue
    fi
    unresolved+="$id "
done

rm -rf "$LEC_LOG_DIR" 2>/dev/null || true

if [[ -n "$unresolved" || -n "$broken_declares" ]]; then
    [[ -n "$unresolved" ]] && echo "未解析的函数调用: $unresolved"
    [[ -n "$broken_declares" ]] && echo "加载后不可见的顶层声明: $broken_declares"
    exit 1
fi
exit 0
