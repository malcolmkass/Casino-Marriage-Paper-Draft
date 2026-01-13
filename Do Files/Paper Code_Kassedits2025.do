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
log using "$output/paper_analysis_log.txt", replace text

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

/*==============================================================================
1. LOAD AND PREPARE CASINO DATA - INCLUDING NEARBY COUNTIES
==============================================================================*/

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
    tempfile county_info
    save `county_info'
restore

* Create balanced panel
keep county_id year
expand 24
bysort county_id: replace year = 1999 + _n
keep if year >= 2000 & year <= 2023
duplicates drop county_id year, force

* Merge county info back
merge m:1 county_id using `county_info', keep(match) nogen

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
     has_children num_children female age age_sq white black hispanic migrate1 ///
     perwt statefip countyfip age_group longterm_resident acs_sample


/*==============================================================================
3. MERGE DATASETS AND CREATE CONTROL GROUP
==============================================================================*/

*merge m:1 county_id year using `casino_clean'
cd "C:\Users\mkass\IT (30) Advanced Dropbox\Malcolm Kass\Casino Talk\Marriage and Divorce\Data"
merge m:1 county_id year using casino_clean.dta

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

/*------------------------------------------------------------------------------
3. PREPARE POPULATION ANALYSIS DATASET (ALL AGES) - EXACT MATCH
------------------------------------------------------------------------------*/

use "$data\ACSData.dta", clear
keep if year >= 2000 & year <= 2023
gen county_id = statefip * 1000 + countyfip

* Keep all ages for population analysis (remove age restriction)
* Generate age group indicators
gen all_ages = 1
gen child_rearing_age = (age >= 18 & age <= 40)
gen children = (age <= 17)
gen school_age = (age >= 5 & age <= 17)

* Generate school enrollment variables using IPUMS variables
* SCHOOL: 1=No, not in school, 2=Yes, in school
* SCHLTYPE: 2=Public school, 3=Private school
gen enrolled_in_school = (school == 2) if !missing(school)
gen enrolled_public = (school == 2 & schltype == 2) if !missing(school) & !missing(schltype)
gen enrolled_private = (school == 2 & schltype == 3) if !missing(school) & !missing(schltype)

* School enrollment for ages 5-17 only
gen school_age_enrolled = enrolled_in_school if school_age == 1
gen school_age_public = enrolled_public if school_age == 1

* Keep necessary variables
keep county_id year all_ages child_rearing_age children school_age ///
     school_age_enrolled school_age_public enrolled_in_school enrolled_public ///
     perwt statefip countyfip age school schltype

* Merge with casino data
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

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)

* Generate treatment variables
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)

* Create 8-year event study variables for population analysis
forvalues j = 3(-1)2 {
    gen lag`j'_pop = 0
    replace lag`j'_pop = 1 if rel_time == -`j' & !missing(rel_time)
}

forvalues j = 0/7 {
    gen lead`j'_pop = 0
    replace lead`j'_pop = 1 if rel_time == `j' & !missing(rel_time)
}

gen lead8plus_pop = 0
replace lead8plus_pop = 1 if rel_time >= 8 & !missing(rel_time)

tempfile population_analysis_data
save `population_analysis_data'

/*------------------------------------------------------------------------------
4. PREPARE RELIGIOUS DATA
------------------------------------------------------------------------------*/

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

* Create differenced variables for religious analysis
sort county_id year
by county_id: gen lag_total_adherents = total_adherents_rate[_n-1]
by county_id: gen lag_post_treatment = post_treatment[_n-1]
gen diff_total_adherents = total_adherents_rate - lag_total_adherents
gen diff_post_treatment = post_treatment - lag_post_treatment

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
cap by county_id: gen lag_total_adherents = total_adherents_rate[_n-1]
cap gen diff_total_adherents = total_adherents_rate - lag_total_adherents

* Create spillover variables
cap gen casino_post = casino_county * post_treatment
cap gen nearby_post = nearby_county * post_treatment

tempfile religious_analysis_data
save `religious_analysis_data'

/*==============================================================================
PART II: TABLES AND FIGURES
==============================================================================*/

display ""
display "=============================================================="
display "=== PART II: CREATING TABLES AND FIGURES ==="
display "=============================================================="

/*==============================================================================
TABLE 1: SUMMARY STATISTICS BY TREATMENT STATUS
==============================================================================*/

display ""
display "=== TABLE 1: SUMMARY STATISTICS ==="

