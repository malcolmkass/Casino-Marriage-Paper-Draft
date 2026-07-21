/*This is going thru the pre check of pretrends work, following the Pedro's 10 step
Diff in Diff guide.  So not main results, but prechecks of data

When running this, first check the data from the latest paper code Kass edits file
*/


/*==============================================================================
TABLE 0: Treatment status by Timing group 
==============================================================================*/
*Part 1 of Pedro's checklist


use "$data\main_analysis_data.dta", clear

preserve

*now to drop multi casino counties (kass thinks preferred)
drop if (tot_casino_no > 1 & _merge == 3)
cap drop _merge
drop if year ==.
drop if casino_county !=1
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
countyfips, fips(county_id)

collapse (mean) pt=post_treatment, by(county_name county_id year) fast
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
drop if year ==.
drop if county_name ==""

panelview pt, bytiming i(county_name) t(year) type(treat) ///
xtitle("Year", size(vsmall)) ytitle("County name", size(vsmall)) title("Treatment Status", size(vsmall)) ///
note("no data on Calhoun and Woodbury counties after 2011." ///
"Counties become too unpopulated for ACS reporting", size(vsmall)) 

graph export "$output/figure0_treatment_status.png", replace width(1400) height(900)
graph export "$output/figure0_treatment_status.pdf", replace

restore


*part 2 of pedro did
/*County IDs are a follows
4013 Maricopa, AZ 
6039 Madera, ca
6097 Sonomoa, ca
12011 Broward, fl
12057 hillsborough, fl
19013 blackhawk, ia
19193 Woodbury, IA (sioux city)
20209 Wyandotte, KS
26025 Calhoun, mi (we lose halfway)
36029 Eric, Penn
39049 franklin, ohio
41039 lane co, oregon
53011 Clark, washington
*/


/*Part 3 of Pedro's checklist (unnecessary, will be skipped)
*its a mess:  not worth it: Skip 
{
*Just look at the key variables, population
use "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data\population_analysis_data.dta", clear
preserve
* Create county-year level population data
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
drop if (tot_casino_no > 1 & _merge == 3)
drop if nearby_county == 1
gen total_pop_temp = perwt if all_ages == 1
gen children_pop_temp = perwt if children == 1


collapse (sum) total_pop=total_pop_temp ///
		(sum) children_pop=children_pop_temp, ///
	by(county_id casino_county year treat_year) fast
	
save temp.dta, replace
gen ln_total_pop = ln(total_pop)
replace treat_year = 2023 if treat_year ==.
replace county_id =. if casino_county == 0 

bysort county_id: tab treat_year if casino_county == 1

foreach t in 4013 6039 6097 12011 12057 19013 19193 20209 26025 36029 39049 41039 53011 {
local label = cond(`t' == ., "never treated", "`t' cohort")
local rline = cond(`t' == ., 2023, 2023 )

twoway (line ln_total_pop year if county_id == `t', lcolor(blue) lwidth(medium)) ///
   , ///
   subtitle("`label'") ///
   name(plot_`t', replace) ///
   xline(`rline', lcolor(red) lpattern(dash))
}
   
graph combine plot_4013 plot_6039 plot_6097 plot_12011 plot_12057 plot_19013 plot_19193 plot_20209 plot_26025 plot_36029 plot_39049 plot_41039 plot_53011, ///
    title("Combined Plots of ln of average population by treated county", size(tiny))
	
graph export "./combined_outcomes_bycounty.png", as(png) name("Graph") replace
restore
}
*/

*part 4a

