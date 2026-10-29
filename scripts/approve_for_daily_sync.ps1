param(
    [Parameter(Mandatory = $true)][string]$Branch,
    [Parameter(Mandatory = $true)][string]$Commit
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$expectedRemote = 'https://github.com/rafa-legend21/finpilot-assistant.git'

if ($Branch -notmatch '\A(?:feat|feature|fix|docs|chore|refactor|test)/[A-Za-z0-9._/-]+\z') {
    throw 'Approval requires a feature or maintenance branch.'
}
if ($Commit -notmatch '\A[0-9a-f]{40}\z') {
    throw 'Approval requires a full 40-character commit SHA.'
}

$remote = (& git -C $repo remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0 -or $remote -ne $expectedRemote) {
    throw 'The origin remote does not match the configured FinPilot repository.'
}

$branchHead = (& git -C $repo rev-parse --verify "refs/heads/$Branch").Trim()
if ($LASTEXITCODE -ne 0 -or $branchHead -ne $Commit) {
    throw 'The approved commit must be the current head of the named local branch.'
}

$pendingDir = Join-Path $repo '.finpilot-sync\pending'
New-Item -ItemType Directory -Path $pendingDir -Force | Out-Null
$record = [pscustomobject]@{
    repository = 'rafa-legend21/finpilot-assistant'
    branch = $Branch
    commit = $Commit
    approved_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$record | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $pendingDir "$Commit.json") -Encoding UTF8
Write-Output "Approved $Commit on $Branch for the next daily sync."
