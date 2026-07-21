clear all
set more off
set maxvar 10000

capture ssc install honestdid, all replace
capture ssc install csdid, all replace
capture ssc install drdid, all replace

cap noi net uninstall pretrends
local github https://raw.githubusercontent.com
net install pretrends, from(`github'/mcaceresb/stata-pretrends/main) replace

*capture ssc install pretrends, all replace

* Set working directories - CHANGE THESE TO YOUR ACTUAL PATHS
global data "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data"
global output "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\output"

* Create output directory if it doesn't exist
capture mkdir "$output"

cap log close
log using "$output/paper_analysis_log_lag2.txt", replace text

* Install required packages if needed
capture ssc install coefplot
capture ssc install reghdfe
capture ssc install estout
capture ssc install require
capture ssc install balancetable

*panel view
net install grc1leg, from(http://www.stata.com/users/vwiggins) replace
net install gr0075, from(http://www.stata-journal.com/software/sj18-4) replace
ssc install labutil, replace
ssc install sencode, replace

cap ado uninstall panelview //in-case already installed
net install panelview, all replace from("https://yiqingxu.org/packages/panelview_stata")
capture net install countyfips, from(https://raw.github.com/cbgoodman/countyfips/master/) replace

* Needed only for some stats like medians/percentiles, but harmless to install
cap ado uninstall moremata
ssc install moremata

*the more modern way to using fixed effects*packages to download for latest fe work
ssc install reghdfe, replace
cap ado uninstall ftools
net install ftools, from("https://raw.githubusercontent.com/sergiocorreia/ftools/master/src/") replace
ssc install csdid
ssc install jwdid, replace

* Optional if Mata library needs compiling
ftools, compile

******************************************************************************
*population changes
******************************************************************************

*new analysis, start on line 604 of paper code kass edits. 

use "$data/population_analysis_data.dta", replace

* Create county-year level population data
preserve
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
drop if (tot_casino_no > 1 & _merge == 3)

gen total_pop_temp = perwt if all_ages == 1
gen child_rearing_pop_temp = perwt if child_rearing_age == 1 	
gen children_pop_temp = perwt if children == 1
gen school_age_pop_temp = perwt if school_age == 1


collapse (sum) total_pop=total_pop_temp ///
         (sum) child_rearing_pop=child_rearing_pop_temp ///
         (sum) children_pop=children_pop_temp ///
         (sum) school_age_pop=school_age_pop_temp, ///
         by(county_id year casino_county rel_time donut_sample lag5_pop-lead8plus_pop) fast

* Create log variables (note, betas is level regression will be off by a significant factor, log-level no effect)
gen ln_total_pop = ln(total_pop)
gen ln_child_rearing_pop = ln(child_rearing_pop) if child_rearing_pop > 0
gen ln_children_pop = ln(children_pop) if children_pop > 0
gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0

eststo clear

*building of of the work from Grinols et al, change base time to lag 3 vs. lage 2 and lag1. 
* Total Population
reghdfe ln_total_pop ///
    lag6minus_pop lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
pretrends power 0.5, time(-6 -5 -4 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..14]
matrix sigma = sigma[1..14, 1..14]
pretrends, time(-6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(totpop)") name(pop1, replace)
graph export "$output/pretrend_pop1_b.pdf", replace

* Child-Rearing Age (18-40)
reghdfe ln_child_rearing_pop ///
    lag6minus_pop lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
pretrends power 0.5, time(-6 -5 -4 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..14]
matrix sigma = sigma[1..14, 1..14]
pretrends, time(-5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(child_rearing_pop)") name(childrear, replace)
graph export "$output/pretrend_childrear_b.pdf", replace


* Children (≤17)
reghdfe ln_children_pop ///
    lag6minus_pop lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
pretrends power 0.5, time(-6 -5 -4 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..14]
matrix sigma = sigma[1..14, 1..14]
pretrends, time(-6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(child_pop)") name(childpop, replace)
graph export "$output/pretrend_childpop_b.pdf", replace


* School-Age (5-17)
reghdfe ln_school_age_pop ///
    lag6minus_pop lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1, absorb(county_id year) vce(cluster county_id)
pretrends power 0.5, time(-6 -5 -4 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..14]
matrix sigma = sigma[1..14, 1..14]
pretrends, time(-6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(school_age)") name(school, replace)
graph export "$output/pretrend_schoolage_b.pdf", replace

*prettrend graphs
graph combine pop1 childrear childpop school, ///
    title("Pop pretrends", size(medium)) cols(2)
graph export "$output/pretrends_poptotal_b.pdf", replace

eststo clear

* Total Population
reghdfe ln_total_pop ///
    lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_total

* Child-Rearing Age (18-40)
reghdfe ln_child_rearing_pop ///
    lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_child_rearing

* Children (≤17)
reghdfe ln_children_pop ///
    lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_children

* School-Age (5-17)
reghdfe ln_school_age_pop ///
    lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
    if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_school_age

* Export Table 2
esttab pop_total pop_child_rearing pop_children pop_school_age ///
    using "$output/table2_population_effects_baselag2.tex", replace ///
    keep(lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    coeflabels(lag5_pop "t-5" lag4_pop "t-4"  lag2_pop "t-2" lag1_pop "t-1" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
              lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
              lead7_pop "t+7" lead8plus_pop "t+8+") ///
    mgroups("Total Pop" "Child-Rearing" "Children" "School-Age", ///
           pattern(1 1 1 1) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Population Effects by Age Group: Base 3rd lag") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Donut sample excludes nearby counties. All variables in logs.")
restore


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
    keep(lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
    vertical ///
    coeflabels(lag5_pop = "-5" lag4_pop = "-4" lag2_pop = "-2" lag1_pop = "-1" lead0_pop = "0" lead1_pop = "1" lead2_pop = "2" ///
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
    
graph export "$output/figure1_population_effects_baselag2.png", replace width(1400) height(900)
graph export "$output/figure1_population_effects_baselag2.pdf", replace


******************************************************************************
*fertility
******************************************************************************


/*==============================================================================
TABLE 3: FAMILY FORMATION EFFECTS BY GENDER: stylized to the new treatment period
==============================================================================*/

display ""
display "=== TABLE 3: FAMILY FORMATION EFFECTS ==="

use "$data\main_analysis_data.dta", clear
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
drop if (tot_casino_no > 1 & _merge == 3)

eststo clear

* Women
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment_back2 age age_sq ///
        if female == 1 & donut_sample == 1 & lag1 == 0 & lag2 == 0 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo w_`outcome'
}