*first, just to see whether we see different pretreatment for population changes
{
use "$data\population_analysis_data.dta", clear
*again, full dataset for 2005
drop if year <2005
drop if (tot_casino_no > 1 & _merge == 3)

* Create county-year level population data
gen total_pop_temp = perwt if all_ages == 1
gen child_rearing_pop_temp = perwt if child_rearing_age == 1
gen children_pop_temp = perwt if children == 1
gen school_age_pop_temp = perwt if school_age == 1

collapse (sum) total_pop=total_pop_temp ///
		 (sum) child_rearing_pop=child_rearing_pop_temp ///
		 (sum) children_pop=children_pop_temp ///
		 (sum) school_age_pop=school_age_pop_temp, ///
		 by(county_id year donut_sample lag6minus_pop lag5_pop-lead8plus_pop post_treatment casino_county) fast

* Create log variables (note, betas is level regression will be off by a significant factor, log-level no effect)
gen ln_total_pop = ln(total_pop)
gen ln_child_rearing_pop = ln(child_rearing_pop) if child_rearing_pop > 0
gen ln_children_pop = ln(children_pop) if children_pop > 0
gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0

*first, quick pretrends test for these regressions...
eststo clear
* Total Population
reghdfe ln_total_pop ///
	casino_co  ///
	if donut_sample == 1  & post_treatment == 0, absorb(year) vce(cluster county_id)
eststo pop_total_pre
* Child-Rearing Age (18-40)
reghdfe ln_child_rearing_pop ///
	casino_co  ///
	if donut_sample == 1 & post_treatment == 0, absorb(year) vce(cluster county_id)
eststo pop_child_rearing_pre
* Children (≤17)
reghdfe ln_children_pop ///
	casino_co  ///
	if donut_sample == 1 & post_treatment == 0, absorb(year) vce(cluster county_id)
eststo pop_children_pre
* School-Age (5-17)
reghdfe ln_school_age_pop ///
	casino_co  ///
	if donut_sample == 1 & post_treatment == 0, absorb(year) vce(cluster county_id)
eststo pop_school_age_pre

* Export Table pretrends test, 
esttab pop_total_pre pop_child_rearing_pre pop_children_pre pop_school_age_pre ///
	using "$output/table_pretrends1_pop_effect_nomulti.tex", replace ///
	keep(casino_county) ///
	coeflabels(casino_county "Casino County") ///
	mgroups("Total Pop" "Child-Rearing" "Children" "School-Age", ///
		   pattern(1 1 1 1) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
	stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
	se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
	title("Pretrend test:") ///
	addnotes("Standard errors clustered at county level in parentheses." ///
			"Donut sample excludes nearby counties. All variables in logs.")
}


*now fertility	
		
use "$data\main_analysis_data.dta", clear
drop if year <2005
drop if (tot_casino_no > 1 & _merge == 3)

eststo clear
		 
* Women
foreach outcome in married has_children num_children {
    reghdfe `outcome' casino_county age age_sq ///
        if female == 1 & donut_sample == 1 & post_treatment == 0 [aw=perwt], ///
        absorb(year) vce(cluster county_id)
    eststo w_`outcome'
}


* Men  
foreach outcome in married has_children num_children {
    reghdfe `outcome' casino_county age age_sq ///
        if female == 0 & donut_sample == 1 & post_treatment == 0 [aw=perwt], ///
        absorb(year) vce(cluster county_id)
    eststo m_`outcome'
}

* Export Table _pretrend
esttab w_married w_has_children w_num_children m_married m_has_children m_num_children ///
    using "$output/table_family_formation_pretrend1.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_county) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Pretrends examination on family formation") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All regressions include year fixed effects, age and age squared. Only pretreatment data included." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

eststo clear
	
*Separating out long and short term	
* Women:short
foreach outcome in married has_children num_children {
    reghdfe `outcome' casino_county age age_sq ///
        if female == 1 & donut_sample == 1 & post_treatment == 0 & longterm_resident == 0 [aw=perwt], ///
        absorb(year) vce(cluster county_id)
    eststo w_`outcome'
}


* Men:short
foreach outcome in married has_children num_children {
    reghdfe `outcome' casino_county age age_sq ///
        if female == 0 & donut_sample == 1 & post_treatment == 0 & longterm_resident == 0 [aw=perwt], ///
        absorb(year) vce(cluster county_id)
    eststo m_`outcome'
}

* Export Table _pretrend
esttab w_married w_has_children w_num_children m_married m_has_children m_num_children ///
    using "$output/table_family_formation_pretrend1_short.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_county) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Pretrends examination on family formation") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All regressions include year fixed effects, age and age squared. Only pretreatment data included." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")
			
* Women:short
foreach outcome in married has_children num_children {
    reghdfe `outcome' casino_county age age_sq ///
        if female == 1 & donut_sample == 1 & post_treatment == 0 & longterm_resident == 0 [aw=perwt], ///
        absorb(year) vce(cluster county_id)
    eststo w_`outcome'
}


