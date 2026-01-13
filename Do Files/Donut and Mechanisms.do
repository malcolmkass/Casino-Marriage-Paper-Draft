/*==============================================================================
COMPLETE SPILLOVER AND DONUT ANALYSIS WITH EVENT STUDY FIGURES
Casino Effects on Marriage, Divorce, and Fertility - Fixed Code
==============================================================================*/

clear all
set more off
set maxvar 10000

* Set working directories - CHANGE THESE TO YOUR ACTUAL PATHS
global data "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Data"
global output "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Output"

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

* Keep necessary variables
keep county_id year married divorced widowed never_married newly_married migrate1 movedin sample serial ///
     has_children num_children female age age_sq white black hispanic ///
     perwt statefip countyfip age_group

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

display "Sample composition:"
tab casino_county nearby_county

/*==============================================================================
SPILLOVER TESTS - WOMEN
==============================================================================*/

display ""
display "=== SPILLOVER ANALYSIS - WOMEN ==="

preserve
keep if female == 1
eststo clear

eststo w_spill_mar: reghdfe married casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)
    
eststo w_spill_div: reghdfe divorced casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)
    
eststo w_spill_has: reghdfe has_children casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)
    
eststo w_spill_num: reghdfe num_children casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)

esttab w_spill_mar w_spill_div w_spill_has w_spill_num using "$output/spillover_women.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_post nearby_post) ///
    mtitles("Marriage" "Divorce" "Has Children" "Num Children") ///
    title("Spillover Analysis: Women's Outcomes") ///
    addnotes("Notes: All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")
restore

/*==============================================================================
SPILLOVER TESTS - MEN
==============================================================================*/

display ""
display "=== SPILLOVER ANALYSIS - MEN ==="

preserve
keep if female == 0
eststo clear

eststo m_spill_mar: reghdfe married casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)
    
eststo m_spill_div: reghdfe divorced casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)
    
eststo m_spill_has: reghdfe has_children casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)
    
eststo m_spill_num: reghdfe num_children casino_post nearby_post age age_sq ///
    [aw=perwt], absorb(county_id year) vce(cluster county_id)

esttab m_spill_mar m_spill_div m_spill_has m_spill_num using "$output/spillover_men.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_post nearby_post) ///
    mtitles("Marriage" "Divorce" "Has Children" "Num Children") ///
    title("Spillover Analysis: Men's Outcomes") ///
    addnotes("Notes: All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")
restore

/*==============================================================================
SPILLOVER HYPOTHESIS TESTS
==============================================================================*/

display ""
display "=== TESTING SPILLOVER HYPOTHESES ==="

foreach outcome in married divorced has_children num_children {
    foreach gender_name in "Women" "Men" {
        local gender_cond = cond("`gender_name'" == "Women", "female == 1", "female == 0")
        di ""
        di "Testing spillovers for `outcome' - `gender_name'"
        
        quietly reghdfe `outcome' casino_post nearby_post age age_sq ///
            if `gender_cond' [aw=perwt], absorb(county_id year) vce(cluster county_id)
            
        test nearby_post = 0
        local p_spillover_zero = r(p)
        
        test casino_post = nearby_post
        local p_spillover_equal = r(p)
        
        test casino_post = nearby_post = 0
        local p_both_zero = r(p)
        
        di "   Spillover = 0: p = " %6.4f `p_spillover_zero'
        di "   Spillover = Direct: p = " %6.4f `p_spillover_equal'
        di "   Both = 0: p = " %6.4f `p_both_zero'
    }
}

/*==============================================================================
DONUT DESIGN ANALYSIS
==============================================================================*/

display ""
display "=== DONUT DESIGN ANALYSIS ==="

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)
label var donut_sample "Donut Sample (Casino + Far Counties)"

* Display sample statistics
display "=== SAMPLE STATISTICS ==="
tab donut_sample, missing
tab casino_county donut_sample, missing
tab sample_type donut_sample, missing

* Summary statistics
summarize married divorced num_children if donut_sample == 1 & female == 1, detail
summarize married divorced num_children if donut_sample == 1 & female == 0, detail

* Count observations
count
local orig_n = r(N)
count if donut_sample == 1
local donut_n = r(N)

di ""
di "Original sample size: " %12.0fc `orig_n'
di "Donut sample size: " %12.0fc `donut_n'
di "Observations dropped: " %12.0fc (`orig_n' - `donut_n')
di "Percent retained: " %6.2f (100 * `donut_n' / `orig_n') "%"

/*==============================================================================
DONUT vs ORIGINAL COMPARISON - WOMEN
==============================================================================*/

display ""
display "=== DONUT vs ORIGINAL COMPARISON - WOMEN ==="

eststo clear

foreach outcome in married divorced has_children num_children {
    eststo orig_w_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
        
    eststo donut_w_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 1 & donut_sample == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
}

* Export tables
esttab orig_w_married donut_w_married orig_w_divorced donut_w_divorced ///
    using "$output/donut_women_marriage_divorce.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Orig: Marriage" "Donut: Marriage" "Orig: Divorce" "Donut: Divorce") ///
    title("Donut Design Comparison: Women's Marriage and Divorce") ///
    addnotes("Notes: Original sample includes all counties. Donut sample drops nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab orig_w_has_children donut_w_has_children orig_w_num_children donut_w_num_children ///
    using "$output/donut_women_fertility.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Orig: Has Child" "Donut: Has Child" "Orig: Num Child" "Donut: Num Child") ///
    title("Donut Design Comparison: Women's Fertility") ///
    addnotes("Notes: Original sample includes all counties. Donut sample drops nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
DONUT vs ORIGINAL COMPARISON - MEN
==============================================================================*/

display ""
display "=== DONUT vs ORIGINAL COMPARISON - MEN ==="

eststo clear

foreach outcome in married divorced has_children num_children {
    eststo orig_m_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 0 [aw=perwt], absorb(county_id year) vce(cluster county_id)
        
    eststo donut_m_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 0 & donut_sample == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
}

* Export tables
esttab orig_m_married donut_m_married orig_m_divorced donut_m_divorced ///
    using "$output/donut_men_marriage_divorce.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Orig: Marriage" "Donut: Marriage" "Orig: Divorce" "Donut: Divorce") ///
    title("Donut Design Comparison: Men's Marriage and Divorce") ///
    addnotes("Notes: Original sample includes all counties. Donut sample drops nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab orig_m_has_children donut_m_has_children orig_m_num_children donut_m_num_children ///
    using "$output/donut_men_fertility.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Orig: Has Child" "Donut: Has Child" "Orig: Num Child" "Donut: Num Child") ///
    title("Donut Design Comparison: Men's Fertility") ///
    addnotes("Notes: Original sample includes all counties. Donut sample drops nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
EVENT STUDIES - RUN AND SAVE ALL MODELS
==============================================================================*/

display ""
display "=== RUNNING ALL EVENT STUDIES ==="

* Women - Original Sample
foreach outcome in married divorced num_children {
    display "Running women's `outcome' event study (original)..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo orig_es_w_`outcome'
        estimates save "$output/orig_es_w_`outcome'", replace
        display "Saved: orig_es_w_`outcome'"
    }
    else {
        display as error "Failed: orig_es_w_`outcome'"
    }
}

* Men - Original Sample
foreach outcome in married divorced num_children {
    display "Running men's `outcome' event study (original)..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 0 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo orig_es_m_`outcome'
        estimates save "$output/orig_es_m_`outcome'", replace
        display "Saved: orig_es_m_`outcome'"
    }
    else {
        display as error "Failed: orig_es_m_`outcome'"
    }
}

* Women - Donut Sample
foreach outcome in married divorced num_children {
    display "Running women's `outcome' event study (donut)..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo donut_es_w_`outcome'
        estimates save "$output/donut_es_w_`outcome'", replace
        display "Saved: donut_es_w_`outcome'"
    }
    else {
        display as error "Failed: donut_es_w_`outcome'"
    }
}

* Men - Donut Sample
foreach outcome in married divorced num_children {
    display "Running men's `outcome' event study (donut)..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 0 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo donut_es_m_`outcome'
        estimates save "$output/donut_es_m_`outcome'", replace
        display "Saved: donut_es_m_`outcome'"
    }
    else {
        display as error "Failed: donut_es_m_`outcome'"
    }
}

/*==============================================================================
CREATE EVENT STUDY PLOTS - FIXED VERSION
==============================================================================*/

display ""
display "=== CREATING EVENT STUDY PLOTS ==="

* Load all saved estimates
local outcomes "married divorced num_children"
local genders "w m"
local samples "orig donut"

foreach sample in `samples' {
    foreach gender in `genders' {
        foreach outcome in `outcomes' {
            local est_name "`sample'_es_`gender'_`outcome'"
            capture confirm file "$output/`est_name'.ster"
            if _rc == 0 {
                capture estimates use "$output/`est_name'"
                if _rc == 0 {
                    estimates store `est_name'
                    display "Loaded: `est_name'"
                }
            }
        }
    }
}