use `main_analysis_data', clear

* Individual-level summary statistics by treatment status
eststo clear

* Casino counties
estpost summarize married has_children num_children female age white black hispanic ///
    if sample_type == 1 [aw=perwt]
eststo casino_stats

* Nearby counties  
estpost summarize married has_children num_children female age white black hispanic ///
    if sample_type == 2 [aw=perwt]
eststo nearby_stats

* Control counties
estpost summarize married has_children num_children female age white black hispanic ///
    if sample_type == 3 [aw=perwt]
eststo control_stats

* Export summary statistics
esttab casino_stats nearby_stats control_stats ///
    using "$output/table1_summary_stats.tex", replace ///
    cells("mean(fmt(3)) sd(fmt(3))") ///
    mtitles("Casino Counties" "Nearby Counties" "Control Counties") ///
    title("Summary Statistics by County Type") ///
    addnotes("Notes: Individual-level statistics weighted by person weights. Sample includes individuals aged 18-40.")

* Display county counts
display ""
display "=== COUNTY COUNTS BY SAMPLE TYPE ==="
preserve
* Count unique counties by sample type
duplicates drop county_id sample_type, force
tab sample_type
restore

* Count total individuals by sample type
display ""
display "=== INDIVIDUAL COUNTS BY SAMPLE TYPE ==="
tab sample_type

/*==============================================================================
TABLE 2: POPULATION EFFECTS BY AGE GROUP
==============================================================================*/

display ""
display "=== TABLE 2: POPULATION EFFECTS ==="

* Create population analysis dataset
use "$data\ACSData.dta", clear
use ACSData.dta, clear
keep if year >= 2000 & year <= 2023
gen county_id = statefip * 1000 + countyfip

* Generate age group indicators
gen all_ages = 1
gen child_rearing_age = (age >= 18 & age <= 40)
gen children = (age <= 17)
gen school_age = (age >= 5 & age <= 17)

* Generate school enrollment variables using IPUMS variables
gen enrolled_in_school = (school == 2) if !missing(school)
gen enrolled_public = (school == 2 & schltype == 2) if !missing(school) & !missing(schltype)
gen school_age_enrolled = enrolled_in_school if school_age == 1
gen school_age_public = enrolled_public if school_age == 1

* Keep necessary variables
keep county_id year all_ages child_rearing_age children school_age ///
     school_age_enrolled school_age_public enrolled_in_school enrolled_public ///
     perwt statefip countyfip age school schltype

* Merge with casino data
*merge m:1 county_id year using `casino_clean'
merge m:1 county_id year using casino_clean.dta

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

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)

* Generate treatment variables
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)

* Create 8-year event study variables for population analysis
forvalues j = 3(-1)2 {
    gen lag`j'_pop = 0
    replace lag`j'_pop = 1 if rel_time == -`j' & !missing(rel_time)
}

forvalues j = 0/7 {
    gen lead`j'_pop = 0
    replace lead`j'_pop = 1 if rel_time == `j' & !missing(rel_time)
}

gen lead8plus_pop = 0
replace lead8plus_pop = 1 if rel_time >= 8 & !missing(rel_time)

* Create county-year level population data
preserve
gen total_pop_temp = perwt if all_ages == 1
gen child_rearing_pop_temp = perwt if child_rearing_age == 1
gen children_pop_temp = perwt if children == 1
gen school_age_pop_temp = perwt if school_age == 1

collapse (sum) total_pop=total_pop_temp ///
         (sum) child_rearing_pop=child_rearing_pop_temp ///
         (sum) children_pop=children_pop_temp ///
         (sum) school_age_pop=school_age_pop_temp, ///
         by(county_id year casino_county rel_time donut_sample lag3_pop-lead8plus_pop)

* Create log variables (note, betas is level regression will be off by a significant factor, log-level no effect)
gen ln_total_pop = ln(total_pop)
gen ln_child_rearing_pop = ln(child_rearing_pop) if child_rearing_pop > 0
gen ln_children_pop = ln(children_pop) if children_pop > 0
gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0

eststo clear

* Total Population
reghdfe ln_total_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
eststo pop_total

* Child-Rearing Age (18-40)
reghdfe ln_child_rearing_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
eststo pop_child_rearing

* Children (≤17)
reghdfe ln_children_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
eststo pop_children

* School-Age (5-17)
reghdfe ln_school_age_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
eststo pop_school_age

