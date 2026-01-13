/*==============================================================================
CASINO EFFECTS ON RELIGIOUS ADHERENCE ANALYSIS
CORRECTED VERSION WITH ACTUAL VARIABLE NAMES FROM LOG FILE
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
log using "$output/religious_analysis_log.txt", replace text

/*==============================================================================
1. LOAD AND PREPARE RELIGIOUS DATA (2000, 2010, AND 2020)
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

/*==============================================================================
2. MERGE WITH CASINO DATA
==============================================================================*/

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

/*==============================================================================
3. CREATE TREATMENT VARIABLES (CONSISTENT WITH MAIN ANALYSIS)
==============================================================================*/

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

/*==============================================================================
4. SUMMARY STATISTICS AND DATA QUALITY CHECKS
==============================================================================*/

display ""
display "=== RELIGIOUS DATA SUMMARY STATISTICS ==="

* Check data coverage
tab year
tab casino_county year
tab sample_type year

* Summary statistics by treatment status and year
eststo clear

foreach year in 2000 2010 2020 {
    estpost tabstat total_adherents_rate evangelical_rate catholic_rate ///
        mainline_rate southern_baptist_rate if year == `year', ///
        by(casino_county) statistics(mean sd n)
    eststo religious_summary_`year'
}

esttab religious_summary_2000 religious_summary_2010 religious_summary_2020 ///
    using "$output/religious_summary_stats.tex", replace ///
    cells("mean(fmt(2)) sd(fmt(2))") ///
    title("Religious Adherence by Casino Status") ///
    mtitles("2000" "2010" "2020") ///
    addnotes("Means and standard deviations by casino county status")

* Check for missing data and outliers
summarize total_adherents_rate evangelical_rate catholic_rate, detail
count if missing(total_adherents_rate)
count if total_adherents_rate > 1500  // Potential outliers

/*==============================================================================
5. MAIN ANALYSIS: DIFFERENCES-IN-DIFFERENCES
==============================================================================*/

display ""
display "=== MAIN DD ANALYSIS FOR RELIGIOUS ADHERENCE ==="

* Primary specification: Post-treatment indicator
reghdfe total_adherents_rate post_treatment ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store dd_total_adherents

* Years of exposure specification
reghdfe total_adherents_rate years_exposure ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store dd_years_exposure

* Event study approach (limited time variation)
reghdfe total_adherents_rate early_post late_post ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store dd_event_study

* Export main results
esttab dd_total_adherents dd_years_exposure dd_event_study ///
    using "$output/religious_main_results.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment years_exposure early_post late_post) ///
    mtitles("Post-Treatment" "Years Exposure" "Event Study") ///
    title("Casino Effects on Total Religious Adherence Rate") ///
    addnotes("Notes: All regressions include county and year fixed effects." ///
             "Standard errors clustered at county level. Weighted by population." ///
             "*** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
6. DENOMINATION-SPECIFIC ANALYSIS
==============================================================================*/

display ""
display "=== DENOMINATION-SPECIFIC ANALYSIS ==="

eststo clear

* Major religious families
foreach outcome in evangelical_rate catholic_rate mainline_rate orthodox_rate other_rate {
    reghdfe `outcome' post_treatment ///
        [aw=population], absorb(county_id year) vce(cluster county_id)
    estimates store dd_`outcome'
}

* Export denomination results
esttab dd_evangelical_rate dd_catholic_rate dd_mainline_rate dd_orthodox_rate dd_other_rate ///
    using "$output/religious_denominations.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Evangelical" "Catholic" "Mainline" "Orthodox" "Other") ///
    title("Casino Effects by Religious Denomination") ///
    addnotes("Notes: All regressions include county and year fixed effects." ///
             "Standard errors clustered at county level. Weighted by population.")

