# 40_completion.ps1 - kubectl (PowerShell): shell completion.
# PowerShell mirror of the kubectl branch in 40_completion.{bash,zsh}. Roughly:
#   kubectl completion powershell | Out-String | Invoke-Expression
# kubectl is only trusted from the allowlisted locations below (the same Win32
# cascade as 70_history.ps1: %LOCALAPPDATA%\mise shims, ~/.local/share/mise
# shims, scoop shims - PE binaries, the `.exe` spelling is embedded per
# DR-028), and only after a --version smoke test (DR-016). Windows-only for
# now: the candidates are native-binary locations. POSIX PowerShell would need
# its own cascade.
if ($env:OS -eq 'Windows_NT') {
    $la = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
    $scoop = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }

    $kubectl = $null
    foreach ($cand in @(
        (Join-Path $la 'mise\shims\kubectl.exe'),
        (Join-Path $env:USERPROFILE '.local\share\mise\shims\kubectl.exe'),
        (Join-Path $scoop 'shims\kubectl.exe')
    )) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            & $cand --version *>$null
            if ($LASTEXITCODE -eq 0) { $kubectl = $cand; break }
        }
    }
    if ($kubectl) {
        try {
            & $kubectl completion powershell | Out-String | Invoke-Expression
        } catch {
            # The completion blob may assume PSReadLine or a newer PS host -
            # a failed hook must not break the session.
        }
    }
}
