/*==============================================================================
CALLAWAY-SANT'ANNA IMPLEMENTATION - FIXED VERSION
Starting from 2005 when county coverage is robust
==============================================================================*/

clear all
set more off
set maxvar 10000

* Set working directories
global data "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Data"
global output "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Output"

* Install required packages
capture ssc install csdid, all replace
capture ssc install drdid, all replace

cap log close
log using "$output/cs_analysis_fixed_log.txt", replace text

/*==============================================================================
PART I: CREATE COUNTY-YEAR LEVEL DATA (2005-2023 ONLY)
==============================================================================*/

display ""
display "=============================================================="
display "=== PREPARING COUNTY-YEAR DATA FOR CS (2005-2023) ==="
display "=============================================================="

* Load main analysis data - START FROM 2005
use "$data\ACSData.dta", clear
keep if year >= 2005 & year <= 2023  // FIXED: Start from 2005
gen county_id = statefip * 1000 + countyfip
keep if age >= 18 & age <= 40

* Generate outcome and demographic variables
gen married = (marst == 1)
gen has_children = (nchild > 0) if !missing(nchild)
gen num_children = nchild
gen female = (sex == 2)
gen age_sq = age^2
gen white = (race == 1)
gen black = (race == 2)
gen hispanic = (hispan >= 1 & hispan <= 4)

* Create residence duration variables
gen acs_sample = 1
replace acs_sample = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)

sort sample serial
by sample serial: egen movedin_hh = max(movedin)
gen longterm_resident = (movedin_hh >= 4) if !missing(movedin_hh)

/*==============================================================================
COLLAPSE TO COUNTY-YEAR LEVEL
==============================================================================*/

* Create demographic group indicators for analysis
gen women_sample = (female == 1 & acs_sample == 1)
gen men_sample = (female == 0 & acs_sample == 1)
gen women_longterm = (female == 1 & acs_sample == 1 & longterm_resident == 1)
gen women_recent = (female == 1 & acs_sample == 1 & longterm_resident == 0)
gen men_longterm = (female == 0 & acs_sample == 1 & longterm_resident == 1)
gen men_recent = (female == 0 & acs_sample == 1 & longterm_resident == 0)

* Check county coverage before collapsing
display ""
display "=== COUNTY COVERAGE BY YEAR (BEFORE COLLAPSE) ==="
preserve
keep if women_sample == 1
egen county_tag = tag(county_id year)
bysort year: egen counties_per_year = total(county_tag)
bysort year: keep if _n == 1
list year counties_per_year, clean
restore

* Collapse to county-year level for each group
preserve

* Women overall
keep if women_sample == 1
collapse (mean) num_children_w=num_children married_w=married has_children_w=has_children ///
         (mean) age_w=age white_w=white black_w=black hispanic_w=hispanic ///
         (sum) pop_w=perwt ///
         [aw=perwt], by(county_id year)

tempfile women_data
save `women_data'
restore

preserve
* Men overall  
keep if men_sample == 1
collapse (mean) num_children_m=num_children married_m=married has_children_m=has_children ///
         (mean) age_m=age white_m=white black_m=black hispanic_m=hispanic ///
         (sum) pop_m=perwt ///
         [aw=perwt], by(county_id year)

tempfile men_data
save `men_data'
restore

preserve
* Women long-term
keep if women_longterm == 1
collapse (mean) num_children_wl=num_children ///
         (mean) age_wl=age ///
         (sum) pop_wl=perwt ///
         [aw=perwt], by(county_id year)

tempfile women_longterm_data
save `women_longterm_data'
restore

preserve
* Women recent
keep if women_recent == 1
collapse (mean) num_children_wr=num_children ///
         (mean) age_wr=age ///
         (sum) pop_wr=perwt ///
         [aw=perwt], by(county_id year)

tempfile women_recent_data
save `women_recent_data'
restore

preserve
* Men long-term
keep if men_longterm == 1
collapse (mean) num_children_ml=num_children ///
         (mean) age_ml=age ///
         (sum) pop_ml=perwt ///
         [aw=perwt], by(county_id year)

