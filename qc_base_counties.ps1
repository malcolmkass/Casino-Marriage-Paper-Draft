param(
  [Parameter(Mandatory = $true)]
  [string]$InputCsv
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Normalize-Text([string]$s) { if ($null -eq $s) { return "" }; return $s.Trim() }

function Detect-Delimiter([string]$path) {
  $first = (Get-Content -Path $path -TotalCount 1)
  if ($first -match "`t") { return "`t" }
  return ","
}

function Make-Geoid([string]$gestfips, [string]$gtco) {
  $st = [int](Normalize-Text $gestfips)
  $co = [int](Normalize-Text $gtco)
  return $st.ToString("00") + $co.ToString("000")
}

$delim = Detect-Delimiter $InputCsv
$rows = Import-Csv -Path $InputCsv -Delimiter $delim

$groups = $rows | Group-Object casino_name
$issues = New-Object System.Collections.Generic.List[object]
$baseRows = New-Object System.Collections.Generic.List[object]

foreach ($g in $groups) {
  $base = @($g.Group | Where-Object { (Normalize-Text $_.casino_co) -eq "1" })
  if ($base.Count -ne 1) {
    $issues.Add([pscustomobject]@{
      casino_name = $g.Name
      issue = "base_count_not_1"
      base_count = $base.Count
    }) | Out-Null
    continue
  }

  $b = $base[0]
  $computed = Make-Geoid $b.gestfips $b.gtco
  $county_geoid = Normalize-Text $b.county_geoid
  $source_base_geoid = Normalize-Text $b.source_base_geoid

  $baseRows.Add([pscustomobject]@{
    casino_name = $g.Name
    tuyear = $b.tuyear
    Location = $b.Location
    gestfips = $b.gestfips
    gtco = $b.gtco
    casino_id = $b.casino_id
    county_geoid = $county_geoid
    source_base_geoid = $source_base_geoid
    near_county = $b.near_county
  }) | Out-Null

  if ($county_geoid -ne "" -and $county_geoid -ne $computed) {
    $issues.Add([pscustomobject]@{
      casino_name = $g.Name
      issue = "county_geoid_mismatch"
      county_geoid = $county_geoid
      computed = $computed
    }) | Out-Null
  }
  if ($source_base_geoid -ne "" -and $source_base_geoid -ne $computed) {
    $issues.Add([pscustomobject]@{
      casino_name = $g.Name
      issue = "source_base_geoid_mismatch"
      source_base_geoid = $source_base_geoid
      computed = $computed
    }) | Out-Null
  }
  if ((Normalize-Text $b.near_county) -ne "0") {
    $issues.Add([pscustomobject]@{
      casino_name = $g.Name
      issue = "base_near_county_not_0"
      near_county = $b.near_county
    }) | Out-Null
  }
}

Write-Host ("Total casinos: " + $groups.Count)
Write-Host ("Issues found: " + $issues.Count)

if ($issues.Count -gt 0) {
  $issues | Sort-Object casino_name, issue | Format-Table -AutoSize | Out-String -Width 250 | Write-Host
} else {
  Write-Host "No structural issues in base rows."
}

# Also write a handy base-row listing for manual review
$baseOut = Join-Path (Split-Path $InputCsv) "casino_base_rows.csv"
$baseRows | Sort-Object casino_name | Export-Csv -Path $baseOut -NoTypeInformation -Encoding UTF8
Write-Host ("Wrote " + $baseOut)

