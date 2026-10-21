<p align="center">
  <img src="docs/logo.jpg" alt="氢氦集团 Hydrogen Helium Group" width="200">
</p>

<h1 align="center">Ruijie Auto Login</h1>

<p align="center">
  成都信息工程大学校园网（锐捷 ePortal / SMP+ CAS）自动登录工具<br>
  Windows PowerShell · Linux / WSL Shell · Go
</p>

<p align="center">
  <a href="https://github.com/cuit-edu-cn/ruijie-auto-login">原项目</a> ·
  <a href="#quick-start">快速开始</a> ·
  <a href="#config">配置</a> ·
  <a href="#attribution">改编说明</a>
</p>

---

## 1 简介

校园网每次连接都要弹出网页登录认证。本项目可以在不打开网页的情况下自动完成锐捷 ePortal / SMP+ CAS 认证，适合开机自启或后台常驻。

本项目改编自 [cuit-edu-cn/ruijie-auto-login](https://github.com/cuit-edu-cn/ruijie-auto-login)。在原 Shell / Go 版本的基础上，增加了 Windows PowerShell 原生版本、首次运行交互式初始化、运营商适配和更清晰的日志。

<hr>

## 2 特性

- ✅ Windows 原生 PowerShell 版本，不依赖 WSL / Git Bash
- ✅ 终端前台运行，实时打印状态变化和登录过程日志；在线每 1 秒监控，插线自动登录
- ✅ 关闭终端即停止，无后台进程、无自启项、无系统网络设置残留
- ✅ 适配新版锐捷 SMP+ / CAS 门户（AES-ECB 加密登录），并保留旧版 ePortal 接口作为后备
- ✅ 首次运行自动询问学号、密码、运营商，写入配置，之后直接运行
- ✅ 有线 / 无线网络自动识别，显示当前接口和默认路由
- ✅ 支持移动、联通、电信、校园网（含移动编码修复）
- ✅ 掉线自动重新登录，失败后按间隔重试
- ✅ 控制台 + 文件双日志，过程清晰
- ✅ 配置模板化，真实账号密码不进入 Git

## 3 快速开始 <a name="quick-start"></a>

### 3.1 Windows PowerShell（推荐）

1. 下载 / clone 本项目。
2. 双击 `ruijie.bat`，会打开一个终端窗口：
   - 如果还没有账号配置，会在窗口里依次询问学号、密码、运营商，并写入 `shell/ruijie.conf`。
   - 配置完成后，脚本在终端前台运行，每 1 秒检测一次网络；拔插网线后会自动登录。
3. 终端会实时打印断线、登录过程和登录结果；在线监控期间保持安静，不刷屏；日志同时写入 `shell/ruijie.log`。
4. 关闭终端窗口，脚本立即停止；不会留下后台进程、自启项，也不会修改系统网络设置。

其他用法：

```powershell
# 只检测/登录一次后退出（调试）
powershell -NoProfile -ExecutionPolicy Bypass -File .\ruijie-login.ps1 -Once

# 直接前台运行脚本
powershell -NoProfile -ExecutionPolicy Bypass -File .\ruijie-login.ps1
```

> 脚本每 1 秒检测一次，插线后通常几秒内完成登录。Windows 在刚插线时可能仍会短暂弹出“需要登录”的提示；登录完成后会消失。

### 3.2 Linux / WSL Shell

```bash
cd shell
bash ./ruijie-login.sh

# 后台常驻
nohup bash ./ruijie-login.sh >/dev/null 2>&1 &
```

首次运行会自动把 `ruijie.conf.example` 复制成 `ruijie.conf` 并提示填写；填写后再次运行即可。

> Shell 版本目前只适配旧版锐捷 ePortal。新版 SMP+ / CAS 门户请使用 PowerShell 版本。

### 3.3 Go

`auto_login/` 是原项目的 Go 实现，本仓库未改动其逻辑。配置 `configuration.yaml` 后编译运行：

```
UserId:             用户名
Password:           用户密码
Server:             网络服务商，可选参数：
                    移动: 1 | 移动 | yd
                    联通: 2 | 联通 | lt
                    电信: 3 | 电信 | dx
                    校园网: 0 | 教育网 | 校园网 | edu
TimeInterval: 600   时间间隔（秒）
LogPath:            日志文件相对路径（默认 ruijie.log）
LogClearDay: 7      日志清除时间（天）
```

Go 版本的依赖和构建方式请参考原项目。Windows 下推荐直接使用上面的 PowerShell 版本。

## 4 配置说明 <a name="config"></a>

配置文件：`shell/ruijie.conf`

- 该文件已被 `.gitignore` 忽略，**不要提交你的真实账号密码**。
- 模板文件：`shell/ruijie.conf.example`。
- 密码会以明文保存在本地配置文件中（锐捷 ePortal 认证需要明文提交）。

| 字段 | 说明 |
| --- | --- |
| `userId` | 学号 / 账号 |
| `password` | 密码 |
| `timeInterval` | Shell 版的重新登录间隔（秒）；PowerShell 版不再使用 |
| `monitorInterval` | PowerShell 版在线监控间隔（秒），默认 1；拔插网线后快速响应 |
| `log_path` | 日志路径（相对配置文件目录） |
| `log_save_day` | 日志保留天数（Shell 版） |
| `log_clear_day` | 日志清理天数（Shell 版） |
| `network` | 运营商：移动 / 联通 / 电信 / 校园网（新版 SMP+ 会用它自动选择 cmcc / unicom / ctcc；也支持 yd / lt / dx / edu） |

## 5 日志

- PowerShell 版：控制台彩色输出 + `shell/ruijie.log`
- Shell 版：写入 `log_path` 指定的文件

示例：

```
[2026-10-20 22:34:07] [INFO] 账号: 2025xxxxxx    运营商: 移动 (%E7%A7%BB%E5%8A%A8)
[2026-10-20 22:34:09] [INFO] 当前网络接口:
[2026-10-20 22:34:09] [INFO]   以太网  有线  IP=10.18.84.11  网关=10.18.95.254
[2026-10-20 22:34:09] [INFO] 请求默认走: 以太网 (网关 10.18.95.254)
[2026-10-20 22:34:10] [OK] 已在线 (HTTP 204)
```

## 6 改编说明 <a name="attribution"></a>

- 原项目：[cuit-edu-cn/ruijie-auto-login](https://github.com/cuit-edu-cn/ruijie-auto-login)
- 本仓库：[hzhaohe38-lab/Autoconnect-cuitNet](https://github.com/hzhaohe38-lab/Autoconnect-cuitNet)
- 改编人：**Helium**
- 组织：**氢氦集团（Hydrogen Helium Group）**

主要改动：

1. 新增原生 PowerShell 版本（`ruijie-login.ps1`）和双击启动脚本（`ruijie.bat`）
2. 首次运行交互式初始化，自动生成并写入 `shell/ruijie.conf`
3. 修复 Windows 检出导致 Shell 脚本 CRLF 无法运行的问题，新增 `.gitattributes`
4. 修复移动运营商 service 编码多出 `t` 的问题
5. 有线 / 无线网络适配，运行时显示接口与默认路由
6. 改进日志输出，失败重试不再刷屏
7. 新增配置模板，真实配置文件不再纳入 Git
8. 适配新版锐捷 SMP+ / CAS 门户（AES-ECB 密码加密、CAS 表单登录、自动选择运营商）
9. `ruijie.bat` 前台运行并实时打印日志；在线每 2 秒监控，插线自动登录；关闭窗口即停止，无后台残留
10. 修复在线监控间隔过长导致拔插网线后不自动登录的问题

## 7 许可证

本项目沿用原项目的 [Apache License 2.0](LICENSE)。

---

<p align="center">
  <img src="docs/logo.jpg" alt="氢氦集团" width="120"><br>
  <sub>Made with ❤️ by Helium · 氢氦集团</sub>
</p>
