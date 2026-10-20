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
#  📝 模块描述 : 系统实用工具与包/服务管理
#  📁 文件路径 : lib/utils.sh
#  👤 作者信息 : mingy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


# ═══════════════════════════════════════════════════════════════
# 端口占用处理
# ═══════════════════════════════════════════════════════════════

_port_listeners() {
    local port="$1"
    local raw=""

    if command_exists ss; then
        raw=$(ss -lntup "sport = :${port}" 2>/dev/null) || raw=""
        if [[ -n "$raw" ]]; then
            printf '%s\n' "$raw" | grep -oE 'users:\(\("[^"]+",pid=[0-9]+' | sed -E 's/.*\("([^"]+)",pid=([0-9]+)/\2|\1/' | sort -u || true
        fi
    elif command_exists lsof; then
        raw=$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -iUDP:"${port}" 2>/dev/null) || raw=""
        if [[ -n "$raw" ]]; then
            printf '%s\n' "$raw" | awk 'NR>1 {print $2"|"$1}' | sort -u || true
        fi
    fi

    return 0
}

_dns_resolution_ok() {
    local domains=("www.baidu.com" "www.aliyun.com" "mirrors.aliyun.com")
    local domain

    for domain in "${domains[@]}"; do
        if getent hosts "$domain" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

_set_resolved_stub_listener() {
    local conf="$1" dns_server="$2"

    if [[ ! -f "$conf" ]]; then
        msg_warning "未找到${conf}, 跳过配置文件修改"
        return 1
    fi

    backup_file "$conf" ".bak" "resolved" || true

    if grep -qE '^[[:space:]]*DNSStubListener[[:space:]]*=' "$conf"; then
        sed -i -E 's|^[[:space:]]*DNSStubListener[[:space:]]*=.*|DNSStubListener=no|' "$conf"
    else
        printf 'DNSStubListener=no\n' >> "$conf"
    fi

    if ! grep -qE '^[[:space:]]*DNS[[:space:]]*=' "$conf"; then
        if grep -qE '^[[:space:]]*#[[:space:]]*DNS[[:space:]]*=' "$conf"; then
            sed -i -E "s|^[[:space:]]*#[[:space:]]*DNS[[:space:]]*=.*|DNS=${dns_server}|" "$conf"
        else
            printf 'DNS=%s\n' "$dns_server" >> "$conf"
        fi
    fi

    grep -qE '^[[:space:]]*DNSStubListener[[:space:]]*=[[:space:]]*no[[:space:]]*$' "$conf"
}

_resolv_conf_needs_uplink() {
    local resolv="${1:-/etc/resolv.conf}"
    local target=""
    local servers=""
    local s

    if [[ -L "$resolv" ]]; then
        target=$(readlink -f "$resolv" 2>/dev/null) || target=""
        if [[ -z "$target" || "$target" == *stub-resolv.conf || ! -e "$target" ]]; then
            return 0
        fi
        return 1
    fi

    servers=$(awk '$1=="nameserver" {print $2}' "$resolv" 2>/dev/null) || servers=""
    if [[ -z "$servers" ]]; then
        return 0
    fi

    while read -r s; do
        case "$s" in
            127.0.0.53|127.0.0.54) ;;
            *) return 1 ;;
        esac
    done <<< "$servers"

    return 0
}

_point_resolv_conf_to_uplink() {
    local upstream="/run/systemd/resolve/resolv.conf"
    local waited=0

    while [[ $waited -lt 10 && ! -s "$upstream" ]]; do
        sleep 0.5
        waited=$((waited + 1))
    done

    if [[ ! -s "$upstream" ]]; then
        return 1
    fi

    backup_file "/etc/resolv.conf" ".bak" "resolv" || true
    _RESOLV_CONF_BACKUP=$(backup_list "/etc/resolv.conf" | head -n 1)
    if ! ln -sfn "$upstream" /etc/resolv.conf; then
        msg_error "无法创建/etc/resolv.conf软链接(可能被锁定或只读挂载)"
        return 1
    fi

    return 0
}