* Create individual donut plots
foreach gender in w m {
    local gender_label = cond("`gender'" == "w", "Women", "Men")
    
    foreach outcome in married divorced num_children {
        local outcome_label = cond("`outcome'" == "married", "Marriage", ///
                             cond("`outcome'" == "divorced", "Divorce", "Number of Children"))
        
        capture estimates restore donut_es_`gender'_`outcome'
        if _rc == 0 {
            coefplot, ///
                keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
                vertical ///
                coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                          lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                          lead4_alt = "4" lead5plus_alt = "5+") ///
                yline(0, lcolor(red) lpattern(dash)) ///
                xline(2.5, lcolor(blue) lpattern(dash)) ///
                title("Event Study (Donut): `outcome_label' - `gender_label'") ///
                xtitle("Years Relative to Casino Opening") ///
                ytitle("Effect on `outcome_label'") ///
                graphregion(color(white)) plotregion(color(white)) ///
                note("Note: Donut sample excludes nearby counties")
                
            graph export "$output/donut_es_`gender'_`outcome'.png", replace width(1000) height(700)
            graph export "$output/donut_es_`gender'_`outcome'.pdf", replace
            display "Created plot: donut_es_`gender'_`outcome'"
        }
    }
}

* Create comparison plots (original vs donut)
foreach gender in w m {
    local gender_label = cond("`gender'" == "w", "Women", "Men")
    
    foreach outcome in married divorced num_children {
        local outcome_label = cond("`outcome'" == "married", "Marriage", ///
                             cond("`outcome'" == "divorced", "Divorce", "Number of Children"))
        
        * Check if both estimates exist
        local orig_exists = 0
        local donut_exists = 0
        
        capture estimates describe orig_es_`gender'_`outcome'
        if _rc == 0 local orig_exists = 1
        
        capture estimates describe donut_es_`gender'_`outcome'
        if _rc == 0 local donut_exists = 1
        
        if `orig_exists' & `donut_exists' {
            * Original plot
            estimates restore orig_es_`gender'_`outcome'
            coefplot, ///
                keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
                vertical name(orig_`gender'_`outcome', replace) ///
                coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                          lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                          lead4_alt = "4" lead5plus_alt = "5+") ///
                yline(0, lcolor(red) lpattern(dash)) ///
                xline(2.5, lcolor(blue) lpattern(dash)) ///
                title("Original Sample") ///
                xtitle("Years Relative to Casino Opening") ///
                ytitle("Effect") ///
                graphregion(color(white)) plotregion(color(white))
            
            * Donut plot
            estimates restore donut_es_`gender'_`outcome'
            coefplot, ///
                keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
                vertical name(donut_`gender'_`outcome', replace) ///
                coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                          lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                          lead4_alt = "4" lead5plus_alt = "5+") ///
                yline(0, lcolor(red) lpattern(dash)) ///
                xline(2.5, lcolor(blue) lpattern(dash)) ///
                title("Donut Sample") ///
                xtitle("Years Relative to Casino Opening") ///
                ytitle("Effect") ///
                graphregion(color(white)) plotregion(color(white))
            
            * Combine
            graph combine orig_`gender'_`outcome' donut_`gender'_`outcome', ///
                title("Event Study Comparison: `outcome_label' - `gender_label'") ///
                subtitle("Original vs. Donut Sample") ///
                graphregion(color(white)) plotregion(color(white)) ///
                note("Note: Donut sample excludes nearby counties")
                
            graph export "$output/comparison_es_`gender'_`outcome'.png", replace width(1400) height(700)
            graph export "$output/comparison_es_`gender'_`outcome'.pdf", replace
            display "Created comparison: `gender'_`outcome'"
        }
    }
}

* Create combined figures by gender
foreach gender in w m {
    local gender_label = cond("`gender'" == "w", "Women", "Men")
    
    * Check which plots exist for this gender
    local plot_list ""
    foreach outcome in married divorced num_children {
        capture confirm existence donut_`gender'_`outcome'
        if _rc == 0 {
            local plot_list "`plot_list' donut_`gender'_`outcome'"
        }
    }
    
    if "`plot_list'" != "" {
        graph combine `plot_list', ///
            title("Event Studies (Donut Sample): `gender_label''s Outcomes") ///
            subtitle("Marriage, Divorce, and Fertility Effects") ///
            graphregion(color(white)) plotregion(color(white)) ///
            note("Note: Donut sample excludes nearby counties")
            
        graph export "$output/donut_combined_`gender'.png", replace width(1800) height(600)
        graph export "$output/donut_combined_`gender'.pdf", replace
        display "Created combined donut plot for `gender_label'"
    }
}

/*==============================================================================
SUMMARY MATRIX OF KEY RESULTS
==============================================================================*/

display ""
display "=== SUMMARY OF KEY RESULTS ACROSS SPECIFICATIONS ==="

matrix results = J(6, 4, .)
matrix colnames results = "Original" "Donut" "Spillover_Direct" "Spillover_Nearby"
matrix rownames results = "Women_Married" "Women_Divorced" "Women_Fertility" ///
                         "Men_Married" "Men_Divorced" "Men_Fertility"