* Export Table 2
esttab pop_total pop_child_rearing pop_children pop_school_age ///
    using "$output/table2_population_effects.tex", replace ///
    keep(lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    coeflabels(lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
              lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
              lead7_pop "t+7" lead8plus_pop "t+8+") ///
    mgroups("Total Pop" "Child-Rearing" "Children" "School-Age", ///
           pattern(1 1 1 1) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Population Effects by Age Group") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Donut sample excludes nearby counties. All variables in logs.")

restore

/*==============================================================================
FIGURE 1: POPULATION DECLINE EVENT STUDIES
==============================================================================*/

display ""
display "=== FIGURE 1: POPULATION EVENT STUDIES ==="

* Create four-panel population figure
coefplot (pop_total, ///
            ciopts(lcolor(navy) lwidth(medium)) ///
            mcolor(navy) msymbol(O) msize(medium) ///
            label("Total Population")) ///
         (pop_child_rearing, ///
            ciopts(lcolor(maroon) lwidth(medium)) ///
            mcolor(maroon) msymbol(D) msize(medium) ///
            label("Child-Rearing Age (18-40)")) ///
         (pop_children, ///
            ciopts(lcolor(forest_green) lwidth(medium)) ///
            mcolor(forest_green) msymbol(T) msize(medium) ///
            label("Children (≤17)")) ///
         (pop_school_age, ///
            ciopts(lcolor(orange) lwidth(medium)) ///
            mcolor(orange) msymbol(S) msize(medium) ///
            label("School-Age (5-17)")), ///
    keep(lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    vertical ///
    coeflabels(lag3_pop = "-3" lag2_pop = "-2" lead0_pop = "0" lead1_pop = "1" lead2_pop = "2" ///
              lead3_pop = "3" lead4_pop = "4" lead5_pop = "5" lead6_pop = "6" ///
              lead7_pop = "7" lead8plus_pop = "8+", labsize(medium)) ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(2.5, lcolor(gray) lpattern(dash)) ///
    title("Population Effects by Age Group", ///
          size(medlarge) margin(medium) color(black)) ///
    xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
    ytitle("Log Population Effect", size(medium) margin(medium)) ///
    ylabel(, labsize(medium) format(%9.3f)) ///
    xlabel(, labsize(medium)) ///
    legend(position(6) rows(2) size(medium) ///
          region(lcolor(none) fcolor(none)) ///
          symxsize(5) keygap(2) rowgap(1)) ///
    note("Effects on log population by age group. Donut sample excludes nearby counties.", ///
         size(small) margin(small) position(7)) ///
    graphregion(color(white) margin(medium)) ///
    plotregion(color(white) margin(medium)) ///
    scheme(s1color)
    
graph export "$output/figure1_population_effects.png", replace width(1400) height(900)
graph export "$output/figure1_population_effects.pdf", replace

/*==============================================================================
TABLE 3: FAMILY FORMATION EFFECTS BY GENDER
==============================================================================*/

display ""
display "=== TABLE 3: FAMILY FORMATION EFFECTS ==="

use `main_analysis_data', clear

eststo clear

* Women
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment age age_sq ///
        if female == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo w_`outcome'
}

* Men  
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment age age_sq ///
        if female == 0 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo m_`outcome'
}

* Export Table 3
esttab w_married w_has_children w_num_children m_married m_has_children m_num_children ///
    using "$output/table3_family_formation.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    title("Family Formation Effects by Gender") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All regressions include county and year fixed effects, age and age squared." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
FIGURE 2: FERTILITY EVENT STUDIES BY GENDER
==============================================================================*/

display ""
display "=== FIGURE 2: FERTILITY EVENT STUDIES ==="

eststo clear

* Women fertility event study
reghdfe num_children ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo fertility_women

* Men fertility event study
reghdfe num_children ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo fertility_men

* Create two-panel fertility figure
coefplot (fertility_women, ///
            ciopts(lcolor(maroon) lwidth(medium)) ///
            mcolor(maroon) msymbol(O) msize(medium) ///
            label("Women")) ///
         (fertility_men, ///
            ciopts(lcolor(navy) lwidth(medium)) ///
            mcolor(navy) msymbol(D) msize(medium) ///
            label("Men")), ///
    keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
    vertical ///
    coeflabels(lag3_ext = "-3" lag2_ext = "-2" lead0_ext = "0" lead1_ext = "1" lead2_ext = "2" ///
              lead3_ext = "3" lead4_ext = "4" lead5_ext = "5" lead6_ext = "6" ///
              lead7_ext = "7" lead8plus_ext = "8+", labsize(medium)) ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(2.5, lcolor(gray) lpattern(dash)) ///
    title("Fertility Effects by Gender", ///
          size(medlarge) margin(medium) color(black)) ///
    xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
    ytitle("Effect on Number of Children", size(medium) margin(medium)) ///
    ylabel(, labsize(medium) format(%9.3f)) ///
    xlabel(, labsize(medium)) ///
    legend(position(6) rows(1) size(medium) ///
          region(lcolor(none) fcolor(none)) ///
          symxsize(5) keygap(2) rowgap(1)) ///
    note("Event study effects on number of children. Donut sample excludes nearby counties.", ///
         size(small) margin(small) position(7)) ///
    graphregion(color(white) margin(medium)) ///
    plotregion(color(white) margin(medium)) ///
    scheme(s1color)
    
graph export "$output/figure2_fertility_effects.png", replace width(1400) height(900)
graph export "$output/figure2_fertility_effects.pdf", replace

/*==============================================================================
TABLE 4: EFFECTS BY RESIDENCE DURATION
==============================================================================*/

display ""
display "=== TABLE 4: EFFECTS BY RESIDENCE DURATION ==="

eststo clear

* Women - Long-term residents (5+ years)
reghdfe num_children ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_longterm

* Women - Recent movers (<5 years)
reghdfe num_children ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_recent

* Men - Long-term residents (5+ years)
reghdfe num_children ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_longterm

* Men - Recent movers (<5 years)
reghdfe num_children ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_recent

* Export Table 4
esttab w_longterm w_recent m_longterm m_recent ///
    using "$output/table4_residence_duration.tex", replace ///
    keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
    coeflabels(lag3_ext "t-3" lag2_ext "t-2" lead0_ext "t" lead1_ext "t+1" lead2_ext "t+2" ///
              lead3_ext "t+3" lead4_ext "t+4" lead5_ext "t+5" lead6_ext "t+6" ///
              lead7_ext "t+7" lead8plus_ext "t+8+") ///
    mgroups("Women" "Men", pattern(1 0 1 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Long-term (5+)" "Recent (<5)" "Long-term (5+)" "Recent (<5)") ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Effects by Residence Duration: Number of Children") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Long-term = 5+ years in residence, Recent = <5 years in residence." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
FIGURE 3: MECHANISM TEST EVENT STUDIES
==============================================================================*/

display ""
display "=== FIGURE 3: MECHANISM EVENT STUDIES ==="

* Create clean individual panels first
* Women panel
coefplot (w_longterm, ///
            ciopts(lcolor(navy) lwidth(thick)) ///
            mcolor(navy) msymbol(O) msize(large) ///
            label("Long-term Residents")) ///
         (w_recent, ///
            ciopts(lcolor(maroon) lwidth(thick)) ///
            mcolor(maroon) msymbol(D) msize(large) ///
            label("Recent Movers")), ///
    keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
    vertical ///
    coeflabels(lag3_ext = "-3" lag2_ext = "-2" lead0_ext = "0" lead1_ext = "1" lead2_ext = "2" ///
              lead3_ext = "3" lead4_ext = "4" lead5_ext = "5" lead6_ext = "6" ///
              lead7_ext = "7" lead8plus_ext = "8+") ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xline(2.5, lcolor(gs8) lpattern(dash)) ///
    title("Women", size(huge) color(black)) ///
    xtitle("Years Relative to Casino Opening", size(large)) ///
    ytitle("Effect on Number of Children", size(large)) ///
    ylabel(-0.20(0.05)0.05, format(%4.2f) labsize(large)) ///
    xlabel(, labsize(large)) ///
    plotregion(margin(l=0 r=0 t=3 b=3)) ///
    graphregion(margin(l=3 r=3 t=3 b=3)) ///
    legend(off) ///
    name(women_panel, replace) ///
    scheme(s1mono)

* Men panel - match women's formatting exactly
coefplot (m_longterm, ///
            ciopts(lcolor(navy) lwidth(thick)) ///
            mcolor(navy) msymbol(O) msize(large) ///
            label("Long-term Residents")) ///
         (m_recent, ///
            ciopts(lcolor(maroon) lwidth(thick)) ///
            mcolor(maroon) msymbol(D) msize(large) ///
            label("Recent Movers")), ///
    keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
    vertical ///
    coeflabels(lag3_ext = "-3" lag2_ext = "-2" lead0_ext = "0" lead1_ext = "1" lead2_ext = "2" ///
              lead3_ext = "3" lead4_ext = "4" lead5_ext = "5" lead6_ext = "6" ///
              lead7_ext = "7" lead8plus_ext = "8+") ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xline(2.5, lcolor(gs8) lpattern(dash)) ///
    title("Men", size(huge) color(black)) ///
    xtitle("Years Relative to Casino Opening", size(large)) ///
    ytitle("Effect on Number of Children", size(large)) ///
    ylabel(-0.20(0.05)0.05, format(%4.2f) labsize(large)) ///
    xlabel(, labsize(large)) ///
    plotregion(margin(l=0 r=0 t=3 b=3)) ///
    graphregion(margin(l=3 r=3 t=3 b=3)) ///
    legend(off) ///
    name(men_panel, replace) ///
    scheme(s1mono)

* Combine with reasonable spacing
graph combine women_panel men_panel, ///
    title("Mechanism Test: Fertility Effects by Residence Duration", size(vlarge)) ///
    subtitle("Behavioral Change vs Selection", size(large)) ///
    note("● Long-term Residents (5+ years)     ♦ Recent Movers (<5 years)" ///
         "Stronger effects for long-term residents suggest behavioral change rather than selection." ///
         "Donut sample excludes nearby counties.", ///
         size(medium)) ///
    cols(2) ///
    ycommon xcommon ///
    imargin(small) ///
    scheme(s1mono)
    
graph export "$output/figure3_mechanism_test.png", replace width(1400) height(700)
graph export "$output/figure3_mechanism_test.pdf", replace

/*==============================================================================
TABLE 5: POPULATION COMPOSITION TESTS
==============================================================================*/

display ""
display "=== TABLE 5: POPULATION COMPOSITION TESTS ==="

use `main_analysis_data', clear

* Create population composition data at county-year level
preserve

* Create indicator for ACS samples (exclude 2000 Census)
gen acs_sample_comp = 1
replace acs_sample_comp = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)

