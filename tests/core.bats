#!/usr/bin/env bats

load test_helper

setup() {
    load_lib common.sh
    load_lib core.sh
    set +e
}

@test "command_exists对存在的命令返回0" {
    run command_exists bash
    [ "$status" -eq 0 ]
}

@test "command_exists对不存在的命令返回1" {
    run command_exists "definitely_not_a_command_xyz123"
    [ "$status" -eq 1 ]
}

@test "check_os识别支持的系统并导出OS变量" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/core.sh"; check_os; echo "$OS_ID"'
    [ "$status" -eq 0 ]
    case "$output" in
        ubuntu|kali|debian) ;;
        *) fail "OS_ID=$output 不在支持列表中" ;;
    esac
}

@test "get_distro_id返回OS_ID" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/core.sh"; OS_ID="kali"; get_distro_id'
    [ "$output" = "kali" ]
}

@test "get_distro_codename对空值回退为unknown" {
    run bash -c 'source "$PROJECT_ROOT/lib/core.sh"; get_distro_codename'
    [ "$output" = "unknown" ]
}
