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
#  📝 模块描述 : 灯塔 ARL-Next 资产侦察系统配置模块
#  📁 文件路径 : modules/arl.sh
#  👤 作者信息 : mingy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ═══════════════════════════════════════════════════════════════
# 全局变量定义
# ═══════════════════════════════════════════════════════════════

readonly ARL_DIR="/opt/docker_arl"
readonly ARL_DEFAULT_PORT="5173"
readonly ARL_WEB_IMAGE="crpi-laul1izptqrf0tkf.cn-beijing.personal.cr.aliyuncs.com/owl234-arl-prod/arl-web:latest"
readonly ARL_TMP_CONTAINER="arl-temp"
readonly ARL_COMPOSE_FILE="docker-compose.prod.yml"
readonly ARL_WEB_CONTAINER="arl-web-prod"
readonly ARL_MONGO_CONTAINER="arl-mongodb-prod"
readonly ARL_MONGO_URI="mongodb://admin:admin@127.0.0.1:27017/arl?authSource=admin"
readonly ARL_CONTAINER_DICT_DIR="/code/backend/app/dicts"
readonly ARL_CONTAINER_PATTERN="arl-(web|worker|frontend)-prod|arl_(web|worker)"
readonly ARL_FINGER_GIT_URL="https://gitee.com/yijingsec/ARL-Finger-ADD.git"

# ═══════════════════════════════════════════════════════════════
# 内部辅助函数
# ═══════════════════════════════════════════════════════════════

get_python_command() {
    if command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null; then
        echo "python"
    else
        return 1
    fi
}

extract_arl_deploy_files() {
    local image="$1"
    local dest="$2"

    msg_info "正在拉取 ARL-Next 镜像: ${image}"
    if ! (set -o pipefail; sudo docker pull "${image}" 2>&1 | sed 's/^/  /'); then
        msg_error "镜像拉取失败, 请检查网络或镜像地址"
        return 1
    fi

    sudo docker rm -f "${ARL_TMP_CONTAINER}" >/dev/null 2>&1 || true
    if ! sudo docker create --name "${ARL_TMP_CONTAINER}" "${image}" >/dev/null; then
        msg_error "创建临时容器失败"
        return 1
    fi

    local path
    for path in /code/start-prod.sh /code/docker-compose.prod.yml /code/frontend; do
        msg_info "正在从镜像提取 ${path} ..."
        if ! (set -o pipefail; sudo docker cp "${ARL_TMP_CONTAINER}:${path}" "${dest}/" 2>&1 | sed 's/^/  /'); then
            msg_error "提取 ${path} 失败"
            sudo docker rm -f "${ARL_TMP_CONTAINER}" >/dev/null 2>&1 || true
            return 1
        fi
    done

    for path in /code/updater /code/version.txt; do
        msg_info "正在从镜像提取 ${path} ..."
        if ! (set -o pipefail; sudo docker cp "${ARL_TMP_CONTAINER}:${path}" "${dest}/" 2>&1 | sed 's/^/  /'); then
            msg_warning "提取 ${path} 失败, 将跳过对应可选功能"
        fi
    done

    sudo docker rm -f "${ARL_TMP_CONTAINER}" >/dev/null 2>&1 || true
    return 0
}

arl_compose_path() {
    echo "${ARL_DIR}/${ARL_COMPOSE_FILE}"
}

arl_get_host_port() {
    local extracted_port=""
    local compose_path
    compose_path=$(arl_compose_path)
    if [[ -f "${compose_path}" ]]; then
        extracted_port=$(grep -oE "[0-9]+:${ARL_DEFAULT_PORT}" "${compose_path}" | head -n 1 | cut -d: -f1 || true)
    fi
    echo "${extracted_port:-${ARL_DEFAULT_PORT}}"
}

open_arl_firewall_port() {
    local port="$1"
    if command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null; then
        sudo firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
        sudo firewall-cmd --reload >/dev/null 2>&1 || true
    elif command -v ufw &>/dev/null; then
        sudo ufw allow "${port}/tcp" >/dev/null 2>&1 || true
    fi
}

