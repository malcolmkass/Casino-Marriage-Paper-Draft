param(
  [Parameter(Mandatory = $true)]
  [string]$InputCsv
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RequiredColumns = @(
  "casino_name","tuyear","Location","gestfips","gtco","casino_id","casino_co","near_county","county_area"
)

$CENSUS_ADJ_URL = "https://www2.census.gov/geo/docs/reference/county_adjacency.txt"

function UtcNowIso() { return ([DateTimeOffset]::UtcNow).ToString("o") }
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

function Download-Text([string]$url) {
  $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell" }
  return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 180 -Headers $headers).Content
}

function Build-NeighborsMap([string]$adjTxt) {
  $neighbors = @{}    # geoid -> HashSet[string]

  $lines = $adjTxt -split "`n"
  $currentCountyGeoid = $null

  foreach ($raw in $lines) {
    if ($null -eq $raw) { continue }
    $ln = ($raw -replace "`r", "").TrimEnd()
    if ($ln.Trim() -eq "") { continue }

    if ($ln.Contains("|")) {
      $parts = $ln -split "\|"
      if ($parts.Count -lt 3) { continue }
      $g1 = ($parts[0].Trim())
      $g2 = ($parts[2].Trim())
      if ($g1 -notmatch "^\d{5}$" -or $g2 -notmatch "^\d{5}$") { continue }
      if (-not $neighbors.ContainsKey($g1)) { $neighbors[$g1] = [System.Collections.Generic.HashSet[string]]::new() }
      if (-not $neighbors.ContainsKey($g2)) { $neighbors[$g2] = [System.Collections.Generic.HashSet[string]]::new() }
      $null = $neighbors[$g1].Add($g2)
      $null = $neighbors[$g2].Add($g1)
    } else {
      # tab-delimited hierarchical
      $parts = ($raw -replace "`r", "").Split("`t", [System.StringSplitOptions]::None)
      if ($parts.Count -lt 4) { continue }
      $countyGeoidRaw = Normalize-Text $parts[1]
      $neighborGeoidRaw = Normalize-Text $parts[3]

      if ($countyGeoidRaw -match "^\d{5}$") { $currentCountyGeoid = $countyGeoidRaw }
      $g1 = $currentCountyGeoid
      $g2 = $neighborGeoidRaw
      if ($null -eq $g1 -or $g1 -notmatch "^\d{5}$") { continue }
      if ($g2 -notmatch "^\d{5}$") { continue }

      if (-not $neighbors.ContainsKey($g1)) { $neighbors[$g1] = [System.Collections.Generic.HashSet[string]]::new() }
      if (-not $neighbors.ContainsKey($g2)) { $neighbors[$g2] = [System.Collections.Generic.HashSet[string]]::new() }
      $null = $neighbors[$g1].Add($g2)
      $null = $neighbors[$g2].Add($g1)
    }
  }

  return $neighbors
}

function Assert-Columns($rows) {
  if ($rows.Count -eq 0) { throw "CSV has no rows." }
  $cols = $rows[0].PSObject.Properties.Name
  $missing = @()
  foreach ($c in $RequiredColumns) { if ($cols -notcontains $c) { $missing += $c } }
  if ($missing.Count -gt 0) { throw ("Missing required columns: " + ($missing -join ", ")) }
  return $cols
}

# Apply known base-county corrections (no new rows added).
# These fix cases where the casino county was miscoded or casino_co flags were missing.
function Apply-BaseCorrections([object[]]$rows) {
  # Desired base GEOIDs (state2+county3)
  $overrides = @{
    "Casino Fandango" = "32510"          # Carson City, NV (independent city)
    "Live! Casino Pittsburgh" = "42129"  # Westmoreland County, PA
    "Rivers Casino Pittsburgh" = "42003" # Allegheny County, PA
    "WinStar World Casino" = "40085"     # Love County, OK
  }

  foreach ($casino in $overrides.Keys) {
    $target = $overrides[$casino]
    $g = @($rows | Where-Object { $_.casino_name -eq $casino })
    if ($g.Count -eq 0) { continue }

    # If a row already matches the target GEOID, use it as base.
    $matching = @($g | Where-Object { (Make-Geoid $_.gestfips $_.gtco) -eq $target })
    if ($matching.Count -ge 1) {
      foreach ($r in $g) {
        $rowGeoid = Make-Geoid $r.gestfips $r.gtco
        if ($rowGeoid -eq $target) { $r.casino_co = "1"; $r.near_county = "0" }
        else { $r.casino_co = "0"; $r.near_county = "1" }
      }
      continue
    }

    # Otherwise, if there is exactly one currently-marked base row, rewrite its FIPS to the target GEOID.
    $bases = @($g | Where-Object { (Normalize-Text $_.casino_co) -eq "1" })
    if ($bases.Count -eq 1) {
      $b = $bases[0]
      $st = [int]$target.Substring(0, 2)
      $co = [int]$target.Substring(2, 3)
      $b.gestfips = $st.ToString()
      $b.gtco = $co.ToString()
      $b.casino_id = (100 * $st + $co).ToString()
      $b.near_county = "0"
      foreach ($r in $g) {
        if ($r -ne $b) { $r.casino_co = "0"; $r.near_county = "1" }
      }
    }
  }
}

