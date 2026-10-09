param(
    [ValidateSet('Start','Stop','Pull')][string]$Action = 'Start'
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $root 'gitea.exe'
$config = Join-Path $root 'custom\conf\app.ini'
$url = 'http://127.0.0.1:3001/'
$isolatedData = Join-Path $root 'mygitea2-data'
function Ensure-IsolatedConfig {
    if (-not (Test-Path $config)) {
        $confDir = Split-Path $config -Parent
        New-Item -ItemType Directory -Path $confDir -Force | Out-Null
        New-Item -ItemType Directory -Path $isolatedData -Force | Out-Null
        $ini = @"
APP_NAME = MyGitea2
RUN_USER = $env:USERNAME
WORK_PATH = $root
APP_DATA_PATH = $isolatedData

[server]
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3001
ROOT_URL = http://127.0.0.1:3001/
OFFLINE_MODE = true

[database]
DB_TYPE = sqlite3
PATH = $isolatedData\gitea.db

[repository]
ROOT = $isolatedData\repositories

[log]
ROOT_PATH = $isolatedData\log
"@
        [System.IO.File]::WriteAllText($config, $ini)
    }
    $content = Get-Content -Raw $config
    if ($content -notmatch '(?m)^HTTP_PORT\s*=\s*3001\s*$' -or
        $content -notmatch '(?m)^ROOT_URL\s*=\s*http://127\.0\.0\.1:3001/\s*$' -or
        $content -notlike "*PATH = $isolatedData\gitea.db*" -or
        $content -notlike "*ROOT = $isolatedData\repositories*") {
        throw "MyGitea2 config is not confirmed isolated: $config"
    }
}
$script:managedChromePid = $null
function Get-MyGiteaProcesses {
    @(Get-CimInstance Win32_Process -Filter "name='gitea.exe'" |
        Where-Object { $_.ExecutablePath -ieq $exe })
}
function Start-Gitea {
    if (-not (Test-Path $exe)) {
        throw "No gitea.exe in $root. Build or place the executable there before starting."
    }
    Ensure-IsolatedConfig
    if (-not (Get-MyGiteaProcesses)) {
        $args = @('web')
        $args += @('--config', ('"' + $config + '"'))
        Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden | Out-Null
    }
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "Gitea did not respond at $url" }
    $chrome = Get-Command chrome.exe -ErrorAction SilentlyContinue
    if (-not $chrome) {
        foreach ($candidate in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
            if (Test-Path $candidate) { $chrome = @{ Source = $candidate }; break }
        }
    }
    if (-not $chrome) { throw 'Google Chrome is not installed.' }
    $profile = Join-Path $env:LOCALAPPDATA 'MyGitea2\ChromeProfile'
    New-Item -ItemType Directory -Force $profile | Out-Null
    $process = Start-Process -FilePath $chrome.Source -ArgumentList @("--user-data-dir=`"$profile`"",'--app=http://127.0.0.1:3001/','--window-size=1280,850') -PassThru
    $script:managedChromePid = $process.Id
}
function Stop-Gitea {
    foreach ($process in (Get-MyGiteaProcesses)) {
        Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
    }
}
function Pull-Source {
    if (-not (Test-Path (Join-Path $root '.git'))) { throw 'This folder is not a Git checkout.' }
    $dirty = @(git -C $root status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
    if ($dirty.Count -gt 0) { throw 'Local changes detected. Commit or stash before pulling.' }
    $result = & git -C $root pull --ff-only origin main 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($result -join [Environment]::NewLine) }
    return ($result -join [Environment]::NewLine)
}
if ($Action -eq 'Stop') { Stop-Gitea; exit 0 }
if ($Action -eq 'Pull') { Write-Output (Pull-Source); exit 0 }
Start-Gitea
$form = New-Object System.Windows.Forms.Form
$form.Text = 'MyGitea2 - Chrome controls'
$form.Size = New-Object System.Drawing.Size(445,130)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedToolWindow'
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Top'
$panel.Height = 48
$refresh = New-Object System.Windows.Forms.Button
$refresh.Text = 'Auto Check: ON'
$refresh.Width = 125
$pull = New-Object System.Windows.Forms.Button
$pull.Text = 'Pull GitHub'
$pull.Width = 105
$stop = New-Object System.Windows.Forms.Button
$stop.Text = 'Stop Gitea'
$stop.Width = 100
$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Bottom'
$status.Height = 30
$status.Text = 'Gitea running'
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$script:autoRefresh = $true
$timer.Add_Tick({
    if (-not $script:autoRefresh) { return }
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
        $status.Text = "Server OK - $(Get-Date -Format HH:mm:ss)"
    } catch { $status.Text = 'Server unavailable' }
})
$refresh.Add_Click({
    $script:autoRefresh = -not $script:autoRefresh
    $refresh.Text = if ($script:autoRefresh) { 'Auto Check: ON' } else { 'Auto Check: OFF' }
})
$pull.Add_Click({
    try { $status.Text = Pull-Source }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Pull failed') | Out-Null }
})
$stop.Add_Click({ Stop-Gitea; $form.Close() })
$panel.Controls.AddRange(@($refresh,$pull,$stop))
$form.Controls.Add($panel)
$form.Controls.Add($status)
$timer.Start()
$form.Add_FormClosed({ $timer.Stop();$timer.Dispose() })
[void]$form.ShowDialog()