* Black Protestant (only available in 2010 and 2020)
reghdfe black_protestant_rate post_treatment ///
    if year >= 2010 [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store dd_black_protestant_rate

* Major specific denominations
eststo clear

foreach outcome in southern_baptist_rate methodist_rate episcopal_rate mormon_rate nazarene_rate {
    reghdfe `outcome' post_treatment ///
        [aw=population], absorb(county_id year) vce(cluster county_id)
    estimates store dd_`outcome'
}

esttab dd_southern_baptist_rate dd_methodist_rate dd_episcopal_rate dd_mormon_rate dd_nazarene_rate ///
    using "$output/religious_major_denoms.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Southern Baptist" "Methodist" "Episcopal" "Mormon" "Nazarene") ///
    title("Casino Effects on Major Denominations")

/*==============================================================================
7. ROBUSTNESS CHECKS (CONSISTENT WITH MAIN ANALYSIS)
==============================================================================*/

display ""
display "=== ROBUSTNESS CHECKS ==="

eststo clear

* Baseline specification
estimates restore dd_total_adherents
estimates store robust_baseline

* Donut design (exclude nearby counties)
reghdfe total_adherents_rate post_treatment ///
    if donut_sample == 1 [aw=population], ///
    absorb(county_id year) vce(cluster county_id)
estimates store robust_donut

* Add state-year fixed effects
reghdfe total_adherents_rate post_treatment ///
    [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
estimates store robust_stateyear

* Exclude small counties (consistent with main analysis threshold)
reghdfe total_adherents_rate post_treatment ///
    if population >= 5000 [aw=population], ///
    absorb(county_id year) vce(cluster county_id)
estimates store robust_minpop

* Export robustness results
esttab robust_baseline robust_donut robust_stateyear robust_minpop ///
    using "$output/religious_robustness.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Baseline" "Donut Sample" "State-Year FE" "Min Pop 5K") ///
    title("Robustness Checks: Religious Adherence") ///
    addnotes("Notes: Robustness checks for total religious adherence rate." ///
             "All specifications include county and year fixed effects.")

/*==============================================================================
8. HETEROGENEITY ANALYSIS
==============================================================================*/

display ""
display "=== HETEROGENEITY ANALYSIS ==="

* By baseline religiosity (using 2000 levels for better baseline)
preserve
keep if year == 2000
xtile baseline_religiosity_tercile = total_adherents_rate, nq(3)
keep county_id baseline_religiosity_tercile
tempfile baseline_religiosity
save `baseline_religiosity'
restore

merge m:1 county_id using `baseline_religiosity', nogen

* Heterogeneity by baseline religiosity
eststo clear
forvalues t = 1/3 {
    reghdfe total_adherents_rate post_treatment ///
        if baseline_religiosity_tercile == `t' [aw=population], ///
        absorb(county_id year) vce(cluster county_id)
    estimates store hetero_baseline_`t'
}

esttab hetero_baseline_1 hetero_baseline_2 hetero_baseline_3 ///
    using "$output/religious_heterogeneity_baseline.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Low Baseline" "Medium Baseline" "High Baseline") ///
    title("Heterogeneity by Baseline Religiosity (2000 Terciles)")

* By region (create Bible Belt indicator similar to main analysis)
gen bible_belt = 0
replace bible_belt = 1 if inlist(state_code, 1, 12, 13, 21, 28, 37, 45, 47, 51)  // AL, FL, GA, KY, MS, NC, SC, TN, VA

reghdfe total_adherents_rate c.post_treatment##i.bible_belt ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store hetero_region

* Test interaction significance
test 1.bible_belt#c.post_treatment
local p_interaction = r(p)

