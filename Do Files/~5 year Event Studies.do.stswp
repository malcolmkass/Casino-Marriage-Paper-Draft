/*==============================================================================
ALTERNATIVE EVENT STUDY SPECIFICATION WITH 5 POST-PERIODS
==============================================================================*/

/*==============================================================================
CREATE EVENT STUDY VARIABLES WITH 5 POST-PERIODS
==============================================================================*/

* Drop existing event study variables if they exist
capture drop lag3_alt lag2_alt lead0_alt-lead4_alt

* Create alternative event study variables with only 5 post-periods
* Pre-treatment periods (same as before)
forvalues i = 3(-1)2 {
    gen lag`i'_alt = 0  // Start with 0 for everyone (including controls)
    replace lag`i'_alt = 1 if rel_time == -`i' & !missing(rel_time)  // Only treated units get 1
}

* Post-treatment periods (reduced to 5 instead of 10)
forvalues i = 0/4 {
    gen lead`i'_alt = 0  // Start with 0 for everyone (including controls)
    replace lead`i'_alt = 1 if rel_time == `i' & !missing(rel_time)  // Only treated units get 1
}

* Create a 5+ years indicator for periods 5 and beyond
gen lead5plus_alt = 0
replace lead5plus_alt = 1 if rel_time >= 5 & !missing(rel_time)

/*==============================================================================
MAIN EVENT STUDY ANALYSIS WITH 5 POST-PERIODS
==============================================================================*/

display ""
display "=== RUNNING EVENT STUDIES WITH 5 POST-PERIODS ==="

/*==============================================================================
EVENT STUDIES FOR WOMEN - 5 POST-PERIODS
==============================================================================*/

preserve
keep if female == 1

* Marriage event study - 5 periods
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_marriage_women

* Divorce event study - 5 periods
reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_divorce_women

* Children event study - 5 periods
reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_children_women

restore

/*==============================================================================
EVENT STUDIES FOR MEN - 5 POST-PERIODS
==============================================================================*/

preserve
keep if female == 0

* Marriage event study - 5 periods
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_marriage_men

* Divorce event study - 5 periods
reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_divorce_men

* Children event study - 5 periods
reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_children_men

restore

/*==============================================================================
FUNCTION TO CREATE 5-PERIOD EVENT STUDY PLOTS
==============================================================================*/

capture program drop create_event5_plot
program define create_event5_plot
    args est_name outcome gender
    
    estimates restore `est_name'
    
    coefplot, keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
        vertical ///
        coeflabels(lag3_alt = "-3" lag2_alt = "-2" ///
                   lead0_alt = "0" lead1_alt = "1" lead2_alt = "2" ///
                   lead3_alt = "3" lead4_alt = "4" lead5plus_alt = "5+") ///
        yline(0, lcolor(red) lpattern(dash)) ///
        xline(2.5, lcolor(blue) lpattern(dash)) ///
        title("Event Study (5 Periods): Casino Effect on `outcome' - `gender'") ///
        xtitle("Years Relative to Casino Opening") ///
        ytitle("Effect on `outcome'") ///
        graphregion(color(white)) plotregion(color(white)) ///
        note("Note: 5+ represents average effect for years 5 and beyond")
    
    * Export both PNG and PDF versions
    local filename = "event5_study_" + lower(subinstr("`outcome'", " ", "_", .)) + "_" + lower("`gender'")
    graph export "$output/`filename'.png", replace width(1000) height(700)
    graph export "$output/`filename'.pdf", replace
end

/*==============================================================================
CREATE MAIN 5-PERIOD EVENT STUDY PLOTS
==============================================================================*/

create_event5_plot "event5_marriage_women" "Marriage" "Women"
create_event5_plot "event5_divorce_women" "Divorce" "Women"
create_event5_plot "event5_children_women" "Children" "Women"

create_event5_plot "event5_marriage_men" "Marriage" "Men"
create_event5_plot "event5_divorce_men" "Divorce" "Men"
create_event5_plot "event5_children_men" "Children" "Men"

/*==============================================================================
EVENT STUDIES BY AGE GROUP - 5 POST-PERIODS
==============================================================================*/

* Age group event studies for Women - 5 periods
preserve
keep if female == 1

* Ages 18-29 - Women
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_w_1829

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_w_1829

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_w_1829

* Ages 30-40 - Women
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_w_3040

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_w_3040

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_w_3040

restore

* Age group event studies for Men - 5 periods
preserve
keep if female == 0

* Ages 18-29 - Men
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_m_1829

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_m_1829

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_m_1829

* Ages 30-40 - Men
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_m_3040

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_m_3040

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if age_group == 2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_m_3040

restore