set_arl_host_port() {
    local new_port="$1"
    local current_port
    current_port=$(arl_get_host_port)

    [[ "${new_port}" == "${current_port}" ]] && return 0

    msg_info "正在将ARL映射端口从${current_port}修改为${new_port}..."
    sudo sed -i -E "s/- [\"']?[0-9]+:${ARL_DEFAULT_PORT}[\"']?/- \"${new_port}:${ARL_DEFAULT_PORT}\"/" "$(arl_compose_path)"
    open_arl_firewall_port "${new_port}"
}


# ═══════════════════════════════════════════════════════════════
# ARL配置主菜单
# ═══════════════════════════════════════════════════════════════

config_arl() {
    while true; do
        show_submenu "ARL灯塔配置" \
            "安装ARL" \
            "停止ARL" \
            "启动ARL" \
            "卸载ARL" \
            "查看ARL状态" \
            "修改常用配置"

        local choice
        local ret
        msg_prompt "请选择操作 [0-6, q退出]"

        case $choice in
            0) return ;;
            q|Q) exit 0 ;;
            1) install_arl ;;
            2) stop_arl ;;
            3) start_arl ;;
            4) remove_arl ;;
            5) show_arl_status ;;
            6) modify_arl_config; ret=$?; [[ $ret -eq 255 ]] && continue ;;
            *) msg_error "无效选择" ;;
        esac
        pause
    done
}

# ═══════════════════════════════════════════════════════════════
# 安装灯塔ARL
# ═══════════════════════════════════════════════════════════════

install_arl() {
    check_docker || return 1
    check_docker_compose || return 1
    show_section "安装灯塔ARL (ARL-Next)"

    if [[ -d "${ARL_DIR}" ]]; then
        msg_success "检测到灯塔ARL已安装, 路径: ${ARL_DIR}"
        return 0
    fi

    local host_ip
    prompt_host_ip "灯塔ARL" || return 1

    local host_port
    prompt_host_port "灯塔ARL" "${ARL_DEFAULT_PORT}" "host_port" || return 1

    msg_info "正在创建ARL安装目录..."
    sudo mkdir -p "${ARL_DIR}"

    extract_arl_deploy_files "${ARL_WEB_IMAGE}" "${ARL_DIR}" || {
        sudo rm -rf "${ARL_DIR}"
        return 1
    }
    sudo chmod +x "${ARL_DIR}/start-prod.sh"

    msg_info "正在执行 ARL-Next 一键部署 (安装依赖 / 生成证书 / 拉取镜像 / 启动服务)..."
    if ! (cd "${ARL_DIR}" && sudo bash ./start-prod.sh); then
        msg_error "ARL-Next 部署失败, 请根据上方日志排查后通过「启动ARL」重试"
        return 1
    fi

    if [[ "${host_port}" != "${ARL_DEFAULT_PORT}" ]]; then
        set_arl_host_port "${host_port}"
        msg_info "正在按新端口重建前端容器..."
        (cd "${ARL_DIR}" && sudo "${COMPOSE_CMD[@]}" -f "${ARL_COMPOSE_FILE}" up -d arl-frontend >/dev/null 2>&1) || \
            msg_warning "前端容器重建失败, 请手动执行 docker compose -f ${ARL_COMPOSE_FILE} up -d arl-frontend"
    fi

    show_access_info \
        "访问地址: https://${host_ip}:${host_port}" \
        "平台账号: admin" \
        "初始密码: docker exec ${ARL_WEB_CONTAINER} cat /tmp/arl_initial_admin_password" \
        "网关 Basic Auth (默认关闭): admin / arl_next"
    msg_warning "登录后请尽快修改默认密码!"
}

# ═══════════════════════════════════════════════════════════════
# 停止灯塔ARL
# ═══════════════════════════════════════════════════════════════

