# MyGitea2 DPAPI vault and preview-first GitHub migration. Local only.
$script:keyFile = Join-Path $env:LOCALAPPDATA 'MyGitea2\keys.dpapi.json'
function Save-MyGiteaKeys {
 param([string]$github,[string]$gitea)
 if ([string]::IsNullOrWhiteSpace($github) -or [string]::IsNullOrWhiteSpace($gitea)) { throw 'Both tokens required.' }
 New-Item -ItemType Directory -Force (Split-Path $script:keyFile -Parent) | Out-Null
 $record = @{
  github = (ConvertTo-SecureString $github -AsPlainText -Force | ConvertFrom-SecureString)
  gitea = (ConvertTo-SecureString $gitea -AsPlainText -Force | ConvertFrom-SecureString)
 }
 [IO.File]::WriteAllText($script:keyFile,(ConvertTo-Json -InputObject $record -Compress))
 'Saved Windows-user encrypted keys.'
}
function Get-MyGiteaKeys {
 if (-not (Test-Path $script:keyFile)) { throw 'Save both API keys first.' }
 $record = Get-Content -Raw $script:keyFile | ConvertFrom-Json
 $output = @{}
 foreach ($name in @('github','gitea')) {
  $secure = ConvertTo-SecureString $record.$name
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $output[$name] = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
 }
 $output
}
function Invoke-SyncApi {
 param([string]$uri,[string]$token,[string]$method='GET',$body=$null,[switch]$github)
 $headers = @{ Authorization=('token '+$token); Accept='application/json'; 'User-Agent'='MyGitea2-Local-Sync' }
 if ($github) { $headers.Authorization=('Bearer '+$token);$headers['X-GitHub-Api-Version']='2022-11-28' }
 $parameters = @{ Uri=$uri; Headers=$headers; Method=$method; TimeoutSec=45; ErrorAction='Stop' }
 if ($null -ne $body) { $parameters.ContentType='application/json';$parameters.Body=ConvertTo-Json -InputObject $body -Depth 6 -Compress }
 Invoke-RestMethod @parameters
}
function Expand-RepoArray {
 param($value)
 if ($null -eq $value) { return @() }
 $items = @($value)
 while ($items.Count -eq 1 -and $items[0] -is [array]) {
  $items = @($items[0])
 }
 return $items
}
function Get-SyncPreview {
 $keys = Get-MyGiteaKeys
 $me = Invoke-SyncApi ($url+'api/v1/user') $keys.gitea
 $gh = Invoke-SyncApi 'https://api.github.com/user' $keys.github -github
 $source = @()
 for ($i=1;$i -le 100;$i++) {
  $raw = Invoke-SyncApi "https://api.github.com/user/repos?per_page=100&page=$i&affiliation=owner" $keys.github -github
  $batch = @(Expand-RepoArray $raw)
  foreach ($r in $batch) {
   if ($r -is [array] -or -not ($r.full_name -is [string]) -or $r.full_name -notmatch '^[^/]+/[^/]+
  $source += $batch
  if ($batch.Count -lt 100) { break }
 }
 $dest = @{}
 for ($i=1;$i -le 100;$i++) {
  $raw = Invoke-SyncApi ($url+"api/v1/user/repos?limit=50&page=$i") $keys.gitea
  $batch = @(Expand-RepoArray $raw)
  foreach ($r in $batch) { if ($r.owner.login -eq $me.login) { $dest[$r.name.ToLowerInvariant()]=$true } }
  if ($batch.Count -lt 50) { break }
 }
 $missing = @();$skipped=0
 foreach ($r in $source) {
  if ($r -is [array] -or -not ($r.full_name -is [string])) { throw "Invalid preview source. Import disabled." }
  if ($dest.ContainsKey($r.name.ToLowerInvariant())) { $skipped++;continue }
  $missing += @{ name=$r.name;full_name=$r.full_name;private=[bool]$r.private;clone_url=$r.clone_url }
 }
 @{ github_user=$gh.login;gitea_user=$me.login;github_total=$source.Count;skipped=$skipped;missing=$missing }
}
function Import-SyncOne {
 param([string]$fullName)
 $preview=Get-SyncPreview
 $matches=@($preview.missing | Where-Object { $_.full_name -ceq $fullName })
 if ($matches.Count -ne 1) { throw 'Repository not in current preview of missing repositories.' }
 $r=$matches[0];$keys=Get-MyGiteaKeys
 $body=@{
  clone_addr=$r.clone_url;repo_name=$r.name;repo_owner=$preview.gitea_user
  auth_token=$keys.github;service='github';private=[bool]$r.private;mirror=$false
  issues=$true;labels=$true;milestones=$true;pull_requests=$true;releases=$true;wiki=$true;lfs=$true
 }
 $created=Invoke-SyncApi ($url+'api/v1/repos/migrate') $keys.gitea -method POST -body $body
 @{ message='Migration submitted; check status in Gitea.';source=$fullName;destination=$created.html_url }
}
) {
    throw 'Invalid GitHub repository list format; no import attempted.'
   }
  }
  $source += $batch
  if ($batch.Count -lt 100) { break }
 }
 $dest = @{}
 for ($i=1;$i -le 100;$i++) {
  $batch = @(Invoke-SyncApi ($url+"api/v1/user/repos?limit=50&page=$i") $keys.gitea)
  foreach ($r in $batch) { if ($r.owner.login -eq $me.login) { $dest[$r.name.ToLowerInvariant()]=$true } }
  if ($batch.Count -lt 50) { break }
 }
 $missing = @();$skipped=0
 foreach ($r in $source) {
  if ($dest.ContainsKey($r.name.ToLowerInvariant())) { $skipped++;continue }
  $missing += @{ name=$r.name;full_name=$r.full_name;private=[bool]$r.private;clone_url=$r.clone_url }
 }
 @{ github_user=$gh.login;gitea_user=$me.login;github_total=$source.Count;skipped=$skipped;missing=$missing }
}
function Import-SyncOne {
 param([string]$fullName)
 $preview=Get-SyncPreview
 $matches=@($preview.missing | Where-Object { $_.full_name -ceq $fullName })
 if ($matches.Count -ne 1) { throw 'Repository not in current preview of missing repositories.' }
 $r=$matches[0];$keys=Get-MyGiteaKeys
 $body=@{
  clone_addr=$r.clone_url;repo_name=$r.name;repo_owner=$preview.gitea_user
  auth_token=$keys.github;service='github';private=[bool]$r.private;mirror=$false
  issues=$true;labels=$true;milestones=$true;pull_requests=$true;releases=$true;wiki=$true;lfs=$true
 }
 $created=Invoke-SyncApi ($url+'api/v1/repos/migrate') $keys.gitea -method POST -body $body
 @{ message='Migration submitted; check status in Gitea.';source=$fullName;destination=$created.html_url }
}