_release_resolved_stub_listener() {
    local dns_server="$1"
    local unit="systemd-resolved"
    local conf="/etc/systemd/resolved.conf"
    local was_active=false
    local needs_uplink=false

    if is_service_active "$unit"; then
        was_active=true
    fi
    if _resolv_conf_needs_uplink; then
        needs_uplink=true
    fi

    if [[ "$was_active" == "true" ]]; then
        if ! stop_service "$unit"; then
            msg_error "无法停止${unit}, 53端口可能仍被占用"
            return 1
        fi
    fi

    if ! _set_resolved_stub_listener "$conf" "$dns_server"; then
        msg_error "${conf}写入失败, DNS配置未做修改"
        if [[ "$was_active" == "true" ]]; then
            start_service "$unit" || true
        fi
        return 1
    fi
    msg_success "已关闭DNSStubListener"

    if [[ "$was_active" == "true" || "$needs_uplink" == "true" ]]; then
        if ! start_service "$unit"; then
            msg_error "${unit}启动失败, DNS解析可能不可用"
            return 1
        fi
        if [[ "$needs_uplink" == "true" ]] && ! systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            if ! enable_service "$unit"; then
                msg_warning "无法启用${unit}开机自启, 重启后/etc/resolv.conf软链接将失效"
            fi
        else
            msg_info "保留${unit}开机自启, 避免重启后/etc/resolv.conf软链接失效"
        fi
    else
        msg_info "${unit}未运行, 配置将在下次启动时生效"
    fi

    if [[ "$needs_uplink" == "true" ]]; then
        if _point_resolv_conf_to_uplink; then
            msg_success "/etc/resolv.conf已指向上游DNS配置"
        else
            msg_error "上游DNS配置文件未生成, 请手动检查/etc/resolv.conf"
        fi
    else
        msg_info "保留现有/etc/resolv.conf配置"
    fi

    return 0
}

_terminate_port_processes() {
    local lines="$1"
    local pid="" comm=""
    local stubborn=""

    while IFS='|' read -r pid comm; do
        [[ -z "$pid" ]] && continue
        if [[ "$pid" == "1" || "$pid" == "$$" || "$pid" == "$PPID" ]]; then
            msg_warning "跳过关键进程PID ${pid}(${comm})"
            continue
        fi
        if kill -TERM "$pid" 2>/dev/null; then
            msg_info "已发送终止信号PID ${pid}(${comm})"
        else
            msg_warning "终止失败PID ${pid}(${comm})"
        fi
    done <<< "$lines"

    sleep 1

    while IFS='|' read -r pid comm; do
        [[ -z "$pid" ]] && continue
        [[ "$pid" == "1" || "$pid" == "$$" || "$pid" == "$PPID" ]] && continue
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
            stubborn+="PID ${pid}(${comm}) "
        fi
    done <<< "$lines"

    if [[ -n "$stubborn" ]]; then
        msg_warning "已强制终止: ${stubborn}"
    fi

    return 0
}

