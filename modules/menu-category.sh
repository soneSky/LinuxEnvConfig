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
#  📝 模块描述 : 功能模块分类导航 — 主菜单直接显示六阶段分类
#  📁 文件路径 : modules/menu-category.sh
#  👤 作者信息 : mingy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ═══════════════════════════════════════════════════════════════
# 分类子菜单渲染（不自动编号，直接使用 items 中的编号）
# ═══════════════════════════════════════════════════════════════

show_category_submenu() {
    local title="$1"
    shift
    local items=("$@")

    local term_width; term_width=$(get_term_width)
    local total_width=50

    # 计算最大宽度
    local max_len; max_len=$(str_display_width "$title")
    local item
    for item in "${items[@]}"; do
        local w; w=$(str_display_width "  $item")
        [[ $w -gt $max_len ]] && max_len=$w
    done
    total_width=$((max_len + 8))
    [[ $total_width -lt 50 ]] && total_width=50
    [[ $total_width -gt 76 ]] && total_width=76

    local top_border mid_border bottom_border
    ui_set_borders "$total_width"

    clear_screen
    echo ""
    echo -e "  ${GREEN}${top_border}${NC}"
    ui_print_centered_row "$total_width" "${BOLD}${BRIGHT_GREEN}" "$title"
    echo -e "  ${GREEN}${mid_border}${NC}"

    local path_display; path_display=$(_get_menu_path_display)
    local path_w; path_w=$(str_display_width "$path_display")
    local padding=$((total_width - 6 - path_w))
    [[ $padding -lt 0 ]] && padding=0
    echo -e "  ${GREEN}│${NC}  ${WHITE}${path_display}${NC}$(printf '%*s' "$padding" ' ')  ${GREEN}│${NC}"
    ui_print_blank_row "$total_width"

    # 渲染 items（items 已包含编号，直接显示）
    for item in "${items[@]}"; do
        local item_w; item_w=$(str_display_width "  $item")
        local item_pad=$((total_width - 4 - item_w))
        [[ $item_pad -lt 0 ]] && item_pad=0
        echo -e "  ${GREEN}│${NC}  ${BRIGHT_CYAN}${item}${NC}$(printf '%*s' "$item_pad" ' ')${GREEN}│${NC}"
    done

    ui_print_blank_row "$total_width"
    echo -e "  ${GREEN}${mid_border}${NC}"

    ui_print_footer "$total_width" "0. 返回上级菜单" "[q] 退出脚本" "$WHITE" "$BRIGHT_GREEN"
    echo -e "  ${GREEN}${bottom_border}${NC}"
    echo ""

    # 读取用户输入（不使用 local，确保调用者能访问 $choice）
    msg_prompt "请选择操作"
}

# ═══════════════════════════════════════════════════════════════
# 阶段子菜单：直接调用模块 handler
# ═══════════════════════════════════════════════════════════════

