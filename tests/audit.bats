#!/usr/bin/env bats

load test_helper

@test "全仓库标识符均可解析(防孤儿函数回归)" {
    run bash "$PROJECT_ROOT/tests/check_calls.sh"
    if [ "$status" -ne 0 ]; then
        echo "$output" >&2
        return 1
    fi
}