* Create population variables before collapsing
gen longterm_pop_temp = perwt if longterm_resident == 1 & acs_sample_comp == 1
gen total_pop_temp = perwt if acs_sample_comp == 1

* Calculate population by residence type and county-year
collapse (sum) longterm_pop=longterm_pop_temp ///
         (sum) total_pop=total_pop_temp, ///
         by(county_id year casino_county rel_time donut_sample lag3_ext-lead8plus_ext)

* Only keep counties with both populations measured
drop if missing(longterm_pop) | missing(total_pop) | total_pop == 0

* Calculate share of long-term residents
gen longterm_share = longterm_pop / total_pop

* Create log long-term population
gen ln_longterm_pop = ln(longterm_pop)

eststo clear

* Event study for log long-term population
reghdfe ln_longterm_pop ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
eststo pop_level

* Event study for long-term population share
reghdfe longterm_share ///
    lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
eststo pop_share

* Export Table 5
esttab pop_level pop_share ///
    using "$output/table5_population_composition.tex", replace ///
    keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
    coeflabels(lag3_ext "t-3" lag2_ext "t-2" lead0_ext "t" lead1_ext "t+1" lead2_ext "t+2" ///
              lead3_ext "t+3" lead4_ext "t+4" lead5_ext "t+5" lead6_ext "t+6" ///
              lead7_ext "t+7" lead8plus_ext "t+8+") ///
    mtitles("Log Long-term Population" "Long-term Population Share") ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Population Composition Tests") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Tests whether casinos affect size/composition of long-term resident population." ///
            "Long-term = 5+ years in residence. Donut sample excludes nearby counties.")

