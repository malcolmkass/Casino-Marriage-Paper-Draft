/*==============================================================================
CALLAWAY-SANT'ANNA WITH COUNTY-SPECIFIC LINEAR TRENDS
==============================================================================*/

clear all
set more off
capture log close

// Set paths (adjust as needed)
global data "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Data"
global output "C:\Users\jsoriano\Dropbox\2025 Student Adv Metrics Research\Marriage and Divorce\Output"

log using "$output/cs_county_trends_log.txt", replace text

/*==============================================================================
LOAD AND PREPARE DATA (RECREATE FROM PREVIOUS ANALYSIS)
==============================================================================*/

display "=== LOADING AND PREPARING DATA ==="

// Start with main ACS data (same as your previous analysis)
use "$data\ACSData.dta", clear
keep if year >= 2005 & year <= 2023
gen county_id = statefip * 1000 + countyfip
keep if age >= 18 & age <= 40

// Generate outcome and demographic variables
gen married = (marst == 1)
gen has_children = (nchild > 0) if !missing(nchild)
gen num_children = nchild
gen female = (sex == 2)
gen age_sq = age^2
gen white = (race == 1)
gen black = (race == 2)
gen hispanic = (hispan >= 1 & hispan <= 4)

// Create residence duration variables
gen acs_sample = 1
replace acs_sample = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)

sort sample serial
by sample serial: egen movedin_hh = max(movedin)
gen longterm_resident = (movedin_hh >= 4) if !missing(movedin_hh)

// Create demographic group indicators
gen women_sample = (female == 1 & acs_sample == 1)

// Collapse to county-year level for women
keep if women_sample == 1
collapse (mean) num_children_w=num_children married_w=married has_children_w=has_children ///
         (mean) age_w=age white_w=white black_w=black hispanic_w=hispanic ///
         (sum) pop_w=perwt ///
         [aw=perwt], by(county_id year)

tempfile women_data
save `women_data'

// Merge with casino data
use "$data\casino_clean.dta", clear
keep county_id year treat_year casino_county nearby_county
keep if year >= 2005 & year <= 2023

merge 1:1 county_id year using `women_data', nogen

// Create CS variables
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

keep if donut_sample == 1 & !missing(num_children_w)

/*==============================================================================
BASELINE MODELS (FOR COMPARISON)
==============================================================================*/

display ""
display "================================================================================"
display "=== BASELINE MODELS ==="
display "================================================================================"

// Create post-treatment indicator
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year) & treat_year >= 2005
replace post_treatment = 0 if casino_county == 0 | always_treated == 1

// Age variables
gen age_w_sq = age_w^2

// BASELINE TWFE
reghdfe num_children_w post_treatment age_w age_w_sq [aw=pop_w], ///
    absorb(county_id year) vce(cluster county_id)

eststo twfe_baseline

// BASELINE CS
csdid num_children_w age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)

estat simple
eststo cs_dr

/*==============================================================================
METHOD 1: TWFE WITH COUNTY-SPECIFIC TRENDS
==============================================================================*/

display ""
display "================================================================================"
display "=== TWFE WITH COUNTY-SPECIFIC LINEAR TRENDS ==="
display "================================================================================"

// Create county-specific time trend
gen county_time_trend = county_id * (year - 2005)  // Normalized to start at 0

// TWFE with county trends
reghdfe num_children_w post_treatment age_w age_w_sq county_time_trend [aw=pop_w], ///
    absorb(county_id year) vce(cluster county_id)

eststo twfe_trends

// Alternative: Use year as continuous variable
gen year_continuous = year - 2005
gen county_year_trend = county_id * year_continuous

reghdfe num_children_w post_treatment age_w age_w_sq county_year_trend [aw=pop_w], ///
    absorb(county_id year) vce(cluster county_id)

eststo twfe_trends_alt

/*==============================================================================
METHOD 2: TWFE EVENT STUDY WITH COUNTY TRENDS
==============================================================================*/

display ""
display "=== TWFE EVENT STUDY WITH COUNTY TRENDS ==="

// Create event time variables
gen event_time = year - treat_year if casino_county == 1 & treat_year >= 2005
replace event_time = -999 if casino_county == 0

// Create event time dummies (exclude t=-1 as reference)
forvalues k = 10(-1)2 {
    gen lead`k' = (event_time == -`k') if event_time != -999
}
forvalues k = 0/15 {
    gen lag`k' = (event_time == `k') if event_time != -999
}