tempfile men_longterm_data
save `men_longterm_data'
restore

preserve
* Men recent
keep if men_recent == 1
collapse (mean) num_children_mr=num_children ///
         (mean) age_mr=age ///
         (sum) pop_mr=perwt ///
         [aw=perwt], by(county_id year)

tempfile men_recent_data
save `men_recent_data'
restore

/*==============================================================================
MERGE WITH CASINO DATA AND CREATE CS VARIABLES
==============================================================================*/

* Start with casino data
use "$data\casino_clean.dta", clear
keep county_id year treat_year casino_county nearby_county

* Keep only years with good county coverage
keep if year >= 2005 & year <= 2023

* Merge all demographic data
merge 1:1 county_id year using `women_data', nogen
merge 1:1 county_id year using `men_data', nogen
merge 1:1 county_id year using `women_longterm_data', nogen
merge 1:1 county_id year using `women_recent_data', nogen
merge 1:1 county_id year using `men_longterm_data', nogen
merge 1:1 county_id year using `men_recent_data', nogen

* Create sample type indicator
gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if missing(casino_county)  // Control counties

* Fill missing values
replace casino_county = 0 if missing(casino_county)
replace nearby_county = 0 if missing(nearby_county)

* Create donut sample
gen donut_sample = (sample_type == 1 | sample_type == 3)

/*==============================================================================
FIX CS VARIABLE ISSUES
==============================================================================*/

* FIXED: Handle always-treated units (casinos opened before 2005)
gen always_treated = (treat_year < 2005 & casino_county == 1)
tab always_treated

* For CS analysis, set always-treated counties as never-treated
gen gvar_original = treat_year if casino_county == 1 & treat_year >= 2005
replace gvar_original = 0 if casino_county == 0 | always_treated == 1

* Create proper panel structure
gen ivar = county_id
gen time = year

* Label variables
label var gvar_original "Treatment year (0 = never treated, excludes pre-2005)"
label var time "Calendar year" 
label var ivar "County identifier"

* Keep only counties with data
drop if missing(num_children_w) & missing(num_children_m)

* Create age squared variables
gen age_w_sq = age_w^2
gen age_m_sq = age_m^2
gen age_wl_sq = age_wl^2
gen age_wr_sq = age_wr^2
gen age_ml_sq = age_ml^2
gen age_mr_sq = age_mr^2

/*==============================================================================
DIAGNOSTIC: CHECK DATA STRUCTURE
==============================================================================*/

display ""
display "=== DIAGNOSTIC: DATA STRUCTURE FOR CS (2005-2023) ==="

* Check panel balance
duplicates report ivar time
tab time
tab gvar_original

* Check sample sizes
count if donut_sample == 1
count if donut_sample == 1 & gvar_original > 0
count if donut_sample == 1 & gvar_original == 0

display "Counties by treatment status:"
tab gvar_original if donut_sample == 1

/*==============================================================================
CS ANALYSIS: WOMEN FERTILITY 
==============================================================================*/

display ""
display "=============================================================="
display "=== CALLAWAY-SANT'ANNA ANALYSIS: WOMEN FERTILITY ==="
display "=============================================================="

* Keep only counties with women data in donut sample
keep if donut_sample == 1 & !missing(num_children_w)

eststo clear

/*------------------------------------------------------------------------------
1. BASELINE TWFE FOR COMPARISON
------------------------------------------------------------------------------*/

display ""
display "=== 1. BASELINE TWFE (for comparison) ==="

* Create post-treatment indicator
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year) & treat_year >= 2005
replace post_treatment = 0 if casino_county == 0 | always_treated == 1

reghdfe num_children_w post_treatment age_w age_w_sq [aw=pop_w], ///
    absorb(county_id year) vce(cluster county_id)
eststo twfe_baseline

/*------------------------------------------------------------------------------
2. CS METHOD: IPW (Inverse Probability Weighting)
------------------------------------------------------------------------------*/

display ""
display "=== 2. CS METHOD: IPW ==="

