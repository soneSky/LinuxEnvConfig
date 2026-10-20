#!/usr/bin/env bats

load test_helper

setup() {
    load_lib common.sh
    load_lib menu.sh
    pause() { :; }
    set +e
}

@test "push_path与pop_path维护面包屑栈" {
    push_path "基础配置"
    push_path "配置DNS"
    [ "${#MENU_PATH[@]}" -eq 2 ]
    [ "${MENU_PATH[1]}" = "配置DNS" ]
    pop_path
    [ "${#MENU_PATH[@]}" -eq 1 ]
}

@test "pop_path对空栈安全返回" {
    MENU_PATH=()
    run pop_path
    [ "${#MENU_PATH[@]}" -eq 0 ]
}

@test "register_main_menu注册菜单项与处理器" {
    MAIN_MENU_ITEMS=()
    MAIN_MENU_HANDLERS=()
    register_main_menu "配置A" "config_a"
    register_main_menu "配置B" "config_b"
    [ "${#MAIN_MENU_ITEMS[@]}" -eq 2 ]
    [ "${MAIN_MENU_HANDLERS[1]}" = "config_b" ]
}

@test "handle_main_menu透传处理函数返回码" {
    MAIN_MENU_ITEMS=()
    MAIN_MENU_HANDLERS=()
    fake_handler() { return 42; }
    register_main_menu "测试" "fake_handler"
    run handle_main_menu 1
    [ "$status" -eq 42 ]
}

@test "handle_main_menu透传处理函数的255取消返回码" {
    MAIN_MENU_ITEMS=()
    MAIN_MENU_HANDLERS=()
    cancel_handler() { return 255; }
    register_main_menu "测试" "cancel_handler"
    run handle_main_menu 1
    [ "$status" -eq 255 ]
}

@test "handle_main_menu对q返回0(退出由主循环判断)" {
    run handle_main_menu "q"
    [ "$status" -eq 0 ]
}

@test "handle_main_menu对无效输入返回0" {
    run handle_main_menu "abc"
    [ "$status" -eq 0 ]
}

@test "handle_main_menu对超范围选项返回0" {
    MAIN_MENU_ITEMS=()
    MAIN_MENU_HANDLERS=()
    run handle_main_menu "99"
    [ "$status" -eq 0 ]
}

@test "handle_main_menu对未注册处理函数返回0" {
    MAIN_MENU_ITEMS=()
    MAIN_MENU_HANDLERS=()
    MAIN_MENU_HANDLERS+=("ghost_handler")
    MAIN_MENU_ITEMS+=("幽灵项")
    run handle_main_menu "1"
    [ "$status" -eq 0 ]
}