* Create age group 5-period event study plots
create_event5_plot "event5_mar_w_1829" "Marriage" "Women_18-29"
create_event5_plot "event5_div_w_1829" "Divorce" "Women_18-29"
create_event5_plot "event5_kid_w_1829" "Children" "Women_18-29"

create_event5_plot "event5_mar_w_3040" "Marriage" "Women_30-40"
create_event5_plot "event5_div_w_3040" "Divorce" "Women_30-40"
create_event5_plot "event5_kid_w_3040" "Children" "Women_30-40"

create_event5_plot "event5_mar_m_1829" "Marriage" "Men_18-29"
create_event5_plot "event5_div_m_1829" "Divorce" "Men_18-29"
create_event5_plot "event5_kid_m_1829" "Children" "Men_18-29"

create_event5_plot "event5_mar_m_3040" "Marriage" "Men_30-40"
create_event5_plot "event5_div_m_3040" "Divorce" "Men_30-40"
create_event5_plot "event5_kid_m_3040" "Children" "Men_30-40"

/*==============================================================================
EVENT STUDIES BY RACE/ETHNICITY - 5 POST-PERIODS
==============================================================================*/

* Race event studies for Women - 5 periods
preserve
keep if female == 1

* White Women
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_w_white

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_w_white

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_w_white

* Black Women
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_w_black

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_w_black

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_w_black

* Hispanic Women
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_w_hisp

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_w_hisp

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_w_hisp

restore

* Race event studies for Men - 5 periods
preserve
keep if female == 0

* White Men
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_m_white

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_m_white

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if white == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_m_white

* Black Men
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_m_black

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_m_black

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if black == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_m_black

* Hispanic Men
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_mar_m_hisp

reghdfe divorced lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_div_m_hisp

reghdfe num_children lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq if hispanic == 1, ///
    absorb(county_id year) vce(cluster county_id)
estimates store event5_kid_m_hisp

restore

* Create race 5-period event study plots
create_event5_plot "event5_mar_w_white" "Marriage" "Women_White"
create_event5_plot "event5_div_w_white" "Divorce" "Women_White"
create_event5_plot "event5_kid_w_white" "Children" "Women_White"

create_event5_plot "event5_mar_w_black" "Marriage" "Women_Black"
create_event5_plot "event5_div_w_black" "Divorce" "Women_Black"
create_event5_plot "event5_kid_w_black" "Children" "Women_Black"

create_event5_plot "event5_mar_w_hisp" "Marriage" "Women_Hispanic"
create_event5_plot "event5_div_w_hisp" "Divorce" "Women_Hispanic"
create_event5_plot "event5_kid_w_hisp" "Children" "Women_Hispanic"

create_event5_plot "event5_mar_m_white" "Marriage" "Men_White"
create_event5_plot "event5_div_m_white" "Divorce" "Men_White"
create_event5_plot "event5_kid_m_white" "Children" "Men_White"

create_event5_plot "event5_mar_m_black" "Marriage" "Men_Black"
create_event5_plot "event5_div_m_black" "Divorce" "Men_Black"
create_event5_plot "event5_kid_m_black" "Children" "Men_Black"

create_event5_plot "event5_mar_m_hisp" "Marriage" "Men_Hispanic"
create_event5_plot "event5_div_m_hisp" "Divorce" "Men_Hispanic"
create_event5_plot "event5_kid_m_hisp" "Children" "Men_Hispanic"

/*==============================================================================
EXPORT 5-PERIOD EVENT STUDY RESULTS TO TABLES
==============================================================================*/

* Export main event study results with 5 post-periods - Women
esttab event5_marriage_women event5_divorce_women event5_children_women using "$output/event5_results_women.tex", ///
    replace label b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
    mtitles("Marriage" "Divorce" "Children") ///
    title("Event Study Results - Women") ///
    booktabs

* Export main event study results with 5 post-periods - Men  
esttab event5_marriage_men event5_divorce_men event5_children_men using "$output/event5_results_men.tex", ///
    replace label b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
    mtitles("Marriage" "Divorce" "Children") ///
    title("Event Study Results - Men") ///
    booktabs
			 
			 
/*==============================================================================
COMPARISON: 10-PERIOD VS 5-PERIOD EVENT STUDIES
==============================================================================*/

display ""
display "=== COMPARISON: 10-PERIOD vs 5-PERIOD EVENT STUDIES ==="

* Compare coefficients for women's marriage (example)
preserve
keep if female == 1

* Original 10-period specification
reghdfe married lag3 lag2 lead0-lead10 age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store compare_10period

* Alternative 5-period specification  
reghdfe married lag3_alt lag2_alt lead0_alt-lead4_alt lead5plus_alt age age_sq, absorb(county_id year) vce(cluster county_id)
estimates store compare_5period