restore

/*==============================================================================
TABLE 6: SCHOOL POPULATION AND ENROLLMENT EFFECTS
==============================================================================*/

display ""
display "=== TABLE 6: SCHOOL EFFECTS ==="

* Create population analysis dataset for school effects
preserve
use "$data\ACSData.dta", clear
keep if year >= 2000 & year <= 2023
gen county_id = statefip * 1000 + countyfip

* Generate age group indicators
gen all_ages = 1
gen child_rearing_age = (age >= 18 & age <= 40)
gen children = (age <= 17)
gen school_age = (age >= 5 & age <= 17)

* Generate school enrollment variables using IPUMS variables
gen enrolled_in_school = (school == 2) if !missing(school)
gen enrolled_public = (school == 2 & schltype == 2) if !missing(school) & !missing(schltype)
gen school_age_enrolled = enrolled_in_school if school_age == 1
gen school_age_public = enrolled_public if school_age == 1

* Keep necessary variables
keep county_id year all_ages child_rearing_age children school_age ///
     school_age_enrolled school_age_public enrolled_in_school enrolled_public ///
     perwt statefip countyfip age school schltype

* Merge with casino data
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

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)

* Generate treatment variables
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)

* Create 8-year event study variables for population analysis
forvalues j = 3(-1)2 {
    gen lag`j'_pop = 0
    replace lag`j'_pop = 1 if rel_time == -`j' & !missing(rel_time)
}

forvalues j = 0/7 {
    gen lead`j'_pop = 0
    replace lead`j'_pop = 1 if rel_time == `j' & !missing(rel_time)
}

gen lead8plus_pop = 0
replace lead8plus_pop = 1 if rel_time >= 8 & !missing(rel_time)

* Create county-year level school data
gen school_age_pop_temp = perwt if school_age == 1
gen school_enrolled_temp = perwt if school_age_enrolled == 1
gen public_enrolled_temp = perwt if school_age_public == 1

collapse (sum) school_age_pop=school_age_pop_temp ///
         (sum) school_enrolled=school_enrolled_temp ///
         (sum) public_enrolled=public_enrolled_temp, ///
         by(county_id year casino_county rel_time donut_sample lag3_pop-lead8plus_pop)

* Create log variables
gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0
gen ln_school_enrolled = ln(school_enrolled) if school_enrolled > 0
gen ln_public_enrolled = ln(public_enrolled) if public_enrolled > 0

eststo clear

* School-age population
reghdfe ln_school_age_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
eststo school_pop

* Total school enrollment
reghdfe ln_school_enrolled ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
eststo school_enroll

* Public school enrollment
reghdfe ln_public_enrolled ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
eststo public_enroll