csdid num_children_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(ipw) ///
    cluster(county_id)

estat simple
eststo cs_ipw

/*------------------------------------------------------------------------------
3. CS METHOD: Outcome Regression
------------------------------------------------------------------------------*/

display ""
display "=== 3. CS METHOD: Outcome Regression ==="

csdid num_children_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(reg) ///
    cluster(county_id)

estat simple
eststo cs_reg

/*------------------------------------------------------------------------------
4. CS METHOD: Doubly Robust (AIPW)
------------------------------------------------------------------------------*/

display ""
display "=== 4. CS METHOD: Doubly Robust ==="

csdid num_children_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)

estat simple
eststo cs_dr

/*==============================================================================
COMPARISON TABLE: WOMEN FERTILITY
==============================================================================*/

display ""
display "=== CREATING COMPARISON TABLE: WOMEN FERTILITY ==="

esttab twfe_baseline cs_ipw cs_reg cs_dr ///
    using "$output/table_cs_comparison_women_fixed.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("TWFE" "CS-IPW" "CS-Reg" "CS-DR") ///
    title("Callaway-Sant'Anna vs TWFE: Women Fertility Effects (2005-2023)") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "County-year level analysis with population weights." ///
            "Sample: Counties in donut sample, 2005-2023 (robust county coverage)." ///
            "Always-treated counties (casinos opened pre-2005) excluded from CS analysis." ///
            "*** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
EVENT STUDY COMPARISON - FIXED
==============================================================================*/

display ""
display "=== CS EVENT STUDY ANALYSIS (FIXED) ==="

* FIXED: Use iweights instead of aweights
csdid num_children_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)

* Get event study results
estat event
eststo cs_event_dr

/*==============================================================================
PROPER CS EVENT STUDY PLOTS
==============================================================================*/

display ""
display "=== CREATING PROPER CS EVENT STUDY PLOTS ==="

* METHOD 1: Use the dedicated csdid_plot command
csdid_plot, ///
    title("CS Event Study: Women Fertility (2005-2023)") ///
    ytitle("Effect on Number of Children") ///
    xtitle("Years Relative to Casino Opening") ///
    style(rspike)

graph export "$output/cs_event_study_women_FIXED.png", replace

