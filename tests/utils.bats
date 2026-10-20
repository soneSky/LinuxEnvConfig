#!/usr/bin/env bats

load test_helper

setup() {
    load_lib common.sh
    load_lib io.sh
    load_lib utils.sh
    set +e
    TEST_TMP="$(mktemp -d)"
    export TEST_TMP
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "backup_file对存在的文件创建带描述的时间戳备份" {
    local f="$TEST_TMP/sources.list"
    echo "deb http://example.com" > "$f"
    run backup_file "$f" ".bak" "测试"
    [ "$status" -eq 0 ]
    [ "$(ls "$f".bak.* 2>/dev/null | wc -l)" -eq 1 ]
}

@test "backup_file对不存在的文件返回1" {
    run backup_file "$TEST_TMP/不存在.txt"
    [ "$status" -eq 1 ]
}

@test "backup_select选中有效编号并设置出参" {
    local f="$TEST_TMP/apt.list"
    echo "origin" > "$f"
    backup_file "$f" ".bak" "t1" >/dev/null
    export TEST_FILE="$f"
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; source "$PROJECT_ROOT/lib/utils.sh"; set +e; backup_select "标题" "$TEST_FILE" "标签" <<< "1"; echo "rc=$?"; echo "$_SELECTED_BACKUP"'
    [ "${lines[0]}" = "rc=0" ]
    [[ "${lines[1]}" == *".bak."* ]]
}

@test "backup_select对0取消返回255" {
    local f="$TEST_TMP/dns.list"
    echo "origin" > "$f"
    backup_file "$f" ".bak" "t1" >/dev/null
    export TEST_FILE="$f"
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; source "$PROJECT_ROOT/lib/utils.sh"; set +e; backup_select "标题" "$TEST_FILE" "标签" <<< "0" >/dev/null 2>&1'
    [ "$status" -eq 255 ]
}

@test "backup_display无备份时返回1" {
    run backup_display "标签"
    [ "$status" -eq 1 ]
}

@test "backup_clear_all确认后清空全部备份" {
    local f="$TEST_TMP/dns.conf"
    echo "x" > "$f"
    backup_file "$f" >/dev/null
    backup_file "$f" >/dev/null
    export TEST_FILE="$f"
    run bash -c 'source "$PROJECT_ROOT/lib/common.sh"; source "$PROJECT_ROOT/lib/io.sh"; source "$PROJECT_ROOT/lib/utils.sh"; set +e; printf "y\ny\n" | backup_clear_all "测试" "$TEST_FILE" >/dev/null 2>&1; echo "rc=$?"; echo "left=$(ls "$TEST_FILE".bak* 2>/dev/null | wc -l)"'
    [ "${lines[0]}" = "rc=0" ]
    [ "${lines[1]}" = "left=0" ]
}

@test "is_package_installed对已安装包返回0" {
    run is_package_installed bash
    [ "$status" -eq 0 ]
}

@test "is_package_installed对未知包返回1" {
    run is_package_installed "definitely_not_a_package_xyz123"
    [ "$status" -eq 1 ]
}

@test "_set_resolved_stub_listener关闭注释态DNSStubListener并保留其余注释项" {
    local conf="$TEST_TMP/resolved.conf"
    printf '[Resolve]\n#DNS=\n#DNSSEC=no\n#DNSStubListener=yes\n#DNSStubListenerExtra=\n#ReadEtcHosts=yes\n' > "$conf"
    run _set_resolved_stub_listener "$conf" "114.114.114.114"
    [ "$status" -eq 0 ]
    [ "$(grep -cE '^[[:space:]]*DNSStubListener[[:space:]]*=[[:space:]]*no$' "$conf")" -eq 1 ]
    [ "$(grep -cE '^[[:space:]]*DNS[[:space:]]*=114\.114\.114\.114$' "$conf")" -eq 1 ]
    [ "$(grep -cE '^[[:space:]]*#DNSStubListenerExtra=' "$conf")" -eq 1 ]
}

@test "_set_resolved_stub_listener缺少配置项时追加且重复执行保持幂等" {
    local conf="$TEST_TMP/resolved.conf"
    printf '[Resolve]\n#ReadEtcHosts=yes\n' > "$conf"
    run _set_resolved_stub_listener "$conf" "114.114.114.114"
    [ "$status" -eq 0 ]
    [ "$(grep -cE '^[[:space:]]*DNSStubListener[[:space:]]*=[[:space:]]*no$' "$conf")" -eq 1 ]
    [ "$(grep -cE '^[[:space:]]*DNS[[:space:]]*=114\.114\.114\.114$' "$conf")" -eq 1 ]
    cp "$conf" "$TEST_TMP/after_first.conf"
    run _set_resolved_stub_listener "$conf" "114.114.114.114"
    [ "$status" -eq 0 ]
    diff -q "$TEST_TMP/after_first.conf" "$conf" >/dev/null
}

@test "_set_resolved_stub_listener不覆盖已生效的DNS配置" {
    local conf="$TEST_TMP/resolved.conf"
    printf '[Resolve]\n#DNS=\nDNS=223.5.5.5\n#DNSStubListener=yes\n' > "$conf"
    run _set_resolved_stub_listener "$conf" "114.114.114.114"
    [ "$status" -eq 0 ]
    [ "$(grep -E '^[[:space:]]*DNS[[:space:]]*=' "$conf" | tail -n 1 | cut -d= -f2 | tr -d ' ')" = "223.5.5.5" ]
    [ "$(grep -cE '^[[:space:]]*DNSStubListener[[:space:]]*=[[:space:]]*no$' "$conf")" -eq 1 ]
}

@test "_resolv_conf_needs_uplink识别仅含stub地址的静态配置" {
    local resolv="$TEST_TMP/resolv.conf"
    printf 'nameserver 127.0.0.53\n' > "$resolv"
    run _resolv_conf_needs_uplink "$resolv"
    [ "$status" -eq 0 ]
    printf 'nameserver 127.0.0.53\nnameserver 223.5.5.5\n' > "$resolv"
    run _resolv_conf_needs_uplink "$resolv"
    [ "$status" -eq 1 ]
    printf 'nameserver 223.5.5.5\n' > "$resolv"
    run _resolv_conf_needs_uplink "$resolv"
    [ "$status" -eq 1 ]
}

@test "_resolv_conf_needs_uplink识别指向stub-resolv.conf的软链接" {
    local resolv="$TEST_TMP/resolv.conf"
    ln -sf /run/systemd/resolve/stub-resolv.conf "$resolv"
    run _resolv_conf_needs_uplink "$resolv"
    [ "$status" -eq 0 ]
}
