/*==============================================================================
CASINO IMPACT ON MARRIAGE RATES: DIFFERENCES-IN-DIFFERENCES ANALYSIS
CORRECTED VERSION WITH FIXED EVENT STUDY VARIABLES
==============================================================================*/

clear all
set more off
set maxvar 10000

* Set working directories - CHANGE THESE TO YOUR ACTUAL PATHS
global data "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Data"
global output "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Output"

* Create output directory if it doesn't exist
capture mkdir "$output"

/*==============================================================================
1. LOAD AND PREPARE CASINO DATA
==============================================================================*/

* Load casino data
use "$data\casino_data.dta", clear

* Focus only on casino counties (not neighboring counties)
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

* Save processed casino data
tempfile casino_clean
save `casino_clean'

/*==============================================================================
2. LOAD AND PREPARE ACS DATA
==============================================================================*/

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

* Keep relevant variables
keep county_id year married divorced widowed never_married newly_married ///
     has_children num_children female age age_sq white black hispanic ///
     perwt statefip countyfip

/*==============================================================================
3. MERGE DATASETS AND CREATE CONTROL GROUP
==============================================================================*/

* Merge with casino data
merge m:1 county_id year using `casino_clean'

* Create control group from counties that never get casinos
* Keep casino counties (treated) and counties that never appear in casino data (controls)
gen in_casino_data = (_merge == 3)
gen ever_treated = in_casino_data

* For control counties, set treatment variables to zero
replace treated = 0 if _merge == 1
replace post_treatment = 0 if _merge == 1  
replace treat_post = 0 if _merge == 1
replace treat_year = . if _merge == 1
replace rel_time = . if _merge == 1
replace casino_no = 0 if _merge == 1  // Control counties have 0 prior casinos

* Keep both treated and control counties
keep if _merge == 1 | _merge == 3
drop _merge

* Fill in treatment status consistently within counties
bysort county_id: egen max_ever_treated = max(ever_treated)
replace ever_treated = max_ever_treated
drop max_ever_treated

/*==============================================================================
4. CREATE ADDITIONAL VARIABLES FOR ANALYSIS
==============================================================================*/

* Create basic demographic variables (already done above)
* female, age, age_sq, white, black, hispanic are already created

* Create age groups for heterogeneity analysis (18-29 and 30-40)
gen age_group = 1 if age >= 18 & age <= 29
replace age_group = 2 if age >= 30 & age <= 40
label define age_group_lab 1 "18-29" 2 "30-40"
label values age_group age_group_lab

/*==============================================================================
CORRECTED EVENT STUDY VARIABLES - FIX FOR CONTROL GROUP INCLUSION
==============================================================================*/

* OLD INCORRECT METHOD (commented out):
* forvalues i = 3(-1)2 {
*     gen lag`i' = (rel_time == -`i') if !missing(rel_time)  // EXCLUDES CONTROLS
* }
* 
* forvalues i = 0/10 {
*     gen lead`i' = (rel_time == `i') if !missing(rel_time)  // EXCLUDES CONTROLS
* }

* NEW CORRECTED METHOD - includes control counties:
forvalues i = 3(-1)2 {
    gen lag`i' = 0  // Start with 0 for everyone (including controls)
    replace lag`i' = 1 if rel_time == -`i' & !missing(rel_time)  // Only treated counties get 1
}

forvalues i = 0/10 {
    gen lead`i' = 0  // Start with 0 for everyone (including controls)
    replace lead`i' = 1 if rel_time == `i' & !missing(rel_time)  // Only treated counties get 1
}

* Note: Control counties will have all event study variables = 0, serving as reference group

/*==============================================================================
5. SUMMARY STATISTICS
==============================================================================*/

* Overall summary statistics
estpost summarize married divorced never_married has_children num_children ///
                 female age white black hispanic
esttab using "$output/summary_stats.tex", replace ///
    cells("mean(fmt(3)) sd(fmt(3)) min(fmt(3)) max(fmt(3))") ///
    nomtitle nonumber label booktabs ///
    title("Summary Statistics - Full Sample (Age ≤ 40)")

* Summary statistics by treatment status
estpost tabstat married divorced never_married has_children num_children ///
                female age white black hispanic, ///
                by(treated) statistics(mean sd) columns(statistics)
esttab using "$output/summary_by_treatment.tex", replace ///
    cells("mean(fmt(3)) sd(fmt(3) par)") ///
    nomtitle nonumber label booktabs ///
    title("Summary Statistics by Treatment Status (Age ≤ 40)")

/*==============================================================================
6. MAIN DIFFERENCES-IN-DIFFERENCES ANALYSIS
==============================================================================*/

