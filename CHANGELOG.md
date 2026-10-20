# 更新日志

本项目遵循[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)规范,版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 变更
- 重构`unlock_dns_port`:按53端口实际监听者判定占用(取代服务状态推断,修复dnsmasq/docker-proxy占用时漏判),幂等改写resolved.conf(就地改写优先于追加,不覆盖已生效的DNS),保留并确保systemd-resolved开机自启,/etc/resolv.conf软链接改为服务重启且上游配置就绪后建立(此前先建链接后启动,启动失败即悬空),仅当指向stub/悬空/纯stub地址时才接管resolv.conf,改后实测DNS解析验收
- dnscat2安装/直连/中继启动前,53端口释放失败现在会中止后续流程(此前仅告警仍继续,容器必然因端口冲突启动失败)

### 修复
- `unlock_dns_port`:`ln -sfn`建立/etc/resolv.conf软链接失败时误报成功,现检查失败并报错
- `unlock_dns_port`:systemd-resolved处于disabled但运行中状态时,建立指向上游配置的软链接会在重启后导致DNS失效,现确保开机自启

## [2.1.0] - 2026-08-30

### 新增
- 框架层新增`docker_deploy_container`(封装拉取/清理/创建/健康等待)与`docker_confirm_reinstall`(重装确认),7个单容器模块改为声明式配置+薄包装,净减约500行重复代码
- 框架层新增`show_compose_status_table`(支持额外compose参数),统一ARL/DeepAudit/ScopeSentry/XingRin四份完全相同的状态表实现
- 新增lib/update.sh承接项目自更新与Kali GPG管理,网络库回归纯网络职责
- 错误诊断机制(lib/debug.sh):异常退出时自动记录失败命令/文件位置/完整调用栈到/var/log/lec/error.log,终端给出查看指引;`--debug`参数或`LEC_DEBUG=1`开启全输出镜像日志(带时间戳,含会话头)
- 实例锁:基于flock防止多实例并发运行
- 工程化地基:新增.gitignore/.gitattributes/.editorconfig仓库规范文件,LICENSE换行符规范化为LF
- Makefile一键质量检查:`make lint`(shellcheck静态检查)/`make syntax`(bash -n语法检查)/`make test`(bats单元测试)/`make check`(全部)
- Gitee Go持续集成流水线(.workflow/MasterPipeline.yml)
- bats单元测试覆盖lib层核心函数(排版宽度/输入校验/OS识别/菜单栈与调度/备份管理/端口交互)

### 修复
- 修复输入流结束(EOF)时的死循环:菜单/pause/confirm等读取点遇到EOF会无限刷屏,现统一优雅退出并渲染告别屏(Ctrl-D安全)
- 修复`unlock_dns_port`依赖lsof且端口空闲时lsof返回非零导致的崩溃,增加`ss`回退与容错
- 修复Docker状态视图中磁盘占用永远为空的问题(`grep "Total"`大小写不匹配docker表头)
- 修复模块顶层`declare -A`因在函数作用域内加载而变成局部变量的问题:APT镜像表`APT_MIRRORS`在运行时不可见导致自动选速应用时报"unbound variable",COLORS表存在同类隐患;均改为`declare -gA`全局声明,并在审计测试中新增"顶层声明加载后必须可见"检查
- 修复`auto_select_mirror`与DNS测试中调用已迁移函数`check_network_connection`导致的"command not found"(统一改用`check_ip_connectivity`)
- main.sh:预检系统信息查询失败不再导致启动中断(回退"未知")
- lib/utils.sh:Docker Compose操作改为子shell执行不再污染工作目录;compose启停状态显式检查;镜像存在性改为精确匹配(修复子串误判);`docker_wait_healthy`计数器与scopesentry重试计数器的`((count++))`在set -e下的隐患
- lib/utils.sh:`check_docker_compose`在独立compose安装失败时正确返回失败而非误报成功
- lib/network.sh:git更新前检测本地未提交修改并要求确认(不再静默丢弃);tarball更新备份扩展至lib/与modules/且解压/覆盖失败即报错;远程版本比较改用sort -V并兼容v前缀标签
- modules:AWVS/BeEF/BlueLotus/CTFd/Empire重装前检测已有容器并确认(对齐vulfocus/ocr-api模式),预清理docker rm -f容错
- modules:8处docker_pull_image失败现在正确中断部署流程(此前失败后继续执行导致误导性报错)

### 变更
- 模块层规范化:补齐缺失的`local choice`声明与遗漏的`pause`;统一`register_main_menu`引号风格;scopesentry子菜单标题对齐;hfish镜像引用收敛为readonly常量;移除3个模块重复的`set -euo pipefail`
- jdk模块合并重复的环境变量写入与alternatives注册逻辑,提取`_register_jdk_alternatives`/`_write_jdk_env_file`
- xingrin模块消除5处`COMPOSE_CMD`动态遮蔽,profile参数统一经`_xingrin_profile_args`+helper透传;修复`tr`引号解析笔误
- metasploit/xingrin的裸`apt-get`调用迁移至`install_packages`/新增的`purge_package`
- docker.sh的`daemon-reload`改用新增的`systemctl_reload`包装
- 异常退出时不再渲染告别屏,避免清屏覆盖错误指引
- 修复层间反向依赖:lib/utils.sh不再自动调用模块的Docker安装(改为明确提示),lib/network.sh不再调用模块的DNS配置(改为提示用户通过菜单修复),53端口释放函数移入lib/utils.sh供多模块共用
- 系统信息查询函数归入lib/core.sh,部署参数交互函数(prompt_host_ip/port)归入lib/io.sh
- 主循环直接判断q/Q退出,菜单处理函数返回的255(嵌层取消)不再导致整个程序退出,消除各模块手工拦截的脆弱约定
- main.sh预加载循环封装为函数,循环变量局部化;系统信息面板拆分为独立函数并复用统一排版原语;移除不存在的docker-compose核心模块配置
- compose模块安装路径统一收敛至docker_compose_start(支持透传额外参数),scopesentry不再直接调用内部渲染函数
- docker_compose_remove卸载时询问是否同时删除数据卷(默认保留,与原行为兼容)
- 告别屏统一由EXIT trap渲染,模块内exit 0不再绕过
- install.sh移除未使用的颜色变量定义
