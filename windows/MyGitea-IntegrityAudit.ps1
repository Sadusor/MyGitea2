# MyGitea2 read-only GitHub-to-Gitea Git-ref integrity audit.
# Reads API endpoints only; writes CSV/JSON reports under %LOCALAPPDATA%\MyGitea2\Audit.
[CmdletBinding()]
param([ValidateRange(0,10000)][int]$MaxRepositories = 0)
$ErrorActionPreference = 'Stop'
$url = 'http://127.0.0.1:3001/'
. (Join-Path $PSScriptRoot 'MyGitea-Sync.ps1')

function Read-AuditPage {
    param([string]$uri,[string]$token,[switch]$Github)
    $raw = Invoke-SyncApi $uri $token -github:$Github
    if ($null -eq $raw) { return @() }
    $array = @($raw | ForEach-Object { $_ })
    # Invoke-RestMethod in Windows PowerShell can produce a single nested array.
    if ($array.Count -eq 1 -and $array[0] -is [array]) {
        $array = @($array[0] | ForEach-Object { $_ })
    }
    return ,$array
}
function Read-AuditPages {
    param([string]$base,[string]$token,[int]$pageSize=100,[switch]$Github)
    $all = New-Object System.Collections.ArrayList
    for ($page=1; $page -le 100; $page++) {
        $join = if ($base.Contains('?')) { '&' } else { '?' }
        $endpoint = $base + $join + 'page=' + $page + '&' +
          $(if ($Github) { 'per_page=' } else { 'limit=' }) + $pageSize
        $batch = @(Read-AuditPage $endpoint $token -Github:$Github)
        foreach ($entry in $batch) { [void]$all.Add($entry) }
        if ($batch.Count -lt $pageSize) { return ,$all.ToArray() }
    }
    throw 'Pagination limit exceeded: refusing to report partial audit as complete.'
}
function Ref-Map {
    param([object[]]$items,[string]$kind,[switch]$Github)
    $map = @{}
    foreach ($item in $items) {
        if ($null -eq $item -or $item.name -isnot [string]) {
            throw 'Unrecognized branch or tag API entry.'
        }
        $sha = [string]$item.commit.sha
        if (-not $Github -and $kind -eq 'branch') { $sha = [string]$item.commit.id }
        if ($sha -notmatch '^[0-9a-fA-F]{40}$') {
            # Gitea branch APIs on some releases expose commit.sha rather than commit.id.
            if (-not $Github -and $kind -eq 'branch') { $sha = [string]$item.commit.sha }
        }
        if ($sha -notmatch '^[0-9a-fA-F]{40}$') {
            throw "Cannot read Git object ID for $kind $($item.name)."
        }
        $map[$kind + ':' + $item.name] = $sha.ToLowerInvariant()
    }
    return $map
}
function Compare-Refs {
    param([string]$repoFullName,[string]$giteaOwner,[string]$giteaRepo,$keys)
    $sourceBase = 'https://api.github.com/repos/' + $repoFullName
    $destBase = $url + 'api/v1/repos/' + [uri]::EscapeDataString($giteaOwner) + '/' + [uri]::EscapeDataString($giteaRepo)
    $githubMap = @{}
    $giteaMap = @{}
    foreach ($kind in @('branch','tag')) {
        $segment = if ($kind -eq 'branch') { 'branches' } else { 'tags' }
        $src = @(Read-AuditPages ($sourceBase + '/' + $segment) $keys.github -Github)
        $dst = @(Read-AuditPages ($destBase + '/' + $segment) $keys.gitea -pageSize 50)
        $a = Ref-Map $src $kind -Github
        $b = Ref-Map $dst $kind
        foreach ($name in $a.Keys) { $githubMap[$name] = $a[$name] }
        foreach ($name in $b.Keys) { $giteaMap[$name] = $b[$name] }
    }
    $differences = New-Object System.Collections.ArrayList
    foreach ($name in $githubMap.Keys) {
        if (-not $giteaMap.ContainsKey($name)) {
            [void]$differences.Add(($name + ' missing in MyGitea2'))
        } elseif ($githubMap[$name] -ne $giteaMap[$name]) {
            [void]$differences.Add(($name + ' hash differs (' + $githubMap[$name] + ' / ' + $giteaMap[$name] + ')'))
        }
    }
    foreach ($name in $giteaMap.Keys) {
        if (-not $githubMap.ContainsKey($name)) {
            [void]$differences.Add(($name + ' exists only in MyGitea2'))
        }
    }
    @{
        Status = if ($differences.Count -eq 0) { 'MATCH' } else { 'DIFFERENT' }
        BranchesAndTagsGithub = $githubMap.Count
        BranchesAndTagsGitea = $giteaMap.Count
        Details = ($differences -join '; ')
    }
}