$runLog = [ordered]@{
  started_utc = (UtcNowIso)
  input_csv = $InputCsv
  outputs = [ordered]@{
    cleaned_csv = "casino_specific_data_v1_cleaned.csv"
    dropped_rows_csv = "casino_specific_data_v1_dropped_rows.csv"
    manual_review_csv = "casino_specific_data_v1_needs_manual_review.csv"
    run_log_json = "casino_specific_data_v1_clean_run_log.json"
  }
  sources = [ordered]@{
    census_adjacency_url = $CENSUS_ADJ_URL
  }
  counts = [ordered]@{}
  errors = @()
}

try {
  $delim = Detect-Delimiter $InputCsv
  $rows = Import-Csv -Path $InputCsv -Delimiter $delim
  $cols = Assert-Columns $rows

  $adjTxt = Download-Text $CENSUS_ADJ_URL
  $neighbors = Build-NeighborsMap $adjTxt

  Apply-BaseCorrections -rows $rows

  # base per casino (exactly one casino_co==1)
  $groups = $rows | Group-Object casino_name
  $baseByCasino = @{} # casino_name -> geoid
  $needsReview = New-Object System.Collections.Generic.List[object]

  foreach ($g in $groups) {
    $bases = @($g.Group | Where-Object { (Normalize-Text $_.casino_co) -eq "1" })
    if ($bases.Count -ne 1) {
      $needsReview.Add([pscustomobject]@{ casino_name=$g.Name; reason="base_count_not_1"; base_count=$bases.Count }) | Out-Null
      continue
    }
    $b = $bases[0]
    $baseByCasino[$g.Name] = Make-Geoid $b.gestfips $b.gtco
  }

  $kept = New-Object System.Collections.Generic.List[object]
  $dropped = New-Object System.Collections.Generic.List[object]

  foreach ($r in $rows) {
    $casino = $r.casino_name
    $rowGeoid = Make-Geoid $r.gestfips $r.gtco

    if ($baseByCasino.ContainsKey($casino)) {
      $baseGeoid = $baseByCasino[$casino]
      if ($neighbors.ContainsKey($baseGeoid)) {
        $allowed = $neighbors[$baseGeoid]
        $isBase = ($rowGeoid -eq $baseGeoid)
        $isNeighbor = $allowed.Contains($rowGeoid)
        if (-not ($isBase -or $isNeighbor)) {
          $dropped.Add([pscustomobject]@{
            casino_name=$casino; tuyear=$r.tuyear; Location=$r.Location;
            gestfips=$r.gestfips; gtco=$r.gtco; county_geoid=$rowGeoid;
            reason="not_adjacent_to_base"; base_geoid=$baseGeoid
          }) | Out-Null
          continue
        }

        # Clean flags (do not touch casino_no / tot_casino_no)
        if ($isBase) {
          $r.casino_co = "1"
          $r.near_county = "0"
        } else {
          $r.casino_co = "0"
          $r.near_county = "1"
        }
        $r.county_area = "1"
        $r.casino_id = (100 * [int]$r.gestfips + [int]$r.gtco).ToString()
      } else {
        $needsReview.Add([pscustomobject]@{ casino_name=$casino; reason="base_geoid_not_in_adjacency"; base_geoid=$baseGeoid }) | Out-Null
      }
    }

    $kept.Add($r) | Out-Null
  }

  $outClean = Join-Path (Split-Path $InputCsv) $runLog.outputs.cleaned_csv
  $outDropped = Join-Path (Split-Path $InputCsv) $runLog.outputs.dropped_rows_csv
  $outReview = Join-Path (Split-Path $InputCsv) $runLog.outputs.manual_review_csv
  $outLog = Join-Path (Split-Path $InputCsv) $runLog.outputs.run_log_json

  $kept | Export-Csv -Path $outClean -NoTypeInformation -Encoding UTF8
  $dropped | Export-Csv -Path $outDropped -NoTypeInformation -Encoding UTF8
  $needsReview | Export-Csv -Path $outReview -NoTypeInformation -Encoding UTF8

  $runLog.counts.input_rows = $rows.Count
  $runLog.counts.output_rows = $kept.Count
  $runLog.counts.dropped_rows = $dropped.Count
  $runLog.counts.casinos_total = $groups.Count
  $runLog.counts.casinos_with_base = $baseByCasino.Keys.Count
  $runLog.counts.manual_review_rows = $needsReview.Count
  $runLog.finished_utc = (UtcNowIso)
  $runLog | ConvertTo-Json -Depth 6 | Out-File -FilePath $outLog -Encoding UTF8

  Write-Host ("Wrote " + $outClean + " (" + $kept.Count + " rows).")
  Write-Host ("Wrote " + $outDropped + " (" + $dropped.Count + " rows).")
  Write-Host ("Wrote " + $outReview + " (" + $needsReview.Count + " rows).")
  Write-Host ("Wrote " + $outLog + ".")
} catch {
  $runLog.errors += @{ reason="exception"; detail=$PSItem.Exception.Message }
  $runLog.finished_utc = (UtcNowIso)
  $outLog = Join-Path (Split-Path $InputCsv) $runLog.outputs.run_log_json
  $runLog | ConvertTo-Json -Depth 6 | Out-File -FilePath $outLog -Encoding UTF8
  throw
}

