param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Paths
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $Paths -or $Paths.Count -eq 0) {
    $Paths = Get-ChildItem -Path (Join-Path $root 'scripts') -Recurse -Filter *.ps1 |
        Select-Object -ExpandProperty FullName
}

if (-not $Paths -or $Paths.Count -eq 0) {
    Write-Error 'powershell syntax check: no ps1 files discovered'
}

$failed = $false
foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Error "powershell syntax check: file not found: $path"
    }

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) > $null
    if ($parseErrors.Count -gt 0) {
        $failed = $true
        foreach ($parseError in $parseErrors) {
            Write-Error ("powershell syntax check fail: {0}:{1}: {2}" -f $path, $parseError.Extent.StartLineNumber, $parseError.Message)
        }
    }
}

if ($failed) {
    exit 1
}

Write-Output 'powershell syntax check: ok'