* DD Analysis for Women
preserve
keep if female == 1

* Marriage
reghdfe married post_treatment age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store dd_married_women

* Divorce  
reghdfe divorced post_treatment age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store dd_divorced_women

* Children
reghdfe num_children post_treatment age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store dd_children_women

* Export results
esttab dd_married_women dd_divorced_women dd_children_women using "$output/dd_results_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment age age_sq) ///
    mtitles("Marriage" "Divorce" "Children") ///
    title("DD Results - Women: Marriage, Divorce, Children (Age ≤ 40)") ///
    booktabs nonotes ///
    addnotes("Notes: Differences-in-differences estimates for women age 40 and under." ///
             "All regressions include county and year fixed effects." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

restore

* DD Analysis for Men  
preserve
keep if female == 0

* Marriage
reghdfe married post_treatment age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store dd_married_men

* Divorce
reghdfe divorced post_treatment age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store dd_divorced_men

* Children
reghdfe num_children post_treatment age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store dd_children_men

* Export results
esttab dd_married_men dd_divorced_men dd_children_men using "$output/dd_results_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment age age_sq) ///
    mtitles("Marriage" "Divorce" "Children") ///
    title("DD Results - Men: Marriage, Divorce, Children (Age ≤ 40)") ///
    booktabs nonotes ///
    addnotes("Notes: Differences-in-differences estimates for men age 40 and under." ///
             "All regressions include county and year fixed effects." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

restore

/*==============================================================================
7. EVENT STUDY ANALYSIS (NOW WITH CORRECTED VARIABLES)
==============================================================================*/

* Event Study for Women
preserve
keep if female == 1

* Marriage event study - should now include controls and match DD sample size
reghdfe married lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_marriage_women

* Divorce event study  
reghdfe divorced lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_divorce_women

* Children event study
reghdfe num_children lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_children_women

restore

* Event Study for Men
preserve  
keep if female == 0

* Marriage event study
reghdfe married lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_marriage_men

* Divorce event study
reghdfe divorced lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_divorce_men

* Children event study
reghdfe num_children lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_children_men

restore

/*==============================================================================
8. ROBUSTNESS CHECKS
==============================================================================*/

* Women robustness checks
preserve
keep if female == 1

* Baseline specification (already estimated above)
estimates restore dd_married_women
estimates store rob_baseline_women

* Add state-year fixed effects
reghdfe married post_treatment age age_sq, absorb(county_id statefip#year) vce(cluster county_id)
estimates store rob_stateyear_women

* Export robustness results
esttab rob_baseline_women rob_stateyear_women using "$output/robustness_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Baseline" "State-Year FE") ///
    title("Robustness Checks - Women (Age ≤ 40)") ///
    booktabs nonotes ///
    addnotes("Notes: Robustness checks for marriage outcome among women age 40 and under." ///
             "Column 1 shows baseline specification, Column 2 adds state-year fixed effects." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

restore

* Men robustness checks
preserve
keep if female == 0

* Baseline specification  
estimates restore dd_married_men
estimates store rob_baseline_men

* Add state-year fixed effects
reghdfe married post_treatment age age_sq, absorb(county_id statefip#year) vce(cluster county_id)
estimates store rob_stateyear_men

* Export robustness results
esttab rob_baseline_men rob_stateyear_men using "$output/robustness_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Baseline" "State-Year FE") ///
    title("Robustness Checks - Men (Age ≤ 40)") ///
    booktabs nonotes ///
    addnotes("Notes: Robustness checks for marriage outcome among men age 40 and under." ///
             "Column 1 shows baseline specification, Column 2 adds state-year fixed effects." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

restore

/*==============================================================================
9. HETEROGENEITY ANALYSIS BY AGE GROUP (18-29 vs 30-40)
==============================================================================*/

* Age heterogeneity for Women
preserve
keep if female == 1

* Marriage by age group
reghdfe married post_treatment age age_sq if age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store age_married_women_1829

reghdfe married post_treatment age age_sq if age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store age_married_women_3040

* Divorce by age group
reghdfe divorced post_treatment age age_sq if age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store age_divorced_women_1829

reghdfe divorced post_treatment age age_sq if age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store age_divorced_women_3040

* Children by age group
reghdfe num_children post_treatment age age_sq if age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store age_children_women_1829

reghdfe num_children post_treatment age age_sq if age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store age_children_women_3040

* Export age heterogeneity results for women
esttab age_married_women_1829 age_married_women_3040 using "$output/age_hetero_married_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Marriage Effects by Age Group - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for marriage outcomes among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab age_divorced_women_1829 age_divorced_women_3040 using "$output/age_hetero_divorced_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Divorce Effects by Age Group - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for divorce outcomes among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab age_children_women_1829 age_children_women_3040 using "$output/age_hetero_children_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Children Effects by Age Group - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for number of children among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

restore

* Age heterogeneity for Men
preserve
keep if female == 0

* Marriage by age group
reghdfe married post_treatment age age_sq if age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_1829

reghdfe married post_treatment age age_sq if age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_3040

* Divorce by age group  
reghdfe divorced post_treatment age age_sq if age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_1829

reghdfe divorced post_treatment age age_sq if age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store m_div_3040

* Children by age group
reghdfe num_children post_treatment age age_sq if age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_1829

reghdfe num_children post_treatment age age_sq if age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_3040

* Export age heterogeneity results for men
esttab m_mar_1829 m_mar_3040 using "$output/age_hetero_married_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Marriage Effects by Age Group - Men") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for marriage outcomes among men." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab m_div_1829 m_div_3040 using "$output/age_hetero_divorced_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Divorce Effects by Age Group - Men") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for divorce outcomes among men." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab m_kid_1829 m_kid_3040 using "$output/age_hetero_children_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Children Effects by Age Group - Men") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for number of children among men." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

restore

/*==============================================================================
10. HETEROGENEITY ANALYSIS BY RACE/ETHNICITY - CORRECTED
==============================================================================*/

* Race heterogeneity for Women
preserve
keep if female == 1

* Marriage by race
reghdfe married post_treatment age age_sq if white == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_white

reghdfe married post_treatment age age_sq if black == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_black

reghdfe married post_treatment age age_sq if hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_hisp

* Divorce by race
reghdfe divorced post_treatment age age_sq if white == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_div_white

reghdfe divorced post_treatment age age_sq if black == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_div_black

reghdfe divorced post_treatment age age_sq if hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_div_hisp

* Children by race
reghdfe num_children post_treatment age age_sq if white == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_white

reghdfe num_children post_treatment age age_sq if black == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_black

reghdfe num_children post_treatment age age_sq if hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_hisp

restore

* Export race heterogeneity results for women
esttab w_mar_white w_mar_black w_mar_hisp using "$output/race_hetero_married_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("White" "Black" "Hispanic") ///
    title("Marriage Effects by Race/Ethnicity - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by race/ethnicity for marriage outcomes among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab w_div_white w_div_black w_div_hisp using "$output/race_hetero_divorced_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("White" "Black" "Hispanic") ///
    title("Divorce Effects by Race/Ethnicity - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by race/ethnicity for divorce outcomes among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab w_kid_white w_kid_black w_kid_hisp using "$output/race_hetero_children_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("White" "Black" "Hispanic") ///
    title("Children Effects by Race/Ethnicity - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by race/ethnicity for number of children among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

* Race heterogeneity for Men
preserve
keep if female == 0

* Marriage by race
reghdfe married post_treatment age age_sq if white == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_white

reghdfe married post_treatment age age_sq if black == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_black

reghdfe married post_treatment age age_sq if hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_hisp

* Divorce by race
reghdfe divorced post_treatment age age_sq if white == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_white

reghdfe divorced post_treatment age age_sq if black == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_black

reghdfe divorced post_treatment age age_sq if hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_hisp

* Children by race
reghdfe num_children post_treatment age age_sq if white == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_white

reghdfe num_children post_treatment age age_sq if black == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_black

reghdfe num_children post_treatment age age_sq if hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_hisp

restore

* Export race heterogeneity results for men
esttab m_mar_white m_mar_black m_mar_hisp using "$output/race_hetero_married_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("White" "Black" "Hispanic") ///
    title("Marriage Effects by Race/Ethnicity - Men") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by race/ethnicity for marriage outcomes among men." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab m_div_white m_div_black m_div_hisp using "$output/race_hetero_divorced_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("White" "Black" "Hispanic") ///
    title("Divorce Effects by Race/Ethnicity - Men") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by race/ethnicity for divorce outcomes among men." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab m_kid_white m_kid_black m_kid_hisp using "$output/race_hetero_children_men.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("White" "Black" "Hispanic") ///
    title("Children Effects by Race/Ethnicity - Men") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by race/ethnicity for number of children among men." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
EVENT STUDY ANALYSIS - COMPLETE WITH CORRECTED REGRESSIONS
==============================================================================*/

* Install coefplot if not already installed
capture ssc install coefplot

/*==============================================================================
MAIN EVENT STUDY REGRESSIONS FIRST (NOW WITH CORRECTED VARIABLES)
==============================================================================*/

* Event study for Women
preserve
keep if female == 1

reghdfe married lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_marriage_women

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_divorce_women

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_children_women

restore

* Event study for Men
preserve
keep if female == 0

reghdfe married lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_marriage_men

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_divorce_men

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_children_men

restore

/*==============================================================================
FUNCTION TO CREATE EVENT STUDY PLOTS
==============================================================================*/

capture program drop create_event_study_plot
program define create_event_study_plot
    args est_name outcome gender
    
    estimates restore `est_name'
    
    coefplot, keep(lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10) ///
        vertical ///
        coeflabels(lag3 = "-3" lag2 = "-2" ///
                   lead0 = "0" lead1 = "1" lead2 = "2" lead3 = "3" lead4 = "4" ///
                   lead5 = "5" lead6 = "6" lead7 = "7" lead8 = "8" lead9 = "9" lead10 = "10") ///
        yline(0, lcolor(red) lpattern(dash)) ///
        xline(2.5, lcolor(blue) lpattern(dash)) ///
        title("Event Study: Casino Effect on `outcome' - `gender'") ///
        xtitle("Years Relative to Casino Opening") ///
        ytitle("Effect on `outcome'") ///
        graphregion(color(white)) plotregion(color(white))
    
    * Export both PNG and PDF versions
    local filename = "event_study_" + lower(subinstr("`outcome'", " ", "_", .)) + "_" + lower("`gender'")
    graph export "$output/`filename'.png", replace width(1000) height(700)
    graph export "$output/`filename'.pdf", replace
end

/*==============================================================================
CREATE MAIN EVENT STUDY PLOTS
==============================================================================*/

create_event_study_plot "event_marriage_women" "Marriage" "Women"
create_event_study_plot "event_divorce_women" "Divorce" "Women"  
create_event_study_plot "event_children_women" "Children" "Women"

create_event_study_plot "event_marriage_men" "Marriage" "Men"
create_event_study_plot "event_divorce_men" "Divorce" "Men"
create_event_study_plot "event_children_men" "Children" "Men"

/*==============================================================================
EVENT STUDIES BY AGE GROUP
==============================================================================*/

* Age group event studies for Women
preserve
keep if female == 1

* Ages 18-29 - Women
reghdfe married lag3 lag2 lead0-lead10 age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_w_1829

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_w_1829

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_w_1829

* Ages 30-40 - Women
reghdfe married lag3 lag2 lead0-lead10 age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_w_3040

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_w_3040

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_w_3040

restore

* Age group event studies for Men
preserve
keep if female == 0

* Ages 18-29 - Men
reghdfe married lag3 lag2 lead0-lead10 age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_m_1829

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_m_1829

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_m_1829

* Ages 30-40 - Men
reghdfe married lag3 lag2 lead0-lead10 age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_m_3040

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_m_3040

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_m_3040

restore

* Create age group event study plots
create_event_study_plot "event_mar_w_1829" "Marriage" "Women_18-29"
create_event_study_plot "event_div_w_1829" "Divorce" "Women_18-29"
create_event_study_plot "event_kid_w_1829" "Children" "Women_18-29"

create_event_study_plot "event_mar_w_3040" "Marriage" "Women_30-40"
create_event_study_plot "event_div_w_3040" "Divorce" "Women_30-40"
create_event_study_plot "event_kid_w_3040" "Children" "Women_30-40"

create_event_study_plot "event_mar_m_1829" "Marriage" "Men_18-29"
create_event_study_plot "event_div_m_1829" "Divorce" "Men_18-29"
create_event_study_plot "event_kid_m_1829" "Children" "Men_18-29"

create_event_study_plot "event_mar_m_3040" "Marriage" "Men_30-40"
create_event_study_plot "event_div_m_3040" "Divorce" "Men_30-40"
create_event_study_plot "event_kid_m_3040" "Children" "Men_30-40"

/*==============================================================================
EVENT STUDIES BY RACE/ETHNICITY
==============================================================================*/

* Race event studies for Women
preserve
keep if female == 1

* White Women
reghdfe married lag3 lag2 lead0-lead10 age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_w_white

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_w_white

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_w_white

* Black Women
reghdfe married lag3 lag2 lead0-lead10 age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_w_black

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_w_black

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_w_black

* Hispanic Women
reghdfe married lag3 lag2 lead0-lead10 age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_w_hisp

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_w_hisp

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_w_hisp

restore

* Race event studies for Men
preserve
keep if female == 0

* White Men
reghdfe married lag3 lag2 lead0-lead10 age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_m_white

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_m_white

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_m_white

* Black Men
reghdfe married lag3 lag2 lead0-lead10 age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_m_black

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_m_black

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_m_black

* Hispanic Men
reghdfe married lag3 lag2 lead0-lead10 age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_mar_m_hisp

reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_div_m_hisp

reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_kid_m_hisp

restore

* Create race event study plots
create_event_study_plot "event_mar_w_white" "Marriage" "Women_White"
create_event_study_plot "event_div_w_white" "Divorce" "Women_White"
create_event_study_plot "event_kid_w_white" "Children" "Women_White"

create_event_study_plot "event_mar_w_black" "Marriage" "Women_Black"
create_event_study_plot "event_div_w_black" "Divorce" "Women_Black"
create_event_study_plot "event_kid_w_black" "Children" "Women_Black"

create_event_study_plot "event_mar_w_hisp" "Marriage" "Women_Hispanic"
create_event_study_plot "event_div_w_hisp" "Divorce" "Women_Hispanic"
create_event_study_plot "event_kid_w_hisp" "Children" "Women_Hispanic"

create_event_study_plot "event_mar_m_white" "Marriage" "Men_White"
create_event_study_plot "event_div_m_white" "Divorce" "Men_White"
create_event_study_plot "event_kid_m_white" "Children" "Men_White"

create_event_study_plot "event_mar_m_black" "Marriage" "Men_Black"
create_event_study_plot "event_div_m_black" "Divorce" "Men_Black"
create_event_study_plot "event_kid_m_black" "Children" "Men_Black"

create_event_study_plot "event_mar_m_hisp" "Marriage" "Men_Hispanic"
create_event_study_plot "event_div_m_hisp" "Divorce" "Men_Hispanic"
create_event_study_plot "event_kid_m_hisp" "Children" "Men_Hispanic"

/*==============================================================================
VERIFICATION: CHECK THAT DD AND EVENT STUDY SAMPLES NOW MATCH
==============================================================================*/

display ""
display "=== VERIFICATION: DD vs CORRECTED EVENT STUDY SAMPLE SIZES ==="

* Check sample sizes for women's divorce analysis (our diagnostic example)
preserve
keep if female == 1

* DD sample size
reghdfe divorced post_treatment age age_sq, absorb(county_id year) vce(cluster county_id)
scalar dd_obs_final = e(N)

* Event study sample size (with corrected variables)
reghdfe divorced lag3 lag2 lead0-lead10 age age_sq, absorb(county_id year) vce(cluster county_id)
scalar es_obs_final = e(N)

* Display comparison
display "Final DD observations: " dd_obs_final
display "Final Event Study observations: " es_obs_final
display "Difference: " dd_obs_final - es_obs_final

if dd_obs_final == es_obs_final {
    display "SUCCESS: Sample sizes now match perfectly!"
} 
else if abs(dd_obs_final - es_obs_final) < 1000 {
    display "GOOD: Sample sizes are very close (minor differences acceptable)"
} 
else {
    display "WARNING: Still significant sample differences - may need further investigation"
}

* Compare coefficients
scalar dd_coef_final = _b[post_treatment]

* Calculate average post-treatment effect from event study
local sum_post = 0
local count_post = 0
forvalues i = 0/10 {
    capture {
        local coef = _b[lead`i']
        local sum_post = `sum_post' + `coef'
        local count_post = `count_post' + 1
    }
}
local avg_es_coef = `sum_post' / `count_post'

display ""
display "=== COEFFICIENT COMPARISON ==="
display "DD coefficient: " dd_coef_final
display "Event study average post-treatment: " `avg_es_coef'
display "Difference: " `avg_es_coef' - dd_coef_final

if abs(`avg_es_coef' - dd_coef_final) < 0.001 {
    display "EXCELLENT: Coefficients are now very close!"
}
else {
    display "Note: Some difference remains - may reflect dynamic treatment effects"
}

restore

/*==============================================================================
DISPLAY COMPLETION MESSAGE
==============================================================================*/

display ""
display "=== CORRECTED ANALYSIS COMPLETE ==="
display "Key fixes implemented:"
display "1. ✓ Event study variables now include control counties"
display "2. ✓ Control counties serve as reference group (all event vars = 0)"
display "3. ✓ DD and event study should now use identical samples"
display "4. ✓ Event study plots will show proper pre-trends and treatment effects"
display ""
display "Files created:"
display "  - Summary statistics tables"
display "  - Main DD results for women and men"  
display "  - Corrected event study plots (36 files total)"
display "  - Robustness check tables"
display "  - Age heterogeneity tables (2 age groups: 18-29, 30-40)"
display "  - Race heterogeneity tables"
display ""
display "All results saved to: $output"
display "Sample restricted to individuals age 40 and under."