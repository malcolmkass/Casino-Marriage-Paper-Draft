clear all
set more off
set maxvar 10000

* Set working directories - CHANGE THESE TO YOUR ACTUAL PATHS
global data "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Data"
global output "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Output"

cap log close
log using "$output/casino_analysis_log_fixed.txt", replace text



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

tempfile casino_clean
save `casino_clean'

/*==============================================================================
2. LOAD AND PREPARE ACS DATA FOR POPULATION ANALYSIS (ALL AGES)
==============================================================================*/

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

/*==============================================================================
3. MERGE WITH CASINO DATA
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

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)

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

********************************************************************************
* POPULATION ANALYSIS - ALL AGE GROUPS
********************************************************************************

display ""
display "=============================================================="
display "=== POPULATION ANALYSIS BY AGE GROUPS ==="
display "=============================================================="

* Create population analysis at county-year level
preserve

* Create population variables before collapsing
gen total_pop_temp = perwt if all_ages == 1
gen child_rearing_pop_temp = perwt if child_rearing_age == 1
gen children_pop_temp = perwt if children == 1
gen school_age_pop_temp = perwt if school_age == 1
gen school_enrolled_temp = perwt if school_age_enrolled == 1
gen public_enrolled_temp = perwt if school_age_public == 1

* Calculate populations by county-year
collapse (sum) total_pop=total_pop_temp ///
         (sum) child_rearing_pop=child_rearing_pop_temp ///
         (sum) children_pop=children_pop_temp ///
         (sum) school_age_pop=school_age_pop_temp ///
         (sum) school_enrolled=school_enrolled_temp ///
         (sum) public_enrolled=public_enrolled_temp, ///
         by(county_id year casino_county rel_time_full donut_sample)

* Only keep counties with populations measured
drop if missing(total_pop) | total_pop == 0

* Calculate enrollment rates
gen school_enrollment_rate = school_enrolled / school_age_pop if school_age_pop > 0
gen public_enrollment_rate = public_enrolled / school_age_pop if school_age_pop > 0

* Create log population variables
gen ln_total_pop = ln(total_pop)
gen ln_child_rearing_pop = ln(child_rearing_pop) if child_rearing_pop > 0
gen ln_children_pop = ln(children_pop) if children_pop > 0
gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0

* Create event time variables for population analysis
forvalues j = 3(-1)2 {
    gen lag`j'_pop = 0
    replace lag`j'_pop = 1 if rel_time_full == -`j' & !missing(rel_time_full)
}

forvalues j = 0/7 {
    gen lead`j'_pop = 0
    replace lead`j'_pop = 1 if rel_time_full == `j' & !missing(rel_time_full)
}

gen lead8plus_pop = 0
replace lead8plus_pop = 1 if rel_time_full >= 8 & !missing(rel_time_full)

/*==============================================================================
EVENT STUDY REGRESSIONS
==============================================================================*/

display ""
display "=== RUNNING EVENT STUDY REGRESSIONS FOR POPULATION ANALYSIS ==="

* 1. Total Population (All Ages)
reghdfe ln_total_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store pop_total

* 2. Child-Rearing Age Population (18-40)
reghdfe ln_child_rearing_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store pop_child_rearing

* 3. Children Population (≤17)
reghdfe ln_children_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store pop_children

* 4. School-Age Population (5-17)
reghdfe ln_school_age_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store pop_school_age

* 5. School Enrollment Rate
reghdfe school_enrollment_rate ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store enroll_rate

* 6. Public School Enrollment Rate
reghdfe public_enrollment_rate ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store public_enroll_rate

/*==============================================================================
CREATE POPULATION ANALYSIS FIGURES
==============================================================================*/

display ""
display "=== CREATING POPULATION ANALYSIS FIGURES ==="

* Figure 1: Population Effects by Age Group
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
            label("Children (≤17)")), ///
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
    legend(position(6) rows(1) size(medium) ///
          region(lcolor(none) fcolor(none)) ///
          symxsize(5) keygap(2) rowgap(1)) ///
    note("Effects on log population by age group. Donut sample excludes nearby counties.", ///
         size(small) margin(small) position(7)) ///
    graphregion(color(white) margin(medium)) ///
    plotregion(color(white) margin(medium)) ///
    scheme(s1color)
    
graph export "$output/population_effects_by_age.png", replace width(1400) height(900)
graph export "$output/population_effects_by_age.pdf", replace