stop_arl() {
    show_section "停止灯塔ARL"
    if [[ ! -d "${ARL_DIR}" ]]; then
        msg_error "未找到ARL安装目录, 请先安装"
        return 1
    fi
    docker_compose_stop "${ARL_DIR}" "灯塔ARL" -f "${ARL_COMPOSE_FILE}"
}

# ═══════════════════════════════════════════════════════════════
# 启动灯塔ARL
# ═══════════════════════════════════════════════════════════════

start_arl() {
    show_section "启动灯塔ARL"
    if [[ ! -d "${ARL_DIR}" ]]; then
        msg_error "未找到ARL安装目录, 请先安装"
        return 1
    fi

    local host_ip
    prompt_host_ip "灯塔ARL" || return 1

    local current_port
    current_port=$(arl_get_host_port)

    local host_port
    prompt_host_port "灯塔ARL" "${current_port}" "host_port" || return 1

    set_arl_host_port "${host_port}"

    if docker_compose_start "${ARL_DIR}" "灯塔ARL" "up" -f "${ARL_COMPOSE_FILE}"; then
        show_access_info \
            "访问地址: https://${host_ip}:${host_port}" \
            "平台账号: admin" \
            "登录密码: 首次部署生成的初始密码 (容器内 /tmp/arl_initial_admin_password)" \
            "网关 Basic Auth (默认关闭): admin / arl_next"
        msg_warning "登录后请尽快修改默认密码!"
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 查看灯塔ARL状态
# ═══════════════════════════════════════════════════════════════

show_arl_status() {
    show_section "灯塔ARL状态信息"
    show_compose_status_table "${ARL_DIR}" "ARL" -f "${ARL_COMPOSE_FILE}"
}

# ═══════════════════════════════════════════════════════════════
# 卸载灯塔ARL
# ═══════════════════════════════════════════════════════════════

remove_arl() {
    show_section "卸载灯塔ARL"
    check_docker_compose || return 1

    if [[ -d "${ARL_DIR}" ]]; then
        if confirm "检测到ARL安装目录, 确定要删除吗?"; then
            msg_info "停止并清理ARL容器..."
            cd "${ARL_DIR}" || return 1
            sudo "${COMPOSE_CMD[@]}" -f "${ARL_COMPOSE_FILE}" down -v >/dev/null 2>&1

            msg_info "清理安装目录..."
            cd ~ || return 1
            sudo rm -rf "${ARL_DIR}"
            msg_success "物理环境清理完成"
        fi
    else
        msg_info "未检测到ARL安装目录, 跳过物理清理"
    fi

    local images
    images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "(^|/)arl(-|:)" | grep -v "TAG" || true)
    
    if [[ -n "$images" ]]; then
        echo -e "  ${YELLOW}发现相关镜像:${NC}"
        echo "    - ${images//$'\n'/$'\n'    - }"
        if confirm "是否删除上述ARL相关Docker镜像?"; then
            msg_info "正在清理镜像..."
            echo "$images" | while read -r img; do
                sudo docker rmi "$img" >/dev/null 2>&1 && msg_info "已删除: $img" | sed 's/^/  /'
            done
            msg_success "镜像清理操作完成"
        fi
    fi

    msg_success "灯塔ARL卸载流程执行完毕"
}

# ═══════════════════════════════════════════════════════════════
# 给ARL添加指纹
# ═══════════════════════════════════════════════════════════════

