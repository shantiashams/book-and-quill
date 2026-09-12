#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git was not found.' }
Push-Location $projectRoot
try {
    $branch = & git branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
        throw 'Run this command from the existing project on its main branch.'
    }
    & git remote get-url origin
    if ($LASTEXITCODE -ne 0) { throw 'The origin remote is missing.' }
    foreach ($marker in @('MERGE_HEAD', 'rebase-merge', 'rebase-apply', 'CHERRY_PICK_HEAD')) {
        $markerPath = & git rev-parse --git-path $marker
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Git operation state.' }
        if (Test-Path -LiteralPath $markerPath) {
            throw 'A Git merge, rebase or cherry-pick is already in progress. Resolve it before publishing; run git status for details.'
        }
    }
    # This stages only the documented source and app asset formats.
    # Existing staged changes are preserved and included in the commit.
    & (Join-Path $PSScriptRoot 'prepare_android_github.ps1')
    & git diff --cached --quiet
    $diffResult = $LASTEXITCODE
    if ($diffResult -eq 1) {
        & git commit -m 'Fix page arrow placement and footer regression checks - v3.5.2'
        if ($LASTEXITCODE -ne 0) { throw 'Commit failed. No pull or push was attempted.' }
    } elseif ($diffResult -ne 0) {
        throw 'Could not inspect staged changes. No pull or push was attempted.'
    }
    # Preserve local and remote history. Never force-push or reset either side.
    & git pull --no-rebase --no-edit origin main
    if ($LASTEXITCODE -ne 0) {
        throw 'Pull/merge did not complete. Nothing was pushed. Run git status and send its output with the error above; your local commit is preserved.'
    }
    & git push origin main
    if ($LASTEXITCODE -ne 0) { throw 'Push failed. Your local commits are preserved; send the Git error above.' }
    Write-Host 'Published. Open GitHub > Actions > Android APK to see the build.' -ForegroundColor Green
} finally { Pop-Location }