unlock_dns_port() {
    show_section "解除DNS服务53端口占用"

    local dns_server="${1:-114.114.114.114}"
    local port=53
    local listeners=""
    local resolved_owner=false
    local others=""
    local pid="" comm=""
    local port_free=false

    _RESOLV_CONF_BACKUP=""

    if ! command_exists ss && ! command_exists lsof; then
        msg_warning "缺少ss与lsof工具, 无法检测53端口占用情况"
        msg_info "请先安装检测工具: apt-get install -y iproute2 lsof"
        return 0
    fi

    listeners=$(_port_listeners "$port")

    while IFS='|' read -r pid comm; do
        [[ -z "$pid" ]] && continue
        case "$comm" in
            systemd-resolve|systemd-resolved) resolved_owner=true ;;
            *) others+="${pid}|${comm}"$'\n' ;;
        esac
    done <<< "$listeners"

    if [[ "$resolved_owner" == "true" ]]; then
        msg_warning "检测到systemd-resolved监听53端口(DNSStubListener)"
        if confirm "是否关闭DNSStubListener以释放53端口?"; then
            _release_resolved_stub_listener "$dns_server"
        else
            msg_info "已跳过systemd-resolved配置"
        fi
    fi

    if [[ -n "$others" ]]; then
        msg_warning "以下进程占用53端口:"
        draw_line "-" "${GRAY}"
        while IFS='|' read -r pid comm; do
            [[ -z "$pid" ]] && continue
            msg_star "PID ${pid} / ${comm}"
        done <<< "$others"
        draw_line "-" "${GRAY}"

        if confirm "是否终止上述进程以释放53端口?"; then
            _terminate_port_processes "$others"
        fi
    fi

    if [[ "$resolved_owner" != "true" && -z "$others" ]]; then
        msg_info "53端口未被占用"
    fi

    listeners=$(_port_listeners "$port")
    if [[ -z "$listeners" ]]; then
        msg_success "53端口已释放"
        port_free=true
    else
        msg_warning "53端口仍被占用, 可执行 ss -lntup 'sport = :53' 进一步排查"
    fi

    if _dns_resolution_ok; then
        msg_success "DNS解析正常"
    else
        msg_error "DNS解析异常, 请检查/etc/resolv.conf与systemd-resolved状态"
        msg_info "手工恢复: sed -i 's/^DNSStubListener=no/DNSStubListener=yes/' /etc/systemd/resolved.conf && systemctl restart systemd-resolved"
        if [[ -n "${_RESOLV_CONF_BACKUP:-}" ]]; then
            msg_info "改动前/etc/resolv.conf备份: ${_RESOLV_CONF_BACKUP}"
        fi
    fi

    if [[ "$port_free" == "true" ]]; then
        return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════
# 文件备份工具
# ═══════════════════════════════════════════════════════════════

backup_file() {
    local file="$1"
    local backup_suffix="${2:-.bak}"
    local desc="${3:-}"

    if [[ -f $file ]]; then
        local backup
        if [[ -n $desc ]]; then
            backup="${file}${backup_suffix}.${desc}.$(date +%Y%m%d_%H%M%S)"
        else
            backup="${file}${backup_suffix}.$(date +%Y%m%d_%H%M%S)"
        fi
        cp "$file" "$backup"
        msg_info "已备份: $file → $backup"
        return 0
    else
        msg_warning "文件不存在: $file"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 系统信息查询
# ═══════════════════════════════════════════════════════════════

# get_arch/get_memory_info/get_disk_usage 已迁移至lib/core.sh

# ═══════════════════════════════════════════════════════════════
# APT软件包管理
# ═══════════════════════════════════════════════════════════════

is_package_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }
is_package_available() { apt-cache show "$1" >/dev/null 2>&1; }

apt_update_with_progress() {
    msg_info "正在从软件源同步软件包索引 (请稍候)..."
    show_progress 5 100
    local status=0
    DEBIAN_FRONTEND=noninteractive apt-get update -o APT::Status-Fd=3 3>&1 1>/dev/null 2>/dev/null | while read -r line; do
        if [[ "$line" =~ ^(progress|dlstatus): ]]; then
            local percent
            percent=$(echo "$line" | cut -d: -f3 | tr -d ' ' | cut -d. -f1)
            if [[ "$percent" =~ ^[0-9]+$ ]]; then
                show_progress "$percent" 100
            fi
        fi
    done
    status=${PIPESTATUS[0]}
    show_progress 100 100
    echo "" >&2
    return "$status"
}

apt_install_with_progress() {
    msg_info "正在下载并安装软件包..."
    show_progress 5 100
    local status=0
    DEBIAN_FRONTEND=noninteractive apt-get install -y -o APT::Status-Fd=3 "$@" 3>&1 1>/dev/null 2>/dev/null | while read -r line; do
        if [[ "$line" =~ ^(progress|status): ]]; then
            local percent
            percent=$(echo "$line" | cut -d: -f3 | tr -d ' ' | cut -d. -f1)
            if [[ "$percent" =~ ^[0-9]+$ ]]; then
                show_progress "$percent" 100
            fi
        fi
    done
    status=${PIPESTATUS[0]}
    show_progress 100 100
    echo "" >&2
    return "$status"
}

install_packages() {
    local missing=()
    for pkg in "$@"; do if ! is_package_installed "$pkg"; then missing+=("$pkg"); fi; done
    if [[ ${#missing[@]} -eq 0 ]]; then msg_info "所有包已安装"; return 0; fi
    msg_info "准备安装缺失组件: ${missing[*]}"
    apt_update_with_progress
    if apt_install_with_progress "${missing[@]}"; then
        msg_success "软件包安装成功"
        return 0
    fi
    msg_error "软件包安装失败"
    return 1
}

install_package() { install_packages "$1"; }

remove_package() {
    if ! is_package_installed "$1"; then msg_info "$1未安装"; return 0; fi
    msg_info "正在卸载$1..."
    if DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "$1" >/dev/null 2>&1; then
        msg_success "$1卸载成功"
        return 0
    fi
    msg_error "$1卸载失败"
    return 1
}

purge_package() {
    if ! is_package_installed "$1"; then msg_info "$1未安装"; return 0; fi
    msg_info "正在卸载$1..."
    if DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq "$1" >/dev/null 2>&1; then
        msg_success "$1卸载成功"
        return 0
    fi
    msg_error "$1卸载失败"
    return 1
}

# ═══════════════════════════════════════════════════════════════
# Systemd服务管理
# ═══════════════════════════════════════════════════════════════

is_service_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

start_service() {
    msg_info "正在启动$1服务..."
    if systemctl start "$1" 2>/dev/null; then
        msg_success "已启动$1服务"; return 0
    fi
    msg_error "$1启动失败"; return 1
}

stop_service() {
    msg_info "正在停止$1服务..."
    if systemctl stop "$1" 2>/dev/null; then
        msg_success "已停止$1服务"; return 0
    fi
    msg_error "停止$1服务失败"; return 1
}

restart_service() {
    msg_info "正在重启$1服务..."
    if systemctl restart "$1" 2>/dev/null; then
        msg_success "已重启$1服务"; return 0
    fi
    msg_error "重启$1服务失败"; return 1
}

systemctl_reload() {
    if systemctl daemon-reload 2>/dev/null; then
        return 0
    fi
    return 1
}

enable_service() { systemctl enable "$1" 2>/dev/null && msg_success "已启用 $1 开机自启"; }
disable_service() { systemctl disable "$1" 2>/dev/null && msg_success "已取消 $1 开机自启"; }

# ═══════════════════════════════════════════════════════════════
# Docker环境检测与初始化
# ═══════════════════════════════════════════════════════════════

check_docker() {
    if ! command_exists docker; then
        msg_error "未检测到Docker, 请先在主菜单[配置Docker]中安装"
        return 1
    fi

    if ! is_service_active docker; then
        msg_info "正在启动Docker服务..."
        start_service docker
    fi
    return 0
}

check_docker_compose() {
    if declare -p COMPOSE_CMD >/dev/null 2>&1 && [[ "$(declare -p COMPOSE_CMD)" == *"="* ]] && [[ "${COMPOSE_CMD[0]-}" =~ ^docker ]]; then
        return 0
    fi
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD=(docker compose)
        return 0
    elif command_exists docker-compose; then
        COMPOSE_CMD=(docker-compose)
        return 0
    else
        msg_info "Docker Compose未安装, 开始尝试安装..."
        if declare -f install_docker_compose_standalone >/dev/null; then
            if ! install_docker_compose_standalone; then
                msg_error "Docker Compose安装失败, 请先在主菜单手动安装"
                return 1
            fi
            COMPOSE_CMD=(docker-compose)
            return 0
        else
            msg_error "无法找到安装Docker Compose的函数, 请先手动安装"
            return 1
        fi
    fi
}

docker_pull_image() {
    local image="$1"
    msg_info "正在拉取镜像:${image}..."

    local prev_msg=""
    local lines_printed=0

    docker pull "$image" 2>&1 | stdbuf -oL grep -E "^[a-f0-9]{12}:|Digest:|Status:" | while read -r line; do
        local clean_line
        clean_line=$(echo "$line" | xargs | cut -c 1-80)
        [[ -z "$clean_line" ]] && continue

        while [[ $lines_printed -gt 0 ]]; do
            printf "\033[A\r\033[K"
            ((lines_printed--))
        done

        if [[ -n "$prev_msg" ]]; then
            printf "  ${GRAY}➜ %s${NC}\n" "$prev_msg"
            printf "  ${BRIGHT_BLUE}➜${NC} ${CYAN}%s${NC}\n" "$clean_line"
            lines_printed=2
        else
            printf "  ${BRIGHT_BLUE}➜${NC} ${CYAN}%s${NC}\n" "$clean_line"
            lines_printed=1
        fi
        prev_msg="$clean_line"
    done

    if [[ ${PIPESTATUS[0]} -eq 0 ]] || docker_image_exists "$image"; then
        return 0
    else
        msg_error "镜像${image}拉取失败"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Docker容器生命周期管理
# ═══════════════════════════════════════════════════════════════

container_exists() { docker inspect "$1" >/dev/null 2>&1; }
container_running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]; }
docker_image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

docker_stop_container() {
    local container="$1" label="${2:-$1}"
    if ! container_running "$container"; then
        msg_info "${label}容器当前未处于运行状态"
        return 0
    fi
    msg_info "正在停止容器..."
    docker stop "$container" >/dev/null 2>&1
    action "${label}服务已停止" "停止服务失败"
}

docker_start_container() {
    local container="$1" label="${2:-$1}"
    if ! container_exists "$container"; then
        msg_error "未找到${label}容器, 请先执行安装"
        return 1
    fi
    msg_info "正在启动容器服务..."
    docker start "$container" >/dev/null 2>&1
    if action "${label}服务启动成功" "启动服务失败"; then
        return 0
    else
        return 1
    fi
}

docker_remove_container_and_image() {
    local container="$1" image="$2" label="${3:-$1}"
    local found=false

    if container_exists "$container"; then
        found=true
        if confirm "检测到${label}容器, 确定要移除吗?"; then
            msg_info "正在移除容器..."
            docker rm -f "$container" >/dev/null 2>&1
            msg_success "${label}容器移除成功"
        fi
    fi

    if docker_image_exists "$image"; then
        found=true
        if confirm "检测到${label}相关Docker镜像, 是否执行清理?"; then
            msg_info "正在清理本地镜像..."
            docker rmi "$image" >/dev/null 2>&1 || true
            msg_success "镜像清理完成"
        fi
    fi

    if [[ "$found" == "false" ]]; then
        msg_info "未检测到${label}相关的容器或镜像, 可能已卸载"
    else
        msg_success "${label}卸载操作完成"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 文件下载工具
# ═══════════════════════════════════════════════════════════════

download_file() {
    local url="$1"
    local output="$2"
    local ua="${3:-Wget/1.21.1}"
    
    local success=false
    local filename; filename=$(basename "$output")
    if command_exists wget; then
        # 使用 PIPESTATUS 准确获取 wget 的退出状态
        sudo wget -q --user-agent="$ua" --show-progress --progress=bar:force "$url" -O "$output" 2>&1 | while read -r -d $'\r' line; do
            local percent
            percent=$(echo "$line" | grep -oE "[0-9]+%" | tail -n 1)
            [[ -n "$percent" ]] && printf "\r  ${BRIGHT_BLUE}➜${NC} ${CYAN}正在下载 [%s]: %-4s${NC}\033[K" "$filename" "$percent"
        done
        
        if [[ ${PIPESTATUS[0]} -eq 0 && -f "$output" ]]; then
            printf "\r  ${BRIGHT_BLUE}➜${NC} ${CYAN}正在下载 [%s]: 100%%${NC}\033[K\n" "$filename"
            success=true
        fi
    fi
    
    if [[ "$success" == "false" ]] && command_exists curl; then
        msg_info "尝试使用 curl 备用下载..."
        sudo curl -# -L -A "$ua" -o "$output" "$url" 2>&1 | while read -r -d $'\r' line; do
            local percent
            percent=$(echo "$line" | grep -oE "[0-9.]+(%)?" | tail -n 1)
            [[ -n "$percent" ]] && printf "\r  ${BRIGHT_BLUE}➜${NC} ${CYAN}正在下载 [%s]: %-6s${NC}\033[K" "$filename" "$percent"
        done
        
        if [[ ${PIPESTATUS[0]} -eq 0 && -f "$output" ]]; then
            printf "\r  ${BRIGHT_BLUE}➜${NC} ${CYAN}正在下载 [%s]: 100%%${NC}\033[K\n" "$filename"
            success=true
        fi
    fi
    
    if [[ "$success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Docker部署交互
# ═══════════════════════════════════════════════════════════════

# prompt_host_ip/prompt_host_port 已迁移至lib/io.sh

docker_confirm_reinstall() {
    local container="$1" label="${2:-$1}"
    if ! container_exists "$container"; then
        return 0
    fi
    if ! confirm "检测到${label}容器已存在, 是否删除并重新安装?"; then
        msg_info "已取消重新安装"
        return 1
    fi
    docker rm -f "$container" >/dev/null 2>&1 || true
    return 0
}

docker_deploy_container() {
    local image="$1" container="$2" label="$3"
    local fail_msg="${4:-容器启动失败, 请检查端口是否被占用}"
    shift 4
    if ! docker_pull_image "$image"; then
        return 1
    fi
    msg_info "正在部署${label}容器..."
    docker rm -f "$container" >/dev/null 2>&1 || true
    docker run -d "$@" --name "$container" "$image" >/dev/null 2>&1
    action "${label}容器创建成功" "$fail_msg" || return 1
    docker_wait_healthy "$container" "$label" || return 1
    return 0
}

docker_wait_healthy() {
    local container="$1" label="${2:-$1}" timeout="${3:-30}"
    msg_info "正在等待服务初始化..."
    local count=0
    while [[ $count -lt $timeout ]]; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            msg_success "容器处于运行状态"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    msg_warning "${label}容器启动超时, 请稍后通过 docker ps 检查"
    return 1
}

show_access_info() {
    draw_line "-"
    local line
    for line in "$@"; do
        msg_star "$line"
    done
    draw_line "-"
}

# ═══════════════════════════════════════════════════════════════
# DockerCompose生命周期管理
# ═══════════════════════════════════════════════════════════════

# 内部函数：实现双行静默刷新渲染
_docker_compose_render_premium() {
    local label="$1"
    local action="$2"
    shift 2
    local global_flags=("$@")
    local compose_args=("$action")
    [[ "$action" == "up" ]] && compose_args=("up" "-d")

    local prev_msg=""
    # 忽略 Waiting 状态，捕获核心变更
    sudo "${COMPOSE_CMD[@]}" "${global_flags[@]}" "${compose_args[@]}" 2>&1 | while read -r line; do
        if [[ "$line" =~ (Created|Started|Healthy|Running|Stopped|Removing|Removed|Pulled|Up-to-date) ]] && [[ ! "$line" =~ "Waiting" ]]; then
            local clean_line; clean_line=$(echo "$line" | grep -oE "(Container|Network|Volume|Service|Image) [^ ]+ (Created|Started|Healthy|Running|Stopped|Removing|Removed|Pulled|Up-to-date)" | head -n 1)
            [[ -z "$clean_line" ]] && clean_line=$(echo "$line" | xargs | cut -c 1-60)

            # 双行渲染逻辑
            if [[ -n "$prev_msg" ]]; then
                printf "\033[A\r\033[K" # 回退一行并清除
                printf "\033[A\r\033[K" # 再回退一行并清除
                printf "  ${GRAY}➜ %s${NC}\n" "$prev_msg"
            fi
            printf "  ${BRIGHT_BLUE}➜${NC} ${CYAN}%s${NC}\n" "$clean_line"
            prev_msg="$clean_line"
        fi
    done
    return "${PIPESTATUS[0]}"
}

docker_compose_stop() {
    local dir="$1" label="${2:-服务}"
    shift 2
    if [[ ! -d "$dir" ]]; then
        msg_error "未找到${label}安装目录: $dir"
        return 1
    fi
    check_docker_compose || return 1
    msg_info "正在停止${label}容器服务..."
    (cd "$dir" && _docker_compose_render_premium "${label}" "stop" "$@")
    action "${label}服务已停止" "${label}服务停止失败"
}

docker_compose_start() {
    local dir="$1" label="${2:-服务}" mode="${3:-start}"
    shift 3
    if [[ ! -d "$dir" ]]; then
        msg_error "未找到${label}安装目录, 请先执行安装"
        return 1
    fi
    check_docker_compose || return 1
    msg_info "正在启动${label}容器服务..."
    local action_name="start"
    [[ "$mode" == "up" ]] && action_name="up"
    (cd "$dir" && _docker_compose_render_premium "${label}" "$action_name" "$@")
    action "${label}服务启动成功" "${label}服务启动失败"
}

docker_compose_remove() {
    local dir="$1" label="$2"
    shift 2
    local compose_args=()
    local images=()
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--compose-args" ]]; then
            read -ra compose_args <<< "$2"
            shift 2
        else
            images+=("$1")
            shift
        fi
    done
    local found=false

    if [[ -d "$dir" ]]; then
        found=true
        if confirm "检测到${label}安装目录, 确定要卸载吗?"; then
            check_docker_compose || return 1
            local volume_args=()
            if confirm "是否同时删除${label}的数据卷(数据库等数据将不可恢复)?"; then
                volume_args=(-v)
            fi
            msg_info "正在清理容器资源..."
            (cd "$dir" && sudo "${COMPOSE_CMD[@]}" "${compose_args[@]}" down "${volume_args[@]}" >/dev/null 2>&1)
            action "容器资源清理完成" "容器资源清理失败"

            msg_info "正在清理物理文件..."
            sudo rm -rf "$dir"
            action "物理环境清理完成" "物理环境清理失败"
        fi
    fi

    if [[ ${#images[@]} -gt 0 ]]; then
        local image_exists=false
        for img in "${images[@]}"; do
            if docker images --format '{{.Repository}}:{{.Tag}}' | grep -qx "${img}"; then
                image_exists=true
                break
            fi
        done

        if [[ "$image_exists" == "true" ]]; then
            found=true
            if confirm "检测到${label}相关Docker镜像, 是否执行清理?"; then
                msg_info "正在清理本地镜像..."
                for img in "${images[@]}"; do
                    docker rmi "${img}" >/dev/null 2>&1 || true
                done
                msg_success "镜像清理完成"
            fi
        fi
    fi

    if [[ "$found" == "false" ]]; then
        msg_info "未检测到${label}相关的环境资源, 可能已卸载"
    else
        msg_success "${label}卸载操作完成"
    fi
}

show_compose_status_table() {
    local dir="$1" label="${2:-服务}"
    shift 2
    local compose_args=("$@")
    if [[ ! -d "$dir" ]]; then
        msg_error "未找到${label}安装目录, 请先安装"
        return 1
    fi
    check_docker_compose || return 1

    local widths="18 12 10 18"
    echo ""
    msg_table_row "$widths" "${BOLD}服务名称" "运行状态" "健康状况" "端口映射${NC}"
    draw_line "-" "${GRAY}"

    local line
    while read -r line; do
        [[ -z "$line" ]] && continue
        local service state health ports
        IFS='|' read -r service state health ports <<< "$line"

        local state_color="${NC}"
        case "${state,,}" in
            running) state_color="${GREEN}" ;;
            exited|dead) state_color="${RED}" ;;
            *) state_color="${YELLOW}" ;;
        esac

        local health_color="${NC}"
        case "${health,,}" in
            healthy) health_color="${GREEN}" ;;
            unhealthy) health_color="${RED}" ;;
            starting) health_color="${YELLOW}" ;;
            *) health_color="${GRAY}" ;;
        esac

        local simple_ports
        simple_ports=$(echo "$ports" | grep -oE "[0-9]+->[0-9]+" | head -n 1) || true
        [[ -z "$simple_ports" ]] && simple_ports="-"

        msg_table_row "$widths" "${CYAN}${service}${NC}" "${state_color}${state}${NC}" "${health_color}${health:- -}${NC}" "${WHITE}${simple_ports}${NC}"
    done < <((cd "$dir" && sudo "${COMPOSE_CMD[@]}" "${compose_args[@]}" ps --format "{{.Service}}|{{.State}}|{{.Health}}|{{.Ports}}") 2>/dev/null)
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# 通用备份管理
# ═══════════════════════════════════════════════════════════════

backup_list() {
    ls -t "${1}".bak* 2>/dev/null
}

backup_display() {
    local label="$1"
    shift
    local backups=("$@")
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        msg_warning "目前没有任何${label}备份文件"
        return 1
    fi

    echo ""
    local widths="6 32 12 18"
    msg_table_row "$widths" "${BOLD}编号" "备份文件名" "标签" "修改时间${NC}"
    draw_line "-"

    local i
    for i in "${!backups[@]}"; do
        local file="${backups[$i]}"
        local filename
        filename=$(basename "$file")
        
        local tag="legacy"
        if [[ $filename =~ \.bak\.([^.]+)\. ]]; then
            tag="${BASH_REMATCH[1]}"
        fi
        
        local mtime
        mtime=$(date -r "$file" "+%Y-%m-%d %H:%M")
        
        msg_table_row "$widths" "$((i+1))" "$filename" "$tag" "$mtime"
    done
    echo ""
    return 0
}

backup_preview() {
    local file="$1" pattern="${2:-.*}"
    local total
    total=$(grep -c "$pattern" "$file" 2>/dev/null || echo 0)

    msg_info "备份内容预览($file):"
    draw_line "-" "${GRAY}"
    grep "$pattern" "$file" | head -n 5 | sed 's/^/    /'
    if [[ $total -gt 5 ]]; then
        echo "    ... (共${total}条记录)"
    fi
    draw_line "-" "${GRAY}"
}

backup_select() {
    local title="$1" target_file="$2" label="$3"
    show_section "$title"

    local backups=()
    mapfile -t backups < <(backup_list "$target_file")

    if ! backup_display "$label" "${backups[@]}"; then return 255; fi

    local choice
    msg_prompt "请输入备份编号 [1-${#backups[@]}, 0取消]"

    if [[ $choice == "0" ]]; then
        return 255
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]] || [[ $choice -lt 1 || $choice -gt ${#backups[@]} ]]; then
        msg_error "无效编号"
        return 1
    fi

    _SELECTED_BACKUP="${backups[$((choice-1))]}"
    return 0
}

backup_clear_all() {
    local label="$1" target_file="$2"
    show_section "清空全部${label}备份"
    
    local backups=()
    mapfile -t backups < <(backup_list "$target_file")
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        msg_warning "没有备份文件可清理"
        return 0
    fi
    
    msg_warning "即将删除 ${#backups[@]} 个备份文件"
    if confirm "你确定要清空所有的${label}历史备份吗?"; then
        if confirm "请再次确认(操作不可恢复):"; then
            rm -f "${target_file}".bak*
            msg_success "所有备份清理完毕"
        fi
    fi
}