* Fill in the matrix
local row = 1
foreach gender_name in "Women" "Men" {
    local gender_cond = cond("`gender_name'" == "Women", "female == 1", "female == 0")
    
    foreach outcome in married divorced num_children {
        * Original specification
        capture reghdfe `outcome' post_treatment age age_sq ///
            if `gender_cond' [aw=perwt], absorb(county_id year) vce(cluster county_id)
        if _rc == 0 {
            matrix results[`row', 1] = _b[post_treatment]
        }
        
        * Donut specification
        capture reghdfe `outcome' post_treatment age age_sq ///
            if `gender_cond' & donut_sample == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
        if _rc == 0 {
            matrix results[`row', 2] = _b[post_treatment]
        }
        
        * Spillover specification
        capture reghdfe `outcome' casino_post nearby_post age age_sq ///
            if `gender_cond' [aw=perwt], absorb(county_id year) vce(cluster county_id)
        if _rc == 0 {
            matrix results[`row', 3] = _b[casino_post]
            matrix results[`row', 4] = _b[nearby_post]
        }
        
        local row = `row' + 1
    }
}

* Export results matrix
esttab matrix(results, fmt(%6.3f)) using "$output/summary_results.tex", replace ///
    title("Summary of Effects on Marriage, Divorce, and Fertility") ///
    addnotes("Notes: Original and Donut columns show coefficients on post-treatment indicator." ///
             "Spillover columns show coefficients on casino_post and nearby_post." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level.")

* Display results in log
matlist results, format(%9.4f) title("Summary Results Matrix")

/*==============================================================================
SAMPLE COMPOSITION OUTPUT
==============================================================================*/

display ""
display "=== SAMPLE COMPOSITION ==="

eststo clear

* Original sample - treated counties
estpost summarize married divorced has_children num_children ///
                 female age white black hispanic ///
                 if casino_county == 1
eststo orig_treated

* Original sample - control counties
estpost summarize married divorced has_children num_children ///
                 female age white black hispanic ///
                 if casino_county == 0
eststo orig_control

* Donut sample - treated counties
estpost summarize married divorced has_children num_children ///
                 female age white black hispanic ///
                 if casino_county == 1 & donut_sample == 1
eststo donut_treated

* Donut sample - control counties
estpost summarize married divorced has_children num_children ///
                 female age white black hispanic ///
                 if casino_county == 0 & donut_sample == 1
eststo donut_control

* Export sample composition table
esttab orig_treated orig_control donut_treated donut_control ///
    using "$output/sample_composition.tex", replace ///
    cells("mean(fmt(3)) sd(fmt(3))") ///
    mtitles("Orig: Treated" "Orig: Control" "Donut: Treated" "Donut: Control") ///
    title("Sample Composition: Original vs. Donut Design") ///
    addnotes("Note: Treated = casino counties; Control = non-casino counties." ///
            "Donut sample excludes nearby counties.")

/*==============================================================================
ADDITIONAL ROBUSTNESS CHECKS
==============================================================================*/

display ""
display "=== ROBUSTNESS CHECKS ==="

* Check pre-trends in donut sample
display "Pre-trend tests in donut sample:"

foreach outcome in married divorced num_children {
    foreach gender in 1 0 {
        local gender_name = cond(`gender' == 1, "Women", "Men")
        
        display ""
        display "Testing pre-trends for `outcome' - `gender_name' (Donut Sample)"
        
        quietly reghdfe `outcome' ///
            lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
            age age_sq if female == `gender' & donut_sample == 1 [aw=perwt], ///
            absorb(county_id year) vce(cluster county_id)
        
        test lag3_alt = lag2_alt = 0
        local p_pretrend = r(p)
        di "   Joint test of pre-trends: p = " %6.4f `p_pretrend'
    }
}

* Check balance of covariates at baseline
display ""
display "Balance tests at baseline (t=-1):"

preserve
keep if rel_time == -1
* Check if we have both treated and control units at baseline
count if casino_county == 1
local n_treated = r(N)
count if casino_county == 0
local n_control = r(N)

if `n_treated' > 0 & `n_control' > 0 {
    foreach var in age white black hispanic {
        ttest `var' if female == 1, by(casino_county)
        ttest `var' if female == 0, by(casino_county)
    }
}
else {
    display "Cannot perform balance tests - insufficient variation in treatment at t=-1"
}
restore

/*==============================================================================
FINAL SUMMARY AND DIAGNOSTICS
==============================================================================*/

display ""
display "=== ANALYSIS COMPLETE ==="
display ""
display "Files created:"
display "  - spillover_women.tex"
display "  - spillover_men.tex"
display "  - donut_women_marriage_divorce.tex"
display "  - donut_women_fertility.tex"
display "  - donut_men_marriage_divorce.tex"
display "  - donut_men_fertility.tex"
display "  - summary_results.tex"
display "  - sample_composition.tex"
display ""
display "Event study plots created:"
display "  - Individual donut plots: donut_es_[gender]_[outcome].png/pdf"
display "  - Comparison plots: comparison_es_[gender]_[outcome].png/pdf"
display "  - Combined plots: donut_combined_[gender].png/pdf"
display ""



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
SUMMARY STATISTICS BY AGE GROUP
==============================================================================*/

display ""
display "=== SUMMARY STATISTICS BY AGE GROUP (DONUT SAMPLE) ==="

eststo clear

* Young women (18-30)
estpost summarize married divorced has_children num_children ///
    if female == 1 & young == 1 & donut_sample == 1
eststo young_women_stats

* Older women (31-40)
estpost summarize married divorced has_children num_children ///
    if female == 1 & older == 1 & donut_sample == 1
eststo older_women_stats

* Young men (18-30)
estpost summarize married divorced has_children num_children ///
    if female == 0 & young == 1 & donut_sample == 1
eststo young_men_stats

* Older men (31-40)
estpost summarize married divorced has_children num_children ///
    if female == 0 & older == 1 & donut_sample == 1
eststo older_men_stats

* Export summary statistics
esttab young_women_stats older_women_stats young_men_stats older_men_stats ///
    using "$output/age_group_summary_stats.tex", replace ///
    cells("mean(fmt(3)) sd(fmt(3))") ///
    mtitles("Women 18-30" "Women 31-40" "Men 18-30" "Men 31-40") ///
    title("Summary Statistics by Age Group (Donut Sample)") ///
    addnotes("Note: Statistics for donut sample (excludes nearby counties).")

/*==============================================================================
MAIN EFFECTS BY AGE GROUP - WOMEN
==============================================================================*/

display ""
display "=== DONUT DESIGN BY AGE GROUP - WOMEN ==="

eststo clear

* Young women (18-30)
foreach outcome in married divorced has_children num_children {
    eststo yw_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 1 & young == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
}

* Older women (31-40)
foreach outcome in married divorced has_children num_children {
    eststo ow_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 1 & older == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
}

* Export results for women
esttab yw_married ow_married yw_divorced ow_divorced ///
    using "$output/age_hetero_women_marriage_divorce.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Young: Marriage" "Older: Marriage" "Young: Divorce" "Older: Divorce") ///
    title("Age Heterogeneity (Donut): Women's Marriage and Divorce") ///
    addnotes("Notes: Young = 18-30, Older = 31-40. Donut sample excludes nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab yw_has_children ow_has_children yw_num_children ow_num_children ///
    using "$output/age_hetero_women_fertility.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Young: Has Child" "Older: Has Child" "Young: Num Child" "Older: Num Child") ///
    title("Age Heterogeneity (Donut): Women's Fertility") ///
    addnotes("Notes: Young = 18-30, Older = 31-40. Donut sample excludes nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
MAIN EFFECTS BY AGE GROUP - MEN
==============================================================================*/

display ""
display "=== DONUT DESIGN BY AGE GROUP - MEN ==="

eststo clear

* Young men (18-30)
foreach outcome in married divorced has_children num_children {
    eststo ym_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 0 & young == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
}

* Older men (31-40)
foreach outcome in married divorced has_children num_children {
    eststo om_`outcome': reghdfe `outcome' post_treatment age age_sq ///
        if female == 0 & older == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
}

* Export results for men
esttab ym_married om_married ym_divorced om_divorced ///
    using "$output/age_hetero_men_marriage_divorce.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Young: Marriage" "Older: Marriage" "Young: Divorce" "Older: Divorce") ///
    title("Age Heterogeneity (Donut): Men's Marriage and Divorce") ///
    addnotes("Notes: Young = 18-30, Older = 31-40. Donut sample excludes nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

esttab ym_has_children om_has_children ym_num_children om_num_children ///
    using "$output/age_hetero_men_fertility.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Young: Has Child" "Older: Has Child" "Young: Num Child" "Older: Num Child") ///
    title("Age Heterogeneity (Donut): Men's Fertility") ///
    addnotes("Notes: Young = 18-30, Older = 31-40. Donut sample excludes nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
INTERACTION MODEL - TEST FOR SIGNIFICANT DIFFERENCES
==============================================================================*/

display ""
display "=== TESTING AGE GROUP DIFFERENCES ==="

* Women
foreach outcome in married divorced has_children num_children {
    display ""
    display "Testing age differences for women's `outcome':"
    
    reghdfe `outcome' post_treatment young_post age age_sq ///
        if female == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    test young_post = 0
    local p_diff = r(p)
    display "   Differential effect for young women: p = " %6.4f `p_diff'
}

* Men
foreach outcome in married divorced has_children num_children {
    display ""
    display "Testing age differences for men's `outcome':"
    
    reghdfe `outcome' post_treatment young_post age age_sq ///
        if female == 0 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    test young_post = 0
    local p_diff = r(p)
    display "   Differential effect for young men: p = " %6.4f `p_diff'
}

/*==============================================================================
EVENT STUDIES BY AGE GROUP
==============================================================================*/

display ""
display "=== EVENT STUDIES BY AGE GROUP ==="

* Women - Young (18-30)
foreach outcome in married divorced num_children {
    display "Running young women's `outcome' event study..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 1 & young == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo age_es_yw_`outcome'
        estimates save "$output/age_es_yw_`outcome'", replace
        display "Saved: age_es_yw_`outcome'"
    }
}

* Women - Older (31-40)
foreach outcome in married divorced num_children {
    display "Running older women's `outcome' event study..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 1 & older == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo age_es_ow_`outcome'
        estimates save "$output/age_es_ow_`outcome'", replace
        display "Saved: age_es_ow_`outcome'"
    }
}

* Men - Young (18-30)
foreach outcome in married divorced num_children {
    display "Running young men's `outcome' event study..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 0 & young == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo age_es_ym_`outcome'
        estimates save "$output/age_es_ym_`outcome'", replace
        display "Saved: age_es_ym_`outcome'"
    }
}

* Men - Older (31-40)
foreach outcome in married divorced num_children {
    display "Running older men's `outcome' event study..."
    
    capture reghdfe `outcome' ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == 0 & older == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
        
    if _rc == 0 {
        eststo age_es_om_`outcome'
        estimates save "$output/age_es_om_`outcome'", replace
        display "Saved: age_es_om_`outcome'"
    }
}

/*==============================================================================
CREATE AGE-SPECIFIC EVENT STUDY PLOTS
==============================================================================*/

display ""
display "=== CREATING AGE-SPECIFIC EVENT STUDY PLOTS ==="

* Load saved estimates
local age_groups "yw ow ym om"
local age_labels `" "Young Women" "Older Women" "Young Men" "Older Men" "'
local outcomes "married divorced num_children"

foreach ag in `age_groups' {
    foreach outcome in `outcomes' {
        capture confirm file "$output/age_es_`ag'_`outcome'.ster"
        if _rc == 0 {
            capture estimates use "$output/age_es_`ag'_`outcome'"
            if _rc == 0 {
                estimates store age_es_`ag'_`outcome'
                display "Loaded: age_es_`ag'_`outcome'"
            }
        }
    }
}

