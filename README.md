# sing-box VPS Skill

一个用于 Codex 的 VPS 节点部署 Skill。输入一台全新 Debian/Ubuntu VPS 的公网 IPv4 地址，从 Mac 通过 SSH 安装 sing-box，配置 VLESS + Reality，尝试开启 BBR，并生成 Clash Party 与 Shadowrocket 客户端配置。

## 能做什么

- 检查 SSH、系统类型、现有 sing-box 配置及 TCP 443 端口占用。
- 从 sing-box 官方 APT 仓库安装服务，生成新的 UUID、Reality 密钥和 short ID。
- 写入服务配置，运行 `sing-box check`，启动服务并检查监听状态。
- 在内核支持时开启 BBR 和 `fq`；记录实际结果。
- 检测 VPS 的系统配置、出口 IP 与地理信息、VPS 到 Cloudflare 的下载速度，以及 Mac 到 VPS 的 TCP 连接时间。
- 生成完整的 Clash Party YAML、小火箭 VLESS 链接和 JSON 报告。

项目结构：`SKILL.md` 是 Codex 入口，`scripts/deploy.py` 是 Mac 端命令，`scripts/remote_deploy.sh` 在 VPS 上运行，`references/deploy.md` 记录操作边界与手工排查步骤。

## 准备

- Mac 上有 Python 3 和 OpenSSH。
- 一台全新的 Debian/Ubuntu VPS，已允许 root 通过 SSH 登录；默认 SSH 端口为 22。
- 能核对首次 SSH 连接显示的主机指纹。指纹变化时先在 VPS 服务商控制台确认。
- 服务商安全组允许入站 TCP 443。脚本只会在 UFW 已启用时增加 VPS 内的 443 规则，不会替你修改服务商控制台。

## 使用

在 Mac 终端，从仓库目录运行：

```bash
python3 scripts/deploy.py 203.0.113.10 --name MY-VPS
```

把示例 IP 换成你自己的 VPS 公网 IPv4。如果 SSH 端口不是 22：

```bash
python3 scripts/deploy.py 203.0.113.10 --ssh-port 2222 --name MY-VPS
```

成功后会在 `~/.codex/vps-nodes/<IP>/` 生成：

| 文件 | 用途 |
| --- | --- |
| `clash.yaml` | 导入 Clash Party / Mihomo 的完整配置 |
| `shadowrocket.txt` | 粘贴到 Shadowrocket 的 VLESS 链接 |
| `report.json` | 服务、BBR、IP 信息和探针结果 |

这些文件包含可使用节点的客户端凭据，目录权限为 `0700`，文件权限为 `0600`，请勿提交到公开仓库。Reality **私钥只留在 VPS**。

也可以把这个仓库作为 Codex Skill 安装到 `~/.codex/skills/sing-box-vps/`，之后直接说“用 `$sing-box-vps` 部署这台 VPS”。

## 部署后验证

脚本能确认服务端配置通过检查、sing-box 正在监听，以及 Mac 能否连接 TCP 443。客户端仍需导入并选中节点，才能确认代理真正可用。在 Clash Party 的本地 HTTP 代理端口为 7890 时，可在 Mac 上运行：

```bash
curl -x http://127.0.0.1:7890 --connect-timeout 10 -s https://ipinfo.io/ip
```

输出应是预期的 VPS 出口 IP；出口 IP 有时与入站 IP 不同。测速可运行：

```bash
curl -x http://127.0.0.1:7890 --connect-timeout 10 -L -o /dev/null -w 'speed=%{speed_download} B/s time=%{time_total}s code=%{http_code}\n' 'https://speed.cloudflare.com/__down?bytes=5000000'
```

VPS 本机下载速度与客户端经 VPS 下载速度不是同一个指标。仓库内置的是轻量探针，不包含流媒体解锁、回程线路或完整硬件跑分。没有直接执行第三方 `curl | sh` 检测脚本。

## 安全边界

若 `/etc/sing-box/config.json` 已存在、TCP 443 被占用、系统不是 Debian/Ubuntu 或 SSH 主机密钥不可信，脚本会停止。它不会覆盖已有节点，也不会自动删除旧配置。已有节点的迁移与故障排查请看 [部署说明](references/deploy.md)。

## 本地检查

```bash
python3 scripts/test_deploy.py
bash -n scripts/remote_deploy.sh
```

这些测试只验证本地配置生成和脚本语法，不代表已经在真实 VPS 上完成端到端部署。

## 项目信息

- 类型：Codex Skill + Python/Bash 命令行工具
- 支持：Mac 发起部署；VPS 为 Debian/Ubuntu、systemd、root SSH
- 协议：VLESS + Reality，TCP 443，XTLS Vision
- 客户端：Clash Party（Mihomo）、Shadowrocket
- 上游：[sing-box 官方文档](https://sing-box.sagernet.org/)
- 许可证：暂未指定；公开可读不代表授予复制或再分发许可