* METHOD 2: Alternative using estat event + coefplot (if Method 1 doesn't work)
* Store the event study results properly
estat event, estore(event_results)

* Plot the event study estimates (not the main CS results)
coefplot event_results, ///
    keep(Tm* Tp*) ///
    vertical ///
    yline(0) ///
    xlabel(, angle(45)) ///
    title("CS Event Study: Women Fertility (Alternative Method)") ///
    ytitle("Effect on Number of Children") ///
    xtitle("Years Relative to Casino Opening")

graph export "$output/cs_event_study_women_ALT.png", replace

/*==============================================================================
CHECK FOR COEFFICIENT DROPPING ISSUES
==============================================================================*/

display ""
display "=== DIAGNOSTIC: WHY ARE COEFFICIENTS DROPPED? ==="

* Check sample sizes by treatment cohort
display "Sample sizes by treatment cohort:"
tab gvar_original if donut_sample == 1

* Check which cohorts have sufficient pre/post periods
preserve
keep if gvar_original > 0 & donut_sample == 1
bysort gvar_original: gen cohort_obs = _N
bysort gvar_original: keep if _n == 1
list gvar_original cohort_obs
display "Cohorts with <50 observations may have coefficient dropping issues"
restore

* Identify problematic small cohorts
preserve
collapse (count) obs = ivar, by(gvar_original)
display "Treatment cohorts and their sample sizes:"
list if gvar_original > 0
display "Consider restricting to cohorts with obs >= 50"
restore

/*==============================================================================
DIAGNOSTICS
==============================================================================*/

display ""
display "=============================================================="
display "=== CS DIAGNOSTICS ==="
display "=============================================================="

* Pre-trend test
display ""
display "=== PRE-TREND TEST ==="
estat pretrend

* Group-time effects
display ""
display "=== GROUP-TIME EFFECTS ==="
estat group

* Calendar time effects
display ""
display "=== CALENDAR TIME EFFECTS ==="
estat calendar

/*==============================================================================
MEN FERTILITY ANALYSIS - QUICK VERSION
==============================================================================*/

display ""
display "=============================================================="
display "=== CS ANALYSIS: MEN FERTILITY (QUICK) ==="
display "=============================================================="

* Reload data for men
use "$data\casino_clean.dta", clear
keep county_id year treat_year casino_county nearby_county
keep if year >= 2005 & year <= 2023

merge 1:1 county_id year using `men_data', nogen

gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if missing(casino_county)

replace casino_county = 0 if missing(casino_county)
replace nearby_county = 0 if missing(nearby_county)

gen donut_sample = (sample_type == 1 | sample_type == 3)

gen always_treated = (treat_year < 2005 & casino_county == 1)
gen gvar_original = treat_year if casino_county == 1 & treat_year >= 2005
replace gvar_original = 0 if casino_county == 0 | always_treated == 1

gen ivar = county_id
gen time = year
gen age_m_sq = age_m^2

keep if donut_sample == 1 & !missing(num_children_m)

* CS doubly robust for men
csdid num_children_m age_m age_m_sq [iw=pop_m], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)

estat simple
eststo cs_dr_men

/*==============================================================================
MARRIAGE OUTCOMES - QUICK VERSION
==============================================================================*/

display ""
display "=============================================================="
display "=== CS ANALYSIS: MARRIAGE OUTCOMES ==="
display "=============================================================="

* Reload for marriage analysis
use "$data\casino_clean.dta", clear
keep county_id year treat_year casino_county nearby_county
keep if year >= 2005 & year <= 2023

merge 1:1 county_id year using `women_data', nogen

gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if missing(casino_county)

replace casino_county = 0 if missing(casino_county)
replace nearby_county = 0 if missing(nearby_county)

gen donut_sample = (sample_type == 1 | sample_type == 3)

gen always_treated = (treat_year < 2005 & casino_county == 1)
gen gvar_original = treat_year if casino_county == 1 & treat_year >= 2005
replace gvar_original = 0 if casino_county == 0 | always_treated == 1

gen ivar = county_id
gen time = year
gen age_w_sq = age_w^2

keep if donut_sample == 1 & !missing(married_w)

* Marriage outcomes
csdid married_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)
estat simple
eststo cs_married_women

csdid has_children_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)
estat simple
eststo cs_children_women

/*==============================================================================
ROBUSTNESS: RESTRICT TO LARGER COHORTS
==============================================================================*/

display ""
display "=== ROBUSTNESS: RESTRICT TO COHORTS WITH SUFFICIENT DATA ==="

* Identify cohorts with sufficient sample size (>=50 county-year observations)
preserve
collapse (count) obs = ivar, by(gvar_original)
keep if obs >= 50 & gvar_original > 0  // Keep only large treated cohorts
levelsof gvar_original, local(good_cohorts)
display "Large cohorts to keep: `good_cohorts'"
restore

* Restrict analysis to cohorts with sufficient data
gen good_cohort = 0
foreach cohort in `good_cohorts' {
    replace good_cohort = 1 if gvar_original == `cohort'
}
replace good_cohort = 1 if gvar_original == 0  // Keep never-treated

display "Sample size before restriction: " _N
keep if good_cohort == 1
display "Sample size after restriction: " _N

* Re-run CS with restricted sample
display ""
display "=== CS ANALYSIS WITH RESTRICTED SAMPLE ==="

csdid num_children_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)

estat simple
eststo cs_dr_restricted

* Event study with restricted sample
estat event

* Plot restricted sample event study
csdid_plot, ///
    title("CS Event Study: Women Fertility (Large Cohorts Only)") ///
    ytitle("Effect on Number of Children") ///
    xtitle("Years Relative to Casino Opening") ///
    style(rspike)

graph export "$output/cs_event_study_restricted.png", replace

/*==============================================================================
COMPARISON: TWFE EVENT STUDY FOR REFERENCE
==============================================================================*/