menu_category_base() {
    local items=(
        "基础配置 · 系统基础环境与工具优化"
        "配置APT源 · 设置系统包管理器镜像源"
        "配置Docker · 容器环境与代理"
        "配置JDK · Java运行环境"
        "配置Miniconda3 · Python环境管理"
    )
    local handlers=(
        "config_basic"
        "config_apt"
        "config_docker"
        "config_jdk"
        "config_miniconda3"
    )

    while true; do
        show_category_submenu "① 基础环境配置" \
            "5. ${items[4]}" \
            "4. ${items[3]}" \
            "3. ${items[2]}" \
            "2. ${items[1]}" \
            "1. ${items[0]}" \
            "0. 返回主菜单"

        [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
        [[ "$choice" == "0" ]] && break

        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#handlers[@]} ]]; then
            local handler="${handlers[$idx]}"
            if declare -f "$handler" > /dev/null; then
                push_path "${items[$idx]}"
                $handler
                pop_path
            else
                msg_error "处理函数未找到: $handler"
                pause
            fi
        else
            msg_error "选项超出范围 (1-${#handlers[@]})"
            pause
        fi
    done
}

menu_category_recon() {
    local items=(
        "配置ARL · 灯塔资产侦察系统"
        "配置ScopeSentry · 分布式资产侦察管理"
    )
    local handlers=(
        "config_arl"
        "config_scopesentry"
    )

    while true; do
        show_category_submenu "② 信息收集侦察" \
            "2. ${items[1]}" \
            "1. ${items[0]}" \
            "0. 返回主菜单"

        [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
        [[ "$choice" == "0" ]] && break

        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#handlers[@]} ]]; then
            local handler="${handlers[$idx]}"
            if declare -f "$handler" > /dev/null; then
                push_path "${items[$idx]}"
                $handler
                pop_path
            else
                msg_error "处理函数未找到: $handler"
                pause
            fi
        else
            msg_error "选项超出范围 (1-${#handlers[@]})"
            pause
        fi
    done
}

menu_category_exploit() {
    local items=(
        "配置BeEF · 浏览器渗透框架"
        "配置Dnscat2 · DNS隧道"
        "配置Metasploit · 渗透测试框架"
        "配置Viper · 图形化渗透测试框架"
        "配置Empire · 后渗透框架"
        "配置BlueLotus · XSS接收平台"
    )
    local handlers=(
        "config_beef"
        "config_dnscat2"
        "config_metasploit"
        "config_viper"
        "config_empire"
        "config_bluelotus"
    )

    while true; do
        show_category_submenu "③ 漏洞利用平台" \
            "6. ${items[5]}" \
            "5. ${items[4]}" \
            "4. ${items[3]}" \
            "3. ${items[2]}" \
            "2. ${items[1]}" \
            "1. ${items[0]}" \
            "0. 返回主菜单"

        [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
        [[ "$choice" == "0" ]] && break

        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#handlers[@]} ]]; then
            local handler="${handlers[$idx]}"
            if declare -f "$handler" > /dev/null; then
                push_path "${items[$idx]}"
                $handler
                pop_path
            else
                msg_error "处理函数未找到: $handler"
                pause
            fi
        else
            msg_error "选项超出范围 (1-${#handlers[@]})"
            pause
        fi
    done
}

menu_category_scan() {
    local items=(
        "配置AWVS · 漏洞扫描器"
        "配置DeepAudit · 深度审计分析"
        "配置XingRin · 分布式安全扫描平台"
    )
    local handlers=(
        "config_awvs"
        "config_deepaudit"
        "config_xingrin"
    )

    while true; do
        show_category_submenu "④ 自动化扫描" \
            "3. ${items[2]}" \
            "2. ${items[1]}" \
            "1. ${items[0]}" \
            "0. 返回主菜单"

        [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
        [[ "$choice" == "0" ]] && break

        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#handlers[@]} ]]; then
            local handler="${handlers[$idx]}"
            if declare -f "$handler" > /dev/null; then
                push_path "${items[$idx]}"
                $handler
                pop_path
            else
                msg_error "处理函数未找到: $handler"
                pause
            fi
        else
            msg_error "选项超出范围 (1-${#handlers[@]})"
            pause
        fi
    done
}

menu_category_lab() {
    local items=(
        "配置Vulfocus · 漏洞测试平台"
        "配置CTFd · CTF竞赛框架"
        "配置crAPI · API安全靶场"
    )
    local handlers=(
        "config_vulfocus"
        "config_ctfd"
        "config_crAPI"
    )

    while true; do
        show_category_submenu "⑤ 靶场演练平台" \
            "3. ${items[2]}" \
            "2. ${items[1]}" \
            "1. ${items[0]}" \
            "0. 返回主菜单"

        [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
        [[ "$choice" == "0" ]] && break

        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#handlers[@]} ]]; then
            local handler="${handlers[$idx]}"
            if declare -f "$handler" > /dev/null; then
                push_path "${items[$idx]}"
                $handler
                pop_path
            else
                msg_error "处理函数未找到: $handler"
                pause
            fi
        else
            msg_error "选项超出范围 (1-${#handlers[@]})"
            pause
        fi
    done
}

menu_category_defense() {
    local items=(
        "配置HFish · 蜜罐系统"
        "配置OCR-API · 文字识别服务"
        "配置OhMyZsh · 终端美化与增强"
    )
    local handlers=(
        "config_hfish"
        "config_ocr_api_server"
        "config_ohmyzsh"
    )

    while true; do
        show_category_submenu "⑥ 防御监控类" \
            "3. ${items[2]}" \
            "2. ${items[1]}" \
            "1. ${items[0]}" \
            "0. 返回主菜单"

        [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
        [[ "$choice" == "0" ]] && break

        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#handlers[@]} ]]; then
            local handler="${handlers[$idx]}"
            if declare -f "$handler" > /dev/null; then
                push_path "${items[$idx]}"
                $handler
                pop_path
            else
                msg_error "处理函数未找到: $handler"
                pause
            fi
        else
            msg_error "选项超出范围 (1-${#handlers[@]})"
            pause
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
# 分类导航主菜单（直接显示，替代原主菜单）
# ═══════════════════════════════════════════════════════════════

menu_category_nav() {
    local term_width; term_width=$(get_term_width)
    local cols=2
    [[ $term_width -lt 75 ]] && cols=1

    local total_width=66
    [[ $cols -eq 1 ]] && total_width=54

    local top_border mid_border bottom_border
    ui_set_borders "$total_width"

    clear_screen
    echo ""
    echo -e "  ${GREEN}${top_border}${NC}"

    local title="${BOLD}${BRIGHT_GREEN}⚔  LEC 功能模块分类导航${NC}"
    ui_print_centered_row "$total_width" "${BOLD}${BRIGHT_GREEN}" "$title"

    local total_modules=${#MAIN_MENU_ITEMS[@]}
    local desc="按渗透测试生命周期六阶段组织全部 ${total_modules} 个功能模块"
    local tw; tw=$(str_display_width "$desc")
    local pad; pad=$(( (total_width - 2 - tw) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    echo -e "  ${GREEN}│${NC}$(printf '%*s' "$pad" ' ')${GRAY}${desc}${NC}$(printf '%*s' "$pad" ' ')${GREEN}│${NC}"
    echo -e "  ${GREEN}${mid_border}${NC}"

    # ── 六阶段数据 ─────────────────────────────────────────
    local -a PHASE_NUMS=("①" "②" "③" "④" "⑤" "⑥")
    local -a PHASE_NAMES=(
        "基础环境配置"
        "信息收集侦察"
        "漏洞利用平台"
        "自动化扫描"
        "靶场演练平台"
        "防御监控类"
    )
    local -a PHASE_DESCS=(
        "系统初始化 · Java/Python/Docker"
        "资产发现 · 子域名/端口/指纹/暴露面"
        "渗透执行 · 框架/会话/后渗透/C2"
        "漏洞扫描 · Web应用/源代码/微服务"
        "技能训练 · 靶场/CTF/API演练"
        "蓝队视角 · 蜜罐/OCR/终端效率"
    )
    local -a PHASE_MODULES=(
        "basic,apt,jdk,miniconda3,docker"
        "arl,scopesentry"
        "metasploit,viper,empire,dnscat2,beef,bluelotus"
        "awvs,deepaudit,xingrin"
        "vulfocus,ctfd,crapi"
        "hfish,ocr-api,ohmyzsh"
    )
    local -a PHASE_COLORS=(
        "$BRIGHT_GREEN"
        "$BRIGHT_CYAN"
        "$BRIGHT_YELLOW"
        "$BRIGHT_MAGENTA"
        "$BRIGHT_BLUE"
        "$GRAY"
    )

    # ── 绘制六行表格（确保每行右侧│完全对齐）─────────────────
    local inner_w=$(( total_width - 4 ))   # 两个 │ 之间的总字符数
    local sep=" │ "                          # 中间分隔符

    local i
    for ((i=0; i<6; i++)); do
        local icon="${PHASE_COLORS[$i]}"
        local num="${PHASE_NUMS[$i]}"
        local name="${PHASE_NAMES[$i]}"
        local desc="${PHASE_DESCS[$i]}"
        local mods="${PHASE_MODULES[$i]}"

        # 构建内容字符串（不含两端的 │）
        local content="${icon}${num}  ${name}${sep}${desc}  modules: ${mods}"
        local cw; cw=$(str_display_width "$content")
        # 右填充到 inner_w
        local pad=$(( inner_w - cw ))
        [[ $pad -lt 0 ]] && pad=0
        local padded="${content}$(printf '%*s' "$pad" ' ')"

        echo -e "  ${GREEN}│${NC}${padded}${GREEN}│${NC}"
    done

    echo -e "  ${GREEN}${mid_border}${NC}"

    local path_display; path_display=$(_get_menu_path_display)
    ui_print_footer "$total_width" "$path_display" "[q] 退出脚本" "$WHITE" "$BRIGHT_GREEN"
    echo -e "  ${GREEN}${bottom_border}${NC}"
    echo ""

    # ── 读取用户选择 ──────────────────────────────────────
    local cat_choice
    msg_prompt "请选择阶段 [1-6, q退出]"
    case "$cat_choice" in
        1) menu_category_base ;;
        2) menu_category_recon ;;
        3) menu_category_exploit ;;
        4) menu_category_scan ;;
        5) menu_category_lab ;;
        6) menu_category_defense ;;
        [qQ]) return 0 ;;
        *) msg_error "无效选项"; pause; menu_category_nav ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# 注意：不注册到主菜单，由 main.sh 直接调用
# ═══════════════════════════════════════════════════════════════
