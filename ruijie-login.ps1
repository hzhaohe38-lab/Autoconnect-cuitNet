#requires -Version 5.1
<#
  Ruijie Auto Login - PowerShell 版
  直接在有线/无线网络下运行，不依赖 WSL 或 Git Bash。

  用法:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\ruijie-login.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\ruijie-login.ps1 -Once
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string[]]$DetectUrl,
    [int]$RetryInterval = 5,
    [string]$PortalUrl,
    [switch]$Once
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 does not load System.Net.Http by default
Add-Type -AssemblyName System.Net.Http

# ---------- 定位配置文件 ----------
$Root = $PSScriptRoot
if (-not $ConfigPath) {
    $c1 = Join-Path $Root 'ruijie.conf'
    $c2 = Join-Path $Root 'shell\ruijie.conf'
    if (Test-Path $c1) {
        $ConfigPath = $c1
    } elseif (Test-Path $c2) {
        $ConfigPath = $c2
    } else {
        # 首次运行：稍后用模板在 shell 目录创建
        $ConfigPath = $c2
    }
}
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$ConfigDir = Split-Path $ConfigPath -Parent
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$examplePath = $null
foreach ($candidate in @(
    (Join-Path $ConfigDir 'ruijie.conf.example'),
    (Join-Path $Root 'shell\ruijie.conf.example')
)) {
    if (Test-Path $candidate) { $examplePath = $candidate; break }
}
if (-not (Test-Path $ConfigPath) -and -not $examplePath) {
    Write-Host '找不到 ruijie.conf，也没有 ruijie.conf.example 模板。' -ForegroundColor Red
    exit 1
}

# ---------- 读取配置 ----------
$cfg = @{}
if (Test-Path $ConfigPath) {
    Get-Content -Path $ConfigPath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { return }
        $key = $line.Substring(0, $i).Trim()
        $val = $line.Substring($i + 1).Trim()
        if ($val.Length -ge 2) {
            $first = $val.Substring(0, 1)
            $last = $val.Substring($val.Length - 1, 1)
            if ($first -eq "'" -and $last -eq "'") {
                $val = $val.Substring(1, $val.Length - 2).Replace("'\''", "'")
            } elseif ($first -eq '"' -and $last -eq '"') {
                $val = $val.Substring(1, $val.Length - 2)
            }
        }
        $cfg[$key] = $val
    }
}

$userId = $cfg['userId']
$password = $cfg['password']
$network = $cfg['network']

$serviceMap = @{
    '移动'   = '%E7%A7%BB%E5%8A%A8'
    'yd'     = '%E7%A7%BB%E5%8A%A8'
    '1'      = '%E7%A7%BB%E5%8A%A8'
    '联通'   = '%E8%81%94%E9%80%9A'
    'lt'     = '%E8%81%94%E9%80%9A'
    '2'      = '%E8%81%94%E9%80%9A'
    '电信'   = '%E7%94%B5%E4%BF%A1'
    'dx'     = '%E7%94%B5%E4%BF%A1'
    '3'      = '%E7%94%B5%E4%BF%A1'
    '校园网' = '%E6%A0%A1%E5%9B%AD%E7%BD%91'
    '教育网' = '%E6%A0%A1%E5%9B%AD%E7%BD%91'
    'edu'    = '%E6%A0%A1%E5%9B%AD%E7%BD%91'
    '0'      = '%E6%A0%A1%E5%9B%AD%E7%BD%91'
}
$serviceNameMap = @{
    '%E7%A7%BB%E5%8A%A8'         = '移动'
    '%E8%81%94%E9%80%9A'         = '联通'
    '%E7%94%B5%E4%BF%A1'         = '电信'
    '%E6%A0%A1%E5%9B%AD%E7%BD%91' = '校园网'
}
function Get-CanonicalNetwork {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $v = $Value.Trim()
    if ($serviceMap.ContainsKey($v)) {
        return $serviceNameMap[$serviceMap[$v]]
    }
    return $null
}

# ---------- 配置写入 ----------
function Set-ConfigValue {
    param([string]$Text, [string]$Key, [string]$Value)
    $escaped = $Value.Replace("'", "'\''")
    $newLine = "$Key='$escaped'"
    $pattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=.*$'
    if ([regex]::IsMatch($Text, $pattern)) {
        return [regex]::Replace($Text, $pattern, $newLine.Replace('$', '$$'))
    }
    return $Text.TrimEnd("`n") + "`n" + $newLine + "`n"
}

