# 70_history.ps1 - atuin (PowerShell): history hooks + Ctrl-R search.
# PowerShell mirror of 70_history.{bash,zsh}. Roughly:
#   atuin init powershell | Out-String | Invoke-Expression
# but atuin is only trusted from the allowlisted locations below, and only
# after a --version smoke test (DR-016). Windows-only for now: the
# candidates are %LOCALAPPDATA%\mise, ~/.local/share/mise and scoop shims
# (PE binaries - the `.exe` spelling is embedded per DR-028). POSIX
# PowerShell would need its own cascade.
if ($env:OS -eq 'Windows_NT') {
    $la = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
    $scoop = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }

    $atuin = $null
    foreach ($cand in @(
        (Join-Path $la 'mise\shims\atuin.exe'),
        (Join-Path $env:USERPROFILE '.local\share\mise\shims\atuin.exe'),
        (Join-Path $scoop 'shims\atuin.exe')
    )) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            & $cand --version *>$null
            if ($LASTEXITCODE -eq 0) { $atuin = $cand; break }
        }
    }
    if ($atuin) {
        try {
            & $atuin init powershell | Out-String | Invoke-Expression
        } catch {
            # The init blob may reference PSReadLine internals missing on
            # some hosts - a failed hook must not break the session.
        }
    }
}
