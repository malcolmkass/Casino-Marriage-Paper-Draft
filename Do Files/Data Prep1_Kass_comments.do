clear all
set more off
set maxvar 10000

* Set working directories - CHANGE THESE TO YOUR ACTUAL PATHS
global data "C:\Users\mkass\IT (30) Advanced Dropbox\Malcolm Kass\Casino Talk\Relevant material in 2025 Adv Metrics\Data"
global output "C:\Users\mkass\IT (30) Advanced Dropbox\Malcolm Kass\Casino Talk\Relevant material in 2025 Adv Metrics\Output"

cap log close
log using "$output/casino_analysis_log_fixed.txt", replace text

* Install required packages if needed
capture ssc install coefplot
capture ssc install reghdfe
capture ssc install estout

/*==============================================================================
PRE-CHECK REQUIRED VARIABLES
==============================================================================*/

use "$data\ACSData.dta", clear
foreach var in marst nchild sex age statefip countyfip perwt year migrate1 movedin sample serial {
    capture confirm variable `var'
    if _rc != 0 {
        display as error "Required variable `var' not found in ACSData.dta."
        exit 111
    }
}
clear

use "$data\casino_data.dta", clear
foreach var in gestfips gtco tuyear casino_co near_co treat_year {
    capture confirm variable `var'
    if _rc != 0 {
        display as error "Required variable `var' not found in casino_data.dta."
        exit 111
    }
}
clear

/*==============================================================================
1. LOAD AND PREPARE CASINO DATA - INCLUDING NEARBY COUNTIES
==============================================================================*/

use "$data\casino_data.dta", clear
use "C:\Users\mkass\IT (30) Advanced Dropbox\Malcolm Kass\Casino Talk\Marriage and Divorce\Data\casino_data.dta", clear
gen county_id = gestfips * 1000 + gtco
gen casino_county = (casino_co == 1)
gen nearby_county = (near_co == 1)

* Clean treatment year:  
*Kass, this is done in the first part of section 5, step 1 of atus_full
bysort county_id: egen min_treat_year = min(treat_year) if casino_county == 1
bysort county_id: egen treat_year_clean = max(min_treat_year)
replace treat_year = treat_year_clean if casino_county == 1
drop min_treat_year treat_year_clean

* Keep necessary variables
keep county_id tuyear gestfips gtco treat_year casino_no casino_county nearby_county 
rename tuyear year
duplicates drop county_id year, force

* Generate treatment variables
*kass, done in Section 5, step 4 of atus_full
gen treated = casino_county
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0
gen treat_post = treated * post_treatment

*Kass, this done on the students R script files, not in atus_full
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)

**********************************************************************************
/*Kass, this is a count of number of casino openings for the casino and nearby counties:
this is in Section 4, variables total_casino_number (total new casinos in the county 
over the data time span) casino_number (total no. of casino opened in that year)

*/
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
    tempfile county_info
    save temp.dta, replace
restore
*******************************************************************************


* Create balanced panel
keep county_id year
expand 24
bysort county_id: replace year = 1999 + _n
keep if year >= 2000 & year <= 2023
duplicates drop county_id year, force

* Merge county info back
merge m:1 county_id using temp.dta, keep(match) nogen

* Generate treatment variables for balanced panel
gen treated_full = casino_county
gen post_treatment_full = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment_full = 0 if casino_county == 0
gen treat_post_full = treated_full * post_treatment_full
gen rel_time_full = year - treat_year if casino_county == 1 & !missing(treat_year)

save "$data\casino_clean.dta", replace



tempfile casino_clean
save `casino_clean'

/*==============================================================================
2. LOAD AND PREPARE ACS DATA
==============================================================================*/

use "$data\ACSData.dta", clear
keep if year >= 2000 & year <= 2023
gen county_id = statefip * 1000 + countyfip
keep if age >= 18 & age <= 40

* Generate outcome variables
gen married = (marst == 1)
gen divorced = (marst == 4)
gen widowed = (marst == 5)
gen never_married = (marst == 6)
gen newly_married = (married == 1 & age >= 18 & age <= 35)
gen has_children = (nchild > 0) if !missing(nchild)
gen num_children = nchild

* Generate demographic variables
gen female = (sex == 2)
gen age_sq = age^2

* Education variables (if available)
capture confirm variable educ
if _rc == 0 {
    gen high_school = (educ >= 6)
    gen college = (educ >= 10)
}

* Race/ethnicity variables
gen white = (race == 1)
gen black = (race == 2)
gen hispanic = (hispan >= 1 & hispan <= 4)

* Age groups
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
3. MERGE DATASETS AND CREATE CONTROL GROUP
==============================================================================*/

merge m:1 county_id year using `casino_clean'

