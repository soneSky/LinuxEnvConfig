#!/usr/bin/env bats

load test_helper

setup() {
    load_lib common.sh
    set +e
    TEST_STDIN="$(mktemp)"
    export TEST_STDIN
}

teardown() {
    rm -f "$TEST_STDIN"
}

@test "str_display_width计算ASCII宽度" {
    run str_display_width "abc"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "str_display_width计算中文为双列宽度" {
    run str_display_width "中文"
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

@test "str_display_width忽略ANSI颜色码" {
    run str_display_width "  ${RED}[INFO]${NC} abc"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
}

@test "str_display_width对空字符串返回0" {
    run str_display_width ""
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "action在上条命令成功时输出成功消息" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; true; action "成功文案" "失败文案"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ OK ]"*"成功文案"* ]]
}

@test "action在上条命令失败时输出失败消息" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; false; action "成功文案" "失败文案"'
    [ "$status" -eq 1 ]
    [[ "$output" == *"[FAIL]"*"失败文案"* ]]
}

@test "msg_prompt将输入写入指定变量" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; msg_prompt "请输入" myvar <<< "hello"; printf "%s" "$myvar"'
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "msg_prompt默认写入choice变量" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; msg_prompt "请输入" <<< "42"; printf "%s" "$choice"'
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
}

@test "msg_prompt_required对空输入重试直到非空" {
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; set +eu; printf "\n\nvalue\n" > "$TEST_STDIN"; msg_prompt_required "必填项" myvar < "$TEST_STDIN"; printf "%s" "$myvar"'
    [ "$status" -eq 0 ]
    [ "$output" = "value" ]
}