* Export Table 6
esttab school_pop school_enroll public_enroll ///
    using "$output/table6_school_effects.tex", replace ///
    keep(lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    coeflabels(lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
              lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
              lead7_pop "t+7" lead8plus_pop "t+8+") ///
    mtitles("School-Age Pop" "Total Enrollment" "Public Enrollment") ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("School Population and Enrollment Effects") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All variables in logs. School-age = 5-17 years." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

restore
*/
/*==============================================================================
TABLE 7: RELIGIOUS ADHERENCE EFFECTS
==============================================================================*/

* Load 2000 religious data
use "$data\religious_2000.dta", clear

* Generate consistent county identifier
gen county_id = fip
gen year = 2000

* Key outcome variables (using actual 2000 variable names)
gen total_adherents_rate = totrt
gen total_congregations = totcg
gen total_adherents = totad

* Denomination-specific rates  
gen evangelical_rate = evanrt
gen catholic_rate = cathrt  
gen mainline_rate = mainrt
gen orthodox_rate = orthrt
gen other_rate = otherrt
gen jewish_rate = jewrt
gen islam_rate = islamrt

* Major denominations
gen southern_baptist_rate = sbcrt
gen methodist_rate = umethrt
gen lutheran_elca_rate = elcart
gen episcopal_rate = episcrt
gen mormon_rate = ldsrt
gen nazarene_rate = nazarrt
gen assemblies_god_rate = assgdrt

* Population and geographic variables
gen population = POP200
gen state_code = stcod
gen county_code = ctycod
gen state_name = state
gen county_name = county
gen state_abbrev = stateab

* Keep relevant variables
keep county_id year *_rate total_congregations total_adherents population ///
     state_code county_code state_name county_name state_abbrev fip

tempfile religious_2000
save `religious_2000'

* Load 2010 religious data
use "$data\religious_2010.dta", clear

* Generate consistent county identifier
gen county_id = fips  // Note: 2010 uses 'fips' not 'fip'
gen year = 2010

* Key outcome variables (using actual 2010 variable names)
gen total_adherents_rate = totrate
gen total_congregations = totcng
gen total_adherents = totadh

* Denomination-specific rates  
gen evangelical_rate = evanrate
gen catholic_rate = cathrate  
gen mainline_rate = mprtrate  // Note: 2010 uses 'mprtrate' not 'mainrt'
gen orthodox_rate = orthrate
gen other_rate = othrate
gen jewish_rate = ojudrate  // Note: 2010 uses 'ojudrate' not 'jewrt'
gen islam_rate = mslmrate   // Note: 2010 uses 'mslmrate' not 'islamrt'

* Additional denomination in 2010
gen black_protestant_rate = bprtrate

* Major denominations (using 2010 variable names)
gen southern_baptist_rate = sbcrate
gen methodist_rate = umcrate
gen lutheran_elca_rate = elcarate
gen episcopal_rate = ecrate
gen mormon_rate = ldsrate
gen nazarene_rate = nazrate
gen assemblies_god_rate = agrate

* Population and geographic variables
gen population = POP2010
gen state_code = stcode
gen county_code = cntycode
gen state_name = stname
gen county_name = cntyname
gen state_abbrev = stabbr

* Keep relevant variables
keep county_id year *_rate total_congregations total_adherents population ///
     state_code county_code state_name county_name state_abbrev fips

tempfile religious_2010
save `religious_2010'

* Load 2020 religious data
use "$data\religious_2020.dta", clear

* Generate consistent county identifier
gen county_id = fips  // 2020 uses 'fips'
gen year = 2020

* Key outcome variables (using actual 2020 variable names with _2020 suffix)
gen total_adherents_rate = TOTRATE_2020
gen total_congregations = TOTCNG_2020
gen total_adherents = TOTADH_2020

* Denomination-specific rates (2020 uses UPPERCASE with _2020 suffix)
gen evangelical_rate = EVANRATE_2020
gen catholic_rate = CATHRATE_2020  
gen mainline_rate = MPRTRATE_2020
gen orthodox_rate = ORTHRATE_2020
gen other_rate = OTHRATE_2020
gen jewish_rate = OJUDRATE_2020
gen islam_rate = MSLMRATE_2020
gen black_protestant_rate = BPRTRATE_2020

* Major denominations (using 2020 variable names)
gen southern_baptist_rate = SBCRATE_2020
gen methodist_rate = UMCRATE_2020
gen lutheran_elca_rate = ELCARATE_2020
gen episcopal_rate = ECRATE_2020
gen mormon_rate = LDSRATE_2020
gen nazarene_rate = NAZRATE_2020
gen assemblies_god_rate = AGCRATE_2020

* Population and geographic variables
gen population = POP2020
gen state_code = stcod
gen county_code = ctycod
gen state_name = statnam
gen county_name = counam
gen state_abbrev = stabbrev

* Keep relevant variables
keep county_id year *_rate total_congregations total_adherents population ///
     state_code county_code state_name county_name state_abbrev fips

* Append all three years
append using `religious_2010'
append using `religious_2000'

* Merge with your existing casino treatment data (county-year level)
merge 1:1 county_id year using "$data\casino_clean.dta"

* Keep only years where we have religious data (2000, 2010, 2020)
keep if inlist(year, 2000, 2010, 2020)

* Create sample type indicator consistent with main analysis
gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if _merge == 1

* Keep all observations for analysis
keep if sample_type >= 1 & sample_type <= 3

* Fill in missing values for unmatched observations
replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
drop _merge

* Create donut sample indicator (same as main analysis)
gen donut_sample = (sample_type == 1 | sample_type == 3)


* Years of exposure (0 for never-treated counties)
gen years_exposure = 0
replace years_exposure = year - treat_year if casino_county == 1 & year >= treat_year & !missing(treat_year)

* Post-treatment indicator (consistent with main analysis)
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0

* Treatment interaction
gen treat_post = casino_county * post_treatment

* Relative time (for event study with 3 time points)
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)

* Event study variables (now with 2000, 2010, 2020 structure)
* Create more nuanced event study with 3 time points
gen pre_2000 = (rel_time < -10)  // Casinos opened before 1990
gen pre_2000_2010 = (rel_time >= -10 & rel_time < 0)  // Opened 1990-1999, 2000-2009  
gen post_2000_2010 = (rel_time >= 0 & rel_time < 10)  // Opened 2000-2009
gen post_2010 = (rel_time >= 10)  // Opened 2010+

* Alternative: Simple early vs late treatment
gen early_post = (years_exposure > 0 & years_exposure <= 10)
gen late_post = (years_exposure > 10)


