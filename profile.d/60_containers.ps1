# 60_containers.ps1 - dynamic KUBECONFIG (PowerShell mirror of 60_containers.sh).
# If $HOME\.kube\config.d exists and contains files, KUBECONFIG is the list of
# them, joined with ';' on Win32 (kubectl.exe is a native binary and expects
# the platform list separator) and ':' elsewhere. Never set when the directory
# is missing or empty - an inherited KUBECONFIG is left alone otherwise.
# Unlike the sh version, the list is sorted by name (deterministic) and has no
# trailing separator (kubectl treats empty entries as "no file" either way).
$kubeConfigDir = Join-Path $HOME '.kube\config.d'
if (Test-Path -LiteralPath $kubeConfigDir -PathType Container) {
    $kubeFiles = @(Get-ChildItem -LiteralPath $kubeConfigDir -File)
    if ($kubeFiles.Count -gt 0) {
        $sep = ':'
        if ($env:OS -eq 'Windows_NT') { $sep = ';' }
        $env:KUBECONFIG = ($kubeFiles |
            Sort-Object Name |
            ForEach-Object { $_.FullName }) -join $sep
    }
}
Remove-Variable -Name kubeConfigDir, kubeFiles -ErrorAction SilentlyContinue