function Save-Config {
    param([string]$Path, [string]$UserId, [string]$Password, [string]$Network)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (Test-Path $Path) {
        $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    } elseif ($examplePath -and (Test-Path $examplePath)) {
        $text = [IO.File]::ReadAllText($examplePath, [Text.Encoding]::UTF8)
    } else {
        $text = @(
            '# Ruijie auto login configuration',
            'userId=',
            'password=',
            'timeInterval=3600',
            'log_path=./ruijie.log',
            'log_save_day=7',
            'log_clear_day=0',
            "network='校园网'"
        ) -join "`n"
    }
    $text = $text -replace "`r`n", "`n"
    $text = Set-ConfigValue -Text $text -Key 'userId' -Value $UserId
    $text = Set-ConfigValue -Text $text -Key 'password' -Value $Password
    $text = Set-ConfigValue -Text $text -Key 'network' -Value $Network
    [IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- 首次运行交互 ----------
function Read-UserId {
    param([string]$Default)
    while ($true) {
        $hint = '学号/账号'
        if ($Default) { $hint += " [$Default]" }
        $v = (Read-Host -Prompt $hint).Trim()
        if (-not $v -and $Default) { $v = $Default }
        if ($v) { return $v }
        Write-Host '账号不能为空，请重新输入。' -ForegroundColor Yellow
    }
}

function Read-Password {
    param([string]$Existing)
    while ($true) {
        $hint = '密码'
        if ($Existing) { $hint += '（直接回车保留原密码）' }
        $sec = Read-Host -Prompt $hint -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            $v = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
        if (-not $v -and $Existing) { return $Existing }
        if ($v) { return $v }
        Write-Host '密码不能为空，请重新输入。' -ForegroundColor Yellow
    }
}

function Read-Operator {
    param([string]$Default)
    Write-Host ''
    Write-Host '请选择运营商:'
    Write-Host '  1) 移动'
    Write-Host '  2) 联通'
    Write-Host '  3) 电信'
    Write-Host '  0) 校园网'
    while ($true) {
        $hint = '输入序号或名称'
        if ($Default) { $hint += " [$Default]" }
        $v = (Read-Host -Prompt $hint).Trim()
        if (-not $v -and $Default) { $v = $Default }
        $canonical = Get-CanonicalNetwork $v
        if ($canonical) { return $canonical }
        Write-Host '输入无效，请输入 1/2/3/0 或 移动/联通/电信/校园网。' -ForegroundColor Yellow
    }
}

$currentNetwork = Get-CanonicalNetwork $network
$needAccount = [string]::IsNullOrWhiteSpace($userId) -or [string]::IsNullOrWhiteSpace($password)

if ($needAccount) {
    if ([Console]::IsInputRedirected) {
        Write-Host "配置文件缺少账号信息，且当前不是交互式终端。请先编辑: $ConfigPath" -ForegroundColor Red
        exit 1
    }
    Write-Host ''
    Write-Host '=========================================' -ForegroundColor Cyan
    Write-Host '        首次运行 - 填写账号信息' -ForegroundColor Cyan
    Write-Host '=========================================' -ForegroundColor Cyan
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "将创建配置文件: $ConfigPath"
    }
    $userId = Read-UserId -Default $userId
    $password = Read-Password -Existing $password
    $network = Read-Operator -Default $currentNetwork
    Save-Config -Path $ConfigPath -UserId $userId -Password $password -Network $network
    Write-Host ''
    Write-Host "配置已保存: $ConfigPath" -ForegroundColor Green
    Write-Host '以后直接运行即可，不需要再次输入。' -ForegroundColor Green
    $currentNetwork = Get-CanonicalNetwork $network
} elseif (-not $currentNetwork) {
    if ([Console]::IsInputRedirected) {
        Write-Host "配置文件中的 network 无效: $network" -ForegroundColor Red
        exit 1
    }
    $network = Read-Operator -Default '校园网'
    Save-Config -Path $ConfigPath -UserId $userId -Password $password -Network $network
    Write-Host "配置已保存: $ConfigPath" -ForegroundColor Green
    $currentNetwork = Get-CanonicalNetwork $network
}

if (-not $currentNetwork) {
    Write-Host "未知的 network 值: $network（可选：移动/联通/电信/校园网）" -ForegroundColor Red
    exit 1
}
$service = $serviceMap[$currentNetwork]
$serviceName = $serviceNameMap[$service]
$network = $currentNetwork

# 在线监控间隔（秒）：默认 1 秒，插拔网线后能尽快反应
$interval = 1
if ($cfg.ContainsKey('monitorInterval')) {
    $tmp = 0
    if ([int]::TryParse($cfg['monitorInterval'], [ref]$tmp)) { $interval = $tmp }
}
if ($interval -lt 1) { $interval = 1 }
if ($interval -gt 60) { $interval = 60 }
if ($RetryInterval -lt 3) { $RetryInterval = 3 }

$logPath = 'ruijie.log'
if ($cfg.ContainsKey('log_path') -and $cfg['log_path']) { $logPath = $cfg['log_path'] }
if ([IO.Path]::IsPathRooted($logPath)) {
    $LogFile = $logPath
} else {
    $LogFile = Join-Path $ConfigDir $logPath
}
$LogFile = [IO.Path]::GetFullPath($LogFile)

$DetectUrls = @(
    'http://www.google.cn/generate_204',
    'http://connect.rom.miui.com/generate_204',
    'http://wifi.vivo.com.cn/generate_204'
)
if ($DetectUrl) { $DetectUrls = $DetectUrl }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------- 日志 ----------
function Write-Log {
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level,
        [string]$Message
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'DEBUG' { 'DarkGray' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
    try {
        [IO.File]::AppendAllText($LogFile, $line + "`r`n", $Utf8NoBom)
    } catch {
    }
}

function Get-ShortText {
    param([string]$Text, [int]$Max = 300)
    if (-not $Text) { return '' }
    $s = ($Text -replace '\s+', ' ').Trim()
    if ($s.Length -gt $Max) { return $s.Substring(0, $Max) + '...' }
    return $s
}

# ---------- 网络接口 ----------
$script:LastNetSig = ''
function Write-NetworkInfo {
    $routes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object { $_.RouteMetric + $_.InterfaceMetric })

    $items = @()
    foreach ($r in $routes) {
        $addr = Get-NetIPAddress -InterfaceIndex $r.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $addr) { continue }
        if ($addr.IPAddress -like '169.254.*') { continue }
        $adapter = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
        $alias = if ($adapter) { $adapter.Name } else { "接口$($r.InterfaceIndex)" }
        $items += [pscustomobject]@{
            Alias   = $alias
            IP      = $addr.IPAddress
            Gateway = $r.NextHop
            Metric  = $r.RouteMetric + $r.InterfaceMetric
        }
    }
    $items = @($items | Sort-Object Metric | Group-Object Alias | ForEach-Object { $_.Group[0] })

    $sig = ($items | ForEach-Object { "$($_.Alias)|$($_.IP)|$($_.Gateway)" }) -join ';'
    if ($sig -eq $script:LastNetSig) { return }
    $script:LastNetSig = $sig

    if ($items.Count -eq 0) {
        Write-Log WARN '没有检测到可用网络接口（无默认路由或未获取到 IP）'
        return
    }

    Write-Log INFO '当前网络接口:'
    foreach ($n in $items) {
        $type = '有线'
        if ($n.Alias -match 'WLAN|Wi-Fi|Wireless|无线') { $type = '无线' }
        Write-Log INFO ("  {0}  {1}  IP={2}  网关={3}" -f $n.Alias, $type, $n.IP, $n.Gateway)
    }

    $first = $items | Select-Object -First 1
    Write-Log INFO ("请求默认走: {0} (网关 {1})" -f $first.Alias, $first.Gateway)
}

