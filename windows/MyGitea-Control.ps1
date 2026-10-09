param([ValidateSet('Start','Stop','Pull')][string]$Action='Start')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $root 'gitea.exe'
$config = Join-Path $root 'custom\conf\app.ini'
$data = Join-Path $root 'mygitea2-data'
$url = 'http://127.0.0.1:3001/'
$extension = Join-Path $PSScriptRoot 'chrome-extension'

function Get-MyGiteaProcesses {
    @(Get-CimInstance Win32_Process -Filter "name='gitea.exe'" |
        Where-Object { $_.ExecutablePath -ieq $exe })
}
function Stop-MyGitea {
    foreach ($proc in (Get-MyGiteaProcesses)) {
        Stop-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
    }
}
function Pull-MyGiteaSource {
    $dirty = @(git -C $root status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) { throw 'Git status failed' }
    if ($dirty.Count -gt 0) { throw 'Tracked changes detected. Pull refused.' }
    $output = & git -C $root pull --ff-only origin main 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
    return ($output -join [Environment]::NewLine)
}
function Ensure-IsolatedConfig {
    if (-not (Test-Path $config)) {
        New-Item -ItemType Directory -Force (Split-Path $config -Parent) | Out-Null
        New-Item -ItemType Directory -Force $data | Out-Null
        $ini = @"
APP_NAME = MyGitea2
RUN_USER = $env:USERNAME
WORK_PATH = $root
APP_DATA_PATH = $data

[server]
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3001
ROOT_URL = http://127.0.0.1:3001/
OFFLINE_MODE = true
LFS_START_SERVER = true
LFS_CONTENT_PATH = $data\lfs

[database]
DB_TYPE = sqlite3
PATH = $data\gitea.db

[repository]
ROOT = $data\repositories

[log]
ROOT_PATH = $data\log

[attachment]
PATH = $data\attachments

[picture]
AVATAR_UPLOAD_PATH = $data\avatars
REPOSITORY_AVATAR_UPLOAD_PATH = $data\repo-avatars

[lfs]
PATH = $data\lfs
"@
        [IO.File]::WriteAllText($config, $ini)
    }
    $ini = Get-Content -Raw $config
    $required = @(
        'HTTP_PORT = 3001',
        'HTTP_ADDR = 127.0.0.1',
        'ROOT_URL = http://127.0.0.1:3001/',
        "APP_DATA_PATH = $data",
        "PATH = $data\gitea.db",
        "ROOT = $data\repositories",
        "LFS_CONTENT_PATH = $data\lfs"
    )
    foreach ($entry in $required) {
        if (-not $ini.Contains($entry)) {
            throw "MyGitea2 configuration not fully isolated: missing $entry"
        }
    }
    if ($ini -notmatch '(?m)^\[lfs\]') {
        Add-Content -Path $config -Value ([Environment]::NewLine + '[lfs]' + [Environment]::NewLine + "PATH = $data\lfs")
    }
}
function Find-Chrome {
    $cmd = Get-Command chrome.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($candidate in $paths) {
        if (Test-Path $candidate) { return $candidate }
    }
    throw 'Google Chrome not found.'
}
function Send-Reply {
    param($stream, [int]$code, [string]$body, [string]$origin)
    $reason = if ($code -eq 200) { 'OK' } else { 'Error' }
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $lines = @(
        "HTTP/1.1 $code $reason",
        'Content-Type: text/plain; charset=utf-8',
        "Content-Length: $($bytes.Length)",
        'Cache-Control: no-store',
        'Connection: close'
    )
    if ($origin -match '^chrome-extension://[a-z]{32}$') {
        $lines += "Access-Control-Allow-Origin: $origin"
        $lines += 'Access-Control-Allow-Methods: POST, OPTIONS'
        $lines += 'Access-Control-Allow-Headers: Authorization'
    }
    $head = [Text.Encoding]::ASCII.GetBytes(($lines -join [Environment]::NewLine) + [Environment]::NewLine + [Environment]::NewLine)
    $stream.Write($head,0,$head.Length)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Flush()
}
if ($Action -eq 'Stop') { Stop-MyGitea; exit 0 }
if ($Action -eq 'Pull') { Pull-MyGiteaSource; exit 0 }
if (-not (Test-Path $exe)) { throw "Missing executable: $exe" }
if (-not (Test-Path (Join-Path $extension 'manifest.json'))) { throw 'Chrome toolbar extension missing' }
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,3002)
$listener.Start()
try {
    Ensure-IsolatedConfig
    if (-not (Get-MyGiteaProcesses)) {
        Start-Process -FilePath $exe -ArgumentList @('web','--config',('"' + $config + '"')) -WorkingDirectory $root -WindowStyle Hidden | Out-Null
    }
    $ready = $false
    for ($i=0;$i -lt 40;$i++) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $ready=$true;break }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "MyGitea2 not responding at $url" }
    $chrome = Find-Chrome
    $profile = Join-Path $env:LOCALAPPDATA 'MyGitea2\ChromeProfile'
    New-Item -ItemType Directory -Force $profile | Out-Null
    $token = [guid]::NewGuid().ToString()
    $chromeArgs = @(
        ('--user-data-dir="' + $profile + '"'),
        ('--load-extension="' + $extension + '"'),
        '--no-first-run',
        ('--app=' + $url + '#mygitea2-token=' + $token),
        '--window-size=1280,850'
    )
    Start-Process -FilePath $chrome -ArgumentList $chromeArgs | Out-Null
    Write-Host "MyGitea2: $url"
    Write-Host 'Keep this PowerShell launcher open for Pull and Stop controls.'
    while ($true) {
        if (-not $listener.Pending()) {
            Start-Sleep -Milliseconds 150
            continue
        }
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 2500
            $client.SendTimeout = 2500
            $stream = $client.GetStream()
            $reader = New-Object IO.StreamReader($stream,[Text.Encoding]::ASCII,$false,1024,$true)
            $request = $reader.ReadLine()
            $headers = @{}
            while ($true) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($line)) { break }
                $colon = $line.IndexOf(':')
                if ($colon -gt 0) {
                    $headers[$line.Substring(0,$colon).Trim().ToLowerInvariant()] = $line.Substring($colon+1).Trim()
                }
            }
            $origin = [string]$headers['origin']
            if ($request -match '^OPTIONS /(?:pull|stop) HTTP/') {
                Send-Reply $stream 200 '' $origin
                continue
            }
            if ($headers['authorization'] -cne ('Bearer ' + $token)) {
                Send-Reply $stream 403 'Unauthorized' $origin
                continue
            }
            if ($request -match '^POST /pull HTTP/') {
                try {
                    $result = Pull-MyGiteaSource
                    Send-Reply $stream 200 $result $origin
                } catch {
                    Send-Reply $stream 500 $_.Exception.Message $origin
                }
            } elseif ($request -match '^POST /stop HTTP/') {
                Send-Reply $stream 200 'MyGitea2 stopping' $origin
                Stop-MyGitea
                break
            } else {
                Send-Reply $stream 404 'Unknown command' $origin
            }
        } catch {
            Write-Warning $_.Exception.Message
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