* Men:short
foreach outcome in married has_children num_children {
    reghdfe `outcome' casino_county age age_sq ///
        if female == 0 & donut_sample == 1 & post_treatment == 0 & longterm_resident == 0 [aw=perwt], ///
        absorb(year) vce(cluster county_id)
    eststo m_`outcome'
}

* Export Table _pretrend
esttab w_married w_has_children w_num_children m_married m_has_children m_num_children ///
    using "$output/table_family_formation_pretrend1_short.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_county) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Pretrends examination on family formation") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All regressions include year fixed effects, age and age squared. Only pretreatment data included." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")


/*==============================================================================
================================================================================
EXPANDED PRETRENDS / DID DIAGNOSTICS - PEDRO SANT'ANNA's 10-STEP DiD CHECKLIST

  Steps already in this file (above):
     Step 1: Treatment status by timing group (panelview)
     Step 2: Document treated counties (county list with FIPS)
     Step 3: County-level raw outcome trends (skipped per Kass note)
     Step 4a: Initial pretreatment-only level regressions

  Steps added BELOW (per Kass request, May 2026):
     Step 4b: Parallel-trends tests VISUALLY and STATISTICALLY (event-study
              plots + joint F-tests for pre-period coefficients)
     Step 5:  Placebo tests using pre-treatment periods as FAKE treatment dates
     Step 6:  Goodman-Bacon decomposition (diagnose "forbidden comparisons"
              in two-way fixed-effects DiD with staggered timing)
     Step 7:  Modern DiD estimators robust to staggered timing/heterogeneous
              effects:  Callaway-Sant'Anna (csdid), Sun-Abraham
              (eventstudyinteract), Borusyak-Jaravel-Spiess (did_imputation)
     Step 8:  Honest DiD sensitivity analysis (Rambachan-Roth)
     Step 9:  Cohort/heterogeneity diagnostics
     Step 10: Comparison summary across TWFE vs. modern estimators

  UNCERTAINTIES FLAGGED (per project instructions, "flag before guessing"):
  ------------------------------------------------------------------------------
   (a) PLACEBO TIMING SHIFT.  Step 5 uses a fake treatment year shifted
       `placebo_shift' years BEFORE the true treat_year, then drops all
       post-true-treatment rows so only pre-treatment data is used.  Default
       = 3 years; change `local placebo_shift = 3' below if you would prefer
       -5 or another value.
   (b) GOODMAN-BACON requires a strongly-balanced panel of treated/never-
       treated units with a single binary treatment that, once switched on,
       stays on.  Calhoun MI (26025) and Woodbury IA (19193) drop out of
       the ACS in later years; they will be excluded automatically by the
       balanced-panel filter below.  If you prefer to handle these manually,
       edit the code.
   (c) HONESTDID smoothness parameter Mbar is set to a sensitivity grid of
       0, 0.5, 1, 2.  Adjust to match the field convention if needed.
   (d) PATH STYLE.  This file uses "IT Advanced Dropbox" exactly as the
       existing code does, NOT "IT (30) Advanced Dropbox".  If your machine
       path differs, set `local data_path' below.
   (e) PRETREND F-TEST SAMPLE.  In Step 4b the joint F-test for pre-period
       leads is conducted using the same TWFE event-study spec as the main
       paper code (donut_sample == 1, lag6minus(_pop) excluded).  Reference
       period is the year before treatment, i.e. lag1 is the omitted
       indicator (Pedro recommends this; main paper omits lag1 implicitly).
   (f) For csdid / eventstudyinteract, NEVER-TREATED units serve as the
       comparison group.  Counties treated at the start of the sample
       (always-treated) are dropped per CS recommendation.
================================================================================
==============================================================================*/



