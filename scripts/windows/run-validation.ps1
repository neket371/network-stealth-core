param(
    [string]$Ref = "",
    [string]$Repo = "",
    [switch]$SkipLocal,
    [switch]$SkipRemote,
    [switch]$NoWatch,
    [switch]$IncludeNightly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Resolve-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-RepoSlug {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [string]$ExplicitRepo
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRepo)) {
        return $ExplicitRepo.Trim()
    }

    $origin = (& git -C $RepoRoot remote get-url origin).Trim()
    if ($origin -match 'github\.com[:/](?<slug>[A-Za-z0-9._-]+/[A-Za-z0-9._-]+?)(?:\.git)?$') {
        return $Matches["slug"]
    }
    throw "Unable to resolve GitHub repo slug from origin: $origin"
}

function Get-BranchRef {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [string]$ExplicitRef
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRef)) {
        return $ExplicitRef.Trim()
    }

    $branch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    if ($branch -eq "HEAD") {
        throw "Detached HEAD detected. Pass -Ref <branch-or-tag> explicitly."
    }
    return $branch
}

function Invoke-LocalValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $detectScript = Join-Path $RepoRoot "scripts\windows\detect-bash.ps1"
    if (-not (Test-Path -LiteralPath $detectScript)) {
        throw "Bash detector not found: $detectScript"
    }

    $bashPath = (& $detectScript | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($bashPath)) {
        throw "Unable to detect bash.exe. Set BASH_EXE and retry."
    }

    Write-Step "Local QA: make ci-full (WIN_BASH=$bashPath)"
    Push-Location $RepoRoot
    try {
        & make "WIN_BASH=$bashPath" ci-full
        if ($LASTEXITCODE -ne 0) {
            throw "make ci-full failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

function Start-WorkflowAndWait {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoSlug,
        [Parameter(Mandatory = $true)]
        [string]$Workflow,
        [Parameter(Mandatory = $true)]
        [string]$Ref,
        [switch]$NoWatch
    )

    Write-Step "Trigger workflow: $Workflow (ref=$Ref)"
    $runId = ""
    $dispatchOutput = & gh workflow run $Workflow --ref $Ref --repo $RepoSlug 2>&1
    if ($LASTEXITCODE -eq 0) {
        Start-Sleep -Seconds 3
        $runId = (& gh run list --repo $RepoSlug --workflow $Workflow --branch $Ref --event workflow_dispatch --limit 1 --json databaseId --jq ".[0].databaseId").Trim()
    } else {
        $dispatchText = ($dispatchOutput | Out-String).Trim()
        if ($dispatchText -match "does not have 'workflow_dispatch' trigger") {
            Write-Host "Workflow $Workflow has no workflow_dispatch trigger; using rerun fallback."
            $runId = (& gh run list --repo $RepoSlug --workflow $Workflow --branch $Ref --limit 1 --json databaseId --jq ".[0].databaseId").Trim()
            if ([string]::IsNullOrWhiteSpace($runId) -or $runId -eq "null") {
                throw "No previous run found for rerun fallback: $Workflow"
            }
            & gh run rerun $runId --repo $RepoSlug
            if ($LASTEXITCODE -ne 0) {
                throw "Failed rerun fallback for workflow $Workflow (run id: $runId)"
            }
        } else {
            throw "Failed to trigger workflow ${Workflow}: $dispatchText"
        }
    }

    if ([string]::IsNullOrWhiteSpace($runId) -or $runId -eq "null") {
        throw "Unable to resolve run id for workflow $Workflow"
    }

    Write-Host "Run id: $runId"
    if (-not $NoWatch) {
        & gh run watch $runId --repo $RepoSlug --exit-status
        if ($LASTEXITCODE -ne 0) {
            throw "Workflow failed: $Workflow (run id: $runId)"
        }
    }
}

$repoRoot = Resolve-RepoRoot

Write-Step "Repo root: $repoRoot"

if (-not $SkipLocal) {
    Invoke-LocalValidation -RepoRoot $repoRoot
}

if (-not $SkipRemote) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) is not installed."
    }
    & gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "gh auth status failed. Run: gh auth login"
    }

    $repoSlug = Get-RepoSlug -RepoRoot $repoRoot -ExplicitRepo $Repo
    $resolvedRef = Get-BranchRef -RepoRoot $repoRoot -ExplicitRef $Ref

    $workflows = @("ci.yml", "os-matrix-smoke.yml")
    if ($IncludeNightly) {
        $workflows += "nightly-smoke.yml"
    }

    foreach ($workflow in $workflows) {
        Start-WorkflowAndWait -RepoSlug $repoSlug -Workflow $workflow -Ref $resolvedRef -NoWatch:$NoWatch
    }
}

Write-Step "Validation flow finished successfully."
