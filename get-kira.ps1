<#
.SYNOPSIS
Install kirakit into the Claude Code configuration directory.

.DESCRIPTION
Windows PowerShell 5+ and PowerShell 7 counterpart of get-kira.sh, with the same profile,
files and options.

From a clone, files are copied on Windows (symbolic links need Developer Mode: pass -Link)
and linked elsewhere. Without a clone, the repository is fetched into a temporary directory
and files are copied.

Output styles, skills, agents and CLAUDE.md are personalized from a profile: how Kira calls
the user, the user's gender, the answer language and the commit co-author. The installer asks
once and saves the answers in $CLAUDE_CONFIG_DIR\.kirakit-profile for later runs.

Without -Only, styles and claude are installed. The github component copies issue and pull
request templates, workflows and Copilot instructions into a repository's .github directory.

Remote use:
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jstmichel/kirakit/main/get-kira.ps1))) -DryRun

Environment: CLAUDE_CONFIG_DIR (default: ~\.claude), KIRAKIT_REPO and KIRAKIT_REF (repository
and branch or tag fetched without a clone; default: the latest release).

.PARAMETER DryRun
Print what would change, change nothing.
.PARAMETER Name
How Kira calls you.
.PARAMETER Gender
male, female, nonbinary or unspecified.
.PARAMETER Language
Answer language, or auto to follow the conversation.
.PARAMETER CoAuthor
Add this Co-Authored-By trailer to commits, as "NAME <EMAIL>".
.PARAMETER NoCoAuthor
Add no Co-Authored-By trailer to commits.
.PARAMETER DefaultStyle
Output style selected in settings.json (default: kira-cozy).
.PARAMETER Reconfigure
Ask all profile questions again.
.PARAMETER Persona
Install only these personas (default: all).
.PARAMETER Only
Install one component: styles, claude (CLAUDE.md, settings, agents, skills) or github.
.PARAMETER Target
Repository for -Only github (default: the current one).
.PARAMETER Link
Symlink files to the local clone.
.PARAMETER Copy
Copy files.
.PARAMETER Uninstall
Remove what kirakit installed in the configuration directory.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Name,
    [ValidateSet('male', 'female', 'nonbinary', 'unspecified')]
    [string]$Gender,
    [string]$Language,
    [string]$CoAuthor,
    [switch]$NoCoAuthor,
    [string]$DefaultStyle,
    [switch]$Reconfigure,
    [string[]]$Persona = @(),
    [ValidateSet('styles', 'claude', 'github')]
    [string]$Only,
    [string]$Target,
    [switch]$Link,
    [switch]$Copy,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Bound = $PSBoundParameters

$Repo = if ($env:KIRAKIT_REPO) { $env:KIRAKIT_REPO } else { 'https://github.com/jstmichel/kirakit.git' }
# Set to the release tag in the copy attached to each GitHub release, so that it installs its
# own version.
$KiraVersion = ''
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$ClaudeDir = [IO.Path]::GetFullPath($ClaudeDir).TrimEnd('\', '/')

$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Nl = "`n"
$Tab = "`t"
$Sep = [IO.Path]::DirectorySeparatorChar
$ProfilePath = Join-Path $ClaudeDir '.kirakit-profile'
$ManifestPath = Join-Path $ClaudeDir '.kirakit-manifest'
$OriginalsPath = Join-Path $ClaudeDir '.kirakit-originals'
$PlaceholderKeys = @('user', 'they', 'them', 'their', 'language', 'co_author_trailer', 'attribution_rule', 'co_author_rule')

$script:Work = $null
$script:BackupDir = $null
$script:Mode = 'copy'
$script:Src = $null
$script:BuildDir = $null
$script:Installed = New-Object System.Collections.Generic.List[string]
$script:OriginalsNew = New-Object System.Collections.Generic.List[string]

function Write-KiraLog([string]$Message) {
    Write-Host "kirakit: $Message"
}

function Write-DryRun([string]$Message) {
    Write-Host "[dry-run] $Message"
}

function Read-KiraText([string]$Path) {
    return [IO.File]::ReadAllText($Path, $Utf8)
}

function Write-KiraText([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $Utf8)
}

# Lines of a text, without the final newline; an empty text has no lines. Callers wrap the
# result in @() so that one line or none still gives an array.
function Split-KiraLine([string]$Text) {
    $t = $Text.Replace("`r`n", "`n")
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    if ($t -eq '') { return }
    return $t -split "`n"
}

function Join-KiraLine([string[]]$Lines) {
    return ($Lines -join $Nl) + $Nl
}

# The branch or tag to fetch without a clone: KIRAKIT_REF, else the version this copy was
# released with, else the highest vX.Y.Z tag of the repository, else main.
function Get-KiraRef {
    if ($env:KIRAKIT_REF) { return $env:KIRAKIT_REF }
    if ($KiraVersion) { return $KiraVersion }
    # Windows PowerShell 5.1 turns a native command's error output into a terminating error.
    $ErrorActionPreference = 'Continue'
    $best = $null
    $bestTag = 'main'
    foreach ($line in @(& git ls-remote --tags --refs -- $Repo 'v*' 2>$null)) {
        if ($line -match 'refs/tags/(v(\d+)\.(\d+)\.(\d+))$') {
            $tag = $Matches[1]
            $version = New-Object Version ([int]$Matches[2]), ([int]$Matches[3]), ([int]$Matches[4])
            if (-not $best -or $version -gt $best) {
                $best = $version
                $bestTag = $tag
            }
        }
    }
    return $bestTag
}

function Get-KiraWorkDir {
    if (-not $script:Work) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ('kirakit.' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $path | Out-Null
        $script:Work = $path
    }
    return $script:Work
}

function Initialize-KiraDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($DryRun) { Write-DryRun "create directory $Path"; return }
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-KiraLinkTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'SymbolicLink') { return [string](@($item.Target)[0]) }
    return $null
}