*--- install required packages if missing -----------------------------------
cap which bacondecomp
if _rc ssc install bacondecomp, replace
cap which csdid
if _rc ssc install csdid, replace
cap which drdid
if _rc ssc install drdid, replace
cap which eventstudyinteract
if _rc ssc install eventstudyinteract, replace
cap which avar
if _rc ssc install avar, replace
*net install did_imputation, from("https://raw.githubusercontent.com/borusyak/did_imputation/master") replace
*net install event_plot, from("https://raw.githubusercontent.com/borusyak/did_imputation/main") replace
cap which honestdid
if _rc {
    local github https://raw.githubusercontent.com
    net install honestdid, from(`github'/mcaceresb/stata-honestdid/main) replace
}
cap which pretrends
if _rc {
    local github https://raw.githubusercontent.com
    net install pretrends, from(`github'/mcaceresb/stata-pretrends/main) replace
}

global data_path "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data"
global placebo_shift = 3

/*==============================================================================
STEP 4b:  TEST PARALLEL TRENDS - VISUALLY AND STATISTICALLY
==============================================================================
  Reproduces the main-paper event-study TWFE regression on the donut sample,
  reports a joint F-test that all PRE-treatment leads = 0 (statistical
  parallel-trends test), and saves coefplots ("visual" test).
  Outcomes: ln(total pop), ln(child-rearing pop), ln(children pop),
            ln(school-age pop) - aggregated to county-year level.
==============================================================================*/

use "$data\population_analysis_data.dta", clear
drop if year < 2005
drop if (tot_casino_no > 1 & _merge == 3)

preserve

* Create county-year level population data (same logic as main paper code)
gen total_pop_temp        = perwt if all_ages == 1
gen child_rearing_pop_temp = perwt if child_rearing_age == 1
gen children_pop_temp     = perwt if children == 1
gen school_age_pop_temp   = perwt if school_age == 1

collapse (sum) total_pop=total_pop_temp ///
         (sum) child_rearing_pop=child_rearing_pop_temp ///
         (sum) children_pop=children_pop_temp ///
         (sum) school_age_pop=school_age_pop_temp, ///
         by(county_id year donut_sample lag6minus_pop lag5_pop-lead8plus_pop ///
            post_treatment casino_county treat_year rel_time) fast

gen ln_total_pop          = ln(total_pop)
gen ln_child_rearing_pop  = ln(child_rearing_pop)  if child_rearing_pop > 0
gen ln_children_pop       = ln(children_pop)        if children_pop > 0
gen ln_school_age_pop     = ln(school_age_pop)      if school_age_pop > 0

save "$data\popcollapsed_for_pretrends.dta", replace

eststo clear

local outcome_list ln_total_pop ln_child_rearing_pop ln_children_pop ln_school_age_pop

* event-study + joint F-test for pre-period leads
local i = 1
foreach y of local outcome_list {
    reghdfe `y' ///
        lag5_pop lag4_pop lag3_pop lag2_pop ///
        lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop ///
        lead5_pop lead6_pop lead7_pop lead8plus_pop ///
        if donut_sample == 1 & lag6minus_pop != 1, ///
        absorb(county_id year) vce(cluster county_id)
    eststo es_`i'

    *--- statistical parallel-trends test: joint F that all PRE leads = 0 ---*
    test lag5_pop lag4_pop lag3_pop lag2_pop
    di as txt _newline "PARALLEL-TRENDS JOINT F-TEST FOR `y':"
    di as txt "   F(`r(df)' , `r(df_r)') = " %6.3f r(F) "   p = " %6.4f r(p)
    estadd scalar pretrend_F = r(F)
    estadd scalar pretrend_p = r(p)
    local i = `i' + 1
}

* Export statistical pretrend test table
esttab es_1 es_2 es_3 es_4 ///
    using "$output/step4b_paralleltrends_Ftest_pop.tex", replace ///
    keep(lag5_pop lag4_pop lag3_pop lag2_pop) ///
    coeflabels(lag5_pop "t-5" lag4_pop "t-4" lag3_pop "t-3" lag2_pop "t-2") ///
    mtitles("Total Pop" "Child-Rearing" "Children" "School-Age") ///
    stats(pretrend_F pretrend_p N r2_within, ///
          fmt(%6.3f %6.4f %9.0fc %9.3f) ///
          labels("Joint F (pre-leads=0)" "p-value" "Observations" "Within R^2")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Step 4b: Statistical parallel-trends test - population outcomes") ///
    addnotes("Joint F-test of H0: lag5=lag4=lag3=lag2=0. SEs clustered at county.")

* Visual parallel-trends test - coefplot of event-study estimates
coefplot (es_1, label("Total Pop") mcolor(navy)        ciopts(lcolor(navy))) ///
         (es_2, label("Child-Rearing") mcolor(maroon)  ciopts(lcolor(maroon))) ///
         (es_3, label("Children") mcolor(forest_green) ciopts(lcolor(forest_green))) ///
         (es_4, label("School-Age") mcolor(orange)     ciopts(lcolor(orange))), ///
    keep(lag5_pop lag4_pop lag3_pop lag2_pop ///
         lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop ///
         lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    vertical ///
    coeflabels(lag5_pop="-5" lag4_pop="-4" lag3_pop="-3" lag2_pop="-2" ///
               lead0_pop="0"  lead1_pop="1"  lead2_pop="2"  lead3_pop="3" ///
               lead4_pop="4"  lead5_pop="5"  lead6_pop="6"  lead7_pop="7" ///
               lead8plus_pop="8+") ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(4.5, lcolor(gray) lpattern(dash)) ///
    title("Step 4b: Visual Parallel-Trends Test - Population") ///
    xtitle("Years Relative to Casino Opening") ///
    ytitle("Coefficient (log pop)") ///
    legend(rows(2) position(6)) ///
    scheme(s1color)
graph export "$output/step4b_parallel_trends_pop.png", replace width(1400) height(900)
graph export "$output/step4b_parallel_trends_pop.pdf", replace

restore


/*==============================================================================
STEP 5:  PLACEBO TESTS - FAKE TREATMENT DATES
==============================================================================
  Build placebo_treat_year = treat_year - `placebo_shift' (default 3),
  restrict to PRE-true-treatment data only, and re-run the main event-study
  spec.  Under parallel trends + no anticipation, placebo coefficients
  should be statistically indistinguishable from zero.
==============================================================================*/

use "$data\popcollapsed_for_pretrends.dta", clear

gen placebo_treat_year = treat_year - 3 if casino_county == 1
gen placebo_rel_time   = year - placebo_treat_year     if casino_county == 1

* Restrict to data BEFORE the true treatment year (so we are testing
* a fake treatment that occurs entirely within the actual pre-period)
keep if year < treat_year | casino_county == 0

* Build placebo event-study indicators (windowed -4..+2 around fake date)
forvalues j = 4(-1)1 {
    gen plac_lag`j' = (placebo_rel_time == -`j') if casino_county == 1
    replace plac_lag`j' = 0 if casino_county == 0
}
gen plac_lead0 = (placebo_rel_time == 0) if casino_county == 1
replace plac_lead0 = 0 if casino_county == 0
forvalues j = 1/2 {
    gen plac_lead`j' = (placebo_rel_time == `j') if casino_county == 1
    replace plac_lead`j' = 0 if casino_county == 0
}

rename ln_child_rearing_pop ln_rear_pop
local outcome_list ln_total_pop ln_rear_pop ln_children_pop ln_school_age_pop
			
eststo clear
foreach outcome in ln_total_pop ln_rear_pop ln_children_pop ln_school_age_pop {
    reghdfe `outcome' plac_lag4 plac_lag3 plac_lag2 ///
                plac_lead0 plac_lead1 plac_lead2 ///
        if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
    eststo placebo_`outcome'
    *--- joint test: fake-treatment leads jointly zero? ---*
    test plac_lead0 plac_lead1 plac_lead2
    estadd scalar placebo_F = r(F)
    estadd scalar placebo_p = r(p)
}


esttab placebo_ln_total_pop  placebo_ln_rear_pop  placebo_ln_children_pop  placebo_ln_school_age_pop ///
    using "$output/step5_placebo_pop.tex", replace ///
    keep(plac_lag3 plac_lag2 plac_lead0 plac_lead1 plac_lead2) ///
    mtitles("Total Pop" "Child-Rearing" "Children" "School-Age") ///
    stats(placebo_F placebo_p N r2_within, fmt(%6.3f %6.4f %9.0fc %9.3f) ///
        labels("F (placebo posts=0)" "p-value" "Obs" "Within R^2")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Step 5: Placebo Event Study (fake treatment = treat_year - 3)") ///
    addnotes("Sample restricted to pre-true-treatment data.  SEs clustered at county.")

coefplot (placebo_ln_total_pop  , label("Total Pop")    mcolor(navy)         ciopts(lcolor(navy))) ///
         (placebo_ln_rear_pop  , label("Child-Rearing") mcolor(maroon)      ciopts(lcolor(maroon))) ///
         (placebo_ln_children_pop  , label("Children")     mcolor(forest_green) ciopts(lcolor(forest_green))) ///
         (placebo_ln_school_age_pop, label("School-Age")   mcolor(orange)       ciopts(lcolor(orange))), ///
    keep(plac_lag3 plac_lag2 plac_lead0 plac_lead1 plac_lead2) ///
    vertical ///
    coeflabels(plac_lag3="-3" plac_lag2="-2" ///
               plac_lead0="0 (fake)" plac_lead1="1" plac_lead2="2") ///
    yline(0, lcolor(gray) lpattern(dash)) xline(3.5, lcolor(gray) lpattern(dash)) ///
    title("Step 5: Placebo Event Study Coefficients") ///
    xtitle("Years Relative to FAKE casino opening (`placebo_shift' yrs early)") ///
    ytitle("Coefficient (log pop)") legend(rows(2) position(6)) scheme(s1color)
graph export "$output/step5_placebo_pop.png", replace width(1400) height(900)
graph export "$output/step5_placebo_pop.pdf", replace


/*-- placebo on FERTILITY (individual-level, mirrors main paper code) --*/
use "$data\main_analysis_data.dta", clear
drop if year < 2005
drop if (tot_casino_no > 1 & _merge == 3)

gen placebo_treat_year = treat_year - 3 if casino_county == 1
gen placebo_post = (year >= placebo_treat_year) if casino_county == 1 & !missing(placebo_treat_year)
replace placebo_post = 0 if casino_county == 0

* keep only pre-true-treatment rows so the placebo is unconfounded
keep if year < treat_year | casino_county == 0

eststo clear
foreach outcome in married has_children num_children {
    reghdfe `outcome' placebo_post age age_sq ///
        if female == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo w_plac_`outcome'

    reghdfe `outcome' placebo_post age age_sq ///
        if female == 0 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo m_plac_`outcome'
}

esttab w_plac_married w_plac_has_children w_plac_num_children ///
       m_plac_married m_plac_has_children m_plac_num_children ///
    using "$output/step5_placebo_family.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(placebo_post) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Obs" "Within R^2")) ///
    title("Step 5: Placebo family-formation regressions (fake treat = treat_year - `placebo_shift')") ///
    addnotes("Placebo treatment timed `placebo_shift' yrs before true open." ///
             "Sample restricted to PRE-true-treatment data.  SEs clustered at county.")