Write-Host 'MyGitea2 READ-ONLY integrity audit starting. No repositories will be modified.'
$keys = Get-MyGiteaKeys
$me = Invoke-SyncApi ($url + 'api/v1/user') $keys.gitea
$gh = Invoke-SyncApi 'https://api.github.com/user' $keys.github -github
if ([string]::IsNullOrWhiteSpace($gh.login) -or [string]::IsNullOrWhiteSpace($me.login)) {
    throw 'Unable to verify authenticated GitHub and MyGitea2 users.'
}
$srcBase = 'https://api.github.com/user/repos?affiliation=owner'
$githubRepos = @(Read-AuditPages $srcBase $keys.github -Github)
$myRepos = @(Read-AuditPages ($url + 'api/v1/user/repos') $keys.gitea -pageSize 50)
$dest = @{}
foreach ($r in $myRepos) {
    if ($r.owner.login -eq $me.login -and $r.name -is [string]) {
        $dest[$r.name.ToLowerInvariant()] = $r.name
    }
}
$records = New-Object System.Collections.ArrayList
$orderedRepos = @($githubRepos | Sort-Object full_name)
if ($MaxRepositories -gt 0) {
    $orderedRepos = @($orderedRepos | Select-Object -First $MaxRepositories)
}
$index = 0
foreach ($r in $orderedRepos) {
    $index++
    if ($null -eq $r -or $r.name -isnot [string] -or $r.full_name -isnot [string]) {
        throw 'GitHub repository listing returned an invalid entry; audit aborted.'
    }
    $state = 'ERROR'
    $details = ''
    $ghRefs = 0
    $giRefs = 0
    if (-not $dest.ContainsKey($r.name.ToLowerInvariant())) {
        $state = 'MISSING'
        $details = 'Not present in MyGitea2 under the current Gitea user.'
    } else {
        try {
            $result = Compare-Refs $r.full_name $me.login $dest[$r.name.ToLowerInvariant()] $keys
            $state = $result.Status
            $details = $result.Details
            $ghRefs = $result.BranchesAndTagsGithub
            $giRefs = $result.BranchesAndTagsGitea
        } catch {
            $state = 'ERROR'
            $details = [string]$_.Exception.Message
        }
    }
    $record = [pscustomobject]@{
        Repo=$r.full_name; Status=$state; GithubRefs=$ghRefs; MyGitea2Refs=$giRefs; Details=$details
    }
    [void]$records.Add($record)
    Write-Host ("[{0}/{1}] {2} - {3}" -f $index,$orderedRepos.Count,$r.full_name,$state)
}
$folder = Join-Path $env:LOCALAPPDATA 'MyGitea2\Audit'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $folder ('integrity-' + $stamp + '.csv')
$jsonPath = Join-Path $folder ('integrity-' + $stamp + '.json')
$records | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
$summary = @{
    AuditedAt=(Get-Date).ToString('o')
    GithubUser=$gh.login
    GiteaUser=$me.login
    TotalGithub=$githubRepos.Count
    Audited=$records.Count
    Match=@($records | Where-Object Status -eq 'MATCH').Count
    Different=@($records | Where-Object Status -eq 'DIFFERENT').Count
    Missing=@($records | Where-Object Status -eq 'MISSING').Count
    Error=@($records | Where-Object Status -eq 'ERROR').Count
    Limited=($MaxRepositories -gt 0)
    Note='Compares branch/tag commit hashes only; does not verify issues, pull requests, LFS, or unchanged GitHub state since migration.'
}
[IO.File]::WriteAllText($jsonPath,(ConvertTo-Json -InputObject @{summary=$summary;repositories=@($records)} -Depth 8))
$keys = $null
Write-Host ('MATCH {0}; DIFFERENT {1}; MISSING {2}; ERROR {3}' -f $summary.Match,$summary.Different,$summary.Missing,$summary.Error)
Write-Host ('CSV report: ' + $csvPath)
Write-Host ('JSON report: ' + $jsonPath)