add_fingerprint_to_arl() {
    show_section "给ARL添加指纹"
    
    if [[ ! -d "${ARL_DIR}" ]]; then
        msg_error "未找到ARL安装目录, 无法添加指纹"
        return 1
    fi

    cd "${ARL_DIR}" || return 1

    local arl_ip
    prompt_host_ip "灯塔ARL" "arl_ip" || return 1

    local current_port
    current_port=$(arl_get_host_port)

    local arl_port
    prompt_host_port "灯塔ARL" "${current_port}" "arl_port" || return 1
    
    local arl_pass
    read -r -p "  ${CYAN}请输入ARL的登录密码: ${NC}" arl_pass
    if [[ -z "${arl_pass}" ]]; then
        msg_error "密码不能为空"
        return 1
    fi

    msg_info "准备指纹更新脚本..."
    sudo rm -rf "${ARL_DIR}/ARL-Finger-ADD"
    local clone_success=false
    if sudo git clone "${ARL_FINGER_GIT_URL}" "${ARL_DIR}/ARL-Finger-ADD" 2>&1 | sed 's/^/  /'; then
        clone_success=true
    fi

    if $clone_success; then
        cd "${ARL_DIR}/ARL-Finger-ADD" || { sudo rm -rf "${ARL_DIR}/ARL-Finger-ADD"; return 1; }
        
        local py_cmd
        py_cmd=$(get_python_command)
        if [[ -n "$py_cmd" ]]; then
            if ! sudo "$py_cmd" -c "import requests" >/dev/null 2>&1; then
                msg_info "正在安装requests依赖包..."
                local install_success=false
                if sudo "$py_cmd" -m pip install requests --break-system-packages >/dev/null 2>&1 || \
                   sudo "$py_cmd" -m pip install requests >/dev/null 2>&1; then
                    install_success=true
                elif is_package_available "python3-requests" && sudo apt-get install -y python3-requests >/dev/null 2>&1; then
                    install_success=true
                fi
                if ! $install_success; then
                    msg_warning "requests依赖包安装失败"
                fi
            fi
            msg_info "正在执行指纹添加 (这可能需要一些时间)..."
            sudo "$py_cmd" ARL-Finger-ADD.py "https://${arl_ip}:${arl_port}/" "admin" "${arl_pass}" >/dev/null 2>&1
            action "指纹添加任务已完成" "指纹添加任务执行失败"
        else
            msg_error "需要 Python 环境"
        fi
        
        cd "${ARL_DIR}" || true
        sudo rm -rf "${ARL_DIR}/ARL-Finger-ADD"
    else
        msg_error "克隆指纹项目失败"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# ARL-Next 配置读写工具
# ARL-Next2 的配置统一存放于 MongoDB system_config 集合，
# 与 Web 端「系统设置」同一数据源，修改后约30秒内自动生效。
# ═══════════════════════════════════════════════════════════════

arl_mongo_available() {
    sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${ARL_MONGO_CONTAINER}"
}

arl_mongo_eval() {
    local js="$1"
    shift
    if ! arl_mongo_available; then
        msg_error "未检测到运行中的 ${ARL_MONGO_CONTAINER} 容器, 请先启动ARL"
        return 1
    fi
    sudo docker exec "$@" "${ARL_MONGO_CONTAINER}" mongosh "${ARL_MONGO_URI}" --quiet --eval "${js}"
}

arl_config_get() {
    local key="$1"
    arl_mongo_eval 'const d = db.system_config.findOne({_id: "general_config"}) || {}; const v = d[process.env.ARL_CFG_KEY]; if (v === undefined || v === null) { print(""); } else if (typeof v === "object") { print(JSON.stringify(v)); } else { print(String(v)); }' -e "ARL_CFG_KEY=${key}"
}

arl_config_set() {
    local key="$1"
    local json_value="$2"
    arl_mongo_eval 'const v = JSON.parse(process.env.ARL_CFG_VALUE); db.system_config.updateOne({_id: "general_config"}, {$set: {[process.env.ARL_CFG_KEY]: v}}, {upsert: true}); db.system_config.updateOne({_id: "_config_cache_version"}, {$inc: {version: 1}}, {upsert: true});' -e "ARL_CFG_KEY=${key}" -e "ARL_CFG_VALUE=${json_value}" >/dev/null
}

arl_plugin_web_python() {
    local code="$1"
    if ! sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${ARL_WEB_CONTAINER}"; then
        msg_error "未检测到运行中的 ${ARL_WEB_CONTAINER} 容器, 请先启动ARL"
        return 1
    fi
    sudo docker exec -w /code/backend "${ARL_WEB_CONTAINER}" \
        /code/backend/.venv-docker/bin/python3 -c "${code}"
}

arl_plugin_get_all() {
    arl_plugin_web_python 'from app.config import Config; import json; print("ARL_JSON:" + json.dumps(Config.QUERY_PLUGIN_CONFIG))' 2>/dev/null | grep "^ARL_JSON:" | head -n 1 | sed 's/^ARL_JSON://'
}

arl_plugin_get() {
    local plugin="$1"
    local field="$2"
    arl_plugin_web_python "from app.config import Config; v = (Config.QUERY_PLUGIN_CONFIG.get('${plugin}') or {}).get('${field}', ''); print('ARL_VAL:' + (('true' if v is True else 'false') if isinstance(v, bool) else str(v)))" 2>/dev/null | grep "^ARL_VAL:" | head -n 1 | sed 's/^ARL_VAL://'
}

arl_plugin_set() {
    local plugin="$1"
    local field="$2"
    local value="$3"
    local value_type="$4"

    local plugin_json
    plugin_json=$(arl_plugin_get_all) || return 1
    if [[ -z "${plugin_json}" ]]; then
        msg_error "读取ARL三方插件配置失败"
        return 1
    fi

    arl_mongo_eval 'const q = JSON.parse(process.env.ARL_PLUGIN_CFG || "{}"); q[process.env.ARL_PLUGIN] = q[process.env.ARL_PLUGIN] || {}; if (process.env.ARL_VALUE_TYPE === "bool") { q[process.env.ARL_PLUGIN][process.env.ARL_FIELD] = process.env.ARL_VALUE === "true"; } else { q[process.env.ARL_PLUGIN][process.env.ARL_FIELD] = process.env.ARL_VALUE; } db.system_config.updateOne({_id: "general_config"}, {$set: {query_plugin_config: q}}, {upsert: true}); db.system_config.updateOne({_id: "_config_cache_version"}, {$inc: {version: 1}}, {upsert: true});' -e "ARL_PLUGIN_CFG=${plugin_json}" -e "ARL_PLUGIN=${plugin}" -e "ARL_FIELD=${field}" -e "ARL_VALUE=${value}" -e "ARL_VALUE_TYPE=${value_type}" >/dev/null
}

arl_get_forbidden_domains() {
    arl_mongo_eval 'const d = db.system_config.findOne({_id: "security_policy"}) || {}; const list = Array.isArray(d.forbidden_domains) ? d.forbidden_domains : []; print(list.join("\n"));'
}

arl_add_forbidden_domain() {
    local domain="$1"
    arl_mongo_eval 'const d = db.system_config.findOne({_id: "security_policy"}) || {}; const list = Array.isArray(d.forbidden_domains) ? d.forbidden_domains : []; if (!list.includes(process.env.ARL_DOMAIN)) { list.push(process.env.ARL_DOMAIN); } db.system_config.updateOne({_id: "security_policy"}, {$set: {forbidden_domains: list}}, {upsert: true}); db.system_config.updateOne({_id: "_config_cache_version"}, {$inc: {version: 1}}, {upsert: true});' -e "ARL_DOMAIN=${domain}" >/dev/null
}

arl_del_forbidden_domain() {
    local domain="$1"
    arl_mongo_eval 'const d = db.system_config.findOne({_id: "security_policy"}) || {}; const list = (Array.isArray(d.forbidden_domains) ? d.forbidden_domains : []).filter(function (x) { return x !== process.env.ARL_DOMAIN; }); db.system_config.updateOne({_id: "security_policy"}, {$set: {forbidden_domains: list}}, {upsert: true}); db.system_config.updateOne({_id: "_config_cache_version"}, {$inc: {version: 1}}, {upsert: true});' -e "ARL_DOMAIN=${domain}" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# 修改 ARL 常用配置菜单与具体逻辑
# ═══════════════════════════════════════════════════════════════

modify_arl_config() {
    if [[ ! -d "${ARL_DIR}" ]]; then
        msg_error "未找到ARL安装目录, 请先安装"
        pause
        return 1
    fi

    if ! arl_mongo_available; then
        msg_error "未检测到运行中的 ${ARL_MONGO_CONTAINER} 容器, 请先启动ARL服务"
        pause
        return 1
    fi

    push_path "修改ARL常用配置"
    while true; do
        show_submenu "修改ARL常用配置" \
            "修改FOFA API" \
            "修改三方 API" \
            "管理禁止域名" \
            "修改爆破字典路径" \
            "添加指纹" \
            "修改登录密码" \
            "应用配置并重启服务"

        local choice
        msg_prompt "请选择操作 [0-7, q退出]"

        case $choice in
            0) pop_path; return ;;
            q|Q) exit 0 ;;
            1) modify_arl_fofa; pause ;;
            2) modify_arl_thirdparty_api; ret=$?; [[ $ret -eq 255 ]] && continue; pause ;;
            3) manage_arl_forbidden_domains ;;
            4) modify_arl_dict ;;
            5) add_fingerprint_to_arl; pause ;;
            6) change_arl_password; pause ;;
            7) restart_arl_services; pause ;;
            *) msg_error "无效选择"; pause ;;
        esac
    done
    pop_path
}