// TWFE event study with county trends
reghdfe num_children_w lead10-lead2 lag0-lag15 age_w age_w_sq county_time_trend [aw=pop_w], ///
    absorb(county_id year) vce(cluster county_id)

eststo twfe_event_trends

// Plot event study with trends
coefplot, ///
    keep(lead* lag*) ///
    vertical ///
    yline(0) ///
    xlabel(, angle(45)) ///
    title("TWFE Event Study with County Trends: Women Fertility") ///
    ytitle("Effect on Number of Children") ///
    xtitle("Years Relative to Casino Opening")

graph export "$output/twfe_event_study_county_trends.png", replace

/*==============================================================================
METHOD 3: DETRENDED CS ANALYSIS
==============================================================================*/

display ""
display "=== DETRENDED CALLAWAY-SANT'ANNA ANALYSIS ==="

// Method 3A: Detrend outcome variable first, then run CS
preserve

// Estimate county-specific trends using pre-treatment data
gen pre_treatment = (year < treat_year | gvar_original == 0)

// Estimate county trends using only pre-treatment periods
reg num_children_w year_continuous i.county_id if pre_treatment == 1 [aw=pop_w]

// Predict county-specific trends for all periods
predict county_trend_pred

// Create detrended outcome
gen num_children_w_detrended = num_children_w - county_trend_pred

// Run CS on detrended outcome
csdid num_children_w_detrended age_w age_w_sq [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)

estat simple
eststo cs_detrended

// Event study for detrended
estat event
csdid_plot, ///
    title("CS Event Study: Detrended Women Fertility") ///
    ytitle("Effect on Number of Children (Detrended)") ///
    xtitle("Years Relative to Casino Opening")

graph export "$output/cs_event_study_detrended.png", replace

// Test pre-trends on detrended data
estat pretrend
display "Pre-trend test (detrended): chi2 = " r(chi2) ", p-value = " r(p)

restore

/*==============================================================================
METHOD 4: CS WITH COUNTY TRENDS AS COVARIATES
==============================================================================*/

display ""
display "=== CS WITH COUNTY TRENDS AS ADDITIONAL COVARIATES ==="

// Include county-specific trends directly in CS regression
csdid num_children_w age_w age_w_sq county_time_trend [iw=pop_w], ///
    ivar(ivar) time(time) gvar(gvar_original) method(dripw) ///
    cluster(county_id)

estat simple
eststo cs_with_trends

// Event study
estat event
csdid_plot, ///
    title("CS Event Study with County Trends: Women Fertility") ///
    ytitle("Effect on Number of Children") ///
    xtitle("Years Relative to Casino Opening")

graph export "$output/cs_event_study_with_trends.png", replace

// Test pre-trends
estat pretrend
display "Pre-trend test (with county trends): chi2 = " r(chi2) ", p-value = " r(p)

/*==============================================================================
COMPARISON TABLE
==============================================================================*/

// Compare all methods
esttab twfe_baseline twfe_trends cs_dr cs_detrended cs_with_trends ///
    using "$output/table_county_trends_comparison.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("TWFE Base" "TWFE+Trends" "CS Base" "CS Detrended" "CS+Trends") ///
    title("County-Specific Trends Analysis: Women Fertility Effects") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
             "TWFE Base: Standard two-way fixed effects." ///
             "TWFE+Trends: TWFE with county-specific linear trends." ///
             "CS Base: Standard Callaway-Sant'Anna doubly robust." ///
             "CS Detrended: CS on pre-treatment detrended outcome." ///
             "CS+Trends: CS with county trends as covariates." ///
             "*** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
DIAGNOSTIC SUMMARY
==============================================================================*/

display ""
display "================================================================================"
display "=== COUNTY TRENDS ANALYSIS SUMMARY ==="
display "================================================================================"

display ""
display "COEFFICIENT COMPARISON:"
display "• TWFE Baseline: [Check from previous analysis]"
display "• TWFE + County Trends: [Check coefficient]"
display "• CS Baseline: [Check from previous analysis] "
display "• CS Detrended: [Check coefficient]"
display "• CS + County Trends: [Check coefficient]"

display ""
display "PRE-TREND TEST RESULTS:"
display "• CS Baseline: chi2(17) = 190.16, p < 0.001 [From previous]"
display "• CS Detrended: [Check new p-value]"
display "• CS + County Trends: [Check new p-value]"

display ""
display "INTERPRETATION:"
display "• If county trends reduce coefficients → trends were confounding"
display "• If pre-trend tests improve → trends address identification concerns"
display "• If results robust → stronger evidence for causal effects"

cap log close