/*==============================================================================
STEP 6:  GOODMAN-BACON DECOMPOSITION
==============================================================================
  Diagnoses how much of the canonical TWFE DiD estimate is driven by
  "forbidden" 2x2 comparisons (later-treated vs. earlier-treated counties
  used as a control).  Requires a balanced panel with a binary, absorbing
  treatment indicator.
==============================================================================*/

use "$data\popcollapsed_for_pretrends.dta", clear

* keep donut sample only
keep if donut_sample == 1

* bacondecomp needs treat_year coded; never-treated => missing
gen byte D = post_treatment
replace D = 0 if missing(D)

* drop counties that aren't observed every year (balanced-panel requirement)
bysort county_id (year): gen yr_count = _N
qui sum year
local min_yr = r(min)
local max_yr = r(max)
local exp_yrs = `max_yr' - `min_yr' + 1
drop if yr_count < `exp_yrs'
drop yr_count

* Once-on-stays-on check (treatment is absorbing)
bysort county_id (year): gen byte D_lag = D[_n-1]
bysort county_id: egen byte ever_switched_back = max(D_lag > D & !missing(D_lag))
drop if ever_switched_back == 1
drop D_lag ever_switched_back

xtset county_id year

foreach y in ln_total_pop ln_child_rearing_pop ln_children_pop ln_school_age_pop {
    di as txt _newline(2) "============================================================"
    di as txt "GOODMAN-BACON DECOMPOSITION FOR: `y'"
    di as txt "============================================================"
    cap bacondecomp `y' D, ddetail
    if _rc {
        di as err "  bacondecomp failed for `y' (code=`_rc'); panel may be unbalanced."
    }
    else {
        * bacondecomp leaves the decomposition graph; export it
        cap graph export "$output/step6_bacon_`y'.png", replace width(1400) height(900)
        cap graph export "$output/step6_bacon_`y'.pdf", replace
    }
}