* Create comparison plots by outcome and gender
foreach gender in w m {
    local gender_label = cond("`gender'" == "w", "Women", "Men")
    
    foreach outcome in married divorced num_children {
        local outcome_label = cond("`outcome'" == "married", "Marriage", ///
                             cond("`outcome'" == "divorced", "Divorce", "Number of Children"))
        
        * Check if both age group estimates exist
        local young_exists = 0
        local older_exists = 0
        
        capture estimates describe age_es_y`gender'_`outcome'
        if _rc == 0 local young_exists = 1
        
        capture estimates describe age_es_o`gender'_`outcome'
        if _rc == 0 local older_exists = 1
        
        if `young_exists' & `older_exists' {
            * Young plot
            estimates restore age_es_y`gender'_`outcome'
            coefplot, ///
                keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
                vertical name(young_`gender'_`outcome', replace) ///
                coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                          lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                          lead4_alt = "4" lead5plus_alt = "5+") ///
                yline(0, lcolor(red) lpattern(dash)) ///
                xline(2.5, lcolor(blue) lpattern(dash)) ///
                title("Ages 18-30") ///
                xtitle("Years Relative to Casino Opening") ///
                ytitle("Effect") ///
                graphregion(color(white)) plotregion(color(white))
            
            * Older plot
            estimates restore age_es_o`gender'_`outcome'
            coefplot, ///
                keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
                vertical name(older_`gender'_`outcome', replace) ///
                coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                          lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                          lead4_alt = "4" lead5plus_alt = "5+") ///
                yline(0, lcolor(red) lpattern(dash)) ///
                xline(2.5, lcolor(blue) lpattern(dash)) ///
                title("Ages 31-40") ///
                xtitle("Years Relative to Casino Opening") ///
                ytitle("Effect") ///
                graphregion(color(white)) plotregion(color(white))
            
            * Combine
            graph combine young_`gender'_`outcome' older_`gender'_`outcome', ///
                title("Age Heterogeneity: `outcome_label' - `gender_label'") ///
                subtitle("Donut Sample Event Studies by Age Group") ///
                graphregion(color(white)) plotregion(color(white)) ///
                note("Note: Donut sample excludes nearby counties")
                
            graph export "$output/age_hetero_es_`gender'_`outcome'.png", replace width(1400) height(700)
            graph export "$output/age_hetero_es_`gender'_`outcome'.pdf", replace
            display "Created age comparison: `gender'_`outcome'"
        }
    }
}

* Create combined plots showing all outcomes for each age-gender group
foreach gender in w m {
    local gender_label = cond("`gender'" == "w", "Women", "Men")
    
    * Young plots
    local young_plots ""
    foreach outcome in married divorced num_children {
        capture confirm existence young_`gender'_`outcome'
        if _rc == 0 {
            local young_plots "`young_plots' young_`gender'_`outcome'"
        }
    }
    
    if "`young_plots'" != "" {
        graph combine `young_plots', ///
            title("Event Studies: Young (18-30) `gender_label'") ///
            subtitle("Marriage, Divorce, and Fertility Effects") ///
            graphregion(color(white)) plotregion(color(white)) ///
            note("Note: Donut sample excludes nearby counties") ///
            cols(3)
            
        graph export "$output/age_all_outcomes_y`gender'.png", replace width(1800) height(600)
        graph export "$output/age_all_outcomes_y`gender'.pdf", replace
        display "Created combined plot for Young `gender_label'"
    }
    
    * Older plots
    local older_plots ""
    foreach outcome in married divorced num_children {
        capture confirm existence older_`gender'_`outcome'
        if _rc == 0 {
            local older_plots "`older_plots' older_`gender'_`outcome'"
        }
    }
    
    if "`older_plots'" != "" {
        graph combine `older_plots', ///
            title("Event Studies: Older (31-40) `gender_label'") ///
            subtitle("Marriage, Divorce, and Fertility Effects") ///
            graphregion(color(white)) plotregion(color(white)) ///
            note("Note: Donut sample excludes nearby counties") ///
            cols(3)
            
        graph export "$output/age_all_outcomes_o`gender'.png", replace width(1800) height(600)
        graph export "$output/age_all_outcomes_o`gender'.pdf", replace
        display "Created combined plot for Older `gender_label'"
    }
}

/*==============================================================================
SUMMARY MATRIX OF AGE HETEROGENEITY RESULTS
==============================================================================*/

display ""
display "=== SUMMARY OF AGE HETEROGENEITY RESULTS ==="

matrix age_results = J(6, 4, .)
matrix colnames age_results = "Women_Young" "Women_Older" "Men_Young" "Men_Older"
matrix rownames age_results = "Marriage" "Divorce" "Has_Children" ///
                             "Num_Children" "N_Young" "N_Older"

