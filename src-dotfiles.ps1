# src-dotfiles.ps1 - PowerShell entrypoint for the dotfiles, the analog of
# src-dotfiles.sh. Works in Windows PowerShell 5.1 and PowerShell Core
# (7.x). Wire it from $PROFILE:
#
#   . "$HOME\dotfiles\src-dotfiles.ps1"
#
# Like src-dotfiles.sh it only sources profile.d/*.ps1 snippets in sorted
# order. It does NOT translate the POSIX *.sh / *.bash snippets - those
# belong to Git Bash; the PowerShell flow has its own .ps1 mirrors.
#
# Idempotency guard, mirroring the one in src-dotfiles.sh (DR-027). The bash
# guard exists because Termux's $PREFIX/etc/profile sources ~/.bashrc itself
# and bash (login) reads ~/.bash_profile after /etc/profile; in PowerShell
# the equivalent hazard is $PROFILE being dot-sourced more than once in a
# session (e.g. a manual re-source after editing it). Kept as a global
# (session-local) variable, deliberately NOT an env var, so a fresh process
# starts clean - same semantics as the bash guard.
if ($global:DOTFILES_SOURCED) { return }
$global:DOTFILES_SOURCED = $true

# Locate the dotfiles root: $env:DOTFILES wins, else this script's directory.
if ($env:DOTFILES) {
    $dotfiles = $env:DOTFILES
} else {
    $dotfiles = $PSScriptRoot
}
if (-not $dotfiles) {
    $dotfiles = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Source profile.d/*.ps1 in sorted order. Snippets are dot-sourced so their
# functions/aliases persist in the session (same contract as src-dotfiles.sh
# and its 10_..90_ prefix ordering).
$snippets = @(
    Get-ChildItem -LiteralPath (Join-Path $dotfiles 'profile.d') -Filter '*.ps1' -ErrorAction SilentlyContinue |
        Sort-Object Name
)
foreach ($snippet in $snippets) {
    . $snippet.FullName
}
