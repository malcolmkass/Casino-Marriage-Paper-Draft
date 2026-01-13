/*==============================================================================
CASINO IMPACT ON MARRIAGE RATES: DIFFERENCES-IN-DIFFERENCES ANALYSIS
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

* Create event study variables (leads and lags) using rel_time
forvalues i = 3(-1)2 {
    gen lag`i' = (rel_time == -`i') if !missing(rel_time)
}

forvalues i = 0/10 {
    gen lead`i' = (rel_time == `i') if !missing(rel_time)
}

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
reghdfe married post_treatment age age_sq if treated == 1, absorb(county_id year) vce(cluster county_id)
estimates store dd_married_men

* Divorce
reghdfe divorced post_treatment age age_sq if treated == 1, absorb(county_id year) vce(cluster county_id)
estimates store dd_divorced_men

* Children
reghdfe num_children post_treatment age age_sq if treated == 1, absorb(county_id year) vce(cluster county_id)
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
7. EVENT STUDY ANALYSIS
==============================================================================*/

* Event Study for Women
preserve
keep if female == 1

* Marriage event study
reghdfe married lag3 lag2 lead0-lead10 age age_sq if treated == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_marriage_women

* Divorce event study  
reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if treated == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_divorce_women

* Children event study
reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if treated == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_children_women

restore

* Event Study for Men
preserve  
keep if female == 0

* Marriage event study
reghdfe married lag3 lag2 lead0-lead10 age age_sq if treated == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_marriage_men

* Divorce event study
reghdfe divorced lag3 lag2 lead0-lead10 age age_sq if treated == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_divorce_men

* Children event study
reghdfe num_children lag3 lag2 lead0-lead10 age age_sq if treated == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event_children_men

restore

/*==============================================================================
8. ROBUSTNESS CHECKS
==============================================================================*/

* Generate state_id for state-year fixed effects
gen state_id = floor(county_id/1000)

* Women robustness checks
preserve
keep if female == 1

* Baseline specification (already estimated above)
estimates restore dd_married_women
estimates store rob_baseline_women