# ---------- HTTP ----------
function New-Client {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $handler.UseProxy = $false
    $handler.UseCookies = $false
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(8)
    return $client
}

function Invoke-HttpGet {
    param([string]$Url)
    $client = New-Client
    try {
        $resp = $client.GetAsync($Url).GetAwaiter().GetResult()
        $code = [int]$resp.StatusCode
        $body = ''
        if ($resp.Content) {
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        $location = $null
        if ($resp.Headers.Location) { $location = $resp.Headers.Location.ToString() }
        return [pscustomobject]@{ Code = $code; Body = $body; Location = $location }
    } finally {
        $client.Dispose()
    }
}

function Resolve-PortalUrl {
    param([string]$Raw, [string]$BaseUrl)
    $u = [System.Net.WebUtility]::HtmlDecode($Raw).Trim()
    if ($u -match '^//') { $u = 'http:' + $u }
    if ($u -notmatch '^https?://') {
        try {
            $base = New-Object System.Uri($BaseUrl)
            $u = (New-Object System.Uri($base, $u)).AbsoluteUri
        } catch {
        }
    }
    return $u
}

function Get-PortalUrl {
    param([string]$Body, [string]$Location, [string]$BaseUrl)
    if ($Location) { return (Resolve-PortalUrl -Raw $Location -BaseUrl $BaseUrl) }
    if (-not $Body) { return $null }

    $all = @()
    foreach ($m in [regex]::Matches($Body, 'https?://[^\s''"<>]+')) {
        $all += $m.Value
    }
    if ($all.Count -eq 0) { return $null }

    $portal = $all | Where-Object { $_ -match 'index\.jsp|eportal|InterFace\.do' } | Select-Object -First 1
    if (-not $portal) { $portal = $all | Select-Object -First 1 }
    return (Resolve-PortalUrl -Raw $portal -BaseUrl $BaseUrl)
}

# ---------- 联网检测 ----------
function Test-Network {
    foreach ($u in $DetectUrls) {
        try {
            $r = Invoke-HttpGet -Url $u
            if ($r.Code -eq 204) {
                return [pscustomobject]@{ Online = $true; Portal = $null; Code = 204; Source = $u }
            }
            Write-Log DEBUG ("检测 {0} -> HTTP {1}" -f $u, $r.Code)
            $portal = Get-PortalUrl -Body $r.Body -Location $r.Location -BaseUrl $u
            if ($portal) {
                return [pscustomobject]@{ Online = $false; Portal = $portal; Code = $r.Code; Source = $u }
            }
        } catch {
            Write-Log DEBUG ("检测 {0} -> 失败: {1}" -f $u, $_.Exception.Message)
        }
    }
    return [pscustomobject]@{ Online = $false; Portal = $null; Code = $null; Source = $null }
}

# ---------- 新版 SMP+ / CAS 登录 ----------
function New-BrowserClient {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $handler.UseProxy = $false
    $handler.UseCookies = $true
    $handler.CookieContainer = New-Object System.Net.CookieContainer
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36') | Out-Null
    $client.DefaultRequestHeaders.TryAddWithoutValidation('Accept-Language', 'zh-CN,zh;q=0.9') | Out-Null
    return $client
}

function Get-QueryValue {
    param([string]$Url, [string]$Name)
    $m = [regex]::Match($Url, '[?&]' + [regex]::Escape($Name) + '=([^&]*)')
    if ($m.Success) { return [Uri]::UnescapeDataString($m.Groups[1].Value) }
    return $null
}

function Get-HtmlElementText {
    param([string]$Html, [string]$Id)
    $m = [regex]::Match($Html, 'id\s*=\s*["'']' + [regex]::Escape($Id) + '["''][^>]*>([^<]+)<', 'IgnoreCase')
    if ($m.Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim() }
    return $null
}

function Encrypt-AesEcb {
    param([string]$KeyBase64, [string]$PlainText)
    $key = [Convert]::FromBase64String($KeyBase64)
    if ($key.Length -ne 16 -and $key.Length -ne 24 -and $key.Length -ne 32) {
        throw "无效的 AES 密钥长度: $($key.Length)"
    }
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [System.Security.Cryptography.CipherMode]::ECB
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $enc = $aes.CreateEncryptor()
        try {
            $plain = [Text.Encoding]::UTF8.GetBytes($PlainText)
            $cipher = $enc.TransformFinalBlock($plain, 0, $plain.Length)
            return [Convert]::ToBase64String($cipher)
        } finally { $enc.Dispose() }
    } finally { $aes.Dispose() }
}

