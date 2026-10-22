# Tests of get-kira.ps1 run without a clone: it fetches a scratch copy of the repository.
# Runs with Windows PowerShell 5.1 and PowerShell 7: scripts/test.ps1
# Requirements are those of the specification in issue #86.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$shell = (Get-Process -Id $PID).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('kirakit-test.' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$failures = 0

function Test-Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) {
        Write-Host "ok   $Name"
    } else {
        Write-Host "FAIL $Name"
        if ($Detail) { Write-Host $Detail }
        $script:failures++
    }
}

# Runs a git command quietly, and stops on failure.
function Invoke-Git {
    $ErrorActionPreference = 'Continue'
    $out = & git @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $args failed:`n$out" }
}

# The scratch remote: the working tree, committed on main, with an annotated tag (as release
# tags are), then one more commit on main after the tag.
$remote = Join-Path $tmp 'remote'
New-Item -ItemType Directory -Path $remote | Out-Null
Get-ChildItem -LiteralPath $root -Force | Where-Object { $_.Name -ne '.git' } |
    Copy-Item -Destination $remote -Recurse -Force
$who = @('-c', 'user.name=test', '-c', 'user.email=test@example.com')
Invoke-Git -C $remote init -q -b main
Invoke-Git -C $remote -c core.safecrlf=false -c core.autocrlf=false add -A
Invoke-Git -C $remote @who -c commit.gpgsign=false commit -q -m initial
Invoke-Git -C $remote @who -c tag.gpgsign=false tag -a -m v0.11.0 v0.11.0
$pullSkill = Join-Path (Join-Path (Join-Path (Join-Path $remote 'claude') 'skills') 'pull') 'SKILL.md'
Add-Content -LiteralPath $pullSkill -Value 'after the tag'
Invoke-Git -C $remote @who -c commit.gpgsign=false commit -q -a -m 'after the tag'
# A file:// URL, so that the fetch is shallow as it is from GitHub.
$remoteUrl = 'file://' + $(if ($remote.StartsWith('/')) { '' } else { '/' }) + $remote.Replace('\', '/')

# The installer alone, outside any clone, as when it is downloaded.
$alone = Join-Path $tmp 'alone'
New-Item -ItemType Directory -Path $alone | Out-Null
$installer = Join-Path $alone 'get-kira.ps1'
Copy-Item -LiteralPath (Join-Path $root 'get-kira.ps1') -Destination $installer

# Runs the installer in a new process with KIRAKIT_REF set to $Ref and the locale set to
# $Locale, and returns its exit code and its output in order: each line of stdout as text,
# each line of stderr as an error record.
function Invoke-Installer([string]$ConfigDir, [string]$Ref, [string]$Locale, [string[]]$Arguments) {
    $saved = @{}
    $vars = @{ CLAUDE_CONFIG_DIR = $ConfigDir; KIRAKIT_REPO = $remoteUrl; KIRAKIT_REF = $Ref; LANG = $Locale; LC_ALL = $Locale }
    foreach ($name in $vars.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $vars[$name])
    }
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $shell -NoProfile -ExecutionPolicy Bypass -File $installer @Arguments `
                -Name Alex -Gender female -Language auto -NoCoAuthor 2>&1)
        return @{ Status = $LASTEXITCODE; Lines = $lines }
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

# Lines that are not kirakit's own from "kirakit: fetching" (the scratch remote) to
# "kirakit: source", and any line written to stderr: git writes only there. Returns $null
# when "fetching" or "source" is missing.
function Get-ForeignLine($Lines) {
    $fetching = $false
    $source = $false
    $foreign = @()
    foreach ($line in $Lines) {
        $text = "$line"
        if ($line -is [Management.Automation.ErrorRecord]) { $foreign += "stderr: $text"; continue }
        if ($text -like "kirakit: fetching $remoteUrl *") { $fetching = $true }
        if ($fetching -and -not $source -and $text -notlike 'kirakit:*') { $foreign += $text }
        if ($fetching -and $text -like 'kirakit: source: *') { $source = $true }
    }
    if (-not ($fetching -and $source)) { return $null }
    return , $foreign
}

function Test-OnlyKirakit([string]$Name, $Run) {
    $foreign = Get-ForeignLine $Run.Lines
    $ok = $Run.Status -eq 0 -and $null -ne $foreign -and $foreign.Count -eq 0
    Test-Check $Name $ok ("status $($Run.Status):`n" + (($Run.Lines | ForEach-Object { "$_" }) -join "`n"))
}

# R1, R2: only kirakit's lines for an annotated tag and for a branch, in French when git
# has the translation.
$run = Invoke-Installer (Join-Path $tmp 'quiet') 'v0.11.0' 'fr_CA.UTF-8' @('-DryRun')
Test-OnlyKirakit 'fetch: only kirakit lines for an annotated tag (#86 R1, R5)' $run
$run = Invoke-Installer (Join-Path $tmp 'quiet') 'main' 'fr_CA.UTF-8' @('-DryRun')
Test-OnlyKirakit 'fetch: only kirakit lines for a branch (#86 R2, R5)' $run

# R4: the installed source is the commit the requested ref points to.
function Get-InstalledPullSkill([string]$ConfigDir) {
    $path = Join-Path (Join-Path (Join-Path $ConfigDir 'skills') 'pull') 'SKILL.md'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw
}
$atTag = Join-Path $tmp 'at-tag'
$run = Invoke-Installer $atTag 'v0.11.0' 'C' @()
$skill = Get-InstalledPullSkill $atTag
Test-Check 'fetch: a tag installs the commit it points to (#86 R4, R5)' `
    ($run.Status -eq 0 -and $null -ne $skill -and -not $skill.Contains('after the tag')) `
    (($run.Lines | ForEach-Object { "$_" }) -join "`n")
$atMain = Join-Path $tmp 'at-main'
$run = Invoke-Installer $atMain 'main' 'C' @()
$skill = Get-InstalledPullSkill $atMain
Test-Check 'fetch: a branch installs its last commit (#86 R4, R5)' `
    ($run.Status -eq 0 -and $null -ne $skill -and $skill.Contains('after the tag')) `
    (($run.Lines | ForEach-Object { "$_" }) -join "`n")

# R3: an unknown ref fails, with git's error and kirakit's, and installs nothing.
$unknown = Join-Path $tmp 'unknown'
$run = Invoke-Installer $unknown 'no-such-ref' 'C' @()
$output = ($run.Lines | ForEach-Object { "$_" }) -join "`n"
Test-Check 'fetch: an unknown ref fails (#86 R3, R5)' ($run.Status -ne 0) $output
Test-Check "fetch: an unknown ref shows git's error (#86 R3, R5)" `
    $output.Contains("couldn't find remote ref no-such-ref") $output
Test-Check 'fetch: an unknown ref shows could not fetch (#86 R3, R5)' `
    $output.Contains("could not fetch $remoteUrl") $output
Test-Check 'fetch: an unknown ref installs nothing (#86 R3, R5)' (-not (Test-Path -LiteralPath $unknown))

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($failures) {
    Write-Host "$failures check(s) failed"
    exit 1
}
Write-Host 'all checks passed'
