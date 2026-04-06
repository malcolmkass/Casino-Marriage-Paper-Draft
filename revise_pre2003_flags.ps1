param(
  [Parameter(Mandatory = $true)]
  [string]$InputCsv
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$CENSUS_ADJ_URL = "https://www2.census.gov/geo/docs/reference/county_adjacency.txt"

function UtcNowIso() { return ([DateTimeOffset]::UtcNow).ToString("o") }
function Normalize([string]$s) { if ($null -eq $s) { return "" }; return $s.Trim() }

function Download-Text([string]$url) {
  $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell" }
  return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 180 -Headers $headers).Content
}

function Make-Geoid([string]$gestfips, [string]$gtco, [string]$fallbackGeoid) {
  try {
    $st = [int](Normalize $gestfips)
    $co = [int](Normalize $gtco)
    return $st.ToString("00") + $co.ToString("000")
  } catch {
    $fg = Normalize $fallbackGeoid
    if ($fg -match "^\d{5}$") { return $fg }
    return ""
  }
}

function Build-NeighborsMap([string]$adjTxt) {
  $neighbors = @{} # geoid -> HashSet[string]
  $lines = $adjTxt -split "`n"
  $curG = $null
  foreach ($raw in $lines) {
    if ($null -eq $raw) { continue }
    $line = ($raw -replace "`r", "")
    if ($line.Trim() -eq "") { continue }
    $parts = $line.Split("`t", [System.StringSplitOptions]::None)
    if ($parts.Count -lt 4) { continue }
    $cg = (Normalize $parts[1])
    if ($cg -match "^\d{5}$" -and (Normalize $parts[0]) -ne "") { $curG = $cg }
    $g1 = $curG
    $g2 = (Normalize $parts[3])
    if ($null -eq $g1 -or $g1 -notmatch "^\d{5}$") { continue }
    if ($g2 -notmatch "^\d{5}$") { continue }
    if (-not $neighbors.ContainsKey($g1)) { $neighbors[$g1] = [System.Collections.Generic.HashSet[string]]::new() }
    if (-not $neighbors.ContainsKey($g2)) { $neighbors[$g2] = [System.Collections.Generic.HashSet[string]]::new() }
    $null = $neighbors[$g1].Add($g2)
    $null = $neighbors[$g2].Add($g1)
  }
  return $neighbors
}

# Counties with evidence of Vegas-style casino gaming (slots/tables) before 2003.
# Use 5-digit county GEOIDs.
$pre2003Vegas = [System.Collections.Generic.HashSet[string]]::new()
@(
  # AZ
  "04013" # Casino Arizona opened 1998 (Maricopa)

  # MI (Detroit casinos)
  "26163" # Wayne (MGM 1999, etc)

  # CA
  "06005" # Amador (Jackson Rancheria slots pre-2003)
  "06097" # Sonoma (River Rock opened 2002)

  # NM (adjacent-county effects common)
  "35001" # Bernalillo (Sandia 1994)
  "35043" # Sandoval (Santa Ana Star 1993)

  # OK
  "40031" # Comanche (Apache Casino Hotel 1999)

  # IA
  "19193" # Woodbury (Sioux City riverboat casinos started 1993)

  # MS
  "28001" # Adams (Natchez dockside casino 1993)

  # LA / KC metro adjacency & Shreveport-Bossier area
  "22015" # Bossier (Horseshoe 1994)
  "22017" # Caddo (Shreveport riverboats began 1994)

  # NV
  "32007" # Elko (Wendover casinos pre-2003)
  "32510" # Carson City (Carson Nugget 1954)

  # MO (Kansas City metro)
  "29047" # Clay (Harrah's North Kansas City 1994)
  "29165" # Platte (Argosy Riverside 1994)

  # NY (Niagara)
  "36063" # Niagara (Seneca Niagara opened 2002)

  # OR (Douglas County: Seven Feathers casino 1994)
  "41019"
) | ForEach-Object { $null = $pre2003Vegas.Add($_) }

$outPath = [System.IO.Path]::Combine((Split-Path $InputCsv), ([System.IO.Path]::GetFileNameWithoutExtension($InputCsv) + "_pre2003revised.csv"))
$logPath = [System.IO.Path]::Combine((Split-Path $InputCsv), "pre2003revised_run_log.json")

