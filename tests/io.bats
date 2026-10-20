#!/usr/bin/env bats

load test_helper

setup() {
    load_lib common.sh
    load_lib io.sh
    set +e
}

@test "validate_ip接受合法IP" {
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]
    run validate_ip "8.8.8.8"
    [ "$status" -eq 0 ]
}

@test "validate_ip拒绝非法IP" {
    run validate_ip "256.1.1.1"
    [ "$status" -eq 1 ]
    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]
    run validate_ip "not.an.ip.addr"
    [ "$status" -eq 1 ]
}

@test "validate_port接受边界端口1与65535" {
    run validate_port "1"
    [ "$status" -eq 0 ]
    run validate_port "65535"
    [ "$status" -eq 0 ]
}

@test "validate_port拒绝非法端口" {
    run validate_port "0"
    [ "$status" -eq 1 ]
    run validate_port "65536"
    [ "$status" -eq 1 ]
    run validate_port "abc"
    [ "$status" -eq 1 ]
}

@test "confirm接受y返回0" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; confirm "确认?" <<< "y"'
    [ "$status" -eq 0 ]
}

@test "confirm空输入与n返回1" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; set +e; confirm "确认?" <<< ""'
    [ "$status" -eq 1 ]
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; set +e; confirm "确认?" <<< "n"'
    [ "$status" -eq 1 ]
}

@test "confirm对无效输入警告后重新询问" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; set +e; printf "banana\ny\n" | confirm "确认?"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"请输入y或n"* ]]
}

@test "read_password静默读取密码到指定变量" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; read_password "密码" pw <<< "s3cret"; printf "%s" "$pw"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"s3cret"* ]]
}

@test "prompt_host_port回车采用默认端口" {
    local myport
    prompt_host_port "服务" 8080 myport <<< ""
    [ "$?" -eq 0 ]
    [ "$myport" = "8080" ]
}

@test "prompt_host_port接受合法输入" {
    local myport
    prompt_host_port "服务" 8080 myport <<< "9000"
    [ "$?" -eq 0 ]
    [ "$myport" = "9000" ]
}

@test "prompt_host_port拒绝非法端口" {
    local myport
    run prompt_host_port "服务" 8080 myport <<< "99999"
    [ "$status" -eq 1 ]
}
