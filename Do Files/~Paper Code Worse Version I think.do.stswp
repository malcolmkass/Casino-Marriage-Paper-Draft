/*==============================================================================
COMPLETE PAPER ANALYSIS: CASINO EFFECTS ON FAMILY AND COMMUNITY INSTITUTIONS
Creates all tables and figures for paper in sequence
==============================================================================*/

clear all
set more off
set maxvar 10000

* Set working directories - CHANGE THESE TO YOUR ACTUAL PATHS
global data "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Data"
global output "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Output"

* Create output directory if it doesn't exist
capture mkdir "$output"

cap log close
log using "$output/relgiouspaper_analysis_log.txt", replace text

* Install required packages if needed
capture ssc install coefplot
capture ssc install reghdfe
capture ssc install estout

/*==============================================================================
PART I: DATA PREPARATION
==============================================================================*/

display ""
display "=============================================================="
display "=== PART I: DATA PREPARATION ==="
display "=============================================================="

/*------------------------------------------------------------------------------
1. LOAD AND PREPARE CASINO DATA (EXACT MATCH TO ORIGINAL)
------------------------------------------------------------------------------*/

use "$data\casino_data.dta", clear

* Focus only on casino counties (not neighboring counties) initially
keep if casino_co == 1

* Create unique county identifier (state + county FIPS)
gen county_id = gestfips * 1000 + gtco

* For counties with multiple casino openings, keep the earliest treatment year
bysort county_id: egen min_treat_year = min(treat_year)
replace treat_year = min_treat_year
drop min_treat_year

* Keep one observation per county-year and relevant variables
keep county_id tuyear gestfips gtco treat_year casino_no
rename tuyear year
duplicates drop county_id year, force

* Generate treatment variables
gen treated = 1  // All observations are casino counties
gen post_treatment = (year >= treat_year) if !missing(treat_year)
gen treat_post = treated * post_treatment
gen rel_time = year - treat_year if !missing(treat_year)

* Create complete balanced panel 2000-2023 for casino counties
preserve
keep county_id treat_year gestfips gtco casino_no
bysort county_id: egen max_casino_no = max(casino_no)
replace casino_no = max_casino_no
drop max_casino_no
duplicates drop county_id, force
tempfile county_info
save `county_info'
restore

* Expand to full panel
keep county_id year
expand 24
bysort county_id: replace year = 1999 + _n
keep if year >= 2000 & year <= 2023

* Remove duplicates and merge back county info
duplicates drop county_id year, force
merge m:1 county_id using `county_info', keep(match) nogen

* Recreate treatment variables for full panel
gen treated = 1
gen post_treatment = (year >= treat_year) if !missing(treat_year)
gen treat_post = treated * post_treatment
gen rel_time = year - treat_year if !missing(treat_year)

tempfile casino_clean_basic
save `casino_clean_basic'

* Now load full casino data including nearby counties
clear
use "$data\casino_data.dta", clear
gen county_id = gestfips * 1000 + gtco
gen casino_county = (casino_co == 1)
gen nearby_county = (near_co == 1)

* Clean treatment year
bysort county_id: egen min_treat_year = min(treat_year) if casino_county == 1
bysort county_id: egen treat_year_clean = max(min_treat_year)
replace treat_year = treat_year_clean if casino_county == 1
drop min_treat_year treat_year_clean

* Keep necessary variables
keep county_id tuyear gestfips gtco treat_year casino_no casino_county nearby_county 
rename tuyear year
duplicates drop county_id year, force

* Generate treatment variables
gen treated = casino_county
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0
gen treat_post = treated * post_treatment
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)

* Create county-level info file
preserve
    keep county_id treat_year gestfips gtco casino_no casino_county nearby_county
    bysort county_id: egen max_casino_no = max(casino_no)
    replace casino_no = max_casino_no
    drop max_casino_no
    bysort county_id: egen max_casino_county = max(casino_county)
    bysort county_id: egen max_nearby_county = max(nearby_county)
    replace casino_county = max_casino_county
    replace nearby_county = max_nearby_county
    drop max_casino_county max_nearby_county
    duplicates drop county_id, force
    tempfile county_info_full
    save `county_info_full'