$runLog = [ordered]@{
  started_utc = (UtcNowIso)
  input_csv = $InputCsv
  output_csv = $outPath
  sources = [ordered]@{
    census_adjacency_url = $CENSUS_ADJ_URL
  }
  counts = [ordered]@{}
  notes = @(
    "Rules: if tot_casino_no > 1 => force both indicators to 1.",
    "For tot_casino_no = 1: pre2003casino_cas_co_only is group-level (base county) indicator; pre2003_casino_near_co is county-level (self or any neighbor in pre2003Vegas).",
    "pre2003Vegas list is curated; extend as needed."
  )
  finished_utc = $null
}

$rows = Import-Csv -Path $InputCsv

$adjTxt = Download-Text $CENSUS_ADJ_URL
$neighbors = Build-NeighborsMap $adjTxt

# Identify base GEOID per casino_name
$baseByCasino = @{} # casino_name -> base_geoid
$forceAllOnesByCasino = [System.Collections.Generic.HashSet[string]]::new() # casino_name where base tot_casino_no > 1
$groups = $rows | Group-Object casino_name
$badBases = New-Object System.Collections.Generic.List[object]

foreach ($g in $groups) {
  $bases = @($g.Group | Where-Object { (Normalize $_.casino_co) -eq "1" })
  if ($bases.Count -ne 1) {
    $badBases.Add([pscustomobject]@{ casino_name=$g.Name; issue="base_count_not_1"; base_count=$bases.Count }) | Out-Null
    continue
  }
  $b = $bases[0]
  $bg = Make-Geoid $b.gestfips $b.gtco $b.county_geoid
  if ($bg -eq "") {
    $badBases.Add([pscustomobject]@{ casino_name=$g.Name; issue="base_geoid_missing" }) | Out-Null
    continue
  }
  $baseByCasino[$g.Name] = $bg

  # If the base county has tot_casino_no > 1, force both flags to 1 for all rows in this casino_name group.
  $totBase = Normalize $b.tot_casino_no
  if ($totBase -ne "" -and [int]$totBase -gt 1) {
    $null = $forceAllOnesByCasino.Add($g.Name)
  }
}

$updatedTot1 = 0
$updatedTotGt1 = 0

foreach ($r in $rows) {
  $tot = Normalize $r.tot_casino_no
  $casino = $r.casino_name
  $rowGeoid = Make-Geoid $r.gestfips $r.gtco $r.county_geoid

  if ($forceAllOnesByCasino.Contains($casino)) {
    $r.pre2003casino_cas_co_only = "1"
    $r.pre2003_casino_near_co = "1"
    $updatedTotGt1++
    continue
  }

  if ($tot -eq "1" -and $baseByCasino.ContainsKey($casino)) {
    $baseGeoid = $baseByCasino[$casino]
    $baseHasPre = $pre2003Vegas.Contains($baseGeoid)
    $r.pre2003casino_cas_co_only = $(if ($baseHasPre) { "1" } else { "0" })

    $near = $false
    if ($rowGeoid -ne "" -and $pre2003Vegas.Contains($rowGeoid)) { $near = $true }
    elseif ($rowGeoid -ne "" -and $neighbors.ContainsKey($rowGeoid)) {
      foreach ($ng in $neighbors[$rowGeoid]) {
        if ($pre2003Vegas.Contains($ng)) { $near = $true; break }
      }
    }
    if ($baseHasPre) { $near = $true } # enforce implication
    $r.pre2003_casino_near_co = $(if ($near) { "1" } else { "0" })
    $updatedTot1++
    continue
  }
}

$rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8

$runLog.counts.rows_total = $rows.Count
$runLog.counts.casino_groups = $groups.Count
$runLog.counts.bad_base_groups = $badBases.Count
$runLog.counts.rows_updated_tot1 = $updatedTot1
$runLog.counts.rows_forced_totgt1 = $updatedTotGt1
$runLog.counts.pre2003Vegas_geoids = $pre2003Vegas.Count
if ($badBases.Count -gt 0) { $runLog.bad_base_sample = @($badBases | Select-Object -First 50) }
$runLog.finished_utc = (UtcNowIso)
$runLog | ConvertTo-Json -Depth 6 | Out-File -FilePath $logPath -Encoding UTF8

Write-Host ("Wrote " + $outPath)
Write-Host ("Wrote " + $logPath)