* Fill in the matrix
local col = 1
foreach gender in 1 0 {
    foreach age in young older {
        local row = 1
        foreach outcome in married divorced has_children num_children {
            quietly reghdfe `outcome' post_treatment age age_sq ///
                if female == `gender' & `age' == 1 & donut_sample == 1 [aw=perwt], ///
                absorb(county_id year) vce(cluster county_id)
            if _rc == 0 {
                matrix age_results[`row', `col'] = _b[post_treatment]
            }
            local row = `row' + 1
        }
        
        * Add sample sizes
        quietly count if female == `gender' & `age' == 1 & donut_sample == 1
        matrix age_results[5, `col'] = r(N)
        
        local col = `col' + 1
    }
}

* Export age heterogeneity matrix
esttab matrix(age_results, fmt(%6.3f)) using "$output/age_heterogeneity_summary.tex", replace ///
    title("Summary of Age Heterogeneity Effects (Donut Sample)") ///
    addnotes("Notes: Effects of casino opening on outcomes by age group." ///
             "Young = 18-30, Older = 31-40. Donut sample excludes nearby counties." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level.")

* Display results in log
matlist age_results, format(%9.4f) title("Age Heterogeneity Results Matrix")

/*==============================================================================
SAVE LOG OF AGE HETEROGENEITY ANALYSIS
==============================================================================*/

display ""
display "=== AGE HETEROGENEITY ANALYSIS COMPLETE ==="
display "Results saved to: $output"


/*==============================================================================
MECHANISM ANALYSIS: MIGRATION AND SELECTION EFFECTS
==============================================================================*/

display ""
display "=============================================================="
display "=== MECHANISM ANALYSIS: MIGRATION VS. BEHAVIORAL CHANGE ==="
display "=============================================================="

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

/*==============================================================================
APPROACH 1: COMPOSITIONAL CHANGE ANALYSIS
Test if casino counties attract different types of people
==============================================================================*/

display ""
display "=== APPROACH 1: COMPOSITIONAL CHANGE ==="
display "Testing if casinos change population composition"

eststo clear

* Test if treatment affects probability of being a recent mover
eststo comp1: reghdfe mover post_treatment age age_sq ///
    if female == 1 & donut_sample == 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
    
eststo comp2: reghdfe mover post_treatment age age_sq ///
    if female == 0 & donut_sample == 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)

* Test if movers have different characteristics
preserve
keep if donut_sample == 1
collapse (mean) married divorced has_children num_children age ///
    white black hispanic ///
    [aw=perwt], by(county_id year mover casino_county)

* Test if mover characteristics differ in treated vs control counties
gen mover_treated = mover * casino_county
reghdfe has_children mover casino_county mover_treated, ///
    absorb(year) vce(cluster county_id)
eststo comp3

reghdfe num_children mover casino_county mover_treated, ///
    absorb(year) vce(cluster county_id)
eststo comp4
restore

esttab comp1 comp2 comp3 comp4 using "$output/mechanism_composition.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Women: Pr(Mover)" "Men: Pr(Mover)" "Has Children" "Num Children") ///
    title("Compositional Change: Do Casinos Attract Different People?") ///
    addnotes("Notes: Tests whether casinos change population composition." ///
             "Columns 1-2 test if treatment affects migration probability." ///
             "Columns 3-4 test if movers have different fertility in treated counties.")

/*==============================================================================
APPROACH 2: HETEROGENEOUS TREATMENT EFFECTS BY MIGRATION STATUS
Test if effects differ for movers vs stayers
==============================================================================*/

display ""
display "=== APPROACH 2: HETEROGENEOUS EFFECTS BY MIGRATION STATUS ==="

eststo clear

* Women - with triple interaction
foreach outcome in married divorced has_children num_children {
    eststo w_het_`outcome': reghdfe `outcome' ///
        post_treatment stayer stayer_post age age_sq ///
        if female == 1 & donut_sample == 1 & !missing(stayer) [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
}

esttab w_het_* using "$output/mechanism_hetero_women.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment stayer_post) ///
    mtitles("Marriage" "Divorce" "Has Children" "Num Children") ///
    title("Heterogeneous Effects by Migration Status: Women") ///
    addnotes("Notes: post_treatment = effect for movers, stayer_post = additional effect for stayers." ///
             "Total effect for stayers = post_treatment + stayer_post." ///
             "Donut sample, includes county and year FE.")

* Men - with triple interaction
eststo clear
foreach outcome in married divorced has_children num_children {
    eststo m_het_`outcome': reghdfe `outcome' ///
        post_treatment stayer stayer_post age age_sq ///
        if female == 0 & donut_sample == 1 & !missing(stayer) [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
}

esttab m_het_* using "$output/mechanism_hetero_men.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment stayer_post) ///
    mtitles("Marriage" "Divorce" "Has Children" "Num Children") ///
    title("Heterogeneous Effects by Migration Status: Men") ///
    addnotes("Notes: post_treatment = effect for movers, stayer_post = additional effect for stayers." ///
             "Total effect for stayers = post_treatment + stayer_post." ///
             "Donut sample, includes county and year FE.")

/*==============================================================================
APPROACH 3: TIMING ANALYSIS
Recent movers vs. longer-term residents
==============================================================================*/

display ""
display "=== APPROACH 3: TIMING OF EFFECTS ==="
display "Do effects appear immediately (selection) or with delay (behavioral)?"

* Create event-time specific migration interactions
forvalues t = 0/5 {
  cap  gen stayer_lead`t' = stayer * lead`t'_alt if !missing(stayer)
}

cap  gen stayer_lead5 = stayer * lead5plus_alt if !missing(stayer)

* Run event study with migration interactions
eststo clear

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "women", "men")
    
    reghdfe num_children lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        stayer stayer_lead0 stayer_lead1 stayer_lead2 stayer_lead3 stayer_lead4 stayer_lead5 ///
        lag3_alt lag2_alt age age_sq ///
        if female == `gender' & donut_sample == 1 & !missing(stayer) [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    eststo timing_`gname'
}

esttab timing_* using "$output/mechanism_timing.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(lead0_alt lead1_alt lead2_alt stayer_lead0 stayer_lead1 stayer_lead2) ///
    mtitles("Women" "Men") ///
    title("Timing of Effects: Immediate (Selection) vs. Delayed (Behavioral)") ///
    addnotes("Notes: lead0-2 show effects for movers, stayer_lead0-2 show additional effects for stayers." ///
             "Immediate effects suggest selection, delayed effects suggest behavioral change.")

/*==============================================================================
APPROACH 4: PRE-TREATMENT POPULATION CHARACTERISTICS
Test if population characteristics change before casino opening
==============================================================================*/

display ""
display "=== APPROACH 4: PRE-TREATMENT POPULATION CHANGES ==="

* Test if observable characteristics change in anticipation
preserve
keep if rel_time >= -5 & rel_time <= -1 & casino_county == 1
collapse (mean) age white black hispanic has_children num_children ///
    (sum) n=perwt [aw=perwt], by(county_id rel_time)

* Test for pre-trends in demographics
foreach var in age white black hispanic has_children num_children {
    reghdfe `var' rel_time, absorb(county_id) vce(cluster county_id)
    test rel_time = 0
    local p_`var' = r(p)
    display "Pre-trend in `var': p = " %6.4f `p_`var''
}
restore

/*==============================================================================
APPROACH 5: DECOMPOSITION ANALYSIS
Decompose total effect into composition and behavioral components
==============================================================================*/

display ""
display "=== APPROACH 5: DECOMPOSITION ANALYSIS ==="

* Step 1: Get baseline fertility rates by migration status
preserve
keep if year >= 2000 & year <= 2005 & casino_county == 0 & donut_sample == 1
collapse (mean) base_fert_stayer=num_children if stayer == 1 [aw=perwt], by(female)
tempfile base_stayer
save `base_stayer'
restore

preserve
keep if year >= 2000 & year <= 2005 & casino_county == 0 & donut_sample == 1
collapse (mean) base_fert_mover=num_children if mover == 1 [aw=perwt], by(female)
tempfile base_mover
save `base_mover'
restore

* Step 2: Get migration rates pre and post
preserve
keep if donut_sample == 1 & casino_county == 1
collapse (mean) mover_rate=mover [aw=perwt], by(female post_treatment)
reshape wide mover_rate, i(female) j(post_treatment)
gen delta_mover = mover_rate1 - mover_rate0
merge 1:1 female using `base_stayer', nogen
merge 1:1 female using `base_mover', nogen
gen composition_effect = delta_mover * (base_fert_mover - base_fert_stayer)
list female delta_mover base_fert_stayer base_fert_mover composition_effect
restore

/*==============================================================================
SUMMARY AND INTERPRETATION
==============================================================================*/

display ""
display "=== TESTING MECHANISMS: SUMMARY ==="

* Test if effects are stronger for stayers (behavioral) or movers (selection)
foreach outcome in has_children num_children {
    display ""
    display "Testing mechanism for `outcome':"
    
    * Women
    quietly reghdfe `outcome' post_treatment stayer stayer_post age age_sq ///
        if female == 1 & donut_sample == 1 & !missing(stayer) [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    test stayer_post = 0
    local p_diff_w = r(p)
    
    test post_treatment + stayer_post = 0
    local p_stayer_w = r(p)
    
    display "  Women - Differential effect for stayers: p = " %6.4f `p_diff_w'
    display "  Women - Total effect for stayers = 0: p = " %6.4f `p_stayer_w'
    
    * Men
    quietly reghdfe `outcome' post_treatment stayer stayer_post age age_sq ///
        if female == 0 & donut_sample == 1 & !missing(stayer) [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    test stayer_post = 0
    local p_diff_m = r(p)
    
    test post_treatment + stayer_post = 0
    local p_stayer_m = r(p)
    
    display "  Men - Differential effect for stayers: p = " %6.4f `p_diff_m'
    display "  Men - Total effect for stayers = 0: p = " %6.4f `p_stayer_m'
}

/*==============================================================================
CREATE MECHANISM PLOTS
==============================================================================*/

* Event study comparing movers vs stayers
foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    local glabel = cond(`gender' == 1, "Women", "Men")
    
    * Stayers only
    reghdfe num_children ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == `gender' & donut_sample == 1 & stayer == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store mech_stayers_`gname'
    
    * Movers only
    reghdfe num_children ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == `gender' & donut_sample == 1 & mover == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store mech_movers_`gname'
    
    * Create comparison plot
    coefplot (mech_stayers_`gname', label("Stayers")) ///
             (mech_movers_`gname', label("Movers")), ///
        keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
        vertical ///
        coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                  lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                  lead4_alt = "4" lead5plus_alt = "5+") ///
        yline(0, lcolor(gray) lpattern(dash)) ///
        xline(2.5, lcolor(gray) lpattern(dash)) ///
        title("Mechanism Test: Fertility Effects by Migration Status - `glabel'") ///
        xtitle("Years Relative to Casino Opening") ///
        ytitle("Effect on Number of Children") ///
        legend(row(1)) ///
        graphregion(color(white)) plotregion(color(white)) ///
        note("Note: Compares effects for recent movers vs. non-movers")
    
    graph export "$output/mechanism_migration_`gname'.png", replace width(1200) height(800)
    graph export "$output/mechanism_migration_`gname'.pdf", replace
}

********************************************************************************
* COMPREHENSIVE MECHANISM ANALYSIS - FIXED VERSION
* Key fixes:
* 1. Fixed event study variable creation to use rel_time_full consistently
* 2. Fixed population test to use proper time variable
* 3. Ensured proper sample restrictions throughout
********************************************************************************

********************************************************************************
* Data Setup
********************************************************************************

* Create indicator for ACS samples (exclude 2000 Census)
gen acs_sample = 1
replace acs_sample = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)

* Get movedin value from household head and apply to all household members
sort sample serial
by sample serial: egen movedin_hh = max(movedin)

* Create years since moved in based on movedin categories
gen years_in_residence = .
replace years_in_residence = 0.5 if movedin_hh == 1  // This year or last (0-12 months)
replace years_in_residence = 1.5 if movedin_hh == 2  // 13-23 months
replace years_in_residence = 3 if movedin_hh == 3    // 2-4 years
replace years_in_residence = 7 if movedin_hh == 4    // 5-9 years
replace years_in_residence = 14.5 if movedin_hh == 5 // 10-19 years
replace years_in_residence = 24.5 if movedin_hh == 6 // 20-29 years
replace years_in_residence = 35 if movedin_hh == 7   // 30+ years

* Calculate year moved in
gen year_moved_in = year - years_in_residence

* Define "long-term residents" as those who have been in their residence for 5+ years
gen longterm_resident = (movedin_hh >= 4) if !missing(movedin_hh)

* Define "very long-term residents" as those who have been in their residence for 10+ years
gen very_longterm = (movedin_hh >= 5) if !missing(movedin_hh)

********************************************************************************
* ORIGINAL 5-YEAR EVENT STUDY (Uses existing variables from main analysis)
********************************************************************************

display ""
display "=== ORIGINAL 5-YEAR MECHANISM ANALYSIS ==="

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    local glabel = cond(`gender' == 1, "Women", "Men")
    
    display "Running 5-year analysis for `glabel'..."
    
    * Long-term residents regression
    reghdfe num_children ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == `gender' & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    * Store results
    estimates store long_5yr_`gname'
    local n_long_5yr_`gname' = e(N)
    
    * Recent movers regression  
    reghdfe num_children ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == `gender' & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    * Store results
    estimates store recent_5yr_`gname'
    local n_recent_5yr_`gname' = e(N)
    
    display "  Long-term residents: `n_long_5yr_`gname'' observations"
    display "  Recent movers: `n_recent_5yr_`gname'' observations"
}

********************************************************************************
* EXTENDED 8-YEAR EVENT STUDY (Create new variables using rel_time_full)
********************************************************************************

display ""
display "=== CREATING EXTENDED 8-YEAR EVENT STUDY VARIABLES ==="

* CRITICAL FIX: Drop any existing extended variables to avoid conflicts
capture drop lag3_ext lag2_ext lead0_ext-lead7_ext lead8plus_ext

* Create extended event study variables using rel_time_full (same as original analysis)
* Pre-treatment periods (same as original)
forvalues j = 3(-1)2 {
    gen lag`j'_ext = 0
    replace lag`j'_ext = 1 if rel_time_full == -`j' & !missing(rel_time_full)
}

* Post-treatment periods (extended to 8+ years)
forvalues j = 0/7 {
    gen lead`j'_ext = 0  
    replace lead`j'_ext = 1 if rel_time_full == `j' & !missing(rel_time_full)
}

* 8+ years indicator
gen lead8plus_ext = 0
replace lead8plus_ext = 1 if rel_time_full >= 8 & !missing(rel_time_full)

display "Extended variables created using rel_time_full"

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    local glabel = cond(`gender' == 1, "Women", "Men")
    
    display "Running extended 8-year analysis for `glabel'..."
    
    * Extended event study for long-term residents
    reghdfe num_children ///
        lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
        age age_sq if female == `gender' & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store long_8yr_`gname'
    local n_long_8yr_`gname' = e(N)
    
    * Extended event study for recent movers
    reghdfe num_children ///
        lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
        age age_sq if female == `gender' & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store recent_8yr_`gname'
    local n_recent_8yr_`gname' = e(N)
    
    display "  Long-term residents (8yr): `n_long_8yr_`gname'' observations"
    display "  Recent movers (8yr): `n_recent_8yr_`gname'' observations"
    
    * Check if sample sizes match between 5-year and 8-year for overlapping periods
    if `n_long_5yr_`gname'' == `n_long_8yr_`gname'' {
        display "  ✓ Long-term resident sample sizes match!"
    }
    else {
        display "  ⚠ Sample size difference for long-term residents: " (`n_long_8yr_`gname'' - `n_long_5yr_`gname'')
    }
    
    if `n_recent_5yr_`gname'' == `n_recent_8yr_`gname'' {
        display "  ✓ Recent mover sample sizes match!"
    }
    else {
        display "  ⚠ Sample size difference for recent movers: " (`n_recent_8yr_`gname'' - `n_recent_5yr_`gname'')
    }
}

********************************************************************************
* CREATE PLOTS - ORIGINAL 5-YEAR VERSION
********************************************************************************

display ""
display "=== CREATING 5-YEAR MECHANISM PLOTS ==="

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    local glabel = cond(`gender' == 1, "Women", "Men")
    
    * Create comparison plot for 5-year analysis
    coefplot (long_5yr_`gname', ///
                ciopts(lcolor(navy) lwidth(medium)) ///
                mcolor(navy) msymbol(O) msize(medium) ///
                label("Long-term Residents (5+ years)")) ///
             (recent_5yr_`gname', ///
                ciopts(lcolor(maroon) lwidth(medium)) ///
                mcolor(maroon) msymbol(D) msize(medium) ///
                label("Recent Movers (<5 years)")), ///
        keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
        vertical ///
        coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                  lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                  lead4_alt = "4" lead5plus_alt = "5+", labsize(medium)) ///
        yline(0, lcolor(gray) lpattern(dash)) ///
        xline(2.5, lcolor(gray) lpattern(dash)) ///
        title("Mechanism Test: Fertility Effects by Residence Duration", ///
              size(medlarge) margin(medium) color(black)) ///
        subtitle("`glabel'", size(medium) margin(small) color(black)) ///
        xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
        ytitle("Effect on Number of Children", size(medium) margin(medium)) ///
        ylabel(, labsize(medium) format(%9.2f)) ///
        xlabel(, labsize(medium)) ///
        legend(position(6) rows(1) size(medium) ///
              region(lcolor(none) fcolor(none)) ///
              symxsize(5) keygap(2) rowgap(1)) ///
        note("Long-term: Lived in residence 5+ years. Recent: Lived in residence <5 years." ///
             "Donut sample excludes nearby counties", ///
             size(small) margin(small) position(7)) ///
        graphregion(color(white) margin(medium)) ///
        plotregion(color(white) margin(medium)) ///
        scheme(s1color)
    
    graph export "$output/mechanism_movedin_5yr_`gname'.png", replace width(1400) height(900)
    graph export "$output/mechanism_movedin_5yr_`gname'.pdf", replace
    
    display "Created 5-year mechanism plot for `glabel'"
}

********************************************************************************
* CREATE PLOTS - EXTENDED 8-YEAR VERSION  
********************************************************************************

display ""
display "=== CREATING 8-YEAR MECHANISM PLOTS ==="

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    local glabel = cond(`gender' == 1, "Women", "Men")
    
    * Create comparison plot for 8-year analysis
    coefplot (long_8yr_`gname', ///
                ciopts(lcolor(navy) lwidth(medium)) ///
                mcolor(navy) msymbol(O) msize(medium) ///
                label("Long-term Residents (5+ years)")) ///
             (recent_8yr_`gname', ///
                ciopts(lcolor(maroon) lwidth(medium)) ///
                mcolor(maroon) msymbol(D) msize(medium) ///
                label("Recent Movers (<5 years)")), ///
        keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
        vertical ///
        coeflabels(lag3_ext = "-3" lag2_ext = "-2" lead0_ext = "0" lead1_ext = "1" lead2_ext = "2" ///
                  lead3_ext = "3" lead4_ext = "4" lead5_ext = "5" lead6_ext = "6" ///
                  lead7_ext = "7" lead8plus_ext = "8+", labsize(medium)) ///
        yline(0, lcolor(gray) lpattern(dash)) ///
        xline(2.5, lcolor(gray) lpattern(dash)) ///
        title("Extended Mechanism Test: Fertility Effects by Residence Duration", ///
              size(medlarge) margin(medium) color(black)) ///
        subtitle("`glabel'", size(medium) margin(small) color(black)) ///
        xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
        ytitle("Effect on Number of Children", size(medium) margin(medium)) ///
        ylabel(, labsize(medium) format(%9.2f)) ///
        xlabel(, labsize(medium)) ///
        legend(position(6) rows(1) size(medium) ///
              region(lcolor(none) fcolor(none)) ///
              symxsize(5) keygap(2) rowgap(1)) ///
        note("Long-term: Lived in residence 5+ years. Recent: Lived in residence <5 years." ///
             "Extended to 8+ years post-casino. Donut sample excludes nearby counties", ///
             size(small) margin(small) position(7)) ///
        graphregion(color(white) margin(medium)) ///
        plotregion(color(white) margin(medium)) ///
        scheme(s1color)
    
    graph export "$output/mechanism_movedin_8yr_`gname'.png", replace width(1400) height(900)
    graph export "$output/mechanism_movedin_8yr_`gname'.pdf", replace
    
    display "Created 8-year mechanism plot for `glabel'"
}

********************************************************************************
* ROBUSTNESS: Very Long-term Residents (10+ years) - ORIGINAL 5-YEAR
********************************************************************************

display ""
display "=== ROBUSTNESS: VERY LONG-TERM RESIDENTS (5-YEAR) ==="

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    local glabel = cond(`gender' == 1, "Women", "Men")
    
    * Regression for very long-term residents only
    reghdfe num_children ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == `gender' & donut_sample == 1 & ///
        very_longterm == 1 & acs_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store verylongterm_5yr_`gname'
    
    * Regression for shorter-term residents
    reghdfe num_children ///
        lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
        age age_sq if female == `gender' & donut_sample == 1 & ///
        very_longterm == 0 & acs_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store shortterm_5yr_`gname'
    
    * Create comparison plot
    coefplot (verylongterm_5yr_`gname', ///
                ciopts(lcolor(navy) lwidth(medium)) ///
                mcolor(navy) msymbol(O) msize(medium) ///
                label("Very Long-term (10+ years)")) ///
             (shortterm_5yr_`gname', ///
                ciopts(lcolor(maroon) lwidth(medium)) ///
                mcolor(maroon) msymbol(D) msize(medium) ///
                label("Shorter-term (<10 years)")), ///
        keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
        vertical ///
        coeflabels(lag3_alt = "-3" lag2_alt = "-2" lead0_alt = "0" ///
                  lead1_alt = "1" lead2_alt = "2" lead3_alt = "3" ///
                  lead4_alt = "4" lead5plus_alt = "5+", labsize(medium)) ///
        yline(0, lcolor(gray) lpattern(dash)) ///
        xline(2.5, lcolor(gray) lpattern(dash)) ///
        title("Robustness: Very Long-term Residents (5-Year Analysis)", ///
              size(medlarge) margin(medium) color(black)) ///
        subtitle("`glabel'", size(medium) margin(small) color(black)) ///
        xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
        ytitle("Effect on Number of Children", size(medium) margin(medium)) ///
        ylabel(, labsize(medium) format(%9.2f)) ///
        xlabel(, labsize(medium)) ///
        legend(position(6) rows(1) size(medium) ///
              region(lcolor(none) fcolor(none)) ///
              symxsize(5) keygap(2) rowgap(1)) ///
        graphregion(color(white) margin(medium)) ///
        plotregion(color(white) margin(medium)) ///
        scheme(s1color)
    
    graph export "$output/mechanism_verylongterm_5yr_`gname'.png", replace width(1400) height(900)
    graph export "$output/mechanism_verylongterm_5yr_`gname'.pdf", replace
    
    display "Created 5-year robustness plot for `glabel'"
}

********************************************************************************
* ROBUSTNESS: Very Long-term Residents (10+ years) - EXTENDED 8-YEAR
********************************************************************************

display ""
display "=== ROBUSTNESS: VERY LONG-TERM RESIDENTS (8-YEAR) ==="

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    local glabel = cond(`gender' == 1, "Women", "Men")
    
    * Very long-term residents regression (EXTENDED)
    reghdfe num_children ///
        lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
        age age_sq if female == `gender' & donut_sample == 1 & acs_sample == 1 & very_longterm == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store verylongterm_8yr_`gname'
    
    * Shorter-term residents regression (EXTENDED)
    reghdfe num_children ///
        lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext ///
        age age_sq if female == `gender' & donut_sample == 1 & acs_sample == 1 & very_longterm == 0 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    
    estimates store shortterm_8yr_`gname'
    
    * Create extended comparison plot for very long-term residents
    coefplot (verylongterm_8yr_`gname', ///
                ciopts(lcolor(navy) lwidth(medium)) ///
                mcolor(navy) msymbol(O) msize(medium) ///
                label("Very Long-term (10+ years)")) ///
             (shortterm_8yr_`gname', ///
                ciopts(lcolor(maroon) lwidth(medium)) ///
                mcolor(maroon) msymbol(D) msize(medium) ///
                label("Shorter-term (<10 years)")), ///
        keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
        vertical ///
        coeflabels(lag3_ext = "-3" lag2_ext = "-2" lead0_ext = "0" lead1_ext = "1" lead2_ext = "2" ///
                  lead3_ext = "3" lead4_ext = "4" lead5_ext = "5" lead6_ext = "6" ///
                  lead7_ext = "7" lead8plus_ext = "8+", labsize(medium)) ///
        yline(0, lcolor(gray) lpattern(dash)) ///
        xline(2.5, lcolor(gray) lpattern(dash)) ///
        title("Extended Robustness: Very Long-term Residents (8-Year Analysis)", ///
              size(medlarge) margin(medium) color(black)) ///
        subtitle("`glabel'", size(medium) margin(small) color(black)) ///
        xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
        ytitle("Effect on Number of Children", size(medium) margin(medium)) ///
        ylabel(, labsize(medium) format(%9.2f)) ///
        xlabel(, labsize(medium)) ///
        legend(position(6) rows(1) size(medium) ///
              region(lcolor(none) fcolor(none)) ///
              symxsize(5) keygap(2) rowgap(1)) ///
        note("Extended to 8+ years post-casino. Donut sample excludes nearby counties", ///
             size(small) margin(small) position(7)) ///
        graphregion(color(white) margin(medium)) ///
        plotregion(color(white) margin(medium)) ///
        scheme(s1color)
    
    graph export "$output/mechanism_verylongterm_8yr_`gname'.png", replace width(1400) height(900)
    graph export "$output/mechanism_verylongterm_8yr_`gname'.pdf", replace
    
    display "Created 8-year robustness plot for `glabel'"
}

********************************************************************************
* POPULATION COMPOSITION TEST - FIXED
********************************************************************************

display ""
display "=== POPULATION COMPOSITION TEST ==="

* Create population test at county-year level
preserve

* First, create the population variables before collapsing
gen longterm_pop_temp = perwt if longterm_resident==1 & acs_sample==1
gen total_pop_temp = perwt if acs_sample==1

* Calculate population by residence type and county-year
collapse (sum) longterm_pop=longterm_pop_temp ///
         (sum) total_pop=total_pop_temp, ///
         by(county_id year casino_county rel_time_full donut_sample)

* Only keep counties with both populations measured
drop if missing(longterm_pop) | missing(total_pop) | total_pop == 0

* Calculate share of long-term residents
gen longterm_share = longterm_pop / total_pop

* Use rel_time_full for consistency with other analyses
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

* Event study for log long-term population
gen ln_longterm_pop = ln(longterm_pop)

reghdfe ln_longterm_pop ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)