restore

* Create balanced panel
keep county_id year
expand 24
bysort county_id: replace year = 1999 + _n
keep if year >= 2000 & year <= 2023
duplicates drop county_id year, force

* Merge county info back
merge m:1 county_id using `county_info_full', keep(match) nogen

* Generate treatment variables for balanced panel
gen treated_full = casino_county
gen post_treatment_full = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment_full = 0 if casino_county == 0
gen treat_post_full = treated_full * post_treatment_full
gen rel_time_full = year - treat_year if casino_county == 1 & !missing(treat_year)

tempfile casino_clean
save `casino_clean'

/*------------------------------------------------------------------------------
2. PREPARE MAIN ANALYSIS DATASET (ACS + CASINO DATA) - EXACT MATCH
------------------------------------------------------------------------------*/

use "$data\ACSData.dta", clear

* Keep only years 2000-2023
keep if year >= 2000 & year <= 2023

* Create county identifier to match casino data (statefip = gestfips, countyfip = gtco)
gen county_id = statefip * 1000 + countyfip

* Keep only adults aged 18+ (marriage-eligible population)
keep if age >= 18

* RESTRICT SAMPLE TO PEOPLE 40 AND UNDER
keep if age <= 40

* Create outcome variables
gen married = (marst == 1)  // Married, spouse present
gen divorced = (marst == 4)  // Divorced
gen widowed = (marst == 5)   // Widowed
gen never_married = (marst == 6)  // Never married

* Create marriage transition variables (first marriage proxy)
gen newly_married = (married == 1 & age >= 18 & age <= 35)  // Proxy for recent marriage

* Number of children in household (already exists as nchild)
* Create binary indicators for having children
gen has_children = (nchild > 0) if !missing(nchild)
gen num_children = nchild

* Create demographic controls
gen female = (sex == 2)
gen age_sq = age^2

* Education categories (if available in your ACS extract)
* Note: Check if education variable exists in your data
capture confirm variable educ
if _rc == 0 {
    gen high_school = (educ >= 6)  // Adjust based on your education coding
    gen college = (educ >= 10)     // Adjust based on your education coding
}

* Race/ethnicity controls
gen white = (race == 1)
gen black = (race == 2)
gen hispanic = (hispan >= 1 & hispan <= 4)

* Create age groups for heterogeneity analysis (18-29 and 30-40)
gen age_group = 1 if age >= 18 & age <= 29
replace age_group = 2 if age >= 30 & age <= 40
label define age_group_lab 1 "18-29" 2 "30-40"
label values age_group age_group_lab

* Create residence duration variables
gen acs_sample = 1
replace acs_sample = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)

sort sample serial
by sample serial: egen movedin_hh = max(movedin)
gen longterm_resident = (movedin_hh >= 4) if !missing(movedin_hh)

* Keep relevant variables
keep county_id year married divorced widowed never_married newly_married ///
     has_children num_children female age age_sq white black hispanic ///
     perwt statefip countyfip age_group longterm_resident acs_sample

/*==============================================================================
3. MERGE DATASETS AND CREATE CONTROL GROUP - EXACT MATCH
==============================================================================*/