* Create lagged variables (since we have 3 time periods: 2000, 2010, 2020)
sort county_id year
by county_id: gen lag_total_adherents = total_adherents_rate[_n-1]
by county_id: gen lag_post_treatment = post_treatment[_n-1]

* First difference variables
gen diff_total_adherents = total_adherents_rate - lag_total_adherents
gen diff_post_treatment = post_treatment - lag_post_treatment

* Create baseline religiosity terciles (using 2000 data)
preserve
keep if year == 2000
xtile baseline_religiosity_tercile = total_adherents_rate, nq(3)
keep county_id baseline_religiosity_tercile
tempfile baseline_religiosity
save `baseline_religiosity'
restore

merge m:1 county_id using `baseline_religiosity', nogen


eststo clear

* (1) Baseline specification (county + year FE)
reghdfe total_adherents_rate post_treatment ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store relig_baseline

* (2) Medium religiosity counties only (baseline tercile 2)
reghdfe total_adherents_rate post_treatment ///
    if baseline_religiosity_tercile == 2 [aw=population], ///
    absorb(county_id year) vce(cluster county_id)
estimates store relig_medium

* (3) State-year fixed effects (preferred specification)
reghdfe total_adherents_rate post_treatment ///
    [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
estimates store relig_stateyear

* (4) Differenced specification
reghdfe diff_total_adherents diff_post_treatment if year >= 2010 ///
    [aw=population], absorb(year) vce(cluster county_id)
estimates store relig_diff

* Export Table 7
esttab relig_baseline relig_medium relig_stateyear relig_diff ///
    using "$output/table7_religious_adherence.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Baseline" "Medium Religious" "State-Year FE" "Differenced") ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    title("Religious Adherence Effects") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Dependent variable: religious adherents per 1,000 population." ///
            "Medium Religious = counties in middle tercile of 2000 adherence." ///
            "State-Year FE preferred specification. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
TABLE 8: RELIGIOUS EFFECTS BY DENOMINATION
==============================================================================*/

display ""
display "=== TABLE 8: DENOMINATIONAL EFFECTS ==="

eststo clear

* Baseline specifications (county + year FE)
foreach outcome in catholic_rate evangelical_rate mainline_rate southern_baptist_rate {
    reghdfe `outcome' post_treatment ///
        [aw=population], absorb(county_id year) vce(cluster county_id)
    estimates store base_`outcome'
}

* State-year FE specifications
foreach outcome in catholic_rate evangelical_rate mainline_rate southern_baptist_rate {
    reghdfe `outcome' post_treatment ///
        [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
    estimates store sy_`outcome'
}

* Export Table 8
esttab base_catholic_rate sy_catholic_rate base_evangelical_rate sy_evangelical_rate ///
       base_mainline_rate sy_mainline_rate base_southern_baptist_rate sy_southern_baptist_rate ///
    using "$output/table8_denominational_effects.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mgroups("Catholic" "Evangelical" "Mainline" "Southern Baptist", ///
           pattern(1 0 1 0 1 0 1 0) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Baseline" "State-Yr FE" "Baseline" "State-Yr FE" ///
            "Baseline" "State-Yr FE" "Baseline" "State-Yr FE") ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    title("Religious Effects by Denomination") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Dependent variables: denomination adherents per 1,000 population." ///
            "Baseline = county + year FE. State-Yr FE = county + state-year FE." ///
            "*** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
FIGURE 4: RELIGIOUS ADHERENCE AND CASINO EXPOSURE
==============================================================================*/

display ""
display "=== FIGURE 4: RELIGIOUS EXPOSURE SCATTER ==="

* Create exposure scatter plot
preserve
cap gen years_exposure = 0
replace years_exposure = year - treat_year if casino_county == 1 & year >= treat_year & !missing(treat_year)

collapse (mean) total_adherents_rate [aw=population], by(years_exposure casino_county)
keep if years_exposure >= 0 & years_exposure <= 25 & casino_county == 1

twoway (scatter total_adherents_rate years_exposure, mcolor(navy) msize(medium)) ///
    (lfit total_adherents_rate years_exposure, lcolor(maroon) lwidth(medium)), ///
    xtitle("Years Since Casino Opening", size(medium)) ///
    ytitle("Religious Adherents per 1,000 Population", size(medium)) ///
    title("Religious Adherence and Casino Exposure", ///
          size(medlarge) margin(medium) color(black)) ///
    legend(off) ///
    xlabel(, labsize(medium)) ///
    ylabel(, labsize(medium) format(%9.0f)) ///
    note("Average religious adherence rates by years since casino opening. Casino counties only.", ///
         size(small) margin(small) position(7)) ///
    graphregion(color(white) margin(medium)) ///
    plotregion(color(white) margin(medium)) ///
    scheme(s1color)
    
graph export "$output/figure4_religious_exposure.png", replace width(1200) height(800)
graph export "$output/figure4_religious_exposure.pdf", replace

restore

/*==============================================================================
TABLE 9: SPILLOVER EFFECTS (ROBUSTNESS)
==============================================================================*/

