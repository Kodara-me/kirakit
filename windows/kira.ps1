<#
.SYNOPSIS
Start Claude Code as {{assistant_name}}, the assistant.
.DESCRIPTION
Without -Team, the session is solo: the user and {{assistant_name}} work together directly,
with no watch of GitHub and outside the team flow (rules/solo.md). With -Team, the session
leads the team and starts the lead's watch of GitHub, unless it only prints an answer
(-p, --print), whose own prompt would then be a second one. Any other argument goes to claude.
.PARAMETER Team
Lead the team, with all the watchers.
#>
param([switch]$Team)

$ErrorActionPreference = 'Stop'
if ($Team) {
    $print = ($args -contains '-p') -or ($args -contains '--print')
    if ($print) { & claude -n '{{assistant_name}}' @args } else { & claude -n '{{assistant_name}}' '/watch' @args }
} else {
    & claude -n '{{assistant_name}}' --append-system-prompt 'Kirakit solo mode: follow rules/solo.md.' @args
}
exit $LASTEXITCODE