* Merge with casino data
merge m:1 county_id year using `casino_clean'

* Create control group from counties that never get casinos
* Keep casino counties (treated) and counties that never appear in casino data (controls)
gen in_casino_data = (_merge == 3)
gen ever_treated = in_casino_data

* For control counties, set treatment variables to zero
replace treated_full = 0 if _merge == 1
replace post_treatment_full = 0 if _merge == 1  
replace treat_post_full = 0 if _merge == 1
replace treat_year = . if _merge == 1
replace rel_time_full = . if _merge == 1
replace casino_no = 0 if _merge == 1  // Control counties have 0 prior casinos
replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1

* Create sample type indicator
gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if _merge == 1

* Keep both treated and control counties
keep if _merge == 1 | _merge == 3
drop _merge

* Fill in treatment status consistently within counties
bysort county_id: egen max_ever_treated = max(ever_treated)
replace ever_treated = max_ever_treated
drop max_ever_treated

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)

* Generate final treatment variables
gen treated = casino_county
gen post_treatment = post_treatment_full
gen treat_post = treated * post_treatment
gen rel_time = rel_time_full

* Create 8-year event study variables (EXACT MATCH TO ORIGINAL)
forvalues i = 3(-1)2 {
    gen lag`i'_ext = 0  // Start with 0 for everyone (including controls)
    replace lag`i'_ext = 1 if rel_time == -`i' & !missing(rel_time)  // Only treated counties get 1
}

forvalues i = 0/7 {
    gen lead`i'_ext = 0  // Start with 0 for everyone (including controls)
    replace lead`i'_ext = 1 if rel_time == `i' & !missing(rel_time)  // Only treated counties get 1
}

gen lead8plus_ext = 0
replace lead8plus_ext = 1 if rel_time >= 8 & !missing(rel_time)

* Create spillover variables
gen casino_post = casino_county * post_treatment
gen nearby_post = nearby_county * post_treatment



/*==============================================================================
TABLE 7: RELIGIOUS ADHERENCE EFFECTS
==============================================================================*/

display ""
display "=== TABLE 7: RELIGIOUS ADHERENCE EFFECTS ==="

* Create religious analysis dataset
* Load and combine all three years of religious data
use "$data\religious_2000.dta", clear
gen county_id = fip
gen year = 2000
gen total_adherents_rate = totrt
gen evangelical_rate = evanrt
gen catholic_rate = cathrt  
gen mainline_rate = mainrt
gen southern_baptist_rate = sbcrt
gen population = POP200
gen state_code = stcod
keep county_id year *_rate population state_code

tempfile religious_2000
save `religious_2000'

use "$data\religious_2010.dta", clear
gen county_id = fips
gen year = 2010
gen total_adherents_rate = totrate
gen evangelical_rate = evanrate
gen catholic_rate = cathrate  
gen mainline_rate = mprtrate
gen southern_baptist_rate = sbcrate
gen population = POP2010
gen state_code = stcode
keep county_id year *_rate population state_code

tempfile religious_2010
save `religious_2010'

use "$data\religious_2020.dta", clear
gen county_id = fips
gen year = 2020
gen total_adherents_rate = TOTRATE_2020
gen evangelical_rate = EVANRATE_2020
gen catholic_rate = CATHRATE_2020  
gen mainline_rate = MPRTRATE_2020
gen southern_baptist_rate = SBCRATE_2020
gen population = POP2020
gen state_code = stcod
keep county_id year *_rate population state_code

* Append all years
append using `religious_2010'
append using `religious_2000'

* Merge with casino data
merge 1:1 county_id year using `casino_clean'
keep if inlist(year, 2000, 2010, 2020)

gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if _merge == 1

keep if sample_type >= 1 & sample_type <= 3

replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
drop _merge

gen donut_sample = (sample_type == 1 | sample_type == 3)

* Generate treatment variables
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0

* Create baseline religiosity terciles (using 2000 data)
preserve
keep if year == 2000
xtile baseline_religiosity_tercile = total_adherents_rate, nq(3)
keep county_id baseline_religiosity_tercile
tempfile baseline_religiosity
save `baseline_religiosity'
restore

merge m:1 county_id using `baseline_religiosity', nogen

* Create differenced variables
sort county_id year
by county_id: gen lag_total_adherents = total_adherents_rate[_n-1]
gen diff_total_adherents = total_adherents_rate - lag_total_adherents


* (4) Differenced specification
reghdfe diff_total_adherents post_treatment if year >= 2010 ///
    [aw=population], absorb(year) vce(cluster county_id)
estimates store relig_diff


log close