modify_arl_fofa() {
    show_section "修改 FOFA API"

    local current_key current_url
    current_key=$(arl_config_get "fofa_key" || echo "")
    current_url=$(arl_config_get "fofa_url" || echo "")

    msg_info "当前 FOFA 地址: ${current_url:-未配置}"
    msg_info "当前 FOFA Key : ${current_key:-未配置}"
    msg_info "ARL-Next 已无需配置 FOFA 邮箱"
    draw_line "-"

    local key
    read -r -p "  ${CYAN}请输入新的 FOFA Key (回车保持不变): ${NC}" key
    key="${key:-$current_key}"

    if arl_config_set "fofa_key" "\"${key}\""; then
        msg_success "FOFA Key 已保存 (约30秒内自动生效)"
    else
        msg_error "FOFA Key 保存失败"
        return 1
    fi
}

modify_arl_thirdparty_api() {
    push_path "修改三方 API"
    while true; do
        show_submenu "修改三方 API" \
            "奇安信 Hunter (hunter_qax)" \
            "360 Quake (quake_360)" \
            "钟馗之眼 ZoomEye (zoomeye)" \
            "Chaos (chaos)" \
            "VirusTotal (virustotal)" \
            "SecurityTrails (securitytrails)"

        local choice
        msg_prompt "请选择操作 [0-6, q退出]"
        [[ "$choice" == "0" ]] && { pop_path; return 255; }
        [[ "$choice" =~ ^[qQ]$ ]] && { pop_path; return 255; }

        local plugin_name=""
        local token_key="api_key"
        case $choice in
            1) plugin_name="hunter_qax"; token_key="api_key" ;;
            2) plugin_name="quake_360"; token_key="quake_token" ;;
            3) plugin_name="zoomeye"; token_key="api_key" ;;
            4) plugin_name="chaos"; token_key="api_key" ;;
            5) plugin_name="virustotal"; token_key="api_key" ;;
            6) plugin_name="securitytrails"; token_key="api_key" ;;
            *) msg_error "无效选择"; pause; continue ;;
        esac

        show_section "配置 $plugin_name"
        local current_key; current_key=$(arl_plugin_get "$plugin_name" "$token_key" || echo "")
        local current_enable; current_enable=$(arl_plugin_get "$plugin_name" "enable" || echo "")
        current_enable="${current_enable:-true}"

        msg_info "当前API Key/Token : ${current_key:-未配置}"
        msg_info "当前启用状态      : ${current_enable}"
        draw_line "-"

        local new_key
        read -r -p "  ${CYAN}请输入新的 API Key/Token (回车保持不变): ${NC}" new_key
        new_key="${new_key:-$current_key}"

        local enable_choice
        if confirm "是否启用该插件?"; then
            enable_choice="true"
        else
            enable_choice="false"
        fi

        if ! arl_plugin_set "$plugin_name" "$token_key" "$new_key" "string"; then
            msg_error "$plugin_name 配置保存失败"
            pause
            continue
        fi
        if ! arl_plugin_set "$plugin_name" "enable" "$enable_choice" "bool"; then
            msg_error "$plugin_name 启用状态保存失败"
            pause
            continue
        fi

        msg_success "$plugin_name 配置已保存 (约30秒内自动生效)"
        break
    done
    pop_path
}