estimates store pop_level

* Event study for long-term population share
reghdfe longterm_share ///
    lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, ///
    absorb(county_id year) vce(cluster county_id)

estimates store pop_share

* Create population composition plot
coefplot (pop_level, ///
            ciopts(lcolor(navy) lwidth(medium)) ///
            mcolor(navy) msymbol(O) msize(medium) ///
            label("Log Long-term Population")) ///
         (pop_share, ///
            ciopts(lcolor(maroon) lwidth(medium)) ///
            mcolor(maroon) msymbol(D) msize(medium) ///
            label("Long-term Population Share")), ///
    keep(lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    vertical ///
    coeflabels(lag3_pop = "-3" lag2_pop = "-2" lead0_pop = "0" lead1_pop = "1" lead2_pop = "2" ///
              lead3_pop = "3" lead4_pop = "4" lead5_pop = "5" lead6_pop = "6" ///
              lead7_pop = "7" lead8plus_pop = "8+", labsize(medium)) ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(2.5, lcolor(gray) lpattern(dash)) ///
    title("Population Composition Test: Long-term Residents", ///
          size(medlarge) margin(medium) color(black)) ///
    xtitle("Years Relative to Casino Opening", size(medium) margin(medium)) ///
    ytitle("Effect", size(medium) margin(medium)) ///
    ylabel(, labsize(medium) format(%9.3f)) ///
    xlabel(, labsize(medium)) ///
    legend(position(6) rows(1) size(medium) ///
          region(lcolor(none) fcolor(none)) ///
          symxsize(5) keygap(2) rowgap(1)) ///
    note("Tests whether casinos affect the size/composition of long-term resident population. " ///
         "Donut sample excludes nearby counties", ///
         size(small) margin(small) position(7)) ///
    graphregion(color(white) margin(medium)) ///
    plotregion(color(white) margin(medium)) ///
    scheme(s1color)

graph export "$output/population_composition_test.png", replace width(1400) height(900)
graph export "$output/population_composition_test.pdf", replace

restore

********************************************************************************
* Summary Statistics and Hypothesis Tests
********************************************************************************

display ""
display "=== SUMMARY STATISTICS BY RESIDENCE DURATION ==="

* Distribution of residence duration in treated counties
tab movedin_hh if casino_county == 1 & acs_sample == 1, missing
tab longterm_resident if casino_county == 1 & acs_sample == 1, missing

* Test for differences in average effects using interaction model
display ""
display "=== TESTING DIFFERENCES IN EFFECTS BY RESIDENCE DURATION ==="

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    
    * Run interaction model to test for differences
    reghdfe num_children ///
        post_treatment longterm_resident c.post_treatment#c.longterm_resident ///
        age age_sq if female == `gender' & donut_sample == 1 & acs_sample == 1 ///
        [aw=perwt], absorb(county_id year) vce(cluster county_id)
    
    local coef_recent = _b[post_treatment]
    local se_recent = _se[post_treatment]
    local coef_diff = _b[c.post_treatment#c.longterm_resident]
    local se_diff = _se[c.post_treatment#c.longterm_resident]
    local coef_long = `coef_recent' + `coef_diff'
    
    test c.post_treatment#c.longterm_resident = 0
    local p_diff = r(p)
    
    display ""
    display "`gname' - Recent movers effect: " %6.4f `coef_recent' " (SE: " %6.4f `se_recent' ")"
    display "`gname' - Long-term residents effect: " %6.4f `coef_long' " (calculated)"
    display "`gname' - Difference (Long-term - Recent): " %6.4f `coef_diff' " (SE: " %6.4f `se_diff' ")"
    display "`gname' - Difference significant at p = " %6.4f `p_diff'
}