/*==============================================================================
STEP 7:  MODERN DiD ESTIMATORS
==============================================================================
  (a) Callaway-Sant'Anna (csdid) - never-treated control, doubly-robust
  (b) Sun-Abraham (eventstudyinteract) - cohort-interacted event study
  (c) Borusyak-Jaravel-Spiess (did_imputation) - imputation estimator
  Each is run on log population at the county-year level.
==============================================================================*/

use "$data\popcollapsed_for_pretrends.dta", clear
keep if donut_sample == 1

* csdid requires non-missing treat_year for treated, and 0 for never-treated
gen gvar = treat_year
replace gvar = 0 if casino_county == 0 | missing(treat_year)

* drop always-treated (treat_year <= min(year)) per CS recommendation
qui sum year
local min_yr_csdid = r(min)
drop if gvar > 0 & gvar <= `min_yr_csdid'

xtset county_id year

eststo clear
foreach y in ln_total_pop ln_child_rearing_pop ln_children_pop ln_school_age_pop {

    *---- (7a) Callaway-Sant'Anna ----*
    di as txt _newline "=== Callaway-Sant'Anna for `y' ==="
    cap noi csdid `y', ivar(county_id) time(year) gvar(gvar) ///
        notyet method(dripw) agg(event)
    if !_rc {
        cap estat event, estore(cs_`y')
        cap graph export "$output/step7a_cs_`y'.png", replace width(1400) height(900)
    }

    *---- (7b) Sun-Abraham via eventstudyinteract ----*
    di as txt _newline "=== Sun-Abraham for `y' ==="
    cap drop never_treat
    gen never_treat = (gvar == 0)
    cap noi eventstudyinteract `y' lag5_pop lag4_pop lag3_pop lag2_pop ///
        lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop ///
        lead5_pop lead6_pop lead7_pop lead8plus_pop, ///
        cohort(gvar) control_cohort(never_treat) ///
        absorb(i.county_id i.year) vce(cluster county_id)
    if !_rc {
        matrix b_sa = e(b_iw)
        matrix V_sa = e(V_iw)
        cap eststo sa_`y'
    }

}