display ""
display "=== TABLE 9: SPILLOVER EFFECTS ==="

eststo clear

* Fertility spillovers - Women
*use `main_analysis_data', clear
use "C:\Users\mkass\IT (30) Advanced Dropbox\Malcolm Kass\Casino Talk\Marriage and Divorce\Data\merged_analysis_data.dta", clear

reghdfe num_children casino_post nearby_post age age_sq ///
    if female == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_w

* Fertility spillovers - Men
reghdfe num_children casino_post nearby_post age age_sq ///
    if female == 0 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_m

* Population spillovers - Children (need to recreate population data)
preserve
use ACSData.dta, clear
*use "$data\ACSData.dta", clear
keep if year >= 2000 & year <= 2023
gen county_id = statefip * 1000 + countyfip
gen children = (age <= 17)

* Merge with casino data
merge m:1 county_id year using casino_clean.dta

gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if _merge == 1

keep if sample_type >= 1 & sample_type <= 3

replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
drop _merge

gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0

gen children_pop_temp = perwt if children == 1
collapse (sum) children_pop=children_pop_temp, ///
         by(county_id year casino_county nearby_county post_treatment)

gen ln_children_pop = ln(children_pop) if children_pop > 0
gen casino_post = casino_county * post_treatment
gen nearby_post = nearby_county * post_treatment

reghdfe ln_children_pop casino_post nearby_post, ///
    absorb(county_id year) vce(cluster county_id)
estimates store spill_pop



restore

* Religious spillovers (need to recreate religious data)
preserve
use "$data\religious_2000.dta", clear
gen county_id = fip
gen year = 2000
gen total_adherents_rate = totrt
gen population = POP200
keep county_id year total_adherents_rate population

tempfile religious_2000_spill
save `religious_2000_spill'

use "$data\religious_2010.dta", clear
gen county_id = fips
gen year = 2010
gen total_adherents_rate = totrate
gen population = POP2010
keep county_id year total_adherents_rate population

tempfile religious_2010_spill
save `religious_2010_spill'

use "$data\religious_2020.dta", clear
gen county_id = fips
gen year = 2020
gen total_adherents_rate = TOTRATE_2020
gen population = POP2020
keep county_id year total_adherents_rate population

append using `religious_2010_spill'
append using `religious_2000_spill'

merge 1:1 county_id year using `casino_clean'
keep if inlist(year, 2000, 2010, 2020)

gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if _merge == 1

keep if sample_type >= 1 & sample_type <= 3

replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
drop _merge

gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0

gen casino_post = casino_county * post_treatment
gen nearby_post = nearby_county * post_treatment

reghdfe total_adherents_rate casino_post nearby_post ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store spill_relig
restore

* Export Table 9
esttab spill_fert_w spill_fert_m spill_pop spill_relig ///
    using "$output/table9_spillover_effects.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_post nearby_post) ///
    coeflabels(casino_post "Casino County × Post" nearby_post "Nearby County × Post") ///
    mtitles("Fertility (W)" "Fertility (M)" "Child Pop" "Religious") ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    title("Spillover Effects: Casino vs Nearby Counties") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Tests for spillover effects to nearby counties. Justifies donut design." ///
            "Reference group: control counties. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
FINAL COMPLETION MESSAGE
==============================================================================*/

display ""
display "================================================================================"
display "=== PAPER ANALYSIS COMPLETE ==="
display "================================================================================"
display ""
display "ALL TABLES AND FIGURES CREATED:"
display ""
display "TABLES:"
display "• Table 1: Summary Statistics (table1_summary_stats.tex)"
display "• Table 2: Population Effects (table2_population_effects.tex)"
display "• Table 3: Family Formation Effects (table3_family_formation.tex)"
display "• Table 4: Effects by Residence Duration (table4_residence_duration.tex)"
display "• Table 5: Population Composition Tests (table5_population_composition.tex)"
display "• Table 6: School Effects (table6_school_effects.tex)"
display "• Table 7: Religious Adherence Effects (table7_religious_adherence.tex)"
display "• Table 8: Denominational Effects (table8_denominational_effects.tex)"
display "• Table 9: Spillover Effects (table9_spillover_effects.tex)"
display ""
display "FIGURES:"
display "• Figure 1: Population Effects by Age Group (figure1_population_effects.png/pdf)"
display "• Figure 2: Fertility Effects by Gender (figure2_fertility_effects.png/pdf)"
display "• Figure 3: Mechanism Test (figure3_mechanism_test.png/pdf)"
display "• Figure 4: Religious Exposure Scatter (figure4_religious_exposure.png/pdf)"
display ""
display "PAPER FLOW:"
display "1. Data and Summary Statistics"
display "2. Population Effects (decline in child-rearing and child populations)"
display "3. Family Formation (negligible marriage, strong fertility decline)"
display "4. Selection vs Behavioral Mechanisms (stronger effects for long-term residents)"
display "5. Family-Adjacent Institutions (school and religious decline)"
display "6. Robustness (spillover effects)"
display ""
display "All files saved to: $output"
display "================================================================================"

cap log close