manage_arl_forbidden_domains() {
    push_path "管理禁止域名"
    while true; do
        show_submenu "禁止域名操作" \
            "新增禁止域名" \
            "删除禁止域名"

        local domains
        domains=$(arl_get_forbidden_domains || echo "")

        local domain_list=()
        if [[ -n "$domains" ]]; then
            mapfile -t domain_list <<< "$domains"
        fi

        draw_line "-"
        if [[ ${#domain_list[@]} -eq 0 ]]; then
            msg_warning "当前无禁止域名配置"
        else
            msg_info "当前已配置的禁止域名:"
            local i
            for i in "${!domain_list[@]}"; do
                echo -e "      ${GREEN}$((i+1)).${NC} ${domain_list[$i]}"
            done
        fi
        draw_line "-"

        local choice
        msg_prompt "请选择操作 [0-2, q退出]"
        [[ "$choice" == "0" ]] && { pop_path; return; }
        [[ "$choice" =~ ^[qQ]$ ]] && { pop_path; return; }

        case $choice in
            1)
                local new_domain
                read -r -p "  ${CYAN}请输入要新增的域名 (例如 company.com): ${NC}" new_domain
                if [[ -z "$new_domain" ]]; then
                    msg_error "域名不能为空"
                    pause
                    continue
                fi
                if arl_add_forbidden_domain "$new_domain"; then
                    msg_success "已成功新增禁止域名: $new_domain"
                else
                    msg_error "新增禁止域名失败"
                fi
                ;;
            2)
                if [[ ${#domain_list[@]} -eq 0 ]]; then
                    msg_error "当前没有禁止域名可供删除"
                    continue
                fi
                local del_idx
                read -r -p "  ${CYAN}请输入要删除的域名编号 (1-${#domain_list[@]}): ${NC}" del_idx
                if ! [[ "$del_idx" =~ ^[0-9]+$ ]] || [[ "$del_idx" -lt 1 ]] || [[ "$del_idx" -gt ${#domain_list[@]} ]]; then
                    msg_error "无效编号"
                    pause
                    continue
                fi
                local del_domain="${domain_list[$((del_idx-1))]}"
                if arl_del_forbidden_domain "$del_domain"; then
                    msg_success "已成功删除禁止域名: $del_domain"
                else
                    msg_error "删除禁止域名失败"
                fi
                ;;
            *)
                msg_error "无效选择"
                ;;
        esac
        pause
    done
    pop_path
}

update_arl_dict_file() {
    local config_key="$1"
    local containers="$2"
    local dict_name="$3"

    local local_path
    read -r -p "  ${CYAN}请输入本地${dict_name}的绝对路径: ${NC}" local_path
    if [[ -z "$local_path" ]]; then
        msg_error "路径不能为空"
        pause
        return 1
    fi
    if [[ ! -f "$local_path" ]]; then
        msg_error "本地文件不存在: $local_path"
        pause
        return 1
    fi

    local filename; filename=$(basename "$local_path")
    local container_path="${ARL_CONTAINER_DICT_DIR}/$filename"

    local copy_failed=false
    if [[ -n "$containers" ]]; then
        local c
        for c in $containers; do
            msg_info "正在复制 $filename 到容器 $c 的 ${ARL_CONTAINER_DICT_DIR}/ ..."
            if sudo docker cp "$local_path" "$c:$container_path" 2>&1 | sed 's/^/  /'; then
                msg_success "成功复制到容器 $c"
            else
                msg_error "复制到容器 $c 失败"
                copy_failed=true
            fi
        done
    fi

    if $copy_failed; then
        msg_error "由于容器复制过程出现错误，未更新数据库中的字典路径"
        pause
        return 1
    fi

    if arl_config_set "$config_key" "\"${container_path}\""; then
        msg_success "字典路径已更新为: $container_path (约30秒内自动生效)"
    else
        msg_error "字典路径保存失败"
    fi
    pause
}

modify_arl_dict() {
    push_path "修改爆破字典路径"
    while true; do
        show_submenu "修改爆破字典路径" \
            "修改域名爆破字典" \
            "修改文件泄漏字典"

        local current_domain_dict; current_domain_dict=$(arl_config_get "domain_dict" || echo "")
        local current_file_leak_dict; current_file_leak_dict=$(arl_config_get "file_leak_dict" || echo "")

        draw_line "-"
        msg_info "当前域名爆破字典: ${current_domain_dict:-未配置}"
        msg_info "当前文件泄漏字典: ${current_file_leak_dict:-未配置}"
        draw_line "-"

        local containers
        containers=$(sudo docker ps -a --format '{{.Names}}' | grep -E "${ARL_CONTAINER_PATTERN}" || true)
        if [[ -z "$containers" ]]; then
            msg_warning "未检测到 ARL 容器，字典文件将在下次启动或手动复制后生效"
        fi

        local choice
        msg_prompt "请选择修改的字典 [0-2, q退出]"
        [[ "$choice" == "0" ]] && { pop_path; return; }
        [[ "$choice" =~ ^[qQ]$ ]] && { pop_path; return; }

        case $choice in
            1)
                update_arl_dict_file "domain_dict" "$containers" "域名爆破字典"
                ;;
            2)
                update_arl_dict_file "file_leak_dict" "$containers" "文件泄漏字典"
                ;;
            *)
                msg_error "无效选择"
                pause
                ;;
        esac
    done
    pop_path
}

restart_arl_services() {
    if confirm "要立即重启 ARL 服务以应用新配置吗?"; then
        docker_compose_stop "${ARL_DIR}" "灯塔ARL" -f "${ARL_COMPOSE_FILE}"
        docker_compose_start "${ARL_DIR}" "灯塔ARL" "up" -f "${ARL_COMPOSE_FILE}"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 修改ARL登录密码
# ═══════════════════════════════════════════════════════════════

change_arl_password() {
    show_section "修改ARL登录密码"
    if [[ ! -d "${ARL_DIR}" ]]; then
        msg_error "未找到ARL安装目录, 请先安装"
        return 1
    fi

    if ! sudo docker ps --format '{{.Names}}' | grep -qx "${ARL_WEB_CONTAINER}"; then
        msg_error "未检测到运行中的 ${ARL_WEB_CONTAINER} 容器, 请确保ARL服务已启动"
        return 1
    fi

    local arl_pass
    read -r -p "  ${CYAN}请输入新的ARL登录密码 (至少12位): ${NC}" arl_pass
    if [[ ${#arl_pass} -lt 12 ]]; then
        msg_error "密码长度不足12位"
        return 1
    fi

    msg_info "正在修改ARL登录密码..."
    if sudo docker exec -e "ARL_ADMIN_PASSWORD=${arl_pass}" "${ARL_WEB_CONTAINER}" \
        /code/backend/.venv-docker/bin/python3 /code/backend/inject_user.py --reset; then
        msg_success "ARL登录密码修改成功!"
        msg_info "新密码为: ${arl_pass}"
    else
        msg_error "修改ARL密码失败, 请检查 ${ARL_WEB_CONTAINER} 容器状态或日志"
        return 1
    fi
}

register_main_menu "配置ARL · 灯塔资产侦察系统" "config_arl"