* Coefplot comparison: CS vs SA vs BJS for total pop
cap coefplot (cs_ln_total_pop, label("Callaway-Sant'Anna")) ///
             (sa_ln_total_pop, label("Sun-Abraham")) ///
    vertical yline(0, lcolor(gray) lpattern(dash)) ///
    title("Step 7: Modern DiD estimators - ln(total pop)") ///
    xtitle("Event time") ytitle("ATT(e)") legend(rows(1) position(6)) ///
    scheme(s1color)
cap graph export "$output/step7_modern_comparison_totalpop.png", replace width(1400) height(900)


/*==============================================================================
STEP 8:  HONEST DiD (RAMBACHAN-ROTH) SENSITIVITY
==============================================================================
  Bounds the treatment effect under relaxations of strict parallel-trends.
  Two flavors are reported:
     - "Smoothness" restriction (Mbar): post-period trend can deviate by at
       most M times the maximum pre-period trend slope
     - "Relative magnitudes" (Mrel)
==============================================================================*/

use "$data\popcollapsed_for_pretrends.dta", clear
keep if donut_sample == 1

* refit the canonical TWFE event-study for honestdid
reghdfe ln_total_pop ///
    lag5_pop lag4_pop lag3_pop lag2_pop ///
    lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop ///
    lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)

* extract betas/vcov for the 13 event-time coefficients (4 pre, 9 post)
matrix beta_h  = e(b)
matrix beta_h  = beta_h[., 1..13]
matrix sigma_h = e(V)
matrix sigma_h = sigma_h[1..13, 1..13]

di as txt _newline "Honest DiD - smoothness restriction (Mbar grid)"
cap noi honestdid, pre(1/4) post(5/13) mvec(0(0.5)2) ///
    b(beta_h) vcov(sigma_h) coefplot
cap graph export "$output/step8_honestdid_smoothness_totalpop.png", replace width(1400) height(900)

di as txt _newline "Honest DiD - relative-magnitudes restriction"
cap noi honestdid, pre(1/4) post(5/13) mvec(0(0.5)2) ///
    b(beta_h) vcov(sigma_h) delta(rm) coefplot
cap graph export "$output/step8_honestdid_relmag_totalpop.png", replace width(1400) height(900)


/*==============================================================================
STEP 9:  COHORT / HETEROGENEITY DIAGNOSTICS
==============================================================================
  - Cohort-specific ATTs from CS (treatment-effect heterogeneity by cohort)
  - Group-level event studies (men vs. women) on fertility
==============================================================================*/