display ""
display "Bible Belt interaction p-value: " %6.4f `p_interaction'

/*==============================================================================
9. MECHANISM ANALYSIS: CONGREGATIONS VS PARTICIPATION
==============================================================================*/

display ""
display "=== MECHANISM ANALYSIS ==="

* Test if effect operates through fewer congregations or lower participation
reghdfe total_congregations post_treatment ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store mech_congregations

* Calculate congregations per 1,000 population
gen congregations_rate = (total_congregations / population) * 1000

reghdfe congregations_rate post_treatment ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store mech_congregations_rate

* Average congregation size (adherents per congregation)
gen avg_congregation_size = total_adherents / total_congregations if total_congregations > 0

reghdfe avg_congregation_size post_treatment ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store mech_congregation_size

* Export mechanism results
esttab mech_congregations_rate mech_congregation_size ///
    using "$output/religious_mechanisms.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Congregations per 1K" "Avg Congregation Size") ///
    title("Mechanisms: Congregations vs Participation") ///
    addnotes("Notes: Tests whether effects operate through institutional presence" ///
             "or average participation per congregation.")

/*==============================================================================
10. SPILLOVER ANALYSIS (CONSISTENT WITH MAIN ANALYSIS)
==============================================================================*/

display ""
display "=== SPILLOVER ANALYSIS ==="

* Create spillover variables consistent with main analysis
gen casino_post = casino_county * post_treatment
gen nearby_post = nearby_county * post_treatment

* Test for spillover effects
reghdfe total_adherents_rate casino_post nearby_post ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store spillover_total

* Test spillover hypotheses
test nearby_post = 0
local p_spillover_zero = r(p)

test casino_post = nearby_post
local p_spillover_equal = r(p)

display ""
display "Spillover = 0: p = " %6.4f `p_spillover_zero'
display "Spillover = Direct: p = " %6.4f `p_spillover_equal'

/*==============================================================================
11. VISUALIZATION AND ADDITIONAL ANALYSIS
==============================================================================*/

* Create binscatter plot of years exposure vs religious adherence
preserve
collapse (mean) total_adherents_rate [aw=population], by(years_exposure casino_county)
keep if years_exposure >= 0 & years_exposure <= 25 & casino_county == 1

twoway (scatter total_adherents_rate years_exposure) ///
    (lfit total_adherents_rate years_exposure), ///
    xtitle("Years Since Casino Opening") ///
    ytitle("Religious Adherents per 1,000 Population") ///
    title("Religious Adherence and Casino Exposure") ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white))
graph export "$output/religious_exposure_scatter.png", replace
restore

/*==============================================================================
FINAL SUMMARY AND COMPLETION MESSAGE
==============================================================================*/

display ""
display "================================================================================"
display "=== RELIGIOUS ADHERENCE ANALYSIS COMPLETE ==="
display "================================================================================"
display ""
display "KEY RESULTS GENERATED:"
display "• Main DD results for total religious adherence (2000-2020)"
display "• Denomination-specific effects (evangelical, Catholic, mainline, etc.)"
display "• Robustness checks (donut design, state-year FE, minimum population)"
display "• Heterogeneity by baseline religiosity (2000) and region"
display "• Mechanism analysis (congregations vs participation)"
display "• Spillover effects analysis"
display ""
display "FILES CREATED:"
display "• religious_main_results.tex"
display "• religious_denominations.tex"
display "• religious_major_denoms.tex"
display "• religious_robustness.tex"
display "• religious_heterogeneity_baseline.tex"
display "• religious_mechanisms.tex"
display "• religious_exposure_scatter.png"
display ""
display "CORRECTED VARIABLE NAMES FOR EACH YEAR:"
display "• 2000: fip, totrt, totcg, totad, evanrt, cathrt, etc."
display "• 2010: fips, totrate, totcng, totadh, evanrate, cathrate, etc."
display "• 2020: fips, TOTRATE_2020, TOTCNG_2020, TOTADH_2020, etc."
display ""
display "All results saved to: $output"
display "================================================================================"


/*==============================================================================
ADDITIONAL FUNCTIONAL FORM SPECIFICATIONS
==============================================================================*/

display ""
display "=== ADDITIONAL FUNCTIONAL FORM SPECIFICATIONS ==="
display ""

eststo clear

/*------------------------------------------------------------------------------
1. PIECE-WISE LINEAR SPECIFICATION (5-YEAR INTERVALS)
------------------------------------------------------------------------------*/

* Create 5-year interval indicators
gen very_early_post = (years_exposure > 0 & years_exposure <= 5)
gen early_post_5yr = (years_exposure > 5 & years_exposure <= 10) 
gen mid_post = (years_exposure > 10 & years_exposure <= 15)
gen late_post_5yr = (years_exposure > 15 & years_exposure <= 20)
gen very_late_post = (years_exposure > 20)

* Piece-wise linear specification for total adherence
reghdfe total_adherents_rate very_early_post early_post_5yr mid_post late_post_5yr very_late_post ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store piecewise_total

* Test joint significance
test very_early_post early_post_5yr mid_post late_post_5yr very_late_post
local p_joint_piecewise = r(p)

* Test for linear trend
test very_early_post = early_post_5yr = mid_post = late_post_5yr = very_late_post
local p_equal_effects = r(p)

display ""
display "Piece-wise specification - Joint significance: p = " %6.4f `p_joint_piecewise'
display "Piece-wise specification - Equal effects test: p = " %6.4f `p_equal_effects'

/*------------------------------------------------------------------------------
2. DIFFERENCED SPECIFICATION
------------------------------------------------------------------------------*/

* Create lagged variables (since we have 3 time periods: 2000, 2010, 2020)
sort county_id year
by county_id: gen lag_total_adherents = total_adherents_rate[_n-1]
by county_id: gen lag_post_treatment = post_treatment[_n-1]

* First difference variables
gen diff_total_adherents = total_adherents_rate - lag_total_adherents
gen diff_post_treatment = post_treatment - lag_post_treatment

* Differenced specification (drops 2000, uses 2010 and 2020)
reghdfe diff_total_adherents diff_post_treatment if year >= 2010 ///
    [aw=population], absorb(year) vce(cluster county_id)
estimates store diff_spec

display ""
display "Differenced specification completed"

/*------------------------------------------------------------------------------
3. LOG SPECIFICATION (HANDLING ZEROS)
------------------------------------------------------------------------------*/

* Log specification with +1 transformation to handle any zeros
gen ln_total_adherents = ln(total_adherents_rate + 1)

reghdfe ln_total_adherents post_treatment ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store log_spec

* Calculate percentage effect
nlcom (pct_effect: (exp(_b[post_treatment]) - 1) * 100)

/*------------------------------------------------------------------------------
4. THRESHOLD SPECIFICATION (NON-LINEAR EXPOSURE)
------------------------------------------------------------------------------*/

* Create exposure threshold dummies
gen exposure_1to5 = (years_exposure >= 1 & years_exposure <= 5)
gen exposure_6to10 = (years_exposure >= 6 & years_exposure <= 10)
gen exposure_11to15 = (years_exposure >= 11 & years_exposure <= 15)
gen exposure_16to20 = (years_exposure >= 16 & years_exposure <= 20)
gen exposure_21plus = (years_exposure >= 21 & !missing(years_exposure))

reghdfe total_adherents_rate exposure_1to5 exposure_6to10 exposure_11to15 exposure_16to20 exposure_21plus ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store threshold_spec

* Test for threshold effects (non-linearity)
test exposure_1to5 = exposure_6to10 = exposure_11to15 = exposure_16to20 = exposure_21plus
local p_threshold = r(p)

display ""
display "Threshold specification - Non-linearity test: p = " %6.4f `p_threshold'

