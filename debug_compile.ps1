param(
  [Parameter(Mandatory=$false)][string]$tex = "main.tex"
)

$ErrorActionPreference = "Stop"

function Write-DebugNdjson {
  param(
    [Parameter(Mandatory=$true)][string]$hypothesisId,
    [Parameter(Mandatory=$true)][string]$location,
    [Parameter(Mandatory=$true)][string]$message,
    [Parameter(Mandatory=$false)][hashtable]$data
  )

  #region agent log
  $logPath = Join-Path $PSScriptRoot "debug-5a1461.log"
  #endregion

  $payload = @{
    sessionId = "5a1461"
    runId = "pre-fix"
    hypothesisId = $hypothesisId
    location = $location
    message = $message
    data = $data
    timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  }
  try {
    #region agent log
    ($payload | ConvertTo-Json -Compress) + "`n" | Out-File -FilePath $logPath -Append -Encoding utf8
    #endregion
  } catch {
    # best-effort logging; never break compile on log failure
  }
}

try {
  Write-DebugNdjson -hypothesisId "A" -location "debug_compile.ps1:25" -message "Starting LaTeX compile" -data @{
    pwd = (Get-Location).Path
    tex = $tex
    os = $env:OS
    username = $env:USERNAME
  }

  Write-DebugNdjson -hypothesisId "A" -location "debug_compile.ps1:31" -message "Input file existence" -data @{
    texPath = (Join-Path (Get-Location).Path $tex)
    exists = (Test-Path -LiteralPath (Join-Path (Get-Location).Path $tex))
  }

  Write-DebugNdjson -hypothesisId "A" -location "debug_compile.ps1:32" -message "PowerShell runtime" -data @{
    psVersion = $PSVersionTable.PSVersion.ToString()
    psEdition = $PSVersionTable.PSEdition
    nativeCmdEap = if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) { $PSNativeCommandUseErrorActionPreference } else { $null }
    errorActionPreference = $ErrorActionPreference
  }

  $latexmk = Get-Command latexmk -ErrorAction SilentlyContinue
  $pdflatex = Get-Command pdflatex -ErrorAction SilentlyContinue
  $bibtex = Get-Command bibtex -ErrorAction SilentlyContinue
  $biber = Get-Command biber -ErrorAction SilentlyContinue

  Write-DebugNdjson -hypothesisId "A" -location "debug_compile.ps1:38" -message "Resolved LaTeX commands" -data @{
    hasLatexmk = [bool]$latexmk
    hasPdflatex = [bool]$pdflatex
    latexmk = if ($latexmk) { $latexmk.Source } else { $null }
    pdflatex = if ($pdflatex) { $pdflatex.Source } else { $null }
    hasBibtex = [bool]$bibtex
    hasBiber = [bool]$biber
    bibtex = if ($bibtex) { $bibtex.Source } else { $null }
    biber = if ($biber) { $biber.Source } else { $null }
  }

  $cmd = $null
  $args = @()
  if ($latexmk) {
    $cmd = $latexmk.Source
    $args = @("-pdf", "-interaction=nonstopmode", "-file-line-error", $tex)
  } elseif ($pdflatex) {
    $cmd = $pdflatex.Source
    $args = @("-interaction=nonstopmode", "-file-line-error", $tex)
  } else {
    throw "Neither latexmk nor pdflatex found on PATH."
  }

  Write-DebugNdjson -hypothesisId "A" -location "debug_compile.ps1:60" -message "Running compile command" -data @{
    command = $cmd
    args = ($args -join " ")
  }

  # Native commands may emit harmless stderr that PowerShell treats as errors (esp. PS7+).
  # Capture all output as text and rely on the process exit code instead.
  $oldEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $hadNativePref = [bool](Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue)
  if ($hadNativePref) { $oldNativePref = $PSNativeCommandUseErrorActionPreference; $PSNativeCommandUseErrorActionPreference = $false }
  $outputObjs = & $cmd @args 2>&1
  $exit = $LASTEXITCODE
  if ($hadNativePref) { $PSNativeCommandUseErrorActionPreference = $oldNativePref }
  $ErrorActionPreference = $oldEap

  $output = ($outputObjs | ForEach-Object { $_.ToString() }) -join "`n"
  $outputLines = @()
  if ($output) { $outputLines = ($output -split "`r?`n") }

  $errorLines = @()
  $errorLines += ($outputLines | Where-Object { $_ -match "^\!" -or $_ -match "LaTeX Error" -or $_ -match "Emergency stop" -or $_ -match "Fatal error" } | Select-Object -First 30)
  $missingFiles = @()
  $missingFiles += ($outputLines | Where-Object { $_ -match "No file .*" -or $_ -match "not found" -or $_ -match "I can't find file" } | Select-Object -First 30)
  $outputHead = @()
  $outputTail = @()
  $outputHead += ($outputLines | Select-Object -First 40)
  $outputTail += ($outputLines | Select-Object -Last 60)

  Write-DebugNdjson -hypothesisId "B" -location "debug_compile.ps1:75" -message "Compile finished" -data @{
    exitCode = $exit
    errorLines = $errorLines
    missingFiles = $missingFiles
    outputChars = $output.Length
    outputHead = $outputHead
    outputTail = $outputTail
  }

  # Hypothesis C: latexmk can return non-zero due to prior errors even when targets are up-to-date.
  $looksLikeStaleLatexmkError = $false
  if ($latexmk -and $exit -ne 0 -and ($output -match "All targets .* are up-to-date") -and ($output -match "gave an error in previous invocation of latexmk")) {
    $looksLikeStaleLatexmkError = $true
  }

  if ($looksLikeStaleLatexmkError) {
    Write-DebugNdjson -hypothesisId "C" -location "debug_compile.ps1:109" -message "Detected stale latexmk error state; cleaning and rerunning" -data @{
      exitCode = $exit
      tex = $tex
    }

    # Clean aux-type files (keep pdf) to reset latexmk error state, then rerun.
    $cleanArgs = @("-c", $tex)
    $runArgs = @("-pdf", "-interaction=nonstopmode", "-file-line-error", $tex)

    $oldEap2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $hadNativePref2 = [bool](Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue)
    if ($hadNativePref2) { $oldNativePref2 = $PSNativeCommandUseErrorActionPreference; $PSNativeCommandUseErrorActionPreference = $false }

    $cleanOutObjs = & $latexmk.Source @cleanArgs 2>&1
    $cleanExit = $LASTEXITCODE
    $runOutObjs = & $latexmk.Source @runArgs 2>&1
    $exit2 = $LASTEXITCODE

    if ($hadNativePref2) { $PSNativeCommandUseErrorActionPreference = $oldNativePref2 }
    $ErrorActionPreference = $oldEap2

    $cleanOut = (($cleanOutObjs | ForEach-Object { $_.ToString() }) -join "`n")
    $runOut = (($runOutObjs | ForEach-Object { $_.ToString() }) -join "`n")

    $cleanTail = @()
    if ($cleanOut) { $cleanTail = (($cleanOut -split "`r?`n") | Select-Object -Last 40) }
    $runTail = @()
    if ($runOut) { $runTail = (($runOut -split "`r?`n") | Select-Object -Last 80) }

    Write-DebugNdjson -hypothesisId "C" -location "debug_compile.ps1:135" -message "Clean+rerun finished" -data @{
      cleanExitCode = $cleanExit
      rerunExitCode = $exit2
      cleanTail = $cleanTail
      rerunTail = $runTail
    }

    if ($exit2 -ne 0) {
      throw "Compile failed with exit code $exit2 (after clean+rereun)"
    }
  } elseif ($exit -ne 0) {
    throw "Compile failed with exit code $exit"
  }

  Write-Host "Compile succeeded."
} catch {
  Write-DebugNdjson -hypothesisId "A" -location "debug_compile.ps1:90" -message "Compile script error" -data @{
    error = $_.Exception.Message
  }
  Write-Error $_
  exit 1
}