* (9a) cohort-specific ATTs - aggregation by treatment cohort
use "$data\popcollapsed_for_pretrends.dta", clear
keep if donut_sample == 1
gen gvar = treat_year
replace gvar = 0 if casino_county == 0 | missing(treat_year)
qui sum year
drop if gvar > 0 & gvar <= r(min)

cap csdid ln_total_pop, ivar(county_id) time(year) gvar(gvar) notyet method(dripw) agg(group)
if !_rc {
    cap graph export "$output/step9a_cohortATT_totalpop.png", replace width(1400) height(900)
    cap estat group
}

* (9b) male vs. female fertility event studies (heterogeneity by gender)
use "$data\main_analysis_data.dta", clear
drop if year < 2005
drop if (tot_casino_no > 1 & _merge == 3)

eststo clear
reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo fert_w
test lag5 lag4 lag3 lag2
estadd scalar pretrend_F = r(F)
estadd scalar pretrend_p = r(p)

reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo fert_m
test lag5 lag4 lag3 lag2
estadd scalar pretrend_F = r(F)
estadd scalar pretrend_p = r(p)

esttab fert_w fert_m using "$output/step9b_heterogeneity_fertility.tex", replace ///
    keep(lag5 lag4 lag3 lag2) ///
    mtitles("Women" "Men") ///
    stats(pretrend_F pretrend_p N r2_within, fmt(%6.3f %6.4f %9.0fc %9.3f) ///
        labels("Pre-trend F" "p-value" "Obs" "Within R^2")) ///
    title("Step 9b: Pre-trend heterogeneity by gender (fertility)") ///
    addnotes("Joint F(lag5..lag2 = 0).  SEs clustered at county.")


/*==============================================================================
STEP 10: COMPARISON SUMMARY ACROSS ESTIMATORS
==============================================================================
  Side-by-side: average post-treatment effect (or relevant aggregation)
  from TWFE, CS, BJS for the headline outcome (ln_total_pop).
==============================================================================*/

use "$data\popcollapsed_for_pretrends.dta", clear
keep if donut_sample == 1

* (10a) TWFE binary DiD
eststo clear
reghdfe ln_total_pop post_treatment if lag6minus_pop != 1, ///
    absorb(county_id year) vce(cluster county_id)
eststo twfe_total
scalar twfe_att = _b[post_treatment]

* (10b) Callaway-Sant'Anna simple aggregation
gen gvar = treat_year
replace gvar = 0 if casino_county == 0 | missing(treat_year)
qui sum year
drop if gvar > 0 & gvar <= r(min)

scalar cs_att = .
cap csdid ln_total_pop, ivar(county_id) time(year) gvar(gvar) notyet method(dripw) agg(simple)
if !_rc {
    cap estat simple
    cap matrix CS_simple = r(b)
    cap scalar cs_att = el(CS_simple,1,1)
}

* (10c) BJS imputation - average post-treatment ATT
scalar bjs_att = .
cap did_imputation ln_total_pop, ivar(county_id) tvar(year) gvar(gvar) ///
    cluster(county_id) autosample
if !_rc {
    cap matrix BJS = e(b)
    cap scalar bjs_att = el(BJS,1,1)
}

* tabulate comparison
di as txt _newline(2) "=============================================================="
di as txt "STEP 10:  SUMMARY OF ESTIMATORS FOR ln(total_pop)"
di as txt "=============================================================="
di as txt "  TWFE (post_treatment)            : " %9.4f twfe_att
di as txt "  Callaway-Sant'Anna ATT (simple)  : " %9.4f cs_att
di as txt "  Borusyak-Jaravel-Spiess ATT      : " %9.4f bjs_att
di as txt "=============================================================="
di as txt "If TWFE differs substantially from CS/BJS, this suggests"
di as txt "negative-weighting / forbidden-comparison bias in TWFE."
di as txt "=============================================================="

esttab twfe_total using "$output/step10_estimator_summary.tex", replace ///
    keep(post_treatment) b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("TWFE binary") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Obs" "Within R^2")) ///
    title("Step 10: Estimator comparison - ln(total pop). CS and BJS reported separately in log.") ///
    addnotes("Compare against CS and BJS values printed in the log.")

di as txt _newline "PRETRENDS CHECKLIST COMPLETE.  Outputs saved to: $output"