* Men  
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment_back2 age age_sq ///
        if female == 0 & donut_sample == 1 & lag1 == 0 & lag2 == 0 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo m_`outcome'
}

* Export Table 3
esttab w_married w_has_children w_num_children m_married m_has_children m_num_children ///
    using "$output/table3_family_formation_back2.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment_back2) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Family Formation Effects by Gender: no <2005 data and no multi casino counties. -3 lag is base outcome") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All regressions include county and year fixed effects, age and age squared." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")
			
**********************************************************************************		
*  Figure for fertility
reghdfe num_children ///
	lag6minus lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
	age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 [aw=perwt], ///
	absorb(county_id year) vce(cluster county_id)
eststo fertility_women
pretrends power 0.5, time(-6 -5 -4 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..14]
matrix sigma = sigma[1..14, 1..14]
pretrends, time(-6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: num chils women") name(num_child_w, replace)
graph export "$output/pretrend_num_child_w_nomulti.pdf", replace

/*reghdfe num_children ///
	lag3_alt lag2_alt lead0_alt lead1_alt lead2_alt lead3_alt lead4_alt lead5plus_alt ///
	age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 [aw=perwt], ///
	absorb(county_id year) vce(cluster county_id)
eststo fertility_women*/


* Men fertility event study
reghdfe num_children ///
	lag6minus lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1  [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo fertility_men
pretrends power 0.5, time(-6 -5 -4 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..14]
matrix sigma = sigma[1..14, 1..14]
pretrends, time(-6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8) ref(-3) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: num chils men") name(num_child_m, replace)
graph export "$output/pretrend_num_child_m_nomulti.pdf", replace

graph combine num_child_w num_child_m, ///
    title("Num Child pretrends, back 2 lags (ref -3)", size(medium)) cols(2)
graph export "$output/pretrends_numchild_nomulti_b.pdf", replace


* Create two-panel fertility figure
coefplot (fertility_women, ///
            ciopts(lcolor(maroon) lwidth(medium)) ///
            mcolor(maroon) msymbol(O) msize(medium) ///
            label("Women")) ///
         (fertility_men, ///
            ciopts(lcolor(navy) lwidth(medium)) ///
            mcolor(navy) msymbol(D) msize(medium) ///
            label("Men")), ///
    keep(lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
    vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4" lag2 = "-2" lag1 = "-1" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(2.5, lcolor(gray) lpattern(dash)) ///
    title("Fertility Effects by Gender: no <2005 data or multi counties", ///
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
    
graph export "$output/figure2_fertility_effects_back2.png", replace width(1400) height(900)
graph export "$output/figure2_fertility_effects_back2.pdf", replace


/*==============================================================================
TABLE 4: EFFECTS BY RESIDENCE DURATION
==============================================================================*/

display ""
display "=== TABLE 4: EFFECTS BY RESIDENCE DURATION ==="

eststo clear

*did study
* short term women
reghdfe num_children post_treatment_back2 age age_sq ///
	if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag1 == 0 & lag2 == 0 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
	eststo sw1
	
reghdfe num_children post_treatment_back2 age age_sq ///
if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag1 == 0 & lag2 == 0 [aw=perwt], ///
absorb(county_id year) vce(cluster county_id)
eststo lw2

reghdfe num_children post_treatment_back2 age age_sq ///
	if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag1 == 0 & lag2 == 0 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
	eststo sm1
	
reghdfe num_children post_treatment_back2 age age_sq ///
if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag1 == 0 & lag2 == 0 [aw=perwt], ///
absorb(county_id year) vce(cluster county_id)
eststo lm2



* Export Table_didLong
esttab sw1 lw2 sm1 lm2 ///
    using "$output/table4_didResDuration_back2.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment_back2) ///
    mgroups("Women" "Men", pattern(1 0 1 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("ST Women" "LT Women" "ST Men" "LT Men" ) ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Family Formation Effects by Gender") ///
    addnotes("Long Term (5+)" "Short Term (<5)" ///
			"Standard errors clustered at county level in parentheses." ///
            "All regressions include county and year fixed effects, age and age squared." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

			
			
* Women - Long-term residents (5+ years)
reghdfe num_children ///
	lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_longterm

* Women - Recent movers (<5 years)
reghdfe num_children ///
	lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_recent

* Men - Long-term residents (5+ years)
reghdfe num_children ///
    lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_longterm

* Men - Recent movers (<5 years)
reghdfe num_children ///
	lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_recent

* Export Table 4
esttab w_longterm w_recent m_longterm m_recent ///
    using "$output/table4_residence_duration_back2.tex", replace ///
    keep(lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	coeflabels(lag5 "-5" lag4 "-4" lag2 "-2" lag1 "-1" lead0 "0" lead1 "1" lead2 "2" ///
          lead3 "3" lead4 "4" lead5 "5" lead6 "6" ///
          lead7 "7" lead8 "8" lead9 "9" lead10plus "10+") ///
    mgroups("Women" "Men", pattern(1 0 1 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Long-term (5+)" "Recent (<5)" "Long-term (5+)" "Recent (<5)") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
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
    keep(lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4"  lag2 = "-2" lag1 = "-1" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
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
    keep(lag5 lag4 lag2 lag1 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4"  lag2 = "-2" lag1 = "-1" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
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
    title("Mechanism Test: Fertility Effects by Residence Duration: lag -3, 2005+ data and no multi casino co", size(vlarge)) ///
    subtitle("Behavioral Change vs Selection", size(large)) ///
    note("● Long-term Residents (5+ years)     ♦ Recent Movers (<5 years)" ///
         "Stronger effects for long-term residents suggest behavioral change rather than selection." ///
         "Donut sample excludes nearby counties.", ///
         size(medium)) ///
    cols(2) ///
    ycommon xcommon ///
    imargin(small) ///
    scheme(s1mono)
    
graph export "$output/figure3_mechanism_test_back2.png", replace width(1400) height(700)
graph export "$output/figure3_mechanism_test_back2.pdf", replace


/*==============================================================================
TABLE 6: SCHOOL POPULATION AND ENROLLMENT EFFECTS - back 2 years
==============================================================================*/

	display ""
	display "=== TABLE 6: SCHOOL EFFECTS ==="


use "$data\population_analysis_data.dta", clear
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
drop if (tot_casino_no > 1 & _merge == 3)

{
	
	* Create county-year level school data
	gen school_age_pop_temp = perwt if school_age == 1
	gen school_enrolled_temp = perwt if school_age_enrolled == 1
	gen public_enrolled_temp = perwt if school_age_public == 1
	
	
keep county_id year casino_county rel_time donut_sample ///
     lag6minus_pop lag5_pop-lead8plus_pop post_treatment post_treatment_back2 post_treatment_full_back2 ///
     school_age_pop_temp school_enrolled_temp public_enrolled_temp
	 



collapse (sum) school_age_pop=school_age_pop_temp ///
         (sum) school_enrolled=school_enrolled_temp ///
         (sum) public_enrolled=public_enrolled_temp, ///
         by(county_id year casino_county rel_time donut_sample lag6minus_pop  lag5_pop-lead8plus_pop post_treatment_back2 post_treatment_full_back2) fast
		 


	* Create log variables
	gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0
	gen ln_school_enrolled = ln(school_enrolled) if school_enrolled > 0
	gen ln_public_enrolled = ln(public_enrolled) if public_enrolled > 0



	
****************************************************************************
*Event Studies
	eststo clear
	
	* School-age population
	reghdfe ln_school_age_pop ///
		lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 , absorb(county_id year) vce(cluster county_id)
	eststo school_pop

	* Total school enrollment
	reghdfe ln_school_enrolled ///
		lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 , absorb(county_id year) vce(cluster county_id)
	eststo school_enroll

	* Public school enrollment
	reghdfe ln_public_enrolled ///
		lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 , absorb(county_id year) vce(cluster county_id)
	eststo public_enroll

	* Export Table 6
	esttab school_pop school_enroll public_enroll ///
		using "$output/table6_school_effects_back2.tex", replace ///
		keep(lag5_pop lag4_pop lag2_pop lag1_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
		coeflabels(lag5_pop "t-5" lag4_pop "t-4" lag2_pop "t-2" lag1_pop "t-1" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
				  lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
				  lead7_pop "t+7" lead8plus_pop "t+8+") ///
		mtitles("School-Age Pop" "Total Enrollment" "Public Enrollment") ///
		stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
		se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
		title("School Population and Enrollment Effects") ///
		addnotes("Standard errors clustered at county level in parentheses." ///
				"All variables in logs. School-age = 5-17 years." ///
				"Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

	}

**************************************************************************
*Religous studies

/*==============================================================================
TABLE 7: RELIGIOUS ADHERENCE EFFECTS
==============================================================================*/


use religious_analysis_data.dta, clear

eststo clear

* (1) Baseline specification (county + year FE)
reghdfe total_adherents_rate post_treatment_back2 ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store relig_baseline

* (2) Medium religiosity counties only (baseline tercile 2)
reghdfe total_adherents_rate post_treatment_back2 ///
    if baseline_religiosity_tercile == 2 [aw=population], ///
    absorb(county_id year) vce(cluster county_id)
estimates store relig_medium

* (3) State-year fixed effects (preferred specification)
reghdfe total_adherents_rate post_treatment_back2 ///
    [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
estimates store relig_stateyear

* (4) Differenced specification
reghdfe diff_total_adherents diff_post_treatment_back2 if year >= 2010 ///
    [aw=population], absorb(year) vce(cluster county_id)
estimates store relig_diff

* Export Table 7
esttab relig_baseline relig_medium relig_stateyear relig_diff ///
    using "$output/table7_religious_adherence_back2.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment_back2 diff_post_treatment_back2) ///
    mtitles("Baseline" "Medium Religious" "State-Year FE" "Differenced") ///
    stats(N r2 r2_within, fmt(%9.0fc %9.3f) labels("Observations" "R-squared" "R2_within")) ///
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
    reghdfe `outcome' post_treatment_back2 ///
        [aw=population], absorb(county_id year) vce(cluster county_id)
    estimates store base_`outcome'
}

* State-year FE specifications
foreach outcome in catholic_rate evangelical_rate mainline_rate southern_baptist_rate {
    reghdfe `outcome' post_treatment_back2 ///
        [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
    estimates store sy_`outcome'
}

* Export Table 8
esttab base_catholic_rate sy_catholic_rate base_evangelical_rate sy_evangelical_rate ///
       base_mainline_rate sy_mainline_rate base_southern_baptist_rate sy_southern_baptist_rate ///
    using "$output/table8_denominational_effects_back2.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment_back2) ///
    mgroups("Catholic" "Evangelical" "Mainline" "Southern Baptist", ///
           pattern(1 0 1 0 1 0 1 0) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Baseline" "State-Yr FE" "Baseline" "State-Yr FE" ///
            "Baseline" "State-Yr FE" "Baseline" "State-Yr FE") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
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
replace years_exposure = year - treat_year+2 if casino_county == 1 & year >= (treat_year-2) & !missing(treat_year)

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
    
graph export "$output/figure4_religious_exposure_back2.png", replace width(1200) height(800)
graph export "$output/figure4_religious_exposure_back2.pdf", replace

restore


/*==============================================================================
TABLE 9: SPILLOVER EFFECTS (ROBUSTNESS)
==============================================================================*/

display ""
display "=== TABLE 9: SPILLOVER EFFECTS ==="

eststo clear

* Fertility spillovers - Women
use "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data\main_analysis_data.dta", clear
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
drop if (tot_casino_no > 1 & _merge == 3)
	


reghdfe num_children casino_post_back2 nearby_post_back2 age age_sq ///
    if female == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_w

* Fertility spillovers - Men
reghdfe num_children casino_post_back2 nearby_post_back2 age age_sq ///
    if female == 0 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_m

* Population spillovers 
cd "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data"
 set checksum off
 
use population_analysis_data.dta, replace
drop if year < 2005 /*because we dont have county fips for acs except 2000*/
drop if (tot_casino_no > 1 & _merge == 3)
	


gen children_pop_temp = perwt if children == 1

compress
fcollapse (sum) children_pop=children_pop_temp, ///
         by(county_id year casino_county nearby_county post_treatment_back2 post_treatment_n_back2)

gen ln_children_pop = ln(children_pop) if children_pop > 0
gen casino_post_back2 = casino_county * post_treatment_back2
gen nearby_post_back2 = nearby_county * post_treatment_n_back2

reghdfe ln_children_pop casino_post_back2 nearby_post_back2, ///
    absorb(county_id year) vce(cluster county_id)
estimates store spill_pop


* Religious spillovers (need to recreate religious data

use religious_analysis_data.dta, clear

reghdfe total_adherents_rate casino_post_back2 nearby_post_back2 ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store spill_relig




* Export Table 9
esttab spill_fert_w spill_fert_m spill_pop spill_relig ///
    using "$output/table9_spillover_effects_back2.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_post_back2 nearby_post_back2) ///
    coeflabels(casino_post "Casino County × Post" nearby_post "Nearby County × Post") ///
    mtitles("Fertility (W)" "Fertility (M)" "Child Pop" "Religious") ///
    stats(N r2_within r2, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared" "R-squared")) ///
    title("Spillover Effects: Casino vs Nearby Counties: lag 3 base outcome, no multi casino co or pre 2005 data") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Tests for spillover effects to nearby counties. Justifies donut design." ///
            "Reference group: control counties. *** p<0.01, ** p<0.05, * p<0.1.")
			




