# Ruijie Auto Login
```
    ____        _   _ _      ___    __ 
   / __ \__  __(_) (_|_)__  /   |  / / 
  / /_/ / / / / / / / / _ \/ /| | / /  
 / _, _/ /_/ / / / / /  __/ ___ |/ /___
/_/ |_|\__,_/_/_/ /_/\___/_/  |_/_____/
             /___/                     
```


## 1 简介
苦于校园网每次连接都要弹出网页，在网页上登录认证，遂想出此方法一键连接校园网（在不打开网页的情况下）

在这个程序的基础之上可以加一些触发条件比如把这个加到开机自启动里面，这样以后开机就自动联网，不用手动联网了。
<hr>


## 2 当前进度

✅ **Shell**版本实现日志管理  
✅ **GO**版本实现日志管理

<hr/>

## 3 使用方式

### 3.1 Windows PowerShell（推荐）
- 首次运行：双击 `ruijie.bat`，或在仓库根目录运行下面的命令
- 脚本检测到还没有账号信息时，会在控制台依次询问学号、密码、运营商，并自动写入 `shell/ruijie.conf`，然后直接开始运行
- 以后再次运行会自动读取配置，不再询问
- `shell/ruijie.conf` 已被 `.gitignore` 忽略，**不要提交你的真实账号密码**
- 也可以手动把 `shell/ruijie.conf.example` 复制成 `shell/ruijie.conf` 后自行编辑
- 运行：
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\ruijie-login.ps1
  ```
- 也可以直接双击 `ruijie.bat`
- 只检测/登录一次后退出（方便调试）：
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\ruijie-login.ps1 -Once
  ```
- 有线、无线都适用；运行时会打印当前网络接口、默认走哪条线路、检测结果和完整登录过程
- 日志同时输出到控制台和 `shell/ruijie.log`

### 3.2 Linux / WSL Shell
- 首次使用：脚本会自动把 `shell/ruijie.conf.example` 复制成 `shell/ruijie.conf`，填写后再运行
- 或手动复制：`cp shell/ruijie.conf.example shell/ruijie.conf`
- 运行：
  ```bash
  cd shell
  nohup bash ./ruijie-login.sh >/dev/null 2>&1 &
  ```

### 3.3 GO
- configuration.yaml中配置相应项即可，（账号密码、运营商必填）
    - 配置文件说明：
    ```
    UserId:             用户名
    Password:           用户密码
    Server:             网络服务商，可选参数：
                            移动: 1 | 移动 | yd
                            联通: 2 | 联通 | lt
                            电信: 3 | 电信 | dx
                            校园网: 0 | 教育网 | 校园网 | edu
    TimeInterval: 600   时间间隔（s,秒）
    LogPath:            日志文件相对路径（以可执行文件位置为基准,默认为'ruijie.log'）
    LogClearDay: 7      日志清除时间（day）
    ```
- 在对应平台编译后使用