* Figure 2: School Enrollment Effects
coefplot (pop_school_age, ///
            ciopts(lcolor(navy) lwidth(medium)) ///
            mcolor(navy) msymbol(O) msize(medium) ///
            label("School-Age Population (5-17)")) ///
         (enroll_rate, ///
            ciopts(lcolor(maroon) lwidth(medium)) ///
            mcolor(maroon) msymbol(D) msize(medium) ///
            label("School Enrollment Rate")) ///
         (public_enroll_rate, ///
            ciopts(lcolor(forest_green) lwidth(medium)) ///
            mcolor(forest_green) msymbol(T) msize(medium) ///
            label("Public School Enrollment Rate")), ///
    keep(lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    vertical ///
    coeflabels(lag3_pop = "-3" lag2_pop = "-2" lead0_pop = "0" lead1_pop = "1" lead2_pop = "2" ///
              lead3_pop = "3" lead4_pop = "4" lead5_pop = "5" lead6_pop = "6" ///
              lead7_pop = "7" lead8plus_pop = "8+", labsize(medium)) ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(2.5, lcolor(gray) lpattern(dash)) ///
    title("School Enrollment Effects", ///
          size(medlarge) margin(medium) color(black)) ///
    xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
    ytitle("Effect", size(medium) margin(medium)) ///
    ylabel(, labsize(medium) format(%9.3f)) ///
    xlabel(, labsize(medium)) ///
    legend(position(6) rows(1) size(medium) ///
          region(lcolor(none) fcolor(none)) ///
          symxsize(5) keygap(2) rowgap(1)) ///
    note("Effects on school-age population (log) and enrollment rates. Donut sample excludes nearby counties.", ///
         size(small) margin(small) position(7)) ///
    graphregion(color(white) margin(medium)) ///
    plotregion(color(white) margin(medium)) ///
    scheme(s1color)
    
graph export "$output/school_enrollment_effects.png", replace width(1400) height(900)
graph export "$output/school_enrollment_effects.pdf", replace

/*==============================================================================
SUMMARY STATISTICS AND ADDITIONAL ANALYSIS
==============================================================================*/

display ""
display "=== POPULATION ANALYSIS SUMMARY STATISTICS ==="

* Summary statistics for treated vs control counties
tabstat total_pop child_rearing_pop children_pop school_age_pop school_enrollment_rate public_enrollment_rate ///
    if donut_sample == 1, by(casino_county) stats(mean sd n) format(%9.2f)

* Test for pre-trends
display ""
display "=== PRE-TREND TESTS ==="

* Test joint significance of pre-treatment coefficients
foreach outcome in total child_rearing children school_age {
    display ""
    display "Testing pre-trends for `outcome' population:"
    estimates restore pop_`outcome'
    test lag3_pop lag2_pop
    display "F-stat: " r(F) ", p-value: " r(p)
}

* Test joint significance of pre-treatment coefficients for enrollment
display ""
display "Testing pre-trends for school enrollment rate:"
estimates restore enroll_rate
test lag3_pop lag2_pop
display "F-stat: " r(F) ", p-value: " r(p)

display ""
display "Testing pre-trends for public school enrollment rate:"
estimates restore public_enroll_rate
test lag3_pop lag2_pop
display "F-stat: " r(F) ", p-value: " r(p)

/*==============================================================================
SAVE RESULTS TABLES
==============================================================================*/

display ""
display "=== SAVING RESULTS TABLES ==="

* Export population analysis results to table
esttab pop_total pop_child_rearing pop_children pop_school_age ///
    using "$output/population_analysis_results.tex", ///
    replace booktabs fragment ///
    keep(lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    coeflabels(lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
              lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
              lead7_pop "t+7" lead8plus_pop "t+8+") ///
    mgroups("Total Pop" "Child-Rearing" "Children" "School-Age", ///
           pattern(1 1 1 1) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    nonotes addnotes("Standard errors clustered at county level in parentheses." ///
                    "Donut sample excludes nearby counties." ///
                    "All population variables in logs except enrollment rates.")

* Export enrollment analysis results to table  
esttab enroll_rate public_enroll_rate ///
    using "$output/school_enrollment_results.tex", ///
    replace booktabs fragment ///
    keep(lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    coeflabels(lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
              lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
              lead7_pop "t+7" lead8plus_pop "t+8+") ///
    mgroups("Enrollment Rate" "Public Enrollment Rate", ///
           pattern(1 1) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    stats(N r2, fmt(%9.0fc %9.3f) labels("Observations" "R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    nonotes addnotes("Standard errors clustered at county level in parentheses." ///
                    "Donut sample excludes nearby counties." ///
                    "Enrollment rates are fraction of school-age population (5-17) enrolled.")

restore

display ""
display "=== POPULATION ANALYSIS COMPLETE ==="

cap log close