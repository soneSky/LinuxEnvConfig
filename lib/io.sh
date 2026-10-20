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
#  📝 模块描述 : 用户交互与输入验证组件
#  📁 文件路径 : lib/io.sh
#  👤 作者信息 : mingy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


# ═══════════════════════════════════════════════════════════════
# 用户交互输入
# ═══════════════════════════════════════════════════════════════

read_password() {
    local prompt="$1"
    local var_name="$2"
    if ! read -r -sp "  ${GREEN}->${NC} ${prompt}: " "${var_name?}"; then
        printf "\n" >&2
        msg_warning "输入流已结束(EOF), 程序安全退出"
        exit 0
    fi
    echo ""
}

confirm() {
    local prompt="${1:-确认执行此操作?}"
    local response

    while true; do
        if ! read -r -p "  [ ${MAGENTA}??${NC} ] ${BOLD}${WHITE}${prompt}${NC} [y/N]: " response; then
            printf "\n" >&2
            msg_warning "输入流已结束(EOF), 程序安全退出"
            exit 0
        fi
        case "$response" in
            [Yy]*|[Yy][Ee][Ss]) return 0 ;;
            [Nn]*|[Nn][Oo]|"") return 1 ;;
            *) msg_warning "请输入 y 或 n" ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════
# 输入格式验证
# ═══════════════════════════════════════════════════════════════

validate_ip() {
    local ip=$1
    local regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'

    if [[ $ip =~ $regex ]]; then
        return 0
    else
        msg_error "请输入正确的IP地址格式"
        return 1
    fi
}

validate_port() {
    local port=$1

    if [[ $port =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]; then
        return 0
    else
        msg_error "请输入有效的端口号(1-65535)"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 部署参数交互
# ═══════════════════════════════════════════════════════════════

prompt_host_ip() {
    local label="${1:-服务}" var_name="${2:-host_ip}" do_validate="${3:-true}"
    local default_ip
    default_ip=$(get_best_ip)
    local input_val
    if ! read -r -p "  ${CYAN}请输入启动${label}的主机地址 [${default_ip}]: ${NC}" input_val; then
        printf "\n" >&2
        msg_warning "输入流已结束(EOF), 程序安全退出"
        exit 0
    fi
    input_val="${input_val:-$default_ip}"
    if [[ "$do_validate" == "true" ]]; then
        validate_ip "$input_val" || return 1
    fi
    printf -v "$var_name" "%s" "$input_val"
}

prompt_host_port() {
    local label="${1:-服务}" default_port="$2" var_name="${3:-host_port}"
    local input_val
    if ! read -r -p "  ${CYAN}请输入${label}映射端口 [${default_port}]: ${NC}" input_val; then
        printf "\n" >&2
        msg_warning "输入流已结束(EOF), 程序安全退出"
        exit 0
    fi
    input_val="${input_val:-$default_port}"
    validate_port "$input_val" || return 1
    printf -v "$var_name" "%s" "$input_val"
}