function Invoke-JsonPost {
    param($Client, [string]$Url, $Body)
    $json = $Body | ConvertTo-Json -Compress
    $content = New-Object System.Net.Http.StringContent($json, [Text.Encoding]::UTF8, 'application/json')
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $Url)
    $origin = ([Uri]$Url).GetLeftPart([UriPartial]::Authority)
    $req.Headers.TryAddWithoutValidation('Origin', $origin) | Out-Null
    $req.Headers.TryAddWithoutValidation('Referer', $Url) | Out-Null
    $req.Headers.TryAddWithoutValidation('Accept', 'application/json, text/plain, */*') | Out-Null
    $req.Content = $content
    $resp = $Client.SendAsync($req).GetAwaiter().GetResult()
    $text = ''
    if ($resp.Content) { $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
    return [pscustomobject]@{ Code = [int]$resp.StatusCode; Body = $text }
}

function Invoke-LoginSmp {
    param([string]$PortalUrl)

    $client = New-BrowserClient
    try {
        Write-Log INFO ("新版门户: 打开认证页 {0}" -f $PortalUrl)
        $resp = $client.GetAsync($PortalUrl).GetAwaiter().GetResult()
        $finalUrl = $resp.RequestMessage.RequestUri.AbsoluteUri
        $html = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        Write-Log DEBUG ("门户最终地址: {0} (HTTP {1})" -f $finalUrl, [int]$resp.StatusCode)

        # 找 CAS 登录 iframe
        $iframeUrl = $null
        $m = [regex]::Match($html, '<iframe[^>]+src\s*=\s*["'']([^"'']*cas-sso/login[^"'']*)["'']', 'IgnoreCase')
        if ($m.Success) {
            $iframeUrl = Resolve-PortalUrl -Raw ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) -BaseUrl $finalUrl
        }
        if (-not $iframeUrl) {
            # 某些页面由 JS 动态创建 iframe，从门户地址参数拼出来
            $sessionId = Get-QueryValue -Url $finalUrl -Name 'sessionId'
            $customPageId = Get-QueryValue -Url $finalUrl -Name 'customPageId'
            $nasIp = Get-QueryValue -Url $finalUrl -Name 'nasIp'
            $userIp = Get-QueryValue -Url $finalUrl -Name 'userIp'
            if ($sessionId -and $customPageId -and $nasIp -and $userIp) {
                $uri = [Uri]$finalUrl
                $timer = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $iframeUrl = ('{0}://{1}/cas-sso/login?flowSessionId={2}&customPageId={3}&preview=false&appType=normal&language=zh-CN&timer={4}&nasIp={5}&userIp={6}' -f $uri.Scheme, $uri.Authority, $sessionId, $customPageId, $timer, $nasIp, $userIp)
            }
        }
        if (-not $iframeUrl) {
            Write-Log WARN '没有找到 CAS 登录页（不是新版 SMP+ 门户）'
            return 'not_smp'
        }
        Write-Log INFO ("CAS 登录页: {0}" -f $iframeUrl)

        $resp2 = $client.GetAsync($iframeUrl).GetAwaiter().GetResult()
        $html2 = $resp2.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $croypto = Get-HtmlElementText -Html $html2 -Id 'login-croypto'
        $execution = Get-HtmlElementText -Html $html2 -Id 'login-page-flowkey'
        if (-not $croypto -or -not $execution) {
            Write-Log ERROR 'CAS 登录页缺少 croypto / execution 参数'
            return 'failed'
        }
        Write-Log DEBUG ("croypto={0}  execution={1}..." -f $croypto, $execution.Substring(0, [Math]::Min(24, $execution.Length)))

        $action = $null
        $fm = [regex]::Match($html2, '<form[^>]*id\s*=\s*["'']normalLoginForm["''][^>]*>', 'IgnoreCase')
        if ($fm.Success) {
            $am = [regex]::Match($fm.Value, 'action\s*=\s*["'']([^"'']*)["'']', 'IgnoreCase')
            if ($am.Success) { $action = [System.Net.WebUtility]::HtmlDecode($am.Groups[1].Value) }
        }
        if (-not $action) { $action = $iframeUrl }
        $action = Resolve-PortalUrl -Raw $action -BaseUrl $iframeUrl
        if ($action -notmatch '(?i)accept-language=') {
            if ($action.Contains('?')) { $action += '&accept-language=zh-CN' } else { $action += '?accept-language=zh-CN' }
        }
        Write-Log INFO ("登录接口: {0}" -f $action)

        $encPassword = Encrypt-AesEcb -KeyBase64 $croypto -PlainText $password
        $encCaptcha = Encrypt-AesEcb -KeyBase64 $croypto -PlainText '{}'

        $fields = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $fields['username'] = $userId
        $fields['type'] = 'UsernamePassword'
        $fields['_eventId'] = 'submit'
        $fields['geolocation'] = ''
        $fields['execution'] = $execution
        $fields['captcha_code'] = ''
        $fields['croypto'] = $croypto
        $fields['password'] = $encPassword
        $fields['captcha_payload'] = $encCaptcha

        $content = New-Object System.Net.Http.FormUrlEncodedContent($fields)
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $action)
        $origin = ([Uri]$action).GetLeftPart([UriPartial]::Authority)
        $req.Headers.TryAddWithoutValidation('Origin', $origin) | Out-Null
        $req.Headers.TryAddWithoutValidation('Referer', $iframeUrl) | Out-Null
        $req.Headers.TryAddWithoutValidation('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8') | Out-Null
        $req.Content = $content

        $resp3 = $client.SendAsync($req).GetAwaiter().GetResult()
        $code = [int]$resp3.StatusCode
        $body3 = ''
        if ($resp3.Content) { $body3 = $resp3.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
        $finalRespUrl = $resp3.RequestMessage.RequestUri.AbsoluteUri
        $finalPath = ([Uri]$finalRespUrl).AbsolutePath
        Write-Log INFO ("服务器返回: HTTP {0}  {1}" -f $code, (Get-ShortText -Text $body3 -Max 200))
        Write-Log DEBUG ("登录最终页面: {0}" -f $finalPath)

        if ($code -eq 401 -or $code -eq 403) {
            Write-Log ERROR 'CAS 返回 401/403：账号或密码错误'
            return 'auth_failed'
        }

        # CAS 成功后，门户流程还要推进：getCurrentNode -> serviceSelection -> setService
        $sessionId = Get-QueryValue -Url $finalUrl -Name 'sessionId'
        if ($sessionId) {
            $baseUri = ([Uri]$finalUrl).GetLeftPart([UriPartial]::Authority)
            $flowKey = Get-QueryValue -Url $finalUrl -Name 'workFlowKey'
            if (-not $flowKey) { $flowKey = 'portal_auth' }
            $nodeUrl = "$baseUri/eportal/workFlow/getCurrentNode"
            $nodeResp = Invoke-JsonPost -Client $client -Url $nodeUrl -Body @{ sessionId = $sessionId; flowKey = $flowKey }
            $node = $null
            try { $node = $nodeResp.Body | ConvertFrom-Json } catch { }
            if ($node -and $node.code -eq 200 -and $node.data) {
                Write-Log INFO ("流程节点: {0}" -f $node.data.currentNodePath)
                if ($node.data.currentNodePath -eq 'serviceSelection') {
                    Write-Log INFO '需要选择运营商，获取可选列表...'
                    $listUrl = "$baseUri/eportal/network/serviceSelection"
                    $listResp = Invoke-JsonPost -Client $client -Url $listUrl -Body @{ sessionId = $sessionId }
                    $listJson = $null
                    try { $listJson = $listResp.Body | ConvertFrom-Json } catch { }
                    if ($listJson -and $listJson.code -eq 200 -and $listJson.data) {
                        $list = @($listJson.data)
                        $names = ($list | ForEach-Object { "$($_.key)($($_.value))" }) -join ', '
                        Write-Log INFO ("可选运营商: {0}" -f $names)
                        $svc = $list | Where-Object { "$($_.key)" -eq $serviceName -or "$($_.value)" -eq $serviceName } | Select-Object -First 1
                        if (-not $svc) {
                            $svc = $list | Where-Object { "$($_.key)" -match $serviceName -or "$($_.value)" -match $serviceName } | Select-Object -First 1
                        }
                        if ($svc) {
                            # 流程里的服务选择使用 serviceLogin（不是 setService；后者是在线切换服务）
                            $setUrl = "$baseUri/eportal/network/serviceLogin"
                            $setResp = Invoke-JsonPost -Client $client -Url $setUrl -Body @{ sessionId = $sessionId; service = $svc.value }
                            $setJson = $null
                            try { $setJson = $setResp.Body | ConvertFrom-Json } catch { }
                            if ($setJson -and $setJson.code -eq 200 -and $setJson.data -and $setJson.data.authResult -eq 'success') {
                                Write-Log OK ("运营商登录成功: {0} ({1})" -f $svc.key, $svc.value)
                                $nodeResp2 = Invoke-JsonPost -Client $client -Url $nodeUrl -Body @{ sessionId = $sessionId; flowKey = $flowKey }
                                $node2 = $null
                                try { $node2 = $nodeResp2.Body | ConvertFrom-Json } catch { }
                                if ($node2 -and $node2.data) {
                                    Write-Log INFO ("流程节点: {0}" -f $node2.data.currentNodePath)
                                }
                            } else {
                                $msg = ''
                                if ($setJson -and $setJson.data) { $msg = "$($setJson.data.message)" }
                                Write-Log ERROR ("运营商登录失败: HTTP {0} {1}" -f $setResp.Code, (Get-ShortText -Text ($msg + ' ' + $setResp.Body) -Max 200))
                            }
                        } else {
                            Write-Log ERROR ("服务列表中没有匹配到运营商: {0}" -f $serviceName)
                        }
                    } else {
                        Write-Log ERROR ("获取运营商列表失败: HTTP {0} {1}" -f $listResp.Code, (Get-ShortText -Text $listResp.Body -Max 200))
                    }
                }
            } else {
                Write-Log WARN ("获取流程节点失败: HTTP {0} {1}" -f $nodeResp.Code, (Get-ShortText -Text $nodeResp.Body -Max 200))
            }
        }

        # CAS 登录成功后，NAS 需要几秒钟才会放行网络；轮询等待，不要立刻重试登录
        if ($finalPath -match 'auth-success') {
            Write-Log OK 'CAS 认证成功，等待网络生效...'
        }
        $online = $false
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 2
            $after = Test-Network
            if ($after.Online) { $online = $true; break }
            Write-Log DEBUG ("等待网络生效... ({0}/20)" -f ($i + 1))
        }
        if ($online) {
            Write-Log OK '登录成功，网络已恢复'
            return 'success'
        }
        Write-Log ERROR '登录请求已发送，但网络仍未恢复'
        return 'failed'
    } catch {
        Write-Log ERROR ("新版门户登录失败: {0}" -f $_.Exception.Message)
        return 'failed'
    } finally {
        $client.Dispose()
    }
}