/*------------------------------------------------------------------------------
5. STATE-YEAR FE SPECIFICATION (HIGHLIGHTED RESULT)
------------------------------------------------------------------------------*/

* Re-run the state-year FE specification for emphasis
reghdfe total_adherents_rate post_treatment ///
    [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
estimates store stateyear_emphasized

/*------------------------------------------------------------------------------
6. EXPORT RESULTS
------------------------------------------------------------------------------*/

* Main comparison table
esttab robust_baseline piecewise_total diff_spec log_spec stateyear_emphasized ///
    using "$output/functional_form_comparison.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment very_early_post early_post_5yr mid_post late_post_5yr very_late_post diff_post_treatment) ///
    mtitles("Baseline" "Piece-wise" "Differenced" "Log" "State-Year FE") ///
    title("Functional Form Sensitivity Analysis") ///
    addnotes("Notes: Baseline = binary post-treatment. Piece-wise = 5-year intervals." ///
             "Differenced = first differences (2010, 2020 only). Log = ln(rate+1)." ///
             "State-Year FE adds state-specific time trends.")

* Detailed piece-wise results
esttab piecewise_total threshold_spec ///
    using "$output/nonlinear_exposure_effects.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(very_early_post early_post_5yr mid_post late_post_5yr very_late_post ///
         exposure_1to5 exposure_6to10 exposure_11to15 exposure_16to20 exposure_21plus) ///
    mtitles("5-Year Intervals" "Threshold Dummies") ///
    title("Non-linear Treatment Effects by Exposure Duration") ///
    addnotes("Notes: Tests for non-linear effects of casino exposure duration." ///
             "Reference group is never-treated counties.")

