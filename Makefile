SHELL := /usr/bin/env bash

SH_FILES := main.sh install.sh $(wildcard lib/*.sh) $(wildcard modules/*.sh)
BATS_FILES := $(wildcard tests/*.bats)

.PHONY: check lint syntax test

check: lint syntax test

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "[FAIL] 未安装shellcheck(apt install shellcheck)"; exit 1; }
	@echo "[INFO] 正在执行shellcheck静态检查($(words $(SH_FILES))个文件)..."
	@shellcheck $(SH_FILES)
	@echo "[ OK ] shellcheck静态检查通过"

syntax:
	@set -e; for f in $(SH_FILES); do bash -n "$$f"; done
	@echo "[ OK ] bash -n语法检查通过($(words $(SH_FILES))个文件)"

test:
	@command -v bats >/dev/null 2>&1 || { echo "[FAIL] 未安装bats(apt install bats)"; exit 1; }
	@echo "[INFO] 正在执行bats单元测试..."
	@bats $(BATS_FILES)
