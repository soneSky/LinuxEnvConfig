#!/usr/bin/env bash
#
# Copyright 2026 Hunan Yijing Technologies Co., Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  📝 模块描述 : 错误诊断与调试日志组件(必须最先加载)
#  📁 文件路径 : lib/debug.sh
#  👤 作者信息 : mingy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


# ═══════════════════════════════════════════════════════════════
# 配置与状态
# ═══════════════════════════════════════════════════════════════

LEC_LOG_DIR="${LEC_LOG_DIR:-/var/log/lec}"
LEC_DEBUG="${LEC_DEBUG:-0}"
_LEC_MAIN_SCRIPT="${BASH_SOURCE[1]:-${0}}"

_LEC_LAST_ERR_CODE=""
_LEC_LAST_ERR_CMD=""
_LEC_LAST_ERR_LOC=""
_LEC_LAST_ERR_STACK=""
_LEC_FAREWELL_ENABLED=0
_LEC_IN_TRAP=0
declare -ga LEC_TEMP_DIRS=()


# ═══════════════════════════════════════════════════════════════
# 内部工具
# ═══════════════════════════════════════════════════════════════

_lec_now() { date "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown-time"; }

_lec_error_log() {
    mkdir -p "$LEC_LOG_DIR" 2>/dev/null || true
    printf '%s\n' "$1" >> "$LEC_LOG_DIR/error.log" 2>/dev/null || true
}

_lec_rotate_if_needed() {
    local log_file="$LEC_LOG_DIR/error.log"
    [[ -f $log_file ]] || return 0
    local size
    size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
    if [[ $size -gt 1048576 ]]; then
        tail -n 200 "$log_file" > "$log_file.tmp" 2>/dev/null \
            && mv -f "$log_file.tmp" "$log_file" 2>/dev/null || true
    fi
}

_lec_render_stack() {
    local i depth=${#FUNCNAME[@]} start=1 out=""
    while [[ $start -lt $depth && ${FUNCNAME[$start]:-} == _lec_* ]]; do
        start=$((start + 1))
    done
    if [[ $start -ge $depth ]]; then
        printf '    at (顶层脚本) %s' "$1"
        return 0
    fi
    for ((i=start; i<depth; i++)); do
        local func="${FUNCNAME[i]:-?}"
        local src="${BASH_SOURCE[i]:-?}"
        local line="${BASH_LINENO[i-1]:-0}"
        out+="\n    at ${func}() ${src##*/}:${line}"
    done
    printf '%b' "$out"
}


# ═══════════════════════════════════════════════════════════════
# 公共接口
# ═══════════════════════════════════════════════════════════════

lec_register_temp() {
    LEC_TEMP_DIRS+=("$1")
}

lec_enable_farewell() {
    _LEC_FAREWELL_ENABLED=1
}

_lec_cleanup_temp_dirs() {
    [[ ${#LEC_TEMP_DIRS[@]} -gt 0 ]] || return 0
    local d
    for d in "${LEC_TEMP_DIRS[@]}"; do
        rm -rf "$d" 2>/dev/null || true
    done
}

_lec_on_error() {
    [[ $_LEC_IN_TRAP -eq 0 ]] || return 0
    _LEC_IN_TRAP=1
    local code=$1
    local loc stack
    if [[ ${#FUNCNAME[@]} -gt 1 ]]; then
        loc="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]:-0}"
    else
        loc="${_LEC_MAIN_SCRIPT##*/}:${BASH_LINENO[0]:-0}"
    fi
    stack=$(_lec_render_stack "$loc" 2>/dev/null || true)

    _LEC_LAST_ERR_CODE="$code"
    _LEC_LAST_ERR_CMD="${BASH_COMMAND:-unknown}"
    _LEC_LAST_ERR_LOC="$loc"
    _LEC_LAST_ERR_STACK="$stack"

    _lec_rotate_if_needed
    _lec_error_log "[$(_lec_now)] code=$code | 位置:$loc | 栈:${stack//$'\n'/ | } | 命令:${_LEC_LAST_ERR_CMD}"
    _LEC_IN_TRAP=0
    return 0
}

_lec_on_exit() {
    [[ $_LEC_IN_TRAP -eq 0 ]] || return 0
    _LEC_IN_TRAP=1
    trap - EXIT
    local code=$1

    _lec_cleanup_temp_dirs

    if [[ $code -ne 0 ]]; then
        mkdir -p "$LEC_LOG_DIR" 2>/dev/null || true
        if [[ $code == "${_LEC_LAST_ERR_CODE}" && -n "${_LEC_LAST_ERR_LOC}" ]]; then
            {
                printf '════════异常退出现场════════\n'
                printf '时间:%s\n' "$(_lec_now)"
                printf '退出码:%s\n' "$code"
                printf '失败命令:%s\n' "${_LEC_LAST_ERR_CMD}"
                printf '失败位置:%s\n' "${_LEC_LAST_ERR_LOC}"
                printf '调用栈:%s\n' "${_LEC_LAST_ERR_STACK}"
                printf '\n'
            } >> "$LEC_LOG_DIR/error.log" 2>/dev/null || true
            printf '\n  \033[91m✘ 检测到异常退出(码%s),错误现场已写入 %s/error.log\033[0m\n' "$code" "$LEC_LOG_DIR" >&2 || true
            printf '  查看详情:tail -50 %s/error.log\n' "$LEC_LOG_DIR" >&2 || true
            printf '  复现调试:%s --debug\n' "$0" >&2 || true
        elif [[ $code == 130 ]]; then
            _lec_error_log "[$(_lec_now)] 用户中断(Ctrl-C),退出码:$code"
            printf '\n  \033[93m已中断退出,临时资源已清理\033[0m\n' >&2 || true
        else
            _lec_error_log "[$(_lec_now)] 脚本退出,退出码:$code"
        fi
    fi

    if [[ $code -eq 0 && $_LEC_FAREWELL_ENABLED -eq 1 ]] && declare -F show_banner_rich >/dev/null; then
        clear_screen 2>/dev/null || true
        show_banner_rich \
            "👋 感谢使用 $SCRIPT_NAME" \
            "作者: mingy@蚁景科技" \
            "" \
            "https://gitee.com/yijingsec/LinuxEnvConfig" || true
        echo "" || true
    fi
    _LEC_IN_TRAP=0
    return 0
}


# ═══════════════════════════════════════════════════════════════
# 调试模式与trap挂载
# ═══════════════════════════════════════════════════════════════

_lec_start_debug_log() {
    mkdir -p "$LEC_LOG_DIR" 2>/dev/null || return 0
    local log_file
    log_file="$LEC_LOG_DIR/debug-$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$log_file") 2> >(tee -a "$log_file" >&2) || return 0
    {
        printf '════════调试会话════════\n'
        printf '时间:%s\n' "$(_lec_now)"
        printf '版本:%s\n' "${SCRIPT_VERSION:-unknown}"
        printf '参数:%s\n' "${LEC_START_ARGS:-}"
        printf '日志文件:%s\n' "$log_file"
        printf '════════════════════\n'
    } || true
}

if [[ $LEC_DEBUG == 1 ]]; then
    _lec_start_debug_log
fi

set -o errtrace
trap '_lec_on_error $?' ERR
trap '_lec_on_exit $?' EXIT