* Export comparison table
esttab compare_10period compare_5period using "$output/comparison_10vs5_periods.tex", ///
    replace label se(%9.4f) b(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(lag3* lag2* lead0* lead1* lead2* lead3* lead4* lead5*) ///
    mtitles("10 Post-Periods" "5 Post-Periods") ///
    title("Comparison: 10-Period vs 5-Period Event Study - Women's Marriage") ///
    booktabs nonotes ///
    addnotes("Notes: Comparison of event study specifications for marriage among women." ///
             "Left column shows individual coefficients for years 0-10 post-treatment." ///
             "Right column shows individual coefficients for years 0-4, plus average for 5+." ///
             "Standard errors clustered at county level. *** p<0.01, ** p<0.05, * p<0.1.")

restore

/*==============================================================================
COMBINED PLOTS: SIDE-BY-SIDE COMPARISON
==============================================================================*/

capture program drop create_combined_plot
program define create_combined_plot
    args est10 est5 outcome gender
    
    * Create combined plot showing both specifications
    estimates restore `est10'
    coefplot, keep(lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10) ///
        vertical name(plot10, replace) ///
        coeflabels(lag3 = "-3" lag2 = "-2" ///
                   lead0 = "0" lead1 = "1" lead2 = "2" lead3 = "3" lead4 = "4" ///
                   lead5 = "5" lead6 = "6" lead7 = "7" lead8 = "8" lead9 = "9" lead10 = "10") ///
        yline(0, lcolor(red) lpattern(dash)) ///
        xline(2.5, lcolor(blue) lpattern(dash)) ///
        title("10-Period Specification") ///
        xtitle("Years Relative to Casino Opening") ///
        ytitle("Effect on `outcome'") ///
        graphregion(color(white)) plotregion(color(white))
    
    estimates restore `est5'
    coefplot, keep(lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt) ///
        vertical name(plot5, replace) ///
        coeflabels(lag3_alt = "-3" lag2_alt = "-2" ///
                   lead0_alt = "0" lead1_alt = "1" lead2_alt = "2" ///
                   lead3_alt = "3" lead4_alt = "4" lead5plus_alt = "5+") ///
        yline(0, lcolor(red) lpattern(dash)) ///
        xline(2.5, lcolor(blue) lpattern(dash)) ///
        title("5-Period Specification") ///
        xtitle("Years Relative to Casino Opening") ///
        ytitle("Effect on `outcome'") ///
        graphregion(color(white)) plotregion(color(white))
    
    * Combine the plots
    graph combine plot10 plot5, ///
        title("Event Study Comparison: `outcome' - `gender'") ///
        subtitle("10-Period vs 5-Period Specifications") ///
        graphregion(color(white)) plotregion(color(white)) ///
        note("Note: 5+ in right panel represents average effect for years 5 and beyond")
    
    * Export combined plot
    local filename = "combined_event_study_" + lower(subinstr("`outcome'", " ", "_", .)) + "_" + lower("`gender'")
    graph export "$output/`filename'.png", replace width(1400) height(700)
    graph export "$output/`filename'.pdf", replace
end

* Create combined plots for main outcomes
create_combined_plot "event_marriage_women" "event5_marriage_women" "Marriage" "Women"
create_combined_plot "event_divorce_women" "event5_divorce_women" "Divorce" "Women"
create_combined_plot "event_children_women" "event5_children_women" "Children" "Women"

create_combined_plot "event_marriage_men" "event5_marriage_men" "Marriage" "Men"
create_combined_plot "event_divorce_men" "event5_divorce_men" "Divorce" "Men"
create_combined_plot "event_children_men" "event5_children_men" "Children" "Men"

/*==============================================================================
DISPLAY COMPLETION MESSAGE
==============================================================================*/

display ""
display "=== 5-PERIOD EVENT STUDY ANALYSIS COMPLETE ==="
display ""
display "Created alternative event study specification with:"
display "  • 2 pre-treatment periods (t-3, t-2)"
display "  • 5 individual post-treatment periods (t=0, t+1, t+2, t+3, t+4)"
display "  • 1 aggregated long-term period (t+5+)"
display ""
display "Generated files:"
display "  • 36 event study plots with 5-period specification"
display "  • Event study results tables (5-period version)"
display "  • Comparison table: 10-period vs 5-period specifications"
display "  • 6 combined plots showing both specifications side-by-side"
display ""
display "Benefits of 5-period specification:"
display "  • More statistical power (fewer parameters to estimate)"
display "  • Cleaner plots with less noise"
display "  • Focus on short-to-medium term effects"
display "  • Long-term effects captured in 5+ coefficient"
display ""
display "All 5-period results saved to: $output"
display "Filenames include 'event5_' prefix to distinguish from 10-period version"