function Test-KiraPresent([string]$Path) {
    return (Test-Path -LiteralPath $Path) -or [bool](Get-KiraLinkTarget $Path)
}

# Move PATH (or copy it, with -CopyOnly) into this run's backup directory, under PREFIX
# followed by PATH relative to ROOT. Returns the backup path.
function Backup-KiraPath([string]$Path, [string]$Root = $ClaudeDir, [string]$Prefix = '', [switch]$CopyOnly) {
    if (-not $script:BackupDir) {
        # Never reuse the directory of an earlier run started within the same second.
        $base = Join-Path (Join-Path $ClaudeDir '.kirakit-backups') (Get-Date -Format 'yyyyMMdd-HHmmss')
        $dir = $base
        $n = 1
        while (Test-Path -LiteralPath $dir) { $dir = "$base-$n"; $n++ }
        $script:BackupDir = $dir
    }
    $rel = $Path.Substring($Root.Length).TrimStart('\', '/')
    $dest = Join-Path $script:BackupDir ($Prefix.Replace('/', $Sep) + $rel)
    Write-KiraLog "backup: $Path -> $dest"
    Initialize-KiraDirectory (Split-Path -Parent $dest)
    if ($DryRun) {
        Write-DryRun "$(if ($CopyOnly) { 'copy' } else { 'move' }) $Path to $dest"
    } elseif ($CopyOnly) {
        Copy-Item -LiteralPath $Path -Destination $dest -Recurse
    } else {
        Move-Item -LiteralPath $Path -Destination $dest
    }
    return $dest
}

function Get-KiraTreeHash([string]$Path) {
    # Relative paths from the resolved name, which may differ from PATH (e.g. short names).
    $base = (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd('\', '/')
    $entries = Get-ChildItem -LiteralPath $base -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($base.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName).Hash
    } | Sort-Object
    return (@($entries) -join $Nl)
}

# Whether TARGET is already an identical copy of SOURCE (a file or a directory).
function Test-KiraSameCopy([string]$Source, [string]$Destination) {
    if (Get-KiraLinkTarget $Destination) { return $false }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { return $false }
        return (Get-KiraTreeHash $Source) -eq (Get-KiraTreeHash $Destination)
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { return $false }
    return (Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Destination).Hash
}

# Whether PATH is the first tab-separated field of a line of FILE.
function Test-KiraListed([string]$File, [string]$Path) {
    if (-not (Test-Path -LiteralPath $File)) { return $false }
    foreach ($line in [IO.File]::ReadAllLines($File, $Utf8)) {
        if ($line.Split("`t")[0] -eq $Path) { return $true }
    }
    return $false
}

# Link or copy SOURCE (a file or a directory) to DESTINATION, backing up anything else there.
# Destinations in the configuration directory (no ROOT) are recorded in the manifest for
# -Uninstall, with the backup of what was there before kirakit so that -Uninstall can
# restore it.
function Install-KiraFile([string]$Source, [string]$Destination, [string]$Root = '', [string]$Prefix = '') {
    if (-not $Root) { $script:Installed.Add($Destination) }
    if ($script:Mode -eq 'link') {
        if ((Get-KiraLinkTarget $Destination) -eq $Source) { Write-KiraLog "up to date: $Destination"; return }
    } elseif (Test-KiraSameCopy $Source $Destination) {
        Write-KiraLog "up to date: $Destination"
        return
    }

    if (Test-KiraPresent $Destination) {
        $backupRoot = if ($Root) { $Root } else { $ClaudeDir }
        $dest = Backup-KiraPath -Path $Destination -Root $backupRoot -Prefix $Prefix
        if (-not $Root -and -not (Test-KiraListed $ManifestPath $Destination) -and -not (Test-KiraListed $OriginalsPath $Destination)) {
            $script:OriginalsNew.Add("$Destination$Tab$dest")
        }
    }
    Initialize-KiraDirectory (Split-Path -Parent $Destination)
    if ($script:Mode -eq 'link') {
        Write-KiraLog "link: $Destination -> $Source"
        if ($DryRun) { Write-DryRun "link $Destination to $Source"; return }
        New-Item -ItemType SymbolicLink -Path $Destination -Value $Source | Out-Null
    } else {
        Write-KiraLog "copy: $Source -> $Destination"
        if ($DryRun) { Write-DryRun "copy $Source to $Destination"; return }
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse
    }
}

# --- Profile -------------------------------------------------------------------------------

function Test-KiraCoAuthor([string]$Value) {
    return $Value -eq '' -or $Value -match '^[^<>]+ <[^<>\s]+@[^<>\s]+>$'
}

function Test-KiraCanPrompt {
    try { return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected } catch { return $false }
}

function Read-KiraAnswer([string]$Question, [string]$Default = '') {
    $prompt = if ($Default) { "$Question [$Default]" } else { $Question }
    $answer = Read-Host $prompt
    if ($answer) { return $answer }
    return $Default
}

function Read-KiraGender([string]$Current) {
    $default = switch ($Current) { 'male' { '1' } 'female' { '2' } 'nonbinary' { '3' } default { '4' } }
    Write-Host 'How should Kira refer to you?'
    Write-Host '  1) male (he/him)'
    Write-Host '  2) female (she/her)'
    Write-Host '  3) non-binary (they/them)'
    Write-Host '  4) prefer not to say (they/them)'
    while ($true) {
        switch (Read-KiraAnswer 'Choice' $default) {
            '1' { return 'male' }
            '2' { return 'female' }
            '3' { return 'nonbinary' }
            '4' { return 'unspecified' }
        }
    }
}

function Read-KiraCoAuthor([string]$Current) {
    $default = if ($Current) { 'y' } else { 'n' }
    while ($true) {
        $answer = Read-KiraAnswer 'Add a Co-Authored-By trailer to your commit messages? (y/n)' $default
        if ($answer -match '^[Yy]') { break }
        if ($answer -match '^[Nn]') { return '' }
    }
    if ($Current -match '^(.+) <(.+)>$') {
        $currentName = $Matches[1]
        $currentEmail = $Matches[2]
    } else {
        $currentName = 'Kira'
        $currentEmail = ''
    }
    $coName = Read-KiraAnswer 'Co-author name' $currentName
    while ($true) {
        $coEmail = Read-KiraAnswer 'Co-author email' $currentEmail
        $value = "$coName <$coEmail>"
        if ($coEmail -and (Test-KiraCoAuthor $value)) { return $value }
        Write-Host 'Expected a name and an email address such as kira@example.com.'
    }
}

function Read-KiraProfile {
    $saved = @{}
    if (Test-Path -LiteralPath $ProfilePath) {
        foreach ($line in [IO.File]::ReadAllLines($ProfilePath, $Utf8)) {
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $saved[$line.Substring(0, $i)] = $line.Substring($i + 1) }
        }
    }
    return $saved
}

# Resolve the profile from parameters, the saved profile, then questions.
function Get-KiraProfile {
    $saved = Read-KiraProfile
    $given = @{
        name      = $Bound.ContainsKey('Name')
        gender    = $Bound.ContainsKey('Gender')
        language  = $Bound.ContainsKey('Language')
        co_author = $Bound.ContainsKey('CoAuthor') -or $NoCoAuthor
    }
    $result = @{
        name      = if ($given.name) { $Name } elseif ($saved.ContainsKey('name')) { $saved.name } else { '' }
        gender    = if ($given.gender) { $Gender } elseif ($saved.ContainsKey('gender')) { $saved.gender } else { 'unspecified' }
        language  = if ($given.language) { $Language } elseif ($saved.ContainsKey('language')) { $saved.language } else { 'auto' }
        co_author = if ($NoCoAuthor) { '' } elseif ($given.co_author) { $CoAuthor } elseif ($saved.ContainsKey('co_author')) { $saved.co_author } else { '' }
        style     = if ($DefaultStyle) { $DefaultStyle } elseif ($saved.ContainsKey('style') -and $saved.style) { $saved.style } else { 'kira-cozy' }
    }

    $missing = @('name', 'gender', 'language', 'co_author') | Where-Object {
        -not $given[$_] -and ($Reconfigure -or -not $saved.ContainsKey($_))
    }
    if (@($missing).Count -gt 0) {
        if (-not (Test-KiraCanPrompt)) {
            Write-KiraLog "no terminal to ask for: $($missing -join ' '); using defaults (see Get-Help)"
            return $result
        }
        foreach ($key in $missing) {
            switch ($key) {
                'name' { $result.name = Read-KiraAnswer 'How should Kira call you?' $result.name }
                'gender' { $result.gender = Read-KiraGender $result.gender }
                'language' { $result.language = Read-KiraAnswer 'Which language should Kira answer in? (auto follows the conversation)' $result.language }
                'co_author' { $result.co_author = Read-KiraCoAuthor $result.co_author }
            }
        }
    }

    $unchanged = $saved.ContainsKey('co_author')
    foreach ($key in @('name', 'gender', 'language', 'co_author', 'style')) {
        if (-not $saved.ContainsKey($key) -or $saved[$key] -ne $result[$key]) { $unchanged = $false }
    }
    if (-not $unchanged) {
        Write-KiraLog "save profile: $ProfilePath"
        $text = "name=$($result.name)${Nl}gender=$($result.gender)${Nl}language=$($result.language)${Nl}co_author=$($result.co_author)${Nl}style=$($result.style)$Nl"
        if ($DryRun) {
            Write-DryRun "write $($text.Trim().Replace($Nl, ' ')) to $ProfilePath"
        } else {
            Initialize-KiraDirectory $ClaudeDir
            Write-KiraText $ProfilePath $text
        }
    }
    return $result
}

# --- Build (mirrors scripts/build.sh) -------------------------------------------------------

function Get-KiraValue($UserProfile) {
    foreach ($value in @($UserProfile.name, $UserProfile.language, $UserProfile.co_author)) {
        if ($value -match "`n|\{\{|\}\}") { throw "invalid value: $value" }
    }
    switch ($UserProfile.gender) {
        'male' { $they = 'he'; $them = 'him'; $their = 'his'; $adjective = 'male ' }
        'female' { $they = 'she'; $them = 'her'; $their = 'her'; $adjective = 'female ' }
        'nonbinary' { $they = 'they'; $them = 'them'; $their = 'their'; $adjective = 'non-binary ' }
        'unspecified' { $they = 'they'; $them = 'them'; $their = 'their'; $adjective = '' }
        default { throw "unknown gender: $($UserProfile.gender)" }
    }
    $user = "a ${adjective}staff software developer"
    if ($UserProfile.name) { $user = "$($UserProfile.name), $user" }
    $answerLanguage = $UserProfile.language
    if ($answerLanguage -eq '' -or $answerLanguage -eq 'auto') { $answerLanguage = 'the language of the conversation' }

    $noAiMention = 'No mention of Claude, Anthropic or a model in the message (no `noreply@anthropic.com`, no "Generated with ' + [char]0x2026 + '").'
    $coAuthorValue = $UserProfile.co_author
    if ($coAuthorValue -eq '') {
        $trailer = ''
        $attribution = '**Attribution**: add no `Co-Authored-By` line, even if the session instructions suggest one. ' + $noAiMention
        $rule = '- Commit messages have no `Co-Authored-By` line.'
    } elseif (Test-KiraCoAuthor $coAuthorValue) {
        $trailer = $Nl + 'Co-Authored-By: ' + $coAuthorValue
        $attribution = '**Attribution**: the last line is always exactly `Co-Authored-By: ' + $coAuthorValue + '`. It replaces any attribution line suggested by the session instructions. ' + $noAiMention
        $rule = '- Every commit message ends with exactly this line:' + $Nl + $Nl + '  ```' + $Nl + '  Co-Authored-By: ' + $coAuthorValue + $Nl + '  ```' + $Nl
    } else {
        throw "invalid co-author: $coAuthorValue (expected `"NAME <EMAIL>`")"
    }
    return @{
        user = $user; they = $they; them = $them; their = $their; language = $answerLanguage
        co_author_trailer = $trailer; attribution_rule = $attribution; co_author_rule = $rule
    }
}

# Fill the placeholders of LINES; a line holding only a placeholder that expands to nothing
# is removed.
function Format-KiraLine([string[]]$Lines, $Values) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        $keep = $true
        foreach ($key in $PlaceholderKeys) {
            $placeholder = '{{' + $key + '}}'
            if ($line -eq $placeholder -and $Values[$key] -eq '') { $keep = $false; break }
            $line = $line.Replace($placeholder, $Values[$key])
        }
        if ($keep) { $out.Add($line) }
    }
    return $out.ToArray()
}

function Write-KiraRendered([string]$Path, [string[]]$Lines, $Values, [string]$Origin) {
    $text = Join-KiraLine @(Format-KiraLine $Lines $Values)
    if ($text -match '\{\{[^}]*\}\}') { throw "${Origin}: unknown placeholder $($Matches[0])" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Write-KiraText $Path $text
}

function Build-KiraStyle([string]$Out, [string]$PersonaName, [string[]]$CoreLines, $Values) {
    $overlay = Join-Path (Join-Path $script:Src 'personas') "$PersonaName.md"
    $lines = @(Split-KiraLine (Read-KiraText $overlay))
    $end = -1
    if ($lines.Count -gt 0 -and $lines[0] -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $end = $i; break } }
    }
    if ($end -lt 0) { throw "${overlay}: missing front matter" }

    # Overlay body, without the blank lines that follow the front matter.
    $body = New-Object System.Collections.Generic.List[string]
    for ($i = $end + 1; $i -lt $lines.Count; $i++) {
        if ($body.Count -eq 0 -and $lines[$i] -eq '') { continue }
        $body.Add($lines[$i])
    }
    $bodyText = $body.ToArray() -join $Nl

    $merged = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -le $end; $i++) { $merged.Add($lines[$i]) }
    $merged.Add('')
    foreach ($line in $CoreLines) {
        $i = $line.IndexOf('{{overlay}}')
        if ($i -ge 0) { $line = $line.Substring(0, $i) + $bodyText + $line.Substring($i + 11) }
        $merged.Add($line)
    }
    Write-KiraRendered (Join-Path (Join-Path $Out 'output-styles') "$PersonaName.md") $merged.ToArray() $Values $overlay
}

function Build-KiraOutput($UserProfile) {
    if ($script:Mode -eq 'link' -and -not $DryRun) {
        $script:BuildDir = Join-Path $script:Src 'dist'
    } else {
        $script:BuildDir = Join-Path (Get-KiraWorkDir) 'dist'
    }
    $out = $script:BuildDir
    $values = Get-KiraValue $UserProfile

    $core = Join-Path (Join-Path $script:Src 'personas') '_core.md'
    $coreText = Read-KiraText $core
    if (-not $coreText.Contains('{{overlay}}')) { throw "${core}: missing {{overlay}} marker" }
    $coreLines = @(Split-KiraLine $coreText)
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:Src 'personas') -Filter '*.md' -File) {
        if ($file.BaseName.StartsWith('_')) { continue }
        Build-KiraStyle $out $file.BaseName $coreLines $values
    }

    $claude = Join-Path $script:Src 'claude'
    $skills = Join-Path $claude 'skills'
    if (Test-Path -LiteralPath $skills) {
        foreach ($dir in Get-ChildItem -LiteralPath $skills -Directory) {
            if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md'))) { continue }
            $dest = Join-Path (Join-Path $out 'skills') $dir.Name
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Copy-Item -LiteralPath $dir.FullName -Destination $dest -Recurse
            foreach ($file in Get-ChildItem -LiteralPath $dest -Recurse -File -Filter '*.md') {
                $origin = Join-Path $dir.FullName $file.FullName.Substring($dest.Length + 1)
                Write-KiraRendered $file.FullName @(Split-KiraLine (Read-KiraText $file.FullName)) $values $origin
            }
        }
    }
    $agents = Join-Path $claude 'agents'
    if (Test-Path -LiteralPath $agents) {
        foreach ($file in Get-ChildItem -LiteralPath $agents -Filter '*.md' -File) {
            Write-KiraRendered (Join-Path (Join-Path $out 'agents') $file.Name) @(Split-KiraLine (Read-KiraText $file.FullName)) $values $file.FullName
        }
    }
    $claudeMd = Join-Path $claude 'CLAUDE.md'
    if (Test-Path -LiteralPath $claudeMd) {
        Write-KiraRendered (Join-Path $out 'CLAUDE.md') @(Split-KiraLine (Read-KiraText $claudeMd)) $values $claudeMd
    }
}

# Where an installed file comes from; symbolic links always point into the clone.
function Get-KiraBuiltPath([string]$Relative) {
    $rel = $Relative.Replace('/', $Sep)
    if ($script:Mode -eq 'link') { return Join-Path (Join-Path $script:Src 'dist') $rel }
    return Join-Path $script:BuildDir $rel
}

# --- Install --------------------------------------------------------------------------------

function Install-KiraStyle {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:Src 'personas') -Filter '*.md' -File | Sort-Object Name) {
        $styleName = $file.BaseName
        if ($styleName.StartsWith('_')) { continue }
        if ($Persona.Count -gt 0 -and $Persona -notcontains $styleName) { continue }
        Install-KiraFile (Get-KiraBuiltPath "output-styles/$styleName.md") (Join-Path (Join-Path $ClaudeDir 'output-styles') "$styleName.md")
    }
}

# Set "outputStyle" in settings.json to the default style, leaving every other setting as it
# is: Claude Code writes to this file too, so it is edited in place, never replaced.
function Install-KiraOutputStyle([string]$Style) {
    $settings = Join-Path $ClaudeDir 'settings.json'
    $styleFile = Join-Path (Join-Path $script:BuildDir 'output-styles') "$Style.md"
    $value = ''
    foreach ($line in @(Split-KiraLine (Read-KiraText $styleFile))) {
        if ($line.StartsWith('name: ')) { $value = $line.Substring(6); break }
    }
    if ($value -eq '' -or $value.Contains('"') -or $value.Contains('\')) { throw "cannot use the name of $Style as outputStyle: $value" }
    $entry = '"outputStyle": "' + $value + '"'

    $exists = Test-Path -LiteralPath $settings
    $text = if ($exists) { Read-KiraText $settings } else { '' }
    if ($text.Contains($entry)) { Write-KiraLog "up to date: $settings (outputStyle)"; return }

    if ($text -eq '' -or ($text -replace '\s', '') -eq '{}') {
        $new = '{' + $Nl + '  ' + $entry + $Nl + '}' + $Nl
    } elseif ($text -match '"outputStyle"\s*:') {
        $new = [regex]::Replace($text, '"outputStyle"\s*:\s*"[^"]*"', $entry.Replace('$', '$$'))
    } else {
        $out = New-Object System.Collections.Generic.List[string]
        $done = $false
        foreach ($line in @(Split-KiraLine $text)) {
            $i = $line.IndexOf('{')
            if (-not $done -and $i -ge 0) {
                $out.Add($line.Substring(0, $i + 1))
                $out.Add('  ' + $entry + ',')
                $rest = $line.Substring($i + 1)
                if ($rest -match '[^ \t]') { $out.Add($rest) }
                $done = $true
                continue
            }
            $out.Add($line)
        }
        $new = Join-KiraLine $out.ToArray()
    }

    if ($exists) { Backup-KiraPath -Path $settings -CopyOnly | Out-Null }
    Write-KiraLog "set outputStyle: $value in $settings"
    if (-not $DryRun) {
        Initialize-KiraDirectory $ClaudeDir
        Write-KiraText $settings $new
    }
}

function Install-KiraClaude([string]$Style) {
    if (Test-Path -LiteralPath (Join-Path $script:BuildDir 'CLAUDE.md')) {
        Install-KiraFile (Get-KiraBuiltPath 'CLAUDE.md') (Join-Path $ClaudeDir 'CLAUDE.md')
    }
    $agents = Join-Path (Join-Path $script:Src 'claude') 'agents'
    if (Test-Path -LiteralPath $agents) {
        foreach ($file in Get-ChildItem -LiteralPath $agents -Filter '*.md' -File | Sort-Object Name) {
            Install-KiraFile (Get-KiraBuiltPath "agents/$($file.Name)") (Join-Path (Join-Path $ClaudeDir 'agents') $file.Name)
        }
    }
    # Skills are directories holding a SKILL.md, installed as a whole.
    $skills = Join-Path (Join-Path $script:Src 'claude') 'skills'
    if (Test-Path -LiteralPath $skills) {
        foreach ($dir in Get-ChildItem -LiteralPath $skills -Directory | Sort-Object Name) {
            if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md'))) { continue }
            Install-KiraFile (Get-KiraBuiltPath "skills/$($dir.Name)") (Join-Path (Join-Path $ClaudeDir 'skills') $dir.Name)
        }
    }
    Install-KiraOutputStyle $Style
}

# Copy github\ into the target repository's .github directory. Files are always copied:
# they belong to that repository and are committed there.
function Install-KiraGithub {
    $root = $Target
    if (-not $root) {
        # Windows PowerShell 5.1 turns a native command's error output into a terminating error.
        $ErrorActionPreference = 'Continue'
        $root = & git rev-parse --show-toplevel 2>$null
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0 -or -not $root) { throw '-Only github needs a Git repository: run it from one or pass -Target DIR' }
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "not a directory: $root" }
    $root = (Resolve-Path -LiteralPath $root).ProviderPath.TrimEnd('\', '/')
    Write-KiraLog "github target: $(Join-Path $root '.github')"
    $script:Mode = 'copy'
    $source = Join-Path $script:Src 'github'
    $prefix = 'github/' + (Split-Path -Leaf $root) + '/'
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' } | Sort-Object FullName) {
        $rel = $file.FullName.Substring($source.Length + 1)
        Install-KiraFile $file.FullName (Join-Path (Join-Path $root '.github') $rel) $root $prefix
    }
}

# Merge this run's destinations into the manifest read by -Uninstall, and the backups of files
# that were there before kirakit into the list of originals.
function Save-KiraManifest {
    if ($script:Installed.Count -eq 0) { return }
    if ($DryRun) { Write-DryRun "record installed files in $ManifestPath"; return }
    $all = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $ManifestPath) { $all.AddRange([IO.File]::ReadAllLines($ManifestPath, $Utf8)) }
    $all.AddRange($script:Installed)
    $sorted = $all | Where-Object { $_ } | Sort-Object -Unique
    Write-KiraText $ManifestPath (Join-KiraLine @($sorted))
    if ($script:OriginalsNew.Count -gt 0) {
        $previous = if (Test-Path -LiteralPath $OriginalsPath) { Read-KiraText $OriginalsPath } else { '' }
        Write-KiraText $OriginalsPath ($previous + (Join-KiraLine $script:OriginalsNew.ToArray()))
    }
}

# Remove what the manifest lists: symbolic links are deleted, copies are moved to the
# backups, and files that were there before kirakit are restored.
function Invoke-KiraUninstall {
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "nothing to uninstall: $ManifestPath not found" }
    $originals = @{}
    if (Test-Path -LiteralPath $OriginalsPath) {
        foreach ($line in [IO.File]::ReadAllLines($OriginalsPath, $Utf8)) {
            $fields = $line.Split("`t")
            if ($fields.Count -eq 2 -and -not $originals.ContainsKey($fields[0])) { $originals[$fields[0]] = $fields[1] }
        }
    }
    foreach ($path in [IO.File]::ReadAllLines($ManifestPath, $Utf8)) {
        if (-not $path) { continue }
        if ($path -match '(^|[\\/])\.\.([\\/]|$)' -or -not $path.StartsWith($ClaudeDir + $Sep)) {
            Write-KiraLog "skip: $path"
            continue
        }
        if (Get-KiraLinkTarget $path) {
            Write-KiraLog "remove link: $path"
            if ($DryRun) { Write-DryRun "remove $path" } else { (Get-Item -LiteralPath $path -Force).Delete() }
        } elseif (Test-Path -LiteralPath $path) {
            Backup-KiraPath -Path $path | Out-Null
        }
        if ($originals.ContainsKey($path) -and (Test-KiraPresent $originals[$path])) {
            Write-KiraLog "restore: $($originals[$path]) -> $path"
            if ($DryRun) { Write-DryRun "move $($originals[$path]) to $path" } else { Move-Item -LiteralPath $originals[$path] -Destination $path }
        }
    }
    Write-KiraLog "remove manifest: $ManifestPath"
    if ($DryRun) {
        Write-DryRun "remove $ManifestPath and $OriginalsPath"
    } else {
        Remove-Item -LiteralPath $ManifestPath -Force
        if (Test-Path -LiteralPath $OriginalsPath) { Remove-Item -LiteralPath $OriginalsPath -Force }
    }
    Write-KiraLog "kept: $ProfilePath, $(Join-Path $ClaudeDir '.kirakit-backups') and the outputStyle setting"
}