* Export table comparing effects by residence duration
eststo clear

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    
    * Recent movers only
    eststo recent_`gname': reghdfe num_children post_treatment age age_sq ///
        if female == `gender' & donut_sample == 1 & longterm_resident == 0 & acs_sample == 1 ///
        [aw=perwt], absorb(county_id year) vce(cluster county_id)
        
    * Long-term residents only  
    eststo longterm_`gname': reghdfe num_children post_treatment age age_sq ///
        if female == `gender' & donut_sample == 1 & longterm_resident == 1 & acs_sample == 1 ///
        [aw=perwt], absorb(county_id year) vce(cluster county_id)
}

esttab recent_Women longterm_Women recent_Men longterm_Men ///
    using "$output/mechanism_dd_by_duration.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Women: Recent" "Women: Long-term" "Men: Recent" "Men: Long-term") ///
    title("Difference-in-Differences by Residence Duration") ///
    addnotes("Notes: Recent = <5 years in residence, Long-term = 5+ years in residence." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

********************************************************************************
* COEFFICIENT COMPARISON BETWEEN 5-YEAR AND 8-YEAR ANALYSES
********************************************************************************

display ""
display "=== COMPARING 5-YEAR vs 8-YEAR COEFFICIENTS FOR OVERLAPPING PERIODS ==="

* Create comparison table for overlapping periods (lag3 through lead4)
foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    
    display ""
    display "=== Coefficient Comparison for `gname' - Long-term Residents ==="
    display "Period    5-Year     8-Year     Difference"
    display "--------------------------------------------"
    
    estimates restore long_5yr_`gname'
    matrix coef_5yr = e(b)
    matrix se_5yr = e(V)
    
    estimates restore long_8yr_`gname'
    matrix coef_8yr = e(b)
    matrix se_8yr = e(V)
    
    * Compare overlapping coefficients
    local vars "lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt"
    local vars_ext "lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext"
    local periods "-3 -2 0 1 2 3 4"
    
    local i = 1
    foreach var5 in `vars' {
        local var8 : word `i' of `vars_ext'
        local period : word `i' of `periods'
        
        * Get coefficients
        local coef5 = coef_5yr[1, colnumb(coef_5yr, "`var5'")]
        local coef8 = coef_8yr[1, colnumb(coef_8yr, "`var8'")]
        local diff = `coef8' - `coef5'
        
        display %6s "`period'" %10.4f `coef5' %10.4f `coef8' %10.4f `diff'
        
        local i = `i' + 1
    }
    
    display ""
    display "=== Coefficient Comparison for `gname' - Recent Movers ==="
    display "Period    5-Year     8-Year     Difference"
    display "--------------------------------------------"
    
    estimates restore recent_5yr_`gname'
    matrix coef_5yr = e(b)
    
    estimates restore recent_8yr_`gname'
    matrix coef_8yr = e(b)
    
    local i = 1
    foreach var5 in `vars' {
        local var8 : word `i' of `vars_ext'
        local period : word `i' of `periods'
        
        * Get coefficients
        local coef5 = coef_5yr[1, colnumb(coef_5yr, "`var5'")]
        local coef8 = coef_8yr[1, colnumb(coef_8yr, "`var8'")]
        local diff = `coef8' - `coef5'
        
        display %6s "`period'" %10.4f `coef5' %10.4f `coef8' %10.4f `diff'
        
        local i = `i' + 1
    }
}

********************************************************************************
* SAMPLE SIZE DIAGNOSTIC
********************************************************************************

display ""
display "=== FINAL SAMPLE SIZE DIAGNOSTIC ==="

foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    
    display ""
    display "Sample sizes for `gname':"
    
    * Check if the locals exist and have values
    if "`n_long_5yr_`gname''" != "" {
        display "  5-Year Analysis:"
        display "    Long-term residents: `n_long_5yr_`gname''"
        display "    Recent movers: `n_recent_5yr_`gname''"
    }
    else {
        display "  5-Year Analysis: Sample sizes not available (regressions may have failed)"
    }
    
    if "`n_long_8yr_`gname''" != "" {
        display "  8-Year Analysis:"
        display "    Long-term residents: `n_long_8yr_`gname''"
        display "    Recent movers: `n_recent_8yr_`gname''"
    }
    else {
        display "  8-Year Analysis: Sample sizes not available (regressions may have failed)"
    }
    
    * Only calculate differences if both sets of locals exist
    if "`n_long_5yr_`gname''" != "" & "`n_long_8yr_`gname''" != "" {
        * Calculate differences
        local diff_long = `n_long_8yr_`gname'' - `n_long_5yr_`gname''
        local diff_recent = `n_recent_8yr_`gname'' - `n_recent_5yr_`gname''
        
        display "  Differences (8yr - 5yr):"
        display "    Long-term residents: `diff_long'"
        display "    Recent movers: `diff_recent'"
        
        if `diff_long' == 0 & `diff_recent' == 0 {
            display "    ✓ Perfect match - Extended analysis uses same sample!"
        }
        else if abs(`diff_long') < 100 & abs(`diff_recent') < 100 {
            display "    ≈ Very close match - Minor differences acceptable"
        }
        else {
            display "    ⚠ Significant differences - May need investigation"
        }
    }
    else {
        display "  Cannot calculate differences - missing sample size information"
        
        * Try to get current sample sizes directly from data
        display "  Checking current data for sample sizes..."
        
        quietly count if female == `gender' & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & !missing(num_children)
        display "    Current long-term residents available: " r(N)
        
        quietly count if female == `gender' & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & !missing(num_children)
        display "    Current recent movers available: " r(N)
    }
}