* Create sample type indicator
gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if _merge == 1

* Keep all observations
keep if sample_type >= 1 & sample_type <= 3

* Fill in missing values for unmatched observations
replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
drop _merge

* Generate treatment variables
gen ever_treated = casino_county
gen treated = casino_county
replace post_treatment_full = 0 if missing(post_treatment_full)
gen post_treatment = post_treatment_full
gen treat_post = treated * post_treatment
gen rel_time = rel_time_full

* Replace missing values
replace casino_no = 0 if missing(casino_no)
replace treated_full = 0 if missing(treated_full)
replace treat_post_full = 0 if missing(treat_post_full)
replace rel_time_full = . if missing(rel_time_full)

/*==============================================================================
CREATE EVENT STUDY VARIABLES
==============================================================================*/

* Create event study indicators
forvalues i = 3(-1)2 {
    gen lag`i' = 0
    replace lag`i' = 1 if rel_time == -`i' & !missing(rel_time)
}

forvalues i = 0/10 {
    gen lead`i' = 0
    replace lead`i' = 1 if rel_time == `i' & !missing(rel_time)
}

* Alternative event study specification
forvalues i = 3(-1)2 {
    gen lag`i'_alt = 0
    replace lag`i'_alt = 1 if rel_time == -`i' & !missing(rel_time)
}

forvalues i = 0/4 {
    gen lead`i'_alt = 0
    replace lead`i'_alt = 1 if rel_time == `i' & !missing(rel_time)
}

gen lead5plus_alt = 0
replace lead5plus_alt = 1 if rel_time >= 5 & !missing(rel_time)

/*==============================================================================
SPILLOVER ANALYSIS SETUP
==============================================================================*/

display ""
display "=== SETTING UP SPILLOVER ANALYSIS ==="

gen post = post_treatment
label var post "Post-treatment period"

gen casino_post = casino_county * post
gen nearby_post = nearby_county * post
label var casino_post "Casino County × Post"
label var nearby_post "Nearby County × Post"


/*==============================================================================
DONUT DESIGN ANALYSIS
==============================================================================*/

display ""
display "=== DONUT DESIGN ANALYSIS ==="

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)
label var donut_sample "Donut Sample (Casino + Far Counties)"



/*==============================================================================
AGE HETEROGENEITY ANALYSIS - DONUT DESIGN
==============================================================================*/

display ""
display "=============================================================="
display "=== AGE HETEROGENEITY ANALYSIS - DONUT DESIGN ==="
display "=============================================================="

/*==============================================================================
CREATE AGE GROUP INDICATORS
==============================================================================*/

* Create more detailed age groups if not already done
capture drop age_group_detail
gen age_group_detail = 1 if age >= 18 & age <= 30
replace age_group_detail = 2 if age >= 31 & age <= 40
label define age_detail_lab 1 "18-30" 2 "31-40"
label values age_group_detail age_detail_lab

* Create interaction variables for age groups
gen young = (age_group_detail == 1)
gen older = (age_group_detail == 2)

gen young_post = young * post_treatment
gen older_post = older * post_treatment
gen young_casino_post = young * casino_post
gen older_casino_post = older * casino_post



/*==============================================================================
PREPARE MIGRATION VARIABLES
==============================================================================*/

* Create migration indicators
gen stayer = (migrate1 == 1) if migrate1 >= 1 & migrate1 <= 4
gen mover = (migrate1 >= 2 & migrate1 <= 4) if migrate1 >= 1 & migrate1 <= 4
gen mover_within_state = (migrate1 == 2) if migrate1 >= 1 & migrate1 <= 4
gen mover_between_states = (migrate1 == 3) if migrate1 >= 1 & migrate1 <= 4

* Create interaction variables
gen stayer_post = stayer * post_treatment
gen mover_post = mover * post_treatment

* For donut sample interactions
gen stayer_donut = stayer if donut_sample == 1
gen mover_donut = mover if donut_sample == 1