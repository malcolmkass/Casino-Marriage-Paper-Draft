param(
  [Parameter(Mandatory = $true)]
  [string]$InputCsv
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RequiredColumns = @(
  "casino_name",
  "tuyear",
  "Location",
  "gestfips",
  "gtco",
  "casino_id",
  "casino_co",
  "near_county",
  "county_area"
)

$FCC_FIPS_URL = "https://transition.fcc.gov/oet/info/maps/census/fips/fips.txt"
$CENSUS_ADJ_URL = "https://www2.census.gov/geo/docs/reference/county_adjacency.txt"

function UtcNowIso() {
  return ([DateTimeOffset]::UtcNow).ToString("o")
}

function Normalize-Whitespace([string]$s) {
  return ($s -replace "\s+", " ").Trim()
}

function Normalize-CountyName([string]$name) {
  $s = Normalize-Whitespace $name
  # Use single-quoted regex to avoid PowerShell backtick escaping issues
  $s = $s -replace '["''`]', ""
  $s = $s -replace "[\.,]", ""
  $s = $s -replace "\b(County|Parish|Borough|Census Area|Municipality|City and Borough|District)\b", ""
  return (Normalize-Whitespace $s).ToLowerInvariant()
}

function Pad2([int]$n) { return $n.ToString("00") }
function Pad3([int]$n) { return $n.ToString("000") }
function Make-Geoid([int]$st, [int]$co) { return (Pad2 $st) + (Pad3 $co) }

function Try-ParseInt([string]$s) {
  if ($null -eq $s) { return $null }
  $t = ($s.ToString()).Trim()
  if ($t -eq "") { return $null }
  $v = 0
  if ([int]::TryParse($t, [ref]$v)) { return $v }
  return $null
}

function Download-Text([string]$url) {
  # Use basic parsing to avoid IE dependency
  $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell" }
  $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 180 -Headers $headers
  return $resp.Content
}

function Build-FccFipsLookup([string]$fipsTxt) {
  $stateMap = @{}  # key: state name/abbr uppercase -> "NN"
  $countyMap = @{} # key: "NN|normalized_county" -> "MMM"

  $lines = $fipsTxt -split "`n"
  foreach ($raw in $lines) {
    $ln = ($raw -replace "`r", "").TrimEnd()
    if ($ln.Trim() -eq "") { continue }

    # FCC fips.txt has two sections:
    # - State-level: "01        ALABAMA" (two-digit FIPS + state name)
    # - County-level: "01001     Autauga County" (five-digit FIPS + place name)
    $mState = [regex]::Match($ln, "^\s*(\d{2})\s+([A-Z][A-Z ]+)\s*$")
    if ($mState.Success) {
      $st2 = $mState.Groups[1].Value
      $stName = $mState.Groups[2].Value.Trim()
      if ($stName -ne "") { $stateMap[$stName.ToUpperInvariant()] = $st2 }
      continue
    }

    $mCounty = [regex]::Match($ln, "^\s*(\d{5})\s+(.+?)\s*$")
    if (-not $mCounty.Success) { continue }
    $geoid = $mCounty.Groups[1].Value
    $place = $mCounty.Groups[2].Value.Trim()
    if ($place -eq "") { continue }

    $st2 = $geoid.Substring(0, 2)
    $co3 = $geoid.Substring(2, 3)

    # "NN000 <StateName>" lines appear in the county-level section too; use them to map mixed-case names.
    if ($co3 -eq "000") {
      $stateMap[$place.ToUpperInvariant()] = $st2
      continue
    }

    $k = "$st2|$(Normalize-CountyName $place)"
    $countyMap[$k] = $co3
  }

  return @{
    StateMap = $stateMap
    CountyMap = $countyMap
  }
}

function Lookup-Geoid([string]$state, [string]$county, $stateMap, $countyMap) {
  $stKey = (Normalize-Whitespace $state).ToUpperInvariant()
  if (-not $stateMap.ContainsKey($stKey)) {
    return @{ Geoid = $null; Reason = "unknown_state:$state" }
  }
  $st2 = $stateMap[$stKey]
  $coKey = "$st2|$(Normalize-CountyName $county)"
  if (-not $countyMap.ContainsKey($coKey)) {
    return @{ Geoid = $null; Reason = "unknown_county:$county" }
  }
  return @{ Geoid = "$st2$($countyMap[$coKey])"; Reason = $null }
}

function Build-NeighborsMap([string]$adjTxt) {
  $neighbors = @{}    # geoid -> HashSet[string]
  $geoidToName = @{}  # geoid -> name

  $lines = $adjTxt -split "`n"
  $currentCountyGeoid = $null
  $currentCountyName = $null

  function Unquote([string]$s) {
    if ($null -eq $s) { return "" }
    $t = $s.Trim()
    if ($t.StartsWith('"') -and $t.EndsWith('"') -and $t.Length -ge 2) {
      return $t.Substring(1, $t.Length - 2)
    }
    return $t
  }

  foreach ($raw in $lines) {
    $ln = ($raw -replace "`r", "").Trim()
    if ($ln -eq "") { continue }

    # Two observed formats:
    # - pipe-delimited: geoid|name|neighbor_geoid|neighbor_name
    # - tab-delimited hierarchical: "County, ST"\t01001\t"Neighbor, ST"\t01003
    #   followed by lines like: \t\t"Neighbor, ST"\t01021 (county repeated implicitly)
    if ($ln.Contains("|")) {
      $parts = $ln -split "\|"
      if ($parts.Count -lt 4) { continue }
      $g1 = $parts[0].Trim()
      $n1 = $parts[1].Trim()
      $g2 = $parts[2].Trim()
      $n2 = $parts[3].Trim()
      if ($g1 -notmatch "^\d{5}$" -or $g2 -notmatch "^\d{5}$") { continue }

      if (-not $geoidToName.ContainsKey($g1)) { $geoidToName[$g1] = $n1 }
      if (-not $geoidToName.ContainsKey($g2)) { $geoidToName[$g2] = $n2 }

      if (-not $neighbors.ContainsKey($g1)) { $neighbors[$g1] = [System.Collections.Generic.HashSet[string]]::new() }
      if (-not $neighbors.ContainsKey($g2)) { $neighbors[$g2] = [System.Collections.Generic.HashSet[string]]::new() }
      $null = $neighbors[$g1].Add($g2)
      $null = $neighbors[$g2].Add($g1)
    } else {
      # tab-delimited
      $lineNoCr = ($raw -replace "`r", "")
      $parts = $lineNoCr.Split("`t", [System.StringSplitOptions]::None)
      if ($parts.Count -lt 4) { continue }

      $countyNameRaw = $parts[0]
      $countyGeoidRaw = $parts[1]
      $neighborNameRaw = $parts[2]
      $neighborGeoidRaw = $parts[3]

      if ((Normalize-Whitespace $countyNameRaw) -ne "" -and (Normalize-Whitespace $countyGeoidRaw) -ne "") {
        $currentCountyName = Unquote $countyNameRaw
        $currentCountyGeoid = (Normalize-Whitespace $countyGeoidRaw)
      }

      $g1 = $currentCountyGeoid
      $n1 = $currentCountyName
      $g2 = (Normalize-Whitespace $neighborGeoidRaw)
      $n2 = Unquote $neighborNameRaw

      if ($null -eq $g1 -or $g1 -notmatch "^\d{5}$") { continue }
      if ($g2 -notmatch "^\d{5}$") { continue }

      if (-not $geoidToName.ContainsKey($g1) -and ($n1 + "").Trim() -ne "") { $geoidToName[$g1] = $n1 }
      if (-not $geoidToName.ContainsKey($g2) -and ($n2 + "").Trim() -ne "") { $geoidToName[$g2] = $n2 }

      if (-not $neighbors.ContainsKey($g1)) { $neighbors[$g1] = [System.Collections.Generic.HashSet[string]]::new() }
      if (-not $neighbors.ContainsKey($g2)) { $neighbors[$g2] = [System.Collections.Generic.HashSet[string]]::new() }
      $null = $neighbors[$g1].Add($g2)
      $null = $neighbors[$g2].Add($g1)
    }
  }

  return @{
    Neighbors = $neighbors
    GeoidToName = $geoidToName
  }
}

function Row-Geoid($row) {
  $st = Try-ParseInt $row.gestfips
  $co = Try-ParseInt $row.gtco
  if ($null -eq $st -or $null -eq $co) { return $null }
  return Make-Geoid $st $co
}

function Assert-RequiredColumns($rows) {
  if ($rows.Count -eq 0) { throw "CSV appears to have no rows." }
  $cols = $rows[0].PSObject.Properties.Name
  $missing = @()
  foreach ($c in $RequiredColumns) {
    if ($cols -notcontains $c) { $missing += $c }
  }
  if ($missing.Count -gt 0) {
    throw ("Missing required columns: " + ($missing -join ", "))
  }
  return $cols
}

$runLog = [ordered]@{
  started_utc = (UtcNowIso)
  input_csv = $InputCsv
  outputs = [ordered]@{
    "counties_enriched.csv" = "counties_enriched.csv"
    "needs_manual_review.csv" = "needs_manual_review.csv"
    "run_log.json" = "run_log.json"
  }
  sources = [ordered]@{
    fcc_fips_url = $FCC_FIPS_URL
    census_adjacency_url = $CENSUS_ADJ_URL
  }
  counts = [ordered]@{}
  errors = @()
}

try {
  # Step 0: Load CSV and validate columns
  # Note: this input file uses classic Mac-style CR line endings in places. Normalize to LF before parsing.
  $rawCsv = Get-Content -Path $InputCsv -Raw -Encoding UTF8
  $rawCsv = $rawCsv -replace "`r`n", "`n"
  $rawCsv = $rawCsv -replace "`r", "`n"
  # Support both comma-CSV and tab-delimited files (Excel sometimes saves as TSV while keeping .csv name).
  $firstLine = ($rawCsv -split "`n", 2)[0]
  $delim = ","
  if ($firstLine -match "`t") { $delim = "`t" }
  $rows = $rawCsv | ConvertFrom-Csv -Delimiter $delim
  $originalCols = Assert-RequiredColumns $rows

  # Step 1: Build FIPS lookup table from FCC fips.txt
  $stateMap = @{}
  $countyMap = @{}
  try {
    $fipsTxt = Download-Text $FCC_FIPS_URL
    $look = Build-FccFipsLookup $fipsTxt
    $stateMap = $look.StateMap
    $countyMap = $look.CountyMap
    $runLog.counts.fcc_states_parsed = ($stateMap.Values | Sort-Object -Unique).Count
    $runLog.counts.fcc_counties_parsed = $countyMap.Count
    if ($runLog.counts.fcc_counties_parsed -eq 0) {
      $sample = $fipsTxt.Substring(0, [Math]::Min(300, $fipsTxt.Length))
      $runLog.errors += @{ step = 1; reason = "fcc_parse_zero_rows"; sample = $sample }
    }
  } catch {
    $runLog.errors += @{ step = 1; reason = "fcc_download_or_parse_failed"; detail = $PSItem.Exception.Message }
  }

# Deliverable function (available in-session): Lookup-Geoid
# Example:
#   Lookup-Geoid -state "CA" -county "San Diego County" -stateMap $stateMap -countyMap $countyMap

  # Step 2: Get adjacency data and build neighbors map
  $neighbors = @{}
  $geoidToName = @{}
  try {
    $adjTxt = Download-Text $CENSUS_ADJ_URL
    $adj = Build-NeighborsMap $adjTxt
    $neighbors = $adj.Neighbors
    $geoidToName = $adj.GeoidToName
    $runLog.counts.adjacency_geoids = $neighbors.Count
    $degSum = 0
    foreach ($k in $neighbors.Keys) { $degSum += $neighbors[$k].Count }
    $runLog.counts.adjacency_pairs_total_degree = $degSum

    # Augment stateMap with USPS abbreviations from adjacency names ("County, ST")
    foreach ($g in $geoidToName.Keys) {
      $nm = $geoidToName[$g]
      if ($nm -match ",\s*([A-Z]{2})\s*$") {
        $abbr = $Matches[1]
        $st2 = $g.Substring(0, 2)
        if (-not $stateMap.ContainsKey($abbr)) { $stateMap[$abbr] = $st2 }
      }
    }
    if ($runLog.counts.adjacency_geoids -eq 0) {
      $sample = $adjTxt.Substring(0, [Math]::Min(300, $adjTxt.Length))
      $runLog.errors += @{ step = 2; reason = "adjacency_parse_zero_rows"; sample = $sample }
      throw "Adjacency file parsed to 0 geoids; cannot enrich."
    }
  } catch {
    $runLog.errors += @{ step = 2; reason = "adjacency_download_or_parse_failed"; detail = $PSItem.Exception.Message }
  }

# Prepare output columns (same as input + new)
$addedCols = @("county_geoid", "added_by_agent", "source_base_geoid")
$outCols = @($originalCols)
foreach ($c in $addedCols) {
  if ($outCols -notcontains $c) { $outCols += $c }
}

# Build indexes: existing geoids per casino, base geoids per casino (casino_co==1)
$baseGeoidsByCasino = @{}
foreach ($r in $rows) {
  $casino = $r.casino_name
  $g = Row-Geoid $r
  if (($r.casino_co + "").Trim() -eq "1" -and $null -ne $g) {
    if (-not $baseGeoidsByCasino.ContainsKey($casino)) {
      $baseGeoidsByCasino[$casino] = New-Object System.Collections.Generic.List[string]
    }
    $baseGeoidsByCasino[$casino].Add($g)
  }
}

# Build allowed GEOIDs per casino: base + adjacent counties (first ring).
# If the base GEOID is missing from adjacency, we won't filter (avoid accidental data loss).
$allowedGeoidsByCasino = @{} # casino_name -> HashSet[string]
$droppedNonAdjacent = New-Object System.Collections.Generic.List[object]
foreach ($casino in $baseGeoidsByCasino.Keys) {
  $bases = @($baseGeoidsByCasino[$casino])
  $canFilter = $true
  foreach ($bg in $bases) {
    if (-not $neighbors.ContainsKey($bg)) { $canFilter = $false }
  }
  if (-not $canFilter) { continue }
  $hs = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($bg in $bases) {
    $null = $hs.Add($bg)
    foreach ($ng in $neighbors[$bg]) { $null = $hs.Add($ng) }
  }
  $allowedGeoidsByCasino[$casino] = $hs
}

# Filter rows down to base + adjacent only (where possible).
$keptRows = New-Object System.Collections.Generic.List[object]
foreach ($r in $rows) {
  $casino = $r.casino_name
  $g = Row-Geoid $r
  if ($allowedGeoidsByCasino.ContainsKey($casino) -and $null -ne $g) {
    if (-not $allowedGeoidsByCasino[$casino].Contains($g)) {
      $droppedNonAdjacent.Add([pscustomobject]@{
        casino_name = $casino
        gestfips = $r.gestfips
        gtco = $r.gtco
        county_geoid = $g
        reason = "dropped_not_adjacent_to_base"
      }) | Out-Null
      continue
    }
  }
  $keptRows.Add($r) | Out-Null
}

# De-duplicate kept rows by (casino_name, tuyear, county_geoid).
# Prefer the row with more filled fields; break ties preferring casino_co==1, then added_by_agent==0.
$dedupedRows = New-Object System.Collections.Generic.List[object]
$dupeCount = 0
$grouped = $keptRows | Group-Object { $_.casino_name + "||" + ($_.tuyear + "") + "||" + (Row-Geoid $_) }
foreach ($g in $grouped) {
  if ($g.Count -eq 1) { $dedupedRows.Add($g.Group[0]) | Out-Null; continue }
  $dupeCount += ($g.Count - 1)
  $best = $null
  $bestScore = -1
  foreach ($r in $g.Group) {
    $score = 0
    foreach ($p in $r.PSObject.Properties) {
      $v = ($p.Value + "").Trim()
      if ($v -ne "") { $score++ }
    }
    # tie-breakers
    if ((($r.casino_co + "").Trim()) -eq "1") { $score += 1000 }
    if ((($r.added_by_agent + "").Trim()) -eq "0") { $score += 10 }
    if ($score -gt $bestScore) { $bestScore = $score; $best = $r }
  }
  $dedupedRows.Add($best) | Out-Null
}
$keptRows = $dedupedRows
$runLog.counts.duplicate_rows_removed = $dupeCount

# Rebuild existing geoids per casino based on kept rows
$existingByCasino = @{}
foreach ($r in $keptRows) {
  $casino = $r.casino_name
  if (-not $existingByCasino.ContainsKey($casino)) {
    $existingByCasino[$casino] = [System.Collections.Generic.HashSet[string]]::new()
  }
  $g = Row-Geoid $r
  if ($null -ne $g) { $null = $existingByCasino[$casino].Add($g) }
}

$manualReview = New-Object System.Collections.Generic.List[object]

# Step 3: Create new entries when needed
$newRows = New-Object System.Collections.Generic.List[object]
$created = 0
$casinosProcessed = 0
$casinosNoBase = 0
$casinosMissingAdj = 0

foreach ($casino in $existingByCasino.Keys) {
  $casinosProcessed++
  $existingGeoids = $existingByCasino[$casino]
  $baseGeoids = @()
  if ($baseGeoidsByCasino.ContainsKey($casino)) { $baseGeoids = @($baseGeoidsByCasino[$casino]) }
  if ($baseGeoids.Count -eq 0) {
    $casinosNoBase++
    $manualReview.Add([pscustomobject]@{ casino_name = $casino; reason = "no_base_row_with_casino_co_1" }) | Out-Null
    continue
  }

  # map base_geoid -> base_row object
  $baseRows = $keptRows | Where-Object { $_.casino_name -eq $casino -and (($_.casino_co + "").Trim() -eq "1") }
  $baseRowByGeoid = @{}
  foreach ($br in $baseRows) {
    $bg = Row-Geoid $br
    if ($null -ne $bg) { $baseRowByGeoid[$bg] = $br }
  }

  foreach ($bg in $baseGeoids) {
    if (-not $baseRowByGeoid.ContainsKey($bg)) {
      $manualReview.Add([pscustomobject]@{ casino_name = $casino; reason = "base_geoid_not_found_in_rows"; base_geoid = $bg }) | Out-Null
      continue
    }
    $baseRow = $baseRowByGeoid[$bg]

    if (-not $neighbors.ContainsKey($bg)) {
      $casinosMissingAdj++
      $manualReview.Add([pscustomobject]@{
        casino_name = $casino
        tuyear = $baseRow.tuyear
        Location = $baseRow.Location
        gestfips = $baseRow.gestfips
        gtco = $baseRow.gtco
        county_geoid = $bg
        base_county_name = $(if ($geoidToName.ContainsKey($bg)) { $geoidToName[$bg] } else { "" })
        reason = "base_geoid_not_in_adjacency_map"
      }) | Out-Null
      continue
    }

    # HashSet[T] doesn't expose a .ToArray() instance method; let PowerShell enumerate it.
    $neighborList = @($neighbors[$bg]) | Sort-Object
    foreach ($ng in $neighborList) {
      if ($existingGeoids.Contains($ng)) { continue }

      $st = [int]$ng.Substring(0, 2)
      $co = [int]$ng.Substring(2, 3)

      # Create a new ordered object with all columns
      $o = [ordered]@{}
      foreach ($c in $outCols) { $o[$c] = "" }

      # Copy first 3 columns from base row
      $o["casino_name"] = $baseRow.casino_name
      $o["tuyear"] = $baseRow.tuyear
      $o["Location"] = $baseRow.Location

      # Set requested fields
      $o["gestfips"] = $st.ToString()
      $o["gtco"] = $co.ToString()
      $o["casino_id"] = (100 * $st + $co).ToString()
      $o["casino_co"] = "0"
      $o["near_county"] = "1"
      $o["county_area"] = "1"

      # Enriched helper columns
      $o["county_geoid"] = $ng
      $o["added_by_agent"] = "1"
      $o["source_base_geoid"] = $bg

      $newRows.Add([pscustomobject]$o) | Out-Null
      $null = $existingGeoids.Add($ng)
      $created++
    }
  }
}

# Fill enriched columns for original rows
$enrichedOriginalRows = New-Object System.Collections.Generic.List[object]
foreach ($r in $keptRows) {
  $o = [ordered]@{}
  foreach ($c in $outCols) {
    if ($r.PSObject.Properties.Name -contains $c) {
      $o[$c] = $r.$c
    } else {
      $o[$c] = ""
    }
  }
  # Always normalize county_geoid from gestfips/gtco to a 5-digit GEOID (preserves leading zeros).
  $g = Row-Geoid $r
  $o["county_geoid"] = $(if ($null -ne $g) { $g } else { "" })
  if (($o["added_by_agent"] + "").Trim() -eq "") { $o["added_by_agent"] = "0" }
  # Fill source_base_geoid for ALL rows when we can identify a base county (casino_co==1)
  $casinoName = $r.casino_name
  $base = ""
  if ($baseGeoidsByCasino.ContainsKey($casinoName) -and $baseGeoidsByCasino[$casinoName].Count -gt 0) {
    $base = $baseGeoidsByCasino[$casinoName][0]
  }
  # Always set source_base_geoid when we know the base.
  if ($base -ne "") { $o["source_base_geoid"] = $base }
  $enrichedOriginalRows.Add([pscustomobject]$o) | Out-Null
}

# Step 4: Quality control
$qcIssues = New-Object System.Collections.Generic.List[object]
$allRowsForQc = @($enrichedOriginalRows.ToArray()) + @($newRows.ToArray())
$rowIndex = 0
foreach ($r in $allRowsForQc) {
  $rowIndex++
  $st = Try-ParseInt $r.gestfips
  $co = Try-ParseInt $r.gtco
  $g = ($r.county_geoid + "").Trim()
  if ($g -eq "" -and $null -ne $st -and $null -ne $co) { $g = Make-Geoid $st $co }

  if ($null -eq $st -or $null -eq $co) {
    $qcIssues.Add([pscustomobject]@{ row = $rowIndex; reason = "missing_fips"; gestfips = $r.gestfips; gtco = $r.gtco }) | Out-Null
    continue
  }
  if ((Pad2 $st) -notmatch "^\d{2}$") {
    $qcIssues.Add([pscustomobject]@{ row = $rowIndex; reason = "state_fips_not_2_digits"; gestfips = $r.gestfips }) | Out-Null
  }
  if ((Pad3 $co) -notmatch "^\d{3}$") {
    $qcIssues.Add([pscustomobject]@{ row = $rowIndex; reason = "county_fips_not_3_digits"; gtco = $r.gtco }) | Out-Null
  }
  if ($g -notmatch "^\d{5}$") {
    $qcIssues.Add([pscustomobject]@{ row = $rowIndex; reason = "county_geoid_not_5_digits"; county_geoid = $g }) | Out-Null
  }
}

  $runLog.counts.input_rows = $rows.Count
  $runLog.counts.casinos_processed = $casinosProcessed
  $runLog.counts.casinos_without_base_row = $casinosNoBase
  $runLog.counts.casinos_missing_adjacency_for_base = $casinosMissingAdj
  $runLog.counts.new_adjacent_rows_created = $created
$runLog.counts.dropped_not_adjacent_rows = $droppedNonAdjacent.Count
  $runLog.counts.qc_issue_count = $qcIssues.Count
  $runLog.counts.manual_review_count = $manualReview.Count

if ($qcIssues.Count -gt 0) {
  $runLog["qc_issue_sample"] = @($qcIssues | Select-Object -First 50)
}
if ($droppedNonAdjacent.Count -gt 0) {
  $runLog["dropped_not_adjacent_sample"] = @($droppedNonAdjacent | Select-Object -First 50)
}

# Step 5: Write outputs
$outEnriched = "counties_enriched.csv"
$outReview = "needs_manual_review.csv"
$outLog = "run_log.json"

@($enrichedOriginalRows.ToArray()) + @($newRows.ToArray()) | Export-Csv -Path $outEnriched -NoTypeInformation -Encoding UTF8
$manualReview | Export-Csv -Path $outReview -NoTypeInformation -Encoding UTF8

  $runLog.finished_utc = (UtcNowIso)
  $runLog | ConvertTo-Json -Depth 8 | Out-File -FilePath $outLog -Encoding UTF8

  Write-Host "Wrote $outEnriched ($($enrichedOriginalRows.Count + $newRows.Count) rows; +$($newRows.Count) new)."
  Write-Host "Wrote $outReview ($($manualReview.Count) rows)."
  Write-Host "Wrote $outLog."
} catch {
  $msg = $PSItem.Exception.Message
  $pos = ""
  if ($PSItem.InvocationInfo -and $PSItem.InvocationInfo.PositionMessage) { $pos = $PSItem.InvocationInfo.PositionMessage }
  Write-Error "FAILED: $msg`n$pos"
  throw
}