********************************************************************************
* EXPORT RESULTS TABLES
********************************************************************************

display ""
display "=== EXPORTING RESULTS TABLES ==="

* Export 5-year event study results
eststo clear
foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    estimates restore long_5yr_`gname'
    eststo long5_`gname'
    estimates restore recent_5yr_`gname'
    eststo recent5_`gname'
}

esttab long5_Women recent5_Women long5_Men recent5_Men ///
    using "$output/mechanism_event_study_5yr.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
    mtitles("Women: Long-term" "Women: Recent" "Men: Long-term" "Men: Recent") ///
    title("Event Study Results by Residence Duration (5-Year Analysis)") ///
    addnotes("Notes: Long-term = 5+ years in residence, Recent = <5 years in residence." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

* Export 8-year event study results  
eststo clear
foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    estimates restore long_8yr_`gname'
    eststo long8_`gname'
    estimates restore recent_8yr_`gname'
    eststo recent8_`gname'
}

esttab long8_Women recent8_Women long8_Men recent8_Men ///
    using "$output/mechanism_event_study_8yr.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(lag3_ext lag2_ext lead0_ext lead1_ext lead2_ext lead3_ext lead4_ext lead5_ext lead6_ext lead7_ext lead8plus_ext) ///
    mtitles("Women: Long-term" "Women: Recent" "Men: Long-term" "Men: Recent") ///
    title("Event Study Results by Residence Duration (8-Year Analysis)") ///
    addnotes("Notes: Long-term = 5+ years in residence, Recent = <5 years in residence." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

* Export robustness results (very long-term)
eststo clear
foreach gender in 1 0 {
    local gname = cond(`gender' == 1, "Women", "Men")
    estimates restore verylongterm_5yr_`gname'
    eststo vlong5_`gname'
    estimates restore verylongterm_8yr_`gname'
    eststo vlong8_`gname'
}

esttab vlong5_Women vlong8_Women vlong5_Men vlong8_Men ///
    using "$output/mechanism_robustness_verylongterm.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(*lag3* *lag2* *lead0* *lead1* *lead2* *lead3* *lead4*) ///
    mtitles("Women: 5yr" "Women: 8yr" "Men: 5yr" "Men: 8yr") ///
    title("Robustness: Very Long-term Residents (10+ years)") ///
    addnotes("Notes: Results for individuals living in residence 10+ years." ///
             "5yr uses periods -3 to 5+, 8yr uses periods -3 to 8+." ///
             "All regressions include county and year fixed effects, age and age squared." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

********************************************************************************
* FINAL SUMMARY AND COMPLETION MESSAGE
********************************************************************************

display ""
display "================================================================================"
display "=== COMPREHENSIVE MECHANISM ANALYSIS COMPLETE ==="
display "================================================================================"
display ""
display "KEY FIXES IMPLEMENTED:"
display "✓ Extended event study variables created using rel_time_full (consistent with original)"
display "✓ Sample size verification between 5-year and 8-year analyses"
display "✓ Population composition test uses proper time variable"
display "✓ All plots use consistent formatting and labeling"
display "✓ Robustness checks with very long-term residents (10+ years)"
display ""
display "FILES CREATED:"
display "• Plots:"
display "  - mechanism_movedin_5yr_Women.png/pdf"
display "  - mechanism_movedin_5yr_Men.png/pdf"
display "  - mechanism_movedin_8yr_Women.png/pdf"
display "  - mechanism_movedin_8yr_Men.png/pdf"
display "  - mechanism_verylongterm_5yr_Women.png/pdf"
display "  - mechanism_verylongterm_5yr_Men.png/pdf"
display "  - mechanism_verylongterm_8yr_Women.png/pdf"
display "  - mechanism_verylongterm_8yr_Men.png/pdf"
display "  - population_composition_test.png/pdf"
display ""
display "• Tables:"
display "  - mechanism_dd_by_duration.tex"
display "  - mechanism_event_study_5yr.tex"
display "  - mechanism_event_study_8yr.tex"
display "  - mechanism_robustness_verylongterm.tex"
display ""
display "MECHANISM INTERPRETATION:"
display "• Long-term residents: Effects reflect behavioral/cultural changes"
display "• Recent movers: Effects reflect selection/sorting"
display "• Population test: Checks if casinos change resident composition"
display ""
display "NEXT STEPS:"
display "• Compare coefficients between groups to identify mechanism"
display "• Check population composition test for evidence of sorting"
display "• Examine timing of effects (immediate vs. delayed)"
display ""
display "All results saved to: $output"
display "================================================================================"

* Close log
cap log close