display ""
display "=== TWFE EVENT STUDY FOR COMPARISON ==="

* Create event time variables for TWFE event study
gen event_time = year - treat_year if casino_county == 1 & treat_year >= 2005
replace event_time = -999 if casino_county == 0  // Never treated

* Create event time dummies (exclude t=-1 as reference)
forvalues k = 10(-1)2 {
    gen lead`k' = (event_time == -`k') if event_time != -999
}
forvalues k = 0/15 {
    gen lag`k' = (event_time == `k') if event_time != -999
}

* Run TWFE event study
reghdfe num_children_w lead10-lead2 lag0-lag15 age_w age_w_sq [aw=pop_w], ///
    absorb(county_id year) vce(cluster county_id)

* Plot TWFE event study
coefplot, ///
    keep(lead* lag*) ///
    vertical ///
    yline(0) ///
    xlabel(, angle(45)) ///
    title("TWFE Event Study: Women Fertility (For Comparison)") ///
    ytitle("Effect on Number of Children") ///
    xtitle("Years Relative to Casino Opening")

graph export "$output/twfe_event_study_women.png", replace

/*==============================================================================
FINAL SUMMARY TABLE
==============================================================================*/

* Create comprehensive comparison table
esttab twfe_baseline cs_dr cs_dr_restricted ///
    using "$output/table_cs_comprehensive_comparison.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("TWFE" "CS Full Sample" "CS Large Cohorts") ///
    title("Casino Effects on Women Fertility: Comprehensive Comparison") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "TWFE uses county-year level data with population weights." ///
            "CS Full Sample includes all treatment cohorts (2005-2023)." ///
            "CS Large Cohorts restricts to cohorts with >=50 observations." ///
            "*** p<0.01, ** p<0.05, * p<0.1.")

esttab cs_dr cs_dr_men cs_married_women cs_children_women ///
    using "$output/table_cs_all_outcomes_fixed.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Women Fertility" "Men Fertility" "Women Marriage" "Women Have Kids") ///
    title("Callaway-Sant'Anna Results: All Outcomes (2005-2023)") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Doubly robust CS estimator for all outcomes." ///
            "Sample period: 2005-2023 with robust IPUMS county coverage." ///
            "*** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
SUMMARY
==============================================================================*/

display ""
display "================================================================================"
display "=== FIXED CALLAWAY-SANT'ANNA ANALYSIS COMPLETE ==="
display "================================================================================"
display ""
display "KEY FIXES:"
display "1. ✓ Sample period: 2005-2023 (robust county coverage)"
display "2. ✓ Fixed aweights error (now uses iweights)"
display "3. ✓ Always-treated threshold: casinos opened before 2005"
display "4. ✓ Proper handling of IPUMS unbalanced panel"
display "5. ✓ FIXED EVENT STUDY PLOTS using csdid_plot command"
display "6. ✓ Added robustness check restricting to large cohorts"
display "7. ✓ Added TWFE event study for comparison"
display ""
display "TABLES CREATED:"
display "• CS vs TWFE Comparison - Women (table_cs_comparison_women_fixed.tex)"
display "• CS Comprehensive Comparison (table_cs_comprehensive_comparison.tex)"
display "• CS All Outcomes (table_cs_all_outcomes_fixed.tex)"
display ""
display "PLOTS CREATED:"
display "• CS Event Study - Fixed (cs_event_study_women_FIXED.png)"
display "• CS Event Study - Alternative Method (cs_event_study_women_ALT.png)"
display "• CS Event Study - Large Cohorts (cs_event_study_restricted.png)"
display "• TWFE Event Study - For Comparison (twfe_event_study_women.png)"
display ""
display "NEXT STEPS:"
display "1. Compare CS and TWFE event studies to assess pre-trend violations"
display "2. If pre-trends are violated, consider:"
display "   - Adding county-specific linear trends"
display "   - Different control group selection"
display "   - Alternative identification strategies"
display "3. Examine robustness of results across different CS cohort restrictions"
display ""
display "================================================================================"

cap log close