* Add state-year fixed effects
reghdfe married post_treatment age age_sq, absorb(county_id state_id#year) vce(cluster county_id)
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
reghdfe married post_treatment age age_sq, absorb(county_id state_id#year) vce(cluster county_id)
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
9. HETEROGENEITY ANALYSIS BY AGE GROUP (18-29 vs 30-40) - FIXED ESTIMATE NAMES
==============================================================================*/

* Age heterogeneity for Women
preserve
keep if female == 1

* Marriage by age group
reghdfe married post_treatment age age_sq if treated == 1 & age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_1829

reghdfe married post_treatment age age_sq if treated == 1 & age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_3040

* Divorce by age group
reghdfe divorced post_treatment age age_sq if treated == 1 & age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_div_1829

reghdfe divorced post_treatment age age_sq if treated == 1 & age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store w_div_3040

* Children by age group
reghdfe num_children post_treatment age age_sq if treated == 1 & age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_1829

reghdfe num_children post_treatment age age_sq if treated == 1 & age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_3040

* Export age heterogeneity results for women
esttab w_mar_1829 w_mar_3040 using "$output/age_hetero_married_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Marriage Effects by Age Group - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for marriage outcomes among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab w_div_1829 w_div_3040 using "$output/age_hetero_divorced_women.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("18-29" "30-40") ///
    title("Divorce Effects by Age Group - Women") ///
    booktabs nonotes ///
    addnotes("Notes: DD estimates by age group for divorce outcomes among women." ///
             "All regressions include county and year fixed effects and age controls." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab w_kid_1829 w_kid_3040 using "$output/age_hetero_children_women.tex", ///
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
reghdfe married post_treatment age age_sq if treated == 1 & age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_1829

reghdfe married post_treatment age age_sq if treated == 1 & age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_3040

* Divorce by age group  
reghdfe divorced post_treatment age age_sq if treated == 1 & age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_1829

reghdfe divorced post_treatment age age_sq if treated == 1 & age_group == 2, absorb(county_id year) vce(cluster county_id)
estimates store m_div_3040

* Children by age group
reghdfe num_children post_treatment age age_sq if treated == 1 & age_group == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_1829

reghdfe num_children post_treatment age age_sq if treated == 1 & age_group == 2, absorb(county_id year) vce(cluster county_id)
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
10. HETEROGENEITY ANALYSIS BY RACE/ETHNICITY - FIXED ESTIMATE NAMES
==============================================================================*/

* Race heterogeneity for Women
preserve
keep if female == 1

* Marriage by race
reghdfe married post_treatment age age_sq if treated == 1 & white == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_white

reghdfe married post_treatment age age_sq if treated == 1 & black == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_black

reghdfe married post_treatment age age_sq if treated == 1 & hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_mar_hisp

* Divorce by race
reghdfe divorced post_treatment age age_sq if treated == 1 & white == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_div_white

reghdfe divorced post_treatment age age_sq if treated == 1 & black == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_div_black

reghdfe divorced post_treatment age age_sq if treated == 1 & hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_div_hisp

* Children by race
reghdfe num_children post_treatment age age_sq if treated == 1 & white == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_white

reghdfe num_children post_treatment age age_sq if treated == 1 & black == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_black

reghdfe num_children post_treatment age age_sq if treated == 1 & hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store w_kid_hisp

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

restore

* Race heterogeneity for Men
preserve
keep if female == 0

* Marriage by race
reghdfe married post_treatment age age_sq if treated == 1 & white == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_white

reghdfe married post_treatment age age_sq if treated == 1 & black == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_black

reghdfe married post_treatment age age_sq if treated == 1 & hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_mar_hisp

* Divorce by race
reghdfe divorced post_treatment age age_sq if treated == 1 & white == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_white

reghdfe divorced post_treatment age age_sq if treated == 1 & black == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_black

reghdfe divorced post_treatment age age_sq if treated == 1 & hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_div_hisp

* Children by race
reghdfe num_children post_treatment age age_sq if treated == 1 & white == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_white

reghdfe num_children post_treatment age age_sq if treated == 1 & black == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_black

reghdfe num_children post_treatment age age_sq if treated == 1 & hispanic == 1, absorb(county_id year) vce(cluster county_id)
estimates store m_kid_hisp

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

restore

/*==============================================================================
11. CREATE EVENT STUDY PLOTS WITH PROPER X-AXIS LABELS
==============================================================================*/

* Install coefplot if not already installed
capture ssc install coefplot

* Function to create properly labeled event study plots
program define create_event_study_plot
    args est_name outcome gender
    
    estimates restore `est_name'
    
    coefplot, keep(lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10) ///
        vertical ///
        rename(lag3 = -3 lag2 = -2 ///
               lead0 = 0 lead1 = 1 lead2 = 2 lead3 = 3 lead4 = 4 ///
               lead5 = 5 lead6 = 6 lead7 = 7 lead8 = 8 lead9 = 9 lead10 = 10) ///
        coeflabels(-3 = "-3" -2 = "-2" ///
                   0 = "0" 1 = "1" 2 = "2" 3 = "3" 4 = "4" ///
                   5 = "5" 6 = "6" 7 = "7" 8 = "8" 9 = "9" 10 = "10") ///
        yline(0, lcolor(red) lpattern(dash)) ///
        xline(2.5, lcolor(blue) lpattern(dash)) ///
        title("Event Study: Casino Effect on `outcome' - `gender'") ///
        xtitle("Years Relative to Casino Opening") ///
        ytitle("Effect on `outcome'") ///
        xlabel(-3(1)10) ///
        graphregion(color(white)) plotregion(color(white))
    
    * Export both PNG and PDF versions
    local filename = "event_study_" + lower(subinstr("`outcome'", " ", "_", .)) + "_" + lower("`gender'")
    graph export "$output/`filename'.png", replace width(1000) height(700)
    graph export "$output/`filename'.pdf", replace
end

* Create all event study plots with proper labeling
create_event_study_plot "event_marriage_women" "Marriage" "Women"
create_event_study_plot "event_divorce_women" "Divorce" "Women"  
create_event_study_plot "event_children_women" "Children" "Women"

create_event_study_plot "event_marriage_men" "Marriage" "Men"
create_event_study_plot "event_divorce_men" "Divorce" "Men"
create_event_study_plot "event_children_men" "Children" "Men"

/*==============================================================================
12. DISPLAY COMPLETION MESSAGE
==============================================================================*/

display "Analysis complete! All results saved to: $output"
display "Files created:"
display "  - Summary statistics tables"
display "  - Main DD results for women and men"  
display "  - Event study plots (6 files)"
display "  - Robustness check tables"
display "  - Age heterogeneity tables (2 age groups: 18-29, 30-40)"
display "  - Race heterogeneity tables"
display ""
display "Sample restricted to individuals age 40 and under."