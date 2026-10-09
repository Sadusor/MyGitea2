param([ValidateSet('Start','Stop','Pull')][string]$Action='Start')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $root 'gitea.exe'
$config = Join-Path $root 'custom\conf\app.ini'
$data = Join-Path $root 'mygitea2-data'
$url = 'http://127.0.0.1:3001/'
$extension = Join-Path $PSScriptRoot 'chrome-extension'
. (Join-Path $PSScriptRoot 'MyGitea-Sync.ps1')

function Get-MyGiteaProcesses {
    @(Get-CimInstance Win32_Process -Filter "name='gitea.exe'" |
        Where-Object { $_.ExecutablePath -ieq $exe })
}
function Close-MyGiteaChrome {
    # Identify only Chrome instances using MyGitea2's dedicated profile.
    # Do not close windows belonging to the normal Chrome profile.
    $profile = Join-Path $env:LOCALAPPDATA 'MyGitea2\ChromeProfile'
    $chromeProcesses = @(Get-CimInstance Win32_Process -Filter "name='chrome.exe'")
    $roots = @($chromeProcesses | Where-Object {
        $_.CommandLine -and
        $_.CommandLine.IndexOf('MyGitea2\ChromeProfile', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $_.CommandLine.IndexOf('--user-data-dir', [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($roots.Count -eq 0) { return }
    $managed = @{}
    foreach ($rootProcess in $roots) { $managed[[int]$rootProcess.ProcessId] = $true }
    # Chrome creates child renderer/browser processes. Include only children of
    # the confirmed dedicated-profile process(es).
    for ($pass = 0; $pass -lt 12; $pass++) {
        $changed = $false
        foreach ($proc in $chromeProcesses) {
            if ($managed.ContainsKey([int]$proc.ParentProcessId) -and
                -not $managed.ContainsKey([int]$proc.ProcessId)) {
                $managed[[int]$proc.ProcessId] = $true
                $changed = $true
            }
        }
        if (-not $changed) { break }
    }
    if (-not ('MyGiteaWindowCloser' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class MyGiteaWindowCloser {
    public delegate bool WindowCallback(IntPtr handle, IntPtr state);
    [DllImport("user32.dll")] public static extern bool EnumWindows(WindowCallback callback, IntPtr state);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
}
'@
    }
    $callback = [MyGiteaWindowCloser+WindowCallback] {
        param([IntPtr]$handle, [IntPtr]$state)
        [uint32]$ownerId = 0
        [void][MyGiteaWindowCloser]::GetWindowThreadProcessId($handle, [ref]$ownerId)
        if ($managed.ContainsKey([int]$ownerId) -and
            [MyGiteaWindowCloser]::IsWindowVisible($handle)) {
            [void][MyGiteaWindowCloser]::PostMessage($handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        }
        return $true
    }
    [void][MyGiteaWindowCloser]::EnumWindows($callback, [IntPtr]::Zero)
}
function Stop-MyGitea {
    Close-MyGiteaChrome
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
        # Normalize filesystem paths only; never alter http:// URLs.
        $actual = if ($entry -match '^(HTTP_PORT|HTTP_ADDR|ROOT_URL) =') {
            $ini
        } else {
            $ini.Replace('/', '\')
        }
        if (-not $actual.Contains($entry)) {
            throw "MyGitea2 configuration not fully isolated: missing $entry"
        }
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
        $lines += 'Access-Control-Allow-Headers: Authorization, Content-Type'
    }
    $head = [Text.Encoding]::ASCII.GetBytes(($lines -join [Environment]::NewLine) + [Environment]::NewLine + [Environment]::NewLine)
    $stream.Write($head,0,$head.Length)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Flush()
}
if ($Action -eq 'Stop') {
    Stop-MyGitea
    $controlPath = Join-Path $PSScriptRoot 'MyGitea-Control.ps1'
    Get-CimInstance Win32_Process -Filter "name='powershell.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -and
            $_.CommandLine.IndexOf($controlPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    exit 0
}
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
    Write-Host 'Keep this PowerShell launcher open for Keys, Sync, and Stop controls.'
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
            $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::ASCII,$false,1024,$true)
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
            if ($request -match '^OPTIONS /(?:pull|stop|keys|preview|import) HTTP/') {
                Send-Reply $stream 200 '' $origin
                continue
            }
            if ($headers['authorization'] -cne ('Bearer ' + $token)) {
                Send-Reply $stream 403 'Unauthorized' $origin
                continue
            }
            if ($request -match '^POST /(keys|preview|import) HTTP/') {
                try {
                    $length = 0
                    if ($headers.ContainsKey('content-length')) {
                        $length = [int]$headers['content-length']
                    }
                    if ($length -gt 16384 -or $length -lt 0) { throw 'Request too large.' }
                    $bodyText = ''
                    if ($length -gt 0) {
                        $chars = New-Object char[] $length
                        $offset = 0
                        while ($offset -lt $length) {
                            $n = $reader.Read($chars,$offset,$length-$offset)
                            if ($n -le 0) { throw 'Incomplete request body.' }
                            $offset += $n
                        }
                        $bodyText = -join $chars
                    }
                    $inputData = if ($bodyText) { $bodyText | ConvertFrom-Json } else { $null }
                    if ($request -match '^POST /keys HTTP/') {
                        if ($null -eq $inputData) { throw 'Missing keys.' }
                        $result = Save-MyGiteaKeys ([string]$inputData.github) ([string]$inputData.gitea)
                    } elseif ($request -match '^POST /preview HTTP/') {
                        $result = Get-SyncPreview
                    } else {
                        if ($null -eq $inputData -or [string]::IsNullOrWhiteSpace($inputData.full_name)) { throw 'Missing repository name.' }
                        $result = Import-SyncOne ([string]$inputData.full_name)
                    }
                    Send-Reply $stream 200 (ConvertTo-Json -InputObject $result -Depth 8 -Compress) $origin
                } catch {
                    Send-Reply $stream 500 (ConvertTo-Json -InputObject @{ error=$_.Exception.Message } -Compress) $origin
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