# --- Main -----------------------------------------------------------------------------------

$exitCode = 0
try {
    if ($Bound.ContainsKey('CoAuthor') -and ($CoAuthor -eq '' -or -not (Test-KiraCoAuthor $CoAuthor))) {
        throw "invalid co-author: $CoAuthor (expected `"NAME <EMAIL>`")"
    }
    foreach ($personaName in @($Persona) + @($DefaultStyle | Where-Object { $_ })) {
        if ($personaName -notmatch '^[A-Za-z0-9_-]+$') { throw "invalid persona name: $personaName" }
    }
    if ($DryRun) { Write-KiraLog 'dry run: nothing will be changed' }

    if ($Uninstall) {
        Invoke-KiraUninstall
    } else {
        # Use the clone this script lives in, if any; otherwise fetch the repository.
        if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'personas') '_core.md'))) {
            $script:Src = $PSScriptRoot
            $onWindows = $env:OS -eq 'Windows_NT'
            $script:Mode = if ($Link) { 'link' } elseif ($Copy -or $onWindows) { 'copy' } else { 'link' }
        } else {
            if ($Link) { throw '-Link needs a local clone: run get-kira.ps1 from the repository' }
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required' }
            $repoDir = Join-Path (Get-KiraWorkDir) 'repo'
            $ref = Get-KiraRef
            Write-KiraLog "fetching $Repo ($ref)"
            & git clone --quiet --depth 1 --branch $ref -- $Repo $repoDir
            if ($LASTEXITCODE -ne 0) { throw "could not fetch $Repo" }
            $script:Src = $repoDir
            $script:Mode = 'copy'
        }
        foreach ($personaName in @($Persona) + @($DefaultStyle | Where-Object { $_ })) {
            if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $script:Src 'personas') "$personaName.md"))) { throw "unknown persona: $personaName" }
        }
        Write-KiraLog "source: $($script:Src) ($($script:Mode) mode)"

        if ($Only -eq 'github') {
            Install-KiraGithub
        } else {
            Write-KiraLog "target: $ClaudeDir"
            $userProfile = Get-KiraProfile
            if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $script:Src 'personas') "$($userProfile.style).md"))) {
                throw "unknown default style: $($userProfile.style)"
            }
            $shownName = if ($userProfile.name) { $userProfile.name } else { '(no name)' }
            $shownCoAuthor = if ($userProfile.co_author) { $userProfile.co_author } else { 'none' }
            Write-KiraLog "profile: $shownName, $($userProfile.gender), language $($userProfile.language), co-author $shownCoAuthor, style $($userProfile.style)"
            Build-KiraOutput $userProfile
            if (-not $Only -or $Only -eq 'styles') { Install-KiraStyle }
            if (-not $Only -or $Only -eq 'claude') { Install-KiraClaude $userProfile.style }
            Save-KiraManifest
        }
    }
    Write-KiraLog 'done'
} catch {
    [Console]::Error.WriteLine("kirakit: error: $($_.Exception.Message)")
    $exitCode = 1
} finally {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) { Remove-Item -LiteralPath $script:Work -Recurse -Force }
}

# Only exit when run as a file: exiting from a script block would close the caller's session.
if ($PSCommandPath) { exit $exitCode }
