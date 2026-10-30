$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$expectedRemote = 'https://github.com/rafa-legend21/finpilot-assistant.git'
$pendingDir = Join-Path $repo '.finpilot-sync\pending'
$logDir = Join-Path $repo '.finpilot-sync'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath = Join-Path $logDir 'sync.log'

function Write-SyncLog([string]$Message) {
    $stamp = (Get-Date).ToUniversalTime().ToString('o')
    Add-Content -LiteralPath $logPath -Value "$stamp $Message" -Encoding UTF8
}

try {
    $remote = (& git -C $repo remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $remote -ne $expectedRemote) {
        throw 'Origin does not match the configured repository.'
    }
    if (-not (Test-Path -LiteralPath $pendingDir)) {
        Write-SyncLog 'No approved commits pending.'
        return
    }

    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'Never'
    foreach ($file in Get-ChildItem -LiteralPath $pendingDir -Filter '*.json' -File) {
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $branch = [string]$record.branch
            $commit = [string]$record.commit
            if ($record.repository -ne 'rafa-legend21/finpilot-assistant' -or
                $branch -notmatch '\A(?:feat|feature|fix|docs|chore|refactor|test)/[A-Za-z0-9._/-]+\z' -or
                $commit -notmatch '\A[0-9a-f]{40}\z' -or
                $file.BaseName -ne $commit) {
                throw 'Invalid approval record.'
            }

            & git -C $repo cat-file -e ($commit + '^{commit}') *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Approved commit is unavailable locally.' }
            & git -C $repo merge-base --is-ancestor $commit "refs/heads/$branch" *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Approved commit is no longer on the named branch.' }

            # Push the approved SHA, so later unapproved local commits are excluded.
            & git -C $repo push --quiet origin "${commit}:refs/heads/$branch" *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Push failed; the approval remains pending.' }

            Remove-Item -LiteralPath $file.FullName
            Write-SyncLog "Pushed approved commit $commit to $branch."
        }
        catch {
            Write-SyncLog "Skipped $($file.BaseName): $($_.Exception.Message)"
        }
    }
}
catch {
    Write-SyncLog "Daily sync stopped: $($_.Exception.Message)"
    exit 1
}
