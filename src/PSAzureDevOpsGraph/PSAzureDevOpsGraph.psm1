#Requires -Version 7.2
Set-StrictMode -Version Latest

# Dot-source Private first: Public functions depend on them at call time, but
# loading in a defined order keeps failures readable when one file is broken.
foreach ($scope in 'Private', 'Public') {
    $dir = Join-Path $PSScriptRoot $scope
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | Sort-Object Name) {
        try { . $file.FullName }
        catch { throw "Failed to load $($file.FullName): $_" }
    }
}

$public = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue).BaseName
if ($public) { Export-ModuleMember -Function $public }