# ---------- 登录 ----------
function Invoke-LoginLegacy {
    param([string]$PortalUrl)

    $q = ''
    $base = $PortalUrl
    $idx = $PortalUrl.IndexOf('?')
    if ($idx -ge 0) {
        $base = $PortalUrl.Substring(0, $idx)
        $q = $PortalUrl.Substring($idx + 1)
    }

    if ($base -match 'index\.jsp') {
        $loginUrl = $base -replace 'index\.jsp', 'InterFace.do?method=login'
    } else {
        $loginUrl = $base.TrimEnd('/') + '/InterFace.do?method=login'
    }

    # FormUrlEncodedContent will URL-encode the values, so the already-encoded
    # pieces must be reduced to their single-encoded form first:
    #   service     "移动"    -> %E7%A7%BB%E5%8A%A8  (same as the shell version)
    #   queryString a%3Db%26c -> a%253Db%2526c      (same as the shell version)
    $q = $q -replace '&', '%26'
    $q = $q -replace '=', '%3D'

    Write-Log INFO ("认证页: {0}" -f $PortalUrl)
    Write-Log INFO ("登录接口: {0}" -f $loginUrl)
    Write-Log INFO ("运营商: {0} ({1})" -f $serviceName, $service)

    $fields = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $fields['userId'] = $userId
    $fields['password'] = $password
    $fields['service'] = $serviceName
    $fields['queryString'] = $q
    $fields['operatorPwd'] = ''
    $fields['operatorUserId'] = ''
    $fields['validcode'] = ''
    $fields['passwordEncrypt'] = 'false'

    $content = New-Object System.Net.Http.FormUrlEncodedContent($fields)
    $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/x-www-form-urlencoded; charset=UTF-8')

    $cookie = 'EPORTAL_COOKIE_USERNAME=; EPORTAL_COOKIE_PASSWORD=; EPORTAL_COOKIE_SERVER=; EPORTAL_COOKIE_SERVER_NAME=; EPORTAL_AUTO_LAND=; EPORTAL_USER_GROUP=; EPORTAL_COOKIE_OPERATORPWD=;'

    $client = New-Client
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $loginUrl)
        $req.Headers.TryAddWithoutValidation('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36') | Out-Null
        $req.Headers.TryAddWithoutValidation('Referer', $PortalUrl) | Out-Null
        $req.Headers.TryAddWithoutValidation('Cookie', $cookie) | Out-Null
        $req.Headers.TryAddWithoutValidation('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8') | Out-Null
        $req.Content = $content

        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $code = [int]$resp.StatusCode
        $body = ''
        if ($resp.Content) {
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        Write-Log INFO ("服务器返回: HTTP {0}  {1}" -f $code, (Get-ShortText -Text $body -Max 300))
    } catch {
        Write-Log ERROR ("提交登录请求失败: {0}" -f $_.Exception.Message)
        return $false
    } finally {
        $client.Dispose()
    }

    Start-Sleep -Seconds 2
    $after = Test-Network
    if ($after.Online) {
        Write-Log OK '登录成功，网络已恢复'
        return $true
    }
    Write-Log ERROR '登录请求已发送，但网络仍未恢复'
    return $false
}