/*------------------------------------------------------------------------------
7. DENOMINATION-SPECIFIC ANALYSIS WITH STATE-YEAR FE
------------------------------------------------------------------------------*/

display ""
display "=== DENOMINATION ANALYSIS WITH STATE-YEAR FE ==="

* Re-run key denomination results with state-year FE
foreach outcome in evangelical_rate catholic_rate mainline_rate southern_baptist_rate {
    reghdfe `outcome' post_treatment ///
        [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
    
    * Create shorter name for estimates storage
    if "`outcome'" == "southern_baptist_rate" {
        estimates store stateyear_sbaptist
    }
    else {
        estimates store stateyear_`outcome'
    }
    
    * Compare with baseline
    estimates restore dd_`outcome'
    local baseline_coef = _b[post_treatment]
    local baseline_se = _se[post_treatment]
    
    * Restore state-year results
    if "`outcome'" == "southern_baptist_rate" {
        estimates restore stateyear_sbaptist
    }
    else {
        estimates restore stateyear_`outcome'
    }
    
    local stateyear_coef = _b[post_treatment]
    local stateyear_se = _se[post_treatment]
    
    display ""
    display "`outcome' comparison:"
    display "  Baseline: " %8.3f `baseline_coef' " (SE: " %6.3f `baseline_se' ")"
    display "  State-Year FE: " %8.3f `stateyear_coef' " (SE: " %6.3f `stateyear_se' ")"
    display "  Difference: " %8.3f `stateyear_coef' - `baseline_coef'
}

* Export denomination comparison
esttab dd_evangelical_rate stateyear_evangelical_rate ///
       dd_catholic_rate stateyear_catholic_rate ///
       dd_mainline_rate stateyear_mainline_rate ///
       dd_southern_baptist_rate stateyear_sbaptist ///
    using "$output/denominations_stateyear_comparison.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mtitles("Evangelical" "Evang+StateYr" "Catholic" "Cath+StateYr" ///
            "Mainline" "Main+StateYr" "S.Baptist" "SB+StateYr") ///
    title("Denomination Effects: Baseline vs State-Year FE") ///
    addnotes("Notes: Comparison of baseline county+year FE vs county+state-year FE." ///
             "State-year FE controls for state-specific religious trends.")

/*------------------------------------------------------------------------------
8. SUMMARY STATISTICS FOR INTERPRETATION
------------------------------------------------------------------------------*/

* Calculate effect sizes as percentage of mean
quietly summarize total_adherents_rate [aw=population]
local mean_adherence = r(mean)

estimates restore stateyear_emphasized
local stateyear_effect = _b[post_treatment]
local pct_effect_stateyear = (`stateyear_effect' / `mean_adherence') * 100

display ""
display "=== EFFECT SIZE INTERPRETATION ==="
display "Mean religious adherence rate: " %8.2f `mean_adherence'
display "State-year FE effect: " %8.2f `stateyear_effect'
display "Effect as % of mean: " %6.2f `pct_effect_stateyear' "%"

/*------------------------------------------------------------------------------
9. DIAGNOSTIC TESTS
------------------------------------------------------------------------------*/

* Test whether state-year FE substantially changes results
estimates restore robust_baseline
local baseline_coef = _b[post_treatment]
estimates restore stateyear_emphasized  
local stateyear_coef = _b[post_treatment]

display ""
display "=== DIAGNOSTIC INTERPRETATION ==="
display "Baseline coefficient: " %8.3f `baseline_coef'
display "State-Year FE coefficient: " %8.3f `stateyear_coef'
display "Ratio (StateYear/Baseline): " %6.2f `stateyear_coef'/`baseline_coef'
display ""
display "This suggests state-level confounding was masking the true effect."
display "States with more casinos may have different baseline religious trends."

display ""
display "=== FUNCTIONAL FORM ANALYSIS COMPLETE ==="

cap log close