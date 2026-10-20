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
#  📝 模块描述 : 项目自更新与版本管理
#  📁 文件路径 : lib/update.sh
#  👤 作者信息 : mingy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


# ═══════════════════════════════════════════════════════════════
# 版本获取
# ═══════════════════════════════════════════════════════════════

get_remote_version() {
    local api_url="https://gitee.com/api/v5/repos/yijingsec/LinuxEnvConfig/tags"
    local response
    response=$(curl -fsSL --max-time 10 "$api_url" 2>/dev/null || echo "")
    if [[ -z "$response" ]]; then
        echo ""
        return
    fi
    if command_exists jq; then
        echo "$response" | jq -r ".[].name" 2>/dev/null | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1
    else
        echo "$response" | grep -oP '"name":"\K[^"]+' | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 项目在线更新
# ═══════════════════════════════════════════════════════════════

check_project_update() {
    show_section "项目更新检查"
    if ! check_ip_connectivity; then
        msg_warning "网络不可用，跳过更新检查"
        return 1
    fi

    if [[ -d "$SCRIPT_DIR/.git" ]] && command_exists git; then
        local current_branch
        current_branch=$(git -c safe.directory="*" -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        if [[ "$current_branch" != "master" && -n "$current_branch" ]]; then
            msg_info "当前处于开发分支[${current_branch}]，已跳过版本更新检测"
            return 0
        fi

        msg_info "通过Git检查项目更新..."
        local repo_url="https://gitee.com/yijingsec/LinuxEnvConfig.git"
        local remote_latest
        remote_latest=$(git -c safe.directory="*" ls-remote "$repo_url" HEAD 2>/dev/null | cut -f1 || true)
        local local_current
        local_current=$(git -c safe.directory="*" -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)

        if [[ -n "$remote_latest" && -n "$local_current" ]]; then
            if [[ "$remote_latest" != "$local_current" ]]; then
                msg_info "发现新版本(本地:${local_current:0:7}，远程:${remote_latest:0:7})"
                local dirty_files
                dirty_files=$(git -c safe.directory="*" -C "$SCRIPT_DIR" status --porcelain 2>/dev/null || true)
                if [[ -n "$dirty_files" ]]; then
                    msg_warning "检测到本地存在未提交的修改:"
                    printf '%s\n' "$dirty_files" | head -n 10 | sed 's/^/    /' >&2
                    if ! confirm "更新将覆盖这些本地修改, 是否继续?"; then
                        msg_info "已跳过更新"
                        return 2
                    fi
                fi
                if confirm "是否更新到最新项目?"; then
                    msg_info "正在更新项目..."
                    git -c safe.directory="*" -C "$SCRIPT_DIR" restore . >/dev/null 2>&1 || true
                    git -c safe.directory="*" -C "$SCRIPT_DIR" pull --quiet
                    if action "更新项目成功!请重新运行脚本" "更新项目失败，请稍后重试或检查网络"; then
                        exit 0
                    else
                        return 1
                    fi
                else
                    msg_info "已跳过更新"
                    return 2
                fi
            else
                msg_success "项目代码已是最新"
                return 0
            fi
        fi
        msg_warning "无法获取Git提交记录，回退到版本号模式..."
    fi

    msg_info "正在通过API检查版本..."
    local remote_version
    remote_version=$(get_remote_version)
    remote_version="${remote_version#v}"
    if [[ -z $remote_version ]]; then
        msg_warning "无法获取远程版本信息"
        return 1
    fi

    if [[ "$(printf "%s\n%s\n" "$SCRIPT_VERSION" "$remote_version" | sort -V | head -n 1)" != "$SCRIPT_VERSION" ]]; then
        msg_info "发现新版本:$remote_version(当前:$SCRIPT_VERSION)"
        if confirm "是否更新到最新项目?"; then
            update_project_tarball "$remote_version"
        else
            msg_info "已跳过更新"
            return 2
        fi
    else
        msg_success "已是最新版本($SCRIPT_VERSION)"
    fi
}

update_project_tarball() {
    local version="${1:-}"

    msg_info "正在更新项目..."

    local backup_dir
    backup_dir="$SCRIPT_DIR/.backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib "$SCRIPT_DIR"/modules "$backup_dir/" 2>/dev/null || true

    local temp_dir
    temp_dir=$(mktemp -d)
    lec_register_temp "$temp_dir"

    if curl -fsSL -o "$temp_dir/update.tar.gz" \
        "https://gitee.com/yijingsec/LinuxEnvConfig/repository/archive/${version}.tar.gz" 2>/dev/null; then

        if ! tar -xzf "$temp_dir/update.tar.gz" -C "$temp_dir" 2>/dev/null; then
            msg_error "更新包解压失败"
            rm -rf "$temp_dir"
            return 1
        fi

        if ! cp -r "$temp_dir"/LinuxEnvConfig-*/* "$SCRIPT_DIR/" 2>/dev/null; then
            msg_error "更新文件覆盖失败, 备份已保留在:$backup_dir"
            rm -rf "$temp_dir"
            return 1
        fi

        msg_success "更新完成! 请重新运行脚本"
        rm -rf "$temp_dir"

        exit 0
    else
        msg_error "更新包下载失败, 备份已保留在:$backup_dir"
        rm -rf "$temp_dir"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Kali GPG密钥管理
# ═══════════════════════════════════════════════════════════════

update_kali_gpg_key() {
    if [[ "$OS_ID" != "kali" ]]; then
        return 2
    fi

    local kali_ver="$OS_VER"
    local threshold="2025.1"
    [[ "$kali_ver" =~ ^25\. ]] && threshold="25.01"

    if [[ "$(printf "%s\n%s\n" "$threshold" "$kali_ver" | sort -V | head -n1)" != "$kali_ver" ]]; then
        return 2
    fi

    show_section "Kali GPG密钥更新"
    msg_info "检测到旧版Kali($kali_ver)，正在更新GPG密钥..."

    if wget -q -O - https://archive.kali.org/archive-key.asc 2>/dev/null | \
        apt-key add - >/dev/null 2>&1; then
        msg_success "GPG密钥更新成功"
        return 0
    fi

    if gpg --fetch-keys https://archive.kali.org/archive-key.asc 2>/dev/null; then
        msg_success "GPG密钥更新成功"
        return 0
    fi

    msg_warning "GPG密钥更新失败, 可能不影响正常使用"
    return 1
}