# ---------- 主流程 ----------
Write-Host ''
Write-Host '=========================================' -ForegroundColor Cyan
Write-Host '           Ruijie Auto Login' -ForegroundColor Cyan
Write-Host '=========================================' -ForegroundColor Cyan
Write-Log INFO ("配置文件: {0}" -f $ConfigPath)
Write-Log INFO ("日志文件: {0}" -f $LogFile)
Write-Log INFO ("账号: {0}    运营商: {1} ({2})" -f $userId, $serviceName, $service)
Write-Log INFO ("在线监控间隔: {0} 秒    失败重试间隔: {1} 秒" -f $interval, $RetryInterval)
Write-Log INFO ("检测地址: {0}" -f ($DetectUrls -join ', '))
Write-Host '=========================================' -ForegroundColor Cyan
Write-Host ''

if ($PortalUrl) {
    Write-NetworkInfo
    $status = Invoke-LoginSmp -PortalUrl $PortalUrl
    if ($status -eq 'not_smp') {
        if (Invoke-LoginLegacy -PortalUrl $PortalUrl) { $status = 'success' } else { $status = 'failed' }
    }
    if ($status -eq 'success') { exit 0 } else { exit 1 }
}

$exitCode = 0
$lastOnline = $null
while ($true) {
    Write-NetworkInfo
    $state = Test-Network

    if ($state.Online) {
        if ($lastOnline -ne $true) {
            Write-Log OK ("已在线 (HTTP 204, 检测: {0})，开始监控..." -f $state.Source)
            $lastOnline = $true
        }
        if ($Once) { break }
        Start-Sleep -Seconds $interval
        continue
    }

    $lastOnline = $false
    if (-not $state.Portal) {
        Write-Log WARN ("网络不可达，{0} 秒后重试" -f $RetryInterval)
        if ($Once) { $exitCode = 1; break }
        Start-Sleep -Seconds $RetryInterval
        continue
    }

    Write-Log WARN ("未登录 (HTTP {0})，开始自动登录..." -f $state.Code)
    $smp = Invoke-LoginSmp -PortalUrl $state.Portal
    $ok = $false
    if ($smp -eq 'success') {
        $ok = $true
    } elseif ($smp -eq 'not_smp') {
        Write-Log WARN '回退到旧版锐捷 ePortal 接口...'
        $ok = Invoke-LoginLegacy -PortalUrl $state.Portal
    }
    if ($ok) {
        $exitCode = 0
        Write-Log OK '登录完成，继续监控...'
    } else {
        $exitCode = 1
        Write-Log WARN ("登录失败，{0} 秒后重试" -f $RetryInterval)
    }

    if ($Once) { break }
    if (-not $ok) { Start-Sleep -Seconds $RetryInterval }
}

exit $exitCode
