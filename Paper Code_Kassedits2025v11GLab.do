/*Version 11:   Moving items to the proper folders for John.  Adding more text to make sure we describe our 
resulsts as the ATUT vs. ATE, which I would argue is what we want*/

/*Version 10:   Updates are minimal, but remove the pre_2003 restriction, but some key details about
the casino data to pass along.  At this point, some trouble with our control counties, I am not sure what
to do about this, other that we probably need some covariates for the more advanced methods, mainly to add weights
to the casinos more closely related to our control counties.  I don't want to add covariates, but 
I am not sure how to get around this issue

So some thoughts here.  Right now, I am mainly adjusting our treated counties to be more similar to our
control counties, so we can at least pick up a ATUT*/

/*version 9:  Clean up relative to 8, most significant change is that for 
counties will multiple instances of casinos or classified as nearby are now
denoted as casino counties.  This only matters where expanding the analysis
beyond the tabla rasa counties*/


 
/*==============================================================================
COMPLETE PAPER ANALYSIS: CASINO EFFECTS ON FAMILY AND COMMUNITY INSTITUTIONS
Creates all tables and figures for paper in sequence
==============================================================================*/

*****************************************************************************
*****************************************************************************
*Points of emphasis for John will have two lines top and bottom
*****************************************************************************
*****************************************************************************

clear all
set more off
set maxvar 10000


* Set working directories - CHANGE THESE TO YOUR ACTUAL PATHS
global data "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data"
global output "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\output"

* Create output directory if it doesn't exist
capture mkdir "$output"

cap log close
log using "$output/paper_analysis_log.txt", replace text

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

*fcollapse
cap ado uninstall ftools
ssc install ftools

* Needed only for some stats like medians/percentiles, but harmless to install
cap ado uninstall moremata
ssc install moremata

* Optional if Mata library needs compiling
ftools, compile	

*pretrends
cap noi net uninstall pretrends
local github https://raw.githubusercontent.com
net install pretrends, from(`github'/mcaceresb/stata-pretrends/main) replace

/*==============================================================================
PART 0: Kass facts
==============================================================================*/
/*Key points from our data:

 
May 26
1. The big, big change was another fix for our casino county sournces dataset, the tabula rasa casino csv file. Enough fixes were necessary to alter the results somewhat. 
2. Our missing data problem with the ACS still exists.  First, pre 2005 data we really cannot fix via using the nhgis data because county level data still was avialable pre 2005, except
for the decenntial data from 2000
2. if we allow for the dataset to include new casinos in counties even if a casino existed pre 2003, there are still some issues with our treated counties.  There are two counties, Woodbury in Iowa (Sioux City) 
and Calhoun co in michigan where we only have partial data because at some point, these counties did not meet the population threshold to be counted.  Numerous control and nearby counties have the same issues.  Here
The nhgis data can be very benefical.  This is what I am working on now. 
3. Problm with the nhgis data is fertility, I cannot get the same/similar fertility measures as I could in the ACS data. 
4. M resort in Henderson was misidentifies as in Northern Nevada, with the other vegas casinos. Since there are many multi vegas casinos
already, decided to just cut the data since it is already account for as a multi casino. (Earlier I removed a detroit casino, but that was a mistake, it should be there) 


April 26
1.  While there are 9 total "new" casino counties, because we dont have county identifiers
beyond 2005, except for 2000, we have had some very add results when it comes to our event
studies.  We were finding very high, and generally strange values for the 3rd lag with our population
and fertility diff in diff event studies.  The reason is that 2 of our more populated casino 
counties opened in 2003, so 3 years is the lag.  When you eliminate the <2005 data
except for the religious data, then this results is mitigated, but the overall result
still hold. 
2. Calhoun county in Michigan had a geoid up to 2011, but lost this identification in 2012, 
and the county it was merged to is not avialable in our ACS data (there is no 26015, just a few
years of 25025, calhoun)
3.Relating to 1, note that 3 new casino counties are now ALWAYS TREATED, instead of a staggered
treatment timing. 
4. Given other research, the idea of using the 3rd lag the treatment time is in the TreatmentTimingV2 file. 

*/
	

/*==============================================================================
PART I: DATA PREPARATION
==============================================================================*/

display ""
display "=============================================================="
display "=== PART I: DATA PREPARATION ==="
display "=============================================================="

/*==============================================================================
1. LOAD AND PREPARE CASINO DATA - INCLUDING NEARBY COUNTIES
==============================================================================*/

*import delimited "$data\casino_specific_data_V2_cleaned.csv", clear 
*the above is the cleaned version of the initial casino file (without added adjacent counties)
import delimited "$data\counties_enriched_v5.csv", clear 
*the above is the cleaned version of the FULL casino file (with added adjacent counties for Chat agent)

*for the new variables
cap la var pre2003casino_cas_co_only "binary: if a casino existed in the casino county pre 2003"
cap la var pre2003_casino_near_co "binary: if a casino existed in the casino OR a near county pre 2003"
*note that pre2003_casino_near_co is more strict
cap la var source_base_geoid "code for the casino county location for a new casino"
cap gen county_geoid = gestfips*1000+gtco
la var county_geoid "the specific county fips code"
la var tot_casino_no "The total new casino openings for that country, counting instances of new casino and near occurances"
la var casino_no  "A running count of new casino openings for that country, counting instances of new casino and near occurances"

*use "$data\casino_data.dta", clear
gen county_id = county_geoid
gen casino_county = (casino_co == 1)
gen nearby_county = (near_co == 1)
gen treat_year = tuyear
cap drop added_by_agent 

*Paper comments. 
tab casino_name
display r(r)
tab casino_name if tot_casino_no == 1
display r(r)

*******************************************************************************
*****************************************************************************
*Key: part 1
* Clean treatment year
bysort county_id: egen min_treat_year = min(treat_year) if casino_county == 1
bysort county_id: egen treat_year_clean = max(min_treat_year)
replace treat_year = treat_year_clean if casino_county == 1
drop min_treat_year treat_year_clean
*the above is John's way to make sure the treat year is the minimum year
*note that here, the nearby counties do not do thru this process, only the casino_counties
*so when you do the nearby county work, this will need to be taken into account
*******************************************************************************
*******************************************************************************


* Keep necessary variables
keep casino_name location county_id tuyear gestfips gtco treat_year casino_no casino_county nearby_county county_geoid tot_casino_no casino_no pre2003casino_cas_co_only pre2003_casino_near_co
rename tuyear year
*duplicates drop county_id year, force 
/*Above, John is trying to eliminated multiple casino and near counties at the same time,
better to loop back.  For now, I am just going proceed with the full dataset to make 
sure multiple casino and the near counties info are eliminated. */

* Create balanced panel
/*ok, so this is a possible problem because we have counties with multiple locations right now
so when expanded, you get an odd situtation. And remember that the nearby counties are very much a mess
because of overlap between nearby counties and casino counties.  the treat year as the min treat year
only holds for casino counties */

*keep county_id year
expand 24
bysort casino_name county_id: replace year = 1999 + _n
keep if year >= 2000 & year <= 2023
*Just expanding the casino dataset to cover the span of the data, again, just the same as before
*duplicates drop county_id year, force

*OK, there is an issue here....
* Generate treatment variables
gen treated = casino_county
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
gen post_treatment_back2 = ((year+2) >= treat_year) if casino_county == 1 & !missing(treat_year)
*here, it is just indicator for post_treatment
replace post_treatment = 0 if casino_county == 0
replace post_treatment_back2 = 0 if casino_county == 0
*so casino_county = 1 if year is after casino location, but zero for near and pre casino years
gen treat_post = treated * post_treatment
gen treat_post_back2 = treated * post_treatment_back2
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)
gen rel_time_back2 = year - (treat_year-2) if casino_county == 1 & !missing(treat_year)
la var rel_time "No. years bw treatment year and current year"

*******************************************************************************
*******************************************************************************
*so this is just a nearby county measure, but you may have multiple treat years here. 
gen post_treatment_n = (year >= treat_year) if nearby_county == 1 & !missing(treat_year)
bysort county_id: tab treat_year
*when you run the above code, you have nearby counties will multiple treat years
*and some nearby counties are also casino counties.
gen post_treatment_back2_n = ((year+2) >= treat_year) if nearby_county == 1 & !missing(treat_year)
la var post_treatment_back2_n "treatment back for two years, nearby counties"  
replace post_treatment_n = 0 if nearby_county == 0
replace post_treatment_back2_n = 0 if nearby_county == 0
gen rel_time_n = year - treat_year if nearby_county == 1 & !missing(treat_year)
gen rel_time_back2_n = year - (treat_year-2) if nearby_county == 1 & !missing(treat_year)
la var rel_time_back2_n "no. years bw treatment back two years for nearby counties"
*******************************************************************************
*******************************************************************************

* Create county-level info file
gen casino_count = casino_no
preserve
	keep county_id treat_year gestfips gtco casino_no casino_county nearby_county county_geoid ///
	tot_casino_no casino_no casino_count year
	bysort county_id: egen max_casino_no = max(tot_casino_no)
	*max_casino_no is the same as tot_casino_no
	replace casino_no = max_casino_no
	drop max_casino_no
	*ok, so casino_no is now tot_casino_no vs.  a count
	bysort county_id: egen max_casino_county = max(casino_county)
	bysort county_id: egen max_nearby_county = max(nearby_county) if casino_county == 0

********************************************************************************
/*OK, so this is different, because some casino_county for a given year (new casino)
	here also a near county as well, but I am not sure this is good info here because
	now you are conflating casino with near counties and visa versa
	
	Im going to skip the next 3 lines because of this reason.  I will keep the max variables
	replace casino_county = max_casino_county
	replace nearby_county = max_nearby_county
	drop max_casino_county max_nearby_county
	
	Kass, you eliminate these extra lines later, with the virgin dataset
	*/
*********************************************************************************
gsort county_id -casino_county year
duplicates drop county_id, force
*counties that are both casino and nearby are denoted as casino counties
	save county_info.dta, replace
	*I hate to do this, but I can't get the location sharing to work on the desktop in gorman
	tempfile county_info
	save `county_info'
restore

*****************************************************************************

*Now eliminating duplicate counties, where counties that were nearby and casino are default casino
gsort county_id -casino_county year
duplicates drop county_id year, force 

* Merge county info back (I don't think this is necessary.)
*merge m:1 county_id using `county_info', keep(match) nogen
merge m:1 county_id using county_info.dta, keep(match) nogen

* Generate treatment variables for balanced panel: dont forget about the nearby county issues. 
gen treated_full = casino_county
gen treated_full_n = nearby_county
gen post_treatment_full = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
gen post_treatment_full_back2 = ((year+2) >= treat_year) if casino_county == 1 & !missing(treat_year)
gen post_treatment_full_n = (year >= treat_year) if nearby_county == 1 & !missing(treat_year)
gen post_treatment_full_back2_n = ((year+2) >= treat_year) if nearby_county == 1 & !missing(treat_year)
*for casino counties, the years after the new casino
replace post_treatment_full = 0 if casino_county == 0
replace post_treatment_full_back2 = 0 if casino_county == 0
gen treat_post_full = treated_full * post_treatment_full
gen treat_post_full_back2 = treated_full * post_treatment_full_back2
* post_treatment_full and treat_post_full are the same
la var treat_post_full "Binary for casino county and after casino founded"
la var treat_post_full_back2 "Binary for casino county and two years before after casino founded"
gen rel_time_full = year - treat_year if casino_county == 1 & !missing(treat_year)
gen rel_time_full_back2 = year - treat_year-2 if casino_county == 1 & !missing(treat_year)
*for nearby counties, the years after the new casino
replace post_treatment_full_n = 0 if nearby_county == 0
replace post_treatment_full_back2_n = 0 if nearby_county == 0
gen treat_post_full_n = treated_full_n * post_treatment_full_n
gen treat_post_full_back2_n = treated_full_n * post_treatment_full_back2_n
* post_treatment_full and treat_post_full are the same

gen rel_time_full_n = year - treat_year if nearby_county == 1 & !missing(treat_year)
gen rel_time_full_back2_n = (year - (treat_year-2)) if nearby_county == 1 & !missing(treat_year)

save "$data\casino_clean.dta", replace

tempfile casino_clean
save `casino_clean'

/*Much larger dataset, tot_casino_no is to capture counties with multiple casino instances
while casino_count is the running total*/

/*==============================================================================
2. LOAD AND PREPARE ACS DATA
==============================================================================*/

use "$data\ACSData.dta", clear
*the above file is too big for Github
keep if year >= 2000 & year <= 2023
gen county_id = statefip * 1000 + countyfip

*Calhoun county problem lose this fips after 2012, but keep near counties Kalamozoo and Jackson, 75 and 77 (these should be nearby_counties)
tab county_id if county_id == 26015
tab county_id if county_id == 26025

*****************************************************************************
*OK, COUNTY FIPS DO NOT EXIST FOR YEARS 2001 TO 2004, THEY START AGAIN IN 2025
****************************************************************************
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

* Create residence duration variables
gen acs_sample = 1
replace acs_sample = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)
la var acs_sample "if acs data later than 2000"

sort sample serial
by sample serial: egen movedin_hh = max(movedin)
gen longterm_resident = (movedin_hh >= 4) if !missing(movedin_hh)

* Keep relevant variables
keep county_id year married divorced widowed never_married newly_married ///
	 has_children num_children female age age_sq white black hispanic migrate1 ///
	 perwt statefip countyfip age_group longterm_resident acs_sample labforce empstat

/*==============================================================================
3. MERGE DATASETS AND CREATE CONTROL GROUP
==============================================================================*/

*merge m:1 county_id year using `casino_clean'
merge m:1 county_id year using "$data\casino_clean.dta"

************************************************************
************************************************************
*significant clean up of the casino counties and ACS data
*mainly large cities separate from the surronding county, will classify as the surronding county

*Need to combine Horse Casino Baltimore into Baltimore city and County
replace county_id = 24005 if county_id == 24510
*same for st louis
replace county_id = 29189 if county_id == 29510
*wichita
replace county_id = 20173 if county_id == 20191
*shreveport
replace county_id = 22015 if county_id == 22017

************************************************************
************************************************************

* Create sample type indicator
gen sample_type = 1 if casino_county == 1
*if county was EVER as casino location
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
*if county was EVER ONLY a nearby_county (to be removed except for spillover analysis)
replace sample_type = 3 if _merge == 1
*The ACS counties that are not present in the casino data (these are the control counties)

* Keep all observations
keep if sample_type >= 1 & sample_type <= 3

* Fill in missing values for unmatched observations
replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
gen control_county = 0
replace control_county = 1 if _merge == 1

*only dropping unmatched obs from casino.dta (some very low pop counties in casino dataset, but not in ACSData)

drop if _merge == 2
tab year

/*==============================================================================
3b. NOW, WE NEED TO TRIM THE DATA into useable forms

Defination of Trim:  Before you run the following code, each county is either
casino, nearby, or control. Note, that counties that were casino counties and nearby
counties are classified as casino counties.  The first instance of the casino county 
(if only ever a casino county) is the min treat_year. Same for nearby.  For those 
countys that were both casino and nearby at one time, this is again at the first
casino opening as a casino county. data from 2000-2023

1. virgin1, include all counties with a new casino, even with a preexisting casino or followup casinos
	remember that treat_year is the earliest year
==============================================================================*/
save "$data/virgin1.dta", replace


*********************************************************************************
*duplicate check
bysort year county_id location: gen run = _n
preserve
drop if run >1 
duplicates report county_id year
tab year
restore

*================================================================================

*start with the full dataset. 
use virgin1.dta, clear

* Generate treatment variables
*n mean nearby county
cap drop treated rel_time post_treatment ever_treated
gen ever_treated = casino_county
replace treated = casino_county
gen treated_n = nearby_county
replace post_treatment_full = 0 if missing(post_treatment_full)
replace post_treatment_full_back2 = 0 if missing(post_treatment_full_back2)
replace post_treatment = post_treatment_full
replace post_treatment_back2 = post_treatment_full_back2

replace post_treatment_full_n = 0 if missing(post_treatment_full_n)
replace post_treatment_full_back2_n = 0 if missing(post_treatment_full_back2_n)
replace post_treatment_n = post_treatment_full_n
replace post_treatment_back2_n = post_treatment_full_back2_n

replace treat_post = treated * post_treatment
replace treat_post_back2 = treated * post_treatment_back2
gen treat_post_n = treated_n * post_treatment_n
gen treat_post_back2_n = treated_n * post_treatment_back2_n
replace rel_time = rel_time_full

* Replace missing values
replace casino_no = 0 if missing(casino_no)
replace treated_full = 0 if missing(treated_full)
replace treat_post_full = 0 if missing(treat_post_full)
replace rel_time_full = . if missing(rel_time_full)

***


/*==============================================================================
CREATE EVENT STUDY VARIABLES
==============================================================================*/
*note, rel_time and rel_time_full are the same

* Create event study indicators
forvalues i = 5(-1)1 {
	gen lag`i' = 0
	replace lag`i' = 1 if rel_time == -`i' & !missing(rel_time)
}
*for here, this is only creating the 2nd and 3rd lags, nothing more
gen lag6minus = 0
replace lag6minus = 1 if rel_time <= -6 & !missing(rel_time)

forvalues i = 0/9 {
	gen lead`i' = 0
	replace lead`i' = 1 if rel_time == `i' & !missing(rel_time)
}
*only creating leads up to 10
gen lead10plus = 0
replace lead10plus = 1 if rel_time >= 10 & !missing(rel_time)



* Alternative event study specification
forvalues i = 3(-1)2 {
	gen lag`i'_alt = 0
	replace lag`i'_alt = 1 if rel_time == -`i' & !missing(rel_time)
}
*Alt lags are the same as lag

gen lag4minus_alt = 0
replace lag4minus_alt = 1 if rel_time <= -4 & !missing(rel_time)

forvalues i = 0/4 {
	gen lead`i'_alt = 0
	replace lead`i'_alt = 1 if rel_time == `i' & !missing(rel_time)
}
*alt leads are different because they only go up to lead5alt

gen lead5plus_alt = 0
replace lead5plus_alt = 1 if rel_time >= 5 & !missing(rel_time)
*la var lead5plus_alt "lead 5 and beyond leads"

/*==============================================================================
SPILLOVER ANALYSIS SETUP
==============================================================================*/

display ""
display "=== SETTING UP SPILLOVER ANALYSIS ==="

gen post = post_treatment
gen post_back2 = post_treatment_back2
gen post_n = post_treatment_n
gen post_back2_n = post_treatment_back2_n
label var post "Post-treatment period binary"

gen casino_post = casino_county * post
gen nearby_post = nearby_county * post_n
gen casino_post_back2 = casino_county * post_back2
gen nearby_post_back2 = nearby_county * post_back2_n
label var casino_post "Casino County × Post"
label var nearby_post "Nearby County × Post"
la var casino_post "1 if casino co after casino opened"
*post means these this is 1 when the casino opened, not before. 

/*==============================================================================
DONUT DESIGN ANALYSIS
==============================================================================*/

display ""
display "=== DONUT DESIGN ANALYSIS ==="

* Create donut sample indicator
*gen donut_sample = ((sample_type == 1 | sample_type == 3) & near_county == 0)
gen donut_sample = ((sample_type == 1 | sample_type == 3) & nearby_county == 0)
tab donut_sample
label var donut_sample "Donut Sample (Casino + Far Counties), no Near"
*donut_sample, looks good!



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
la var young_casino_post "if person is young parent in a casino co after casino opened"
la var older_casino_post "if person is old parent in a casino co after casino opened"
*these two variable are to determine whether young 18-30 or old 31-40 as younger
*or older parents, smart to do this




/*==============================================================================
PREPARE MIGRATION VARIABLES
==============================================================================*/

* Create migration indicators
*I dont know def of migrate1, but this must be differnet classes
gen stayer = (migrate1 == 1) if migrate1 >= 1 & migrate1 <= 4
la var stayer "didn't move in last 4 years"
gen mover = (migrate1 >= 2 & migrate1 <= 4) if migrate1 >= 1 & migrate1 <= 4
la var mover "moved in last 4 years"
gen mover_within_state = (migrate1 == 2) if migrate1 >= 1 & migrate1 <= 4
gen mover_between_states = (migrate1 == 3) if migrate1 >= 1 & migrate1 <= 4

* Create interaction variables
gen stayer_post = stayer * post_treatment
la var stayer_post "stayer who stayed in casino co after casino opened"
gen mover_post = mover * post_treatment
la var mover_post  "mover (in last 4 years) in casino co after casino opened"
*stayer who stayed in casino co after casino opened. 4 years cutoff

* For donut sample interactions
gen stayer_donut = stayer if donut_sample == 1
gen mover_donut = mover if donut_sample == 1

*******************************************************************************
*cleanup for main_analysis_data
*drop missing county_id
*drop if county_id ==.

*save `main_analysis_data'
save "$data\main_analysis_data.dta", replace



/*------------------------------------------------------------------------------
3. PREPARE POPULATION ANALYSIS DATASET (ALL AGES) - EXACT MATCH
------------------------------------------------------------------------------*/


use "$data\ACSData.dta", clear
keep if year >= 2000 & year <= 2023
gen county_id = statefip * 1000 + countyfip
*AGAIN, MISSING 2001 TO 2004 COUNTYFIPS

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
	 perwt statefip countyfip age school schltype labforce empstat


* Merge with casino data
merge m:1 county_id year using "$data\casino_clean.dta"

************************************************************
************************************************************
*significant clean up of the casino counties and ACS data
*mainly large cities separate from the surronding county, will classify as the surronding county

*Need to combine Horse Casino Baltimore into Baltimore city and County
replace county_id = 24005 if county_id == 24510
*same for st louis
replace county_id = 29189 if county_id == 29510
*wichita
replace county_id = 20173 if county_id == 20191
*shreveport
replace county_id = 22015 if county_id == 22017

************************************************************
************************************************************


* Create sample type indicator
gen sample_type = 1 if casino_county == 1
*if county was EVER as casino location
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
*if county was EVER ONLY a nearby_county (to be removed except for spillover analysis)
replace sample_type = 3 if _merge == 1
*The ACS counties that are not present in the casino data (these are the control counties)

* Keep all observations
keep if sample_type >= 1 & sample_type <= 3

* Fill in missing values for unmatched observations
replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
gen control_county = 0
replace control_county = 1 if _merge == 1

*only dropping unmatched obs from casino.dta (some very low pop counties in casino dataset, but not in ACSData)
drop if _merge == 2


/*==============================================================================
3b. NOW, WE NEED TO TRIM THE DATA TO THE MOST USABLE FORM...
==============================================================================*/

* Create donut sample indicator
gen donut_sample = (sample_type == 1 | sample_type == 3)

* Generate treatment variables
cap drop post_treatment
cap drop post_treatment_n
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
gen post_treatment_n = (year >= treat_year) if nearby_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0
replace post_treatment_n = 0 if nearby_county == 0
cap drop rel_time
cap drop rel_time_n
gen rel_time = year - treat_year if casino_county == 1 & !missing(treat_year)
gen rel_time_n = year - treat_year if nearby_county == 1 & !missing(treat_year)

cap drop post_treatment_back2
cap drop post_treatment_n_back2
gen post_treatment_back2 = (year >= treat_year-2) if casino_county == 1 & !missing(treat_year)
gen post_treatment_n_back2 = (year >= treat_year-2) if nearby_county == 1 & !missing(treat_year)
replace post_treatment_back2 = 0 if casino_county == 0
replace post_treatment_n_back2 = 0 if nearby_county == 0
cap drop rel_time_back2
cap drop rel_time_n_back2
gen rel_time_back2 = year - treat_year-2 if casino_county == 1 & !missing(treat_year)
gen rel_time_n_back2 = year - treat_year-2 if nearby_county == 1 & !missing(treat_year)

gen post = post_treatment
gen post_back2 = post_treatment_back2
gen post_n = post_treatment_n
gen post_back2_n = post_treatment_n_back2
label var post "Post-treatment period binary"

gen casino_post = casino_county * post
gen nearby_post = nearby_county * post_n
gen casino_post_back2 = casino_county * post_back2
gen nearby_post_back2 = nearby_county * post_back2_n
label var casino_post "Casino County × Post"
label var nearby_post "Nearby County × Post"
la var casino_post "1 if casino co after casino opened"
*post means these this is 1 when the casino opened, not before. 


* Create 8-year event study variables for population analysis
forvalues j = 5(-1)1 {
	gen lag`j'_pop = 0
	replace lag`j'_pop = 1 if rel_time == -`j' & !missing(rel_time)
}

gen lag6minus_pop = 0
replace lag6minus_pop = 1 if rel_time <= -6 & !missing(rel_time)

forvalues j = 0/7 {
	gen lead`j'_pop = 0
	replace lead`j'_pop = 1 if rel_time == `j' & !missing(rel_time)
}

gen lead8plus_pop = 0
replace lead8plus_pop = 1 if rel_time >= 8 & !missing(rel_time)


*note this is the fullest population dataset you can have, from the virgin1 data file
save "$data\population_analysis_data.dta", replace


/*------------------------------------------------------------------------------
4. PREPARE RELIGIOUS DATA
------------------------------------------------------------------------------*/
{
* Load and combine all three years of religious data
use "$data\religious_2000.dta", clear
gen county_id = fip
gen year = 2000
gen total_adherents_rate = totrt
gen evangelical_rate = evanrt
gen catholic_rate = cathrt  
gen mainline_rate = mainrt
gen southern_baptist_rate = sbcrt
gen population = POP200
gen state_code = stcod
keep county_id year *_rate population state_code

tempfile religious_2000
save `religious_2000'

use "$data\religious_2010.dta", clear
gen county_id = fips
gen year = 2010
gen total_adherents_rate = totrate
gen evangelical_rate = evanrate
gen catholic_rate = cathrate  
gen mainline_rate = mprtrate
gen southern_baptist_rate = sbcrate
gen population = POP2010
gen state_code = stcode
keep county_id year *_rate population state_code

tempfile religious_2010
save `religious_2010'

use "$data\religious_2020.dta", clear
gen county_id = fips
gen year = 2020
gen total_adherents_rate = TOTRATE_2020
gen evangelical_rate = EVANRATE_2020
gen catholic_rate = CATHRATE_2020  
gen mainline_rate = MPRTRATE_2020
gen southern_baptist_rate = SBCRATE_2020
gen population = POP2020
gen state_code = stcod
keep county_id year *_rate population state_code

* Append all years
append using `religious_2010'
append using `religious_2000'

* Merge with casino data
merge 1:1 county_id year using "$data\casino_clean.dta"
keep if inlist(year, 2000, 2010, 2020)

************************************************************
************************************************************
*significant clean up of the casino counties and ACS data
/*mainly large cities separate from the surronding county, will classify as the surronding county

*Need to combine Horse Casino Baltimore into Baltimore city and County
replace county_id = 24005 if county_id == 24510
*same for st louis
replace county_id = 29189 if county_id == 29510
*wichita
replace county_id = 20173 if county_id == 20191
*shreveport
replace county_id = 22015 if county_id == 22017

************************************************************/
************************************************************

gen sample_type = 1 if casino_county == 1
replace sample_type = 2 if nearby_county == 1 & casino_county == 0
replace sample_type = 3 if _merge == 1

keep if sample_type >= 1 & sample_type <= 3

replace casino_county = 0 if _merge == 1
replace nearby_county = 0 if _merge == 1
drop _merge

gen donut_sample = (sample_type == 1 | sample_type == 3)

* Generate treatment variables
cap drop post_treatment
gen post_treatment = (year >= treat_year) if casino_county == 1 & !missing(treat_year)
replace post_treatment = 0 if casino_county == 0
cap drop post_treatment_n
gen post_treatment_n = (year >= treat_year) if nearby_county == 1 & !missing(treat_year)
replace post_treatment_n = 0 if nearby_county == 0

cap drop post_treatment_back2
gen post_treatment_back2 = (year >= treat_year-2 ) if casino_county == 1 & !missing(treat_year)
replace post_treatment_back2 = 0 if casino_county == 0
cap drop post_treatment_n_back2
gen post_treatment_n_back2 = (year >= treat_year-2) if nearby_county == 1 & !missing(treat_year)
replace post_treatment_n_back2 = 0 if nearby_county == 0

* Create differenced variables for religious analysis
sort county_id year
by county_id: gen lag_total_adherents = total_adherents_rate[_n-1]
by county_id: gen lag_post_treatment = post_treatment[_n-1]
by county_id: gen lag_post_treatment_back2 = post_treatment_back2[_n-1]
by county_id: gen lag_post_treatment_n = post_treatment_n[_n-1]
by county_id: gen lag_post_treatment_n_back2 = post_treatment_n_back2[_n-1]
gen diff_total_adherents = total_adherents_rate - lag_total_adherents
gen diff_post_treatment = post_treatment - lag_post_treatment
gen diff_post_treatment_back2 = post_treatment_back2 - lag_post_treatment_back2
gen diff_post_treatment_n = post_treatment_n - lag_post_treatment_n
gen diff_post_treatment_n_back2 = post_treatment_n_back2 - lag_post_treatment_n_back2

* Create baseline religiosity terciles (using 2000 data)
preserve
keep if year == 2000
xtile baseline_religiosity_tercile = total_adherents_rate, nq(3)
keep county_id baseline_religiosity_tercile
tempfile baseline_religiosity
save `baseline_religiosity'
save temp.dta, replace
restore



merge m:1 county_id using temp.dta, nogen

* Create differenced variables
sort county_id year
cap by county_id: gen lag_total_adherents = total_adherents_rate[_n-1]
cap gen diff_total_adherents = total_adherents_rate - lag_total_adherents

* Create spillover variables
gen post = post_treatment
gen post_back2 = post_treatment_back2
gen post_n = post_treatment_n
gen post_back2_n = post_treatment_n_back2
label var post "Post-treatment period binary"

gen casino_post = casino_county * post
gen nearby_post = nearby_county * post_n
gen casino_post_back2 = casino_county * post_back2
gen nearby_post_back2 = nearby_county * post_back2_n
label var casino_post "Casino County × Post"
label var nearby_post "Nearby County × Post"
la var casino_post "1 if casino co after casino opened"
*post means these this is 1 when the casino opened, not before. 

*drop missing county_id
drop if county_id ==.

tempfile religious_analysis_data
save `religious_analysis_data'
save religious_analysis_data.dta, replace
}

/*==============================================================================
PART II: TABLES AND FIGURES
==============================================================================*/

display ""
display "=============================================================="
display "=== PART II: CREATING TABLES AND FIGURES ==="
display "=============================================================="

/*==============================================================================
TABLE 1: SUMMARY STATISTICS BY TREATMENT STATUS
==============================================================================*/
use "$data\main_analysis_data.dta", clear
*REMEMBER, THIS IS THE FULL DATASET

/*Notes on these results

The closest match of treatment to control are the casino counties with only one new casino in 
the 2003-2023 time frame.  We haven't performed any statistical test, I do think we meet the conditions 
of Balance if we were to use a comparison of means test.  Now, we probably should compare distributions
as well, but that can be for later

The best Stata code for matching pairs is from the balancetable package or the teffects code. 
*/

display ""
display "=== TABLE 1: SUMMARY STATISTICS ==="
drop if year <2005
*full casino data
{
* Individual-level summary statistics by treatment status
eststo clear

* Casino counties
estpost summarize married has_children num_children female age white black hispanic ///
	if sample_type == 1 [aw=perwt]
eststo casino_stats

* Nearby counties  
estpost summarize married has_children num_children female age white black hispanic ///
	if sample_type == 2 [aw=perwt]
eststo nearby_stats

* Control counties
estpost summarize married has_children num_children female age white black hispanic ///
	if sample_type == 3 [aw=perwt]
eststo control_stats

* Export summary statistics
esttab casino_stats nearby_stats control_stats ///
	using "$output/table1_summary_stats_no2005.tex", replace ///
	cells("mean(fmt(3)) sd(fmt(3))") ///
	mtitles("Casino Counties" "Nearby Counties" "Control Counties") ///
	title("Summary Statistics by County Type: All counties past 2005") ///
	addnotes("Notes: Individual-level statistics weighted by person weights. Sample includes individuals aged 18-40.")

* Display county counts
display ""
display "=== COUNTY COUNTS BY SAMPLE TYPE ==="
preserve
* Count unique counties by sample type
duplicates drop county_id sample_type, force
tab sample_type
restore

* Count total individuals by sample type
display ""
display "=== INDIVIDUAL COUNTS BY SAMPLE TYPE ==="
tab sample_type
}

*dropping multiple casino counties
drop if (tot_casino_no > 1 & _merge == 3)
{
* Individual-level summary statistics by treatment status
eststo clear

* Casino counties
estpost summarize married has_children num_children female age white black hispanic ///
	if sample_type == 1 [aw=perwt]
eststo casino_stats

* Nearby counties  
estpost summarize married has_children num_children female age white black hispanic ///
	if sample_type == 2 [aw=perwt]
eststo nearby_stats

* Control counties
estpost summarize married has_children num_children female age white black hispanic ///
	if sample_type == 3 [aw=perwt]
eststo control_stats

* Export summary statistics
esttab casino_stats nearby_stats control_stats ///
	using "$output/table1_summary_stats_multi_removed.tex", replace ///
	cells("mean(fmt(3)) sd(fmt(3))") ///
	mtitles("Casino Counties" "Nearby Counties" "Control Counties") ///
	title("Summary Statistics by County Type: Multiple casino counties removed") ///
	addnotes("Notes: Individual-level statistics weighted by person weights. Sample includes individuals aged 18-40.")

* Display county counts
display ""
display "=== COUNTY COUNTS BY SAMPLE TYPE ==="
preserve
* Count unique counties by sample type
duplicates drop county_id sample_type, force
tab sample_type
restore

* Count total individuals by sample type
display ""
display "=== INDIVIDUAL COUNTS BY SAMPLE TYPE ==="
tab sample_type
}

drop _merge



/*==============================================================================
TABLE 2: POPULATION EFFECTS BY AGE GROUP
==============================================================================*/

display ""
display "=== TABLE 2: POPULATION EFFECTS ==="
	
use "$data\population_analysis_data.dta", clear
*again, full dataset for 2005
drop if year <2005


* Create county-year level population data
gen total_pop_temp = perwt if all_ages == 1
gen child_rearing_pop_temp = perwt if child_rearing_age == 1
gen children_pop_temp = perwt if children == 1
gen school_age_pop_temp = perwt if school_age == 1

collapse (sum) total_pop=total_pop_temp ///
		 (sum) child_rearing_pop=child_rearing_pop_temp ///
		 (sum) children_pop=children_pop_temp ///
		 (sum) school_age_pop=school_age_pop_temp, ///
		 by(county_id year donut_sample lag5_pop-lead8plus_pop post_treatment casino_county) fast

* Create log variables (note, betas is level regression will be off by a significant factor, log-level no effect)
gen ln_total_pop = ln(total_pop)
gen ln_child_rearing_pop = ln(child_rearing_pop) if child_rearing_pop > 0
gen ln_children_pop = ln(children_pop) if children_pop > 0
gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0

eststo clear

*These are for the slides, the aggregate diff and diff needs to be done yet for the paper
* Total Population
reghdfe ln_total_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_total
pretrends power 0.5, pre(1/4) post(5/13)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(totpop)") name(pop1, replace)
graph export "$output/pretrend_pop1.pdf", replace


* Child-Rearing Age (18-40)
reghdfe ln_child_rearing_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_child_rearing
pretrends power 0.5, pre(1/4) post(5/13)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(child_rearing_po)") name(childrear, replace)
graph export "$output/pretrend_childrear.pdf", replace


* Children (≤17)
reghdfe ln_children_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_children
pretrends power 0.5, pre(1/4) post(5/13)
return list
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(child_pop)") name(childpop, replace)
graph export "$output/pretrend_childpop.pdf", replace

* School-Age (5-17)
reghdfe ln_school_age_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_school_age
pretrends power 0.5, pre(1/4) post(5/13)
return list
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(school_age)") name(school, replace)
graph export "$output/pretrend_schoolage.pdf", replace


* Export Table 2
esttab pop_total pop_child_rearing pop_children pop_school_age ///
	using "$output/table2_population_effects_full.tex", replace ///
	keep(lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
	coeflabels(lag5_pop "t-5" lag4_pop "t-4" lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
			  lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
			  lead7_pop "t+7" lead8plus_pop "t+8+") ///
	mgroups("Total Pop" "Child-Rearing" "Children" "School-Age", ///
		   pattern(1 1 1 1) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
	stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
	se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
	title("Population Effects by Age Group: Full") ///
	addnotes("Standard errors clustered at county level in parentheses." ///
			"Donut sample excludes nearby counties. All variables in logs.")


restore

/*==============================================================================
FIGURE 1: POPULATION DECLINE EVENT STUDIES
==============================================================================*/

display ""
display "=== FIGURE 1: POPULATION EVENT STUDIES ==="

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
	keep(lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
	vertical ///
	coeflabels(lag5_pop = "-5" lag4_pop = "-4" lag3_pop = "-3" lag2_pop = "-2" lead0_pop = "0" lead1_pop = "1" lead2_pop = "2" ///
			  lead3_pop = "3" lead4_pop = "4" lead5_pop = "5" lead6_pop = "6" ///
			  lead7_pop = "7" lead8plus_pop = "8+", labsize(medium)) ///
	yline(0, lcolor(gray) lpattern(dash)) ///
	xline(4.5, lcolor(gray) lpattern(dash)) ///
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
	
graph export "$output/figure1_population_effects_all_counties_full.png", replace width(1400) height(900)
graph export "$output/figure1_population_effects_all_counties_full.pdf", replace
}


*dropping multiple casino counties
use "$data\population_analysis_data.dta", clear
*again, full dataset for 2005
drop if year <2005
drop if (tot_casino_no > 1 & _merge == 3)
{
preserve
* Create county-year level population data
gen total_pop_temp = perwt if all_ages == 1
gen child_rearing_pop_temp = perwt if child_rearing_age == 1
gen children_pop_temp = perwt if children == 1
gen school_age_pop_temp = perwt if school_age == 1

collapse (sum) total_pop=total_pop_temp ///
		 (sum) child_rearing_pop=child_rearing_pop_temp ///
		 (sum) children_pop=children_pop_temp ///
		 (sum) school_age_pop=school_age_pop_temp, ///
		 by(county_id year donut_sample lag5_pop-lead8plus_pop post_treatment casino_county) fast

* Create log variables (note, betas is level regression will be off by a significant factor, log-level no effect)
gen ln_total_pop = ln(total_pop)
gen ln_child_rearing_pop = ln(child_rearing_pop) if child_rearing_pop > 0
gen ln_children_pop = ln(children_pop) if children_pop > 0
gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0

eststo clear

*These are for the slides, the aggregate diff and diff needs to be done yet for the paper
* Total Population
reghdfe ln_total_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_total
pretrends power 0.5, pre(1/4) post(5/13)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(totpop)") name(pop1, replace)
graph export "$output/pretrend_pop1.pdf", replace


* Child-Rearing Age (18-40)
reghdfe ln_child_rearing_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_child_rearing
pretrends power 0.5, pre(1/4) post(5/13)
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(child_rearing_po)") name(childrear, replace)
graph export "$output/pretrend_childrear.pdf", replace


* Children (≤17)
reghdfe ln_children_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_children
pretrends power 0.5, pre(1/4) post(5/13)
return list
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(child_pop)") name(childpop, replace)
graph export "$output/pretrend_childpop.pdf", replace

* School-Age (5-17)
reghdfe ln_school_age_pop ///
	lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
	if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
eststo pop_school_age
pretrends power 0.5, pre(1/4) post(5/13)
return list
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: ln(school_age)") name(school, replace)
graph export "$output/pretrend_schoolage.pdf", replace

* Export Table 2
esttab pop_total pop_child_rearing pop_children pop_school_age ///
	using "$output/table2_population_effects_no_multi.tex", replace ///
	keep(lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
	coeflabels(lag5_pop "t-5" lag4_pop "t-4" lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
			  lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
			  lead7_pop "t+7" lead8plus_pop "t+8+") ///
	mgroups("Total Pop" "Child-Rearing" "Children" "School-Age", ///
		   pattern(1 1 1 1) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
	stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
	se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
	title("Population Effects by Age Group: no multiple casino openings") ///
	addnotes("Standard errors clustered at county level in parentheses." ///
			"Donut sample excludes nearby counties. All variables in logs.")
			
*prettrend graphs
graph combine pop1 childrear childpop school, ///
    title("Pop pretrends", size(medium)) cols(2)
graph export "$output/pretrends_poptotal_nomulti.pdf", replace


restore

/*==============================================================================
FIGURE 1: POPULATION DECLINE EVENT STUDIES
==============================================================================*/

display ""
display "=== FIGURE 1: POPULATION EVENT STUDIES ==="

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
	keep(lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
	vertical ///
	coeflabels(lag5_pop = "-5" lag4_pop = "-4" lag3_pop = "-3" lag2_pop = "-2" lead0_pop = "0" lead1_pop = "1" lead2_pop = "2" ///
			  lead3_pop = "3" lead4_pop = "4" lead5_pop = "5" lead6_pop = "6" ///
			  lead7_pop = "7" lead8plus_pop = "8+", labsize(medium)) ///
	yline(0, lcolor(gray) lpattern(dash)) ///
	xline(4.5, lcolor(gray) lpattern(dash)) ///
	title("Population Effects by Age Group: Multi casinos removed", ///
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
	
graph export "$output/figure1_population_effects_no_multi.png", replace width(1400) height(900)
graph export "$output/figure1_population_effects_no_multi.pdf", replace
}

/*removing pre counties
drop if (tot_casino_no == 1 & _merge == 3 & pre2003_casino_near_co == 1)
drop if county_id == 6039
drop if county_id == 12011
drop if county_id == 12057*/

drop _merge

/*==============================================================================
TABLE 3: FAMILY FORMATION EFFECTS BY GENDER
==============================================================================*/

display ""
display "=== TABLE 3: FAMILY FORMATION EFFECTS ==="

use "$data\main_analysis_data.dta", clear
drop if year<2005
*full
{
eststo clear

* Women
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment age age_sq ///
        if female == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo w_`outcome'
}

* Men  
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment age age_sq ///
        if female == 0 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo m_`outcome'
}

* Export Table 3
esttab w_married w_has_children w_num_children m_married m_has_children m_num_children ///
    using "$output/table3_family_formation_full.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Family Formation Effects by Gender") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All regressions include county and year fixed effects, age and age squared." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
FIGURE 2: FERTILITY EVENT STUDIES BY GENDER
==============================================================================*/

display ""
display "=== FIGURE 2: FERTILITY EVENT STUDIES ==="


eststo clear

* Women fertility event study

reghdfe num_children ///
	lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
	age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & lag6minus != 1 [aw=perwt], ///
	absorb(county_id year) vce(cluster county_id)
eststo fertility_women



* Men fertility event study
reghdfe num_children ///
	lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo fertility_men



* Create two-panel fertility figure
coefplot (fertility_women, ///
            ciopts(lcolor(maroon) lwidth(medium)) ///
            mcolor(maroon) msymbol(O) msize(medium) ///
            label("Women")) ///
         (fertility_men, ///
            ciopts(lcolor(navy) lwidth(medium)) ///
            mcolor(navy) msymbol(D) msize(medium) ///
            label("Men")), ///
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
    vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4" lag3 = "-3" lag2 = "-2" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(4.5, lcolor(gray) lpattern(dash)) ///
    title("Fertility Effects by Gender", ///
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

    
graph export "$output/figure2_fertility_effects_full.png", replace width(1400) height(900)
graph export "$output/figure2_fertility_effects_full.pdf", replace
}

*dropping multiple casino counties
drop if (tot_casino_no > 1 & _merge == 3)
{
eststo clear

* Women
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment age age_sq ///
        if female == 1 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo w_`outcome'
}

* Men  
foreach outcome in married has_children num_children {
    reghdfe `outcome' post_treatment age age_sq ///
        if female == 0 & donut_sample == 1 [aw=perwt], ///
        absorb(county_id year) vce(cluster county_id)
    eststo m_`outcome'
}

* Export Table 3
esttab w_married w_has_children w_num_children m_married m_has_children m_num_children ///
    using "$output/table3_family_formation_no_multi.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mgroups("Women" "Men", pattern(1 0 0 1 0 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Marriage" "Has Children" "Num Children" "Marriage" "Has Children" "Num Children") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Family Formation Effects by Gender") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "All regressions include county and year fixed effects, age and age squared." ///
            "Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

/*==============================================================================
FIGURE 2: FERTILITY EVENT STUDIES BY GENDER
==============================================================================*/

display ""
display "=== FIGURE 2: FERTILITY EVENT STUDIES ==="


eststo clear

* Women fertility event study

reghdfe num_children ///
	lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
	age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & lag6minus != 1 [aw=perwt], ///
	absorb(county_id year) vce(cluster county_id)
eststo fertility_women
pretrends power 0.5, pre(1/4) post(5/13)
return list
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: num_child_w_nomulti") name(num_child_w, replace)
graph export "$output/pretrend_num_child_w_nomulti.pdf", replace


* Men fertility event study
reghdfe num_children ///
	lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo fertility_men
pretrends power 0.5, pre(1/4) post(5/13)
return list
matrix sigma = e(V)
matrix beta  = e(b)
matrix beta  = beta[., 1..13]
matrix sigma = sigma[1..13, 1..13]
pretrends, numpre(4) b(beta) v(sigma) slope(`r(slope)') title("Pre Trend Test: num_child_m_nomulti") name(num_child_m, replace)
graph export "$output/pretrend_num_child_m_nomulti.pdf", replace

*prettrend graphs
graph combine num_child_w num_child_m, ///
    title("Num Child pretrends", size(medium)) cols(2)
graph export "$output/pretrends_numchild_nomulti.pdf", replace

* Create two-panel fertility figure
coefplot (fertility_women, ///
            ciopts(lcolor(maroon) lwidth(medium)) ///
            mcolor(maroon) msymbol(O) msize(medium) ///
            label("Women")) ///
         (fertility_men, ///
            ciopts(lcolor(navy) lwidth(medium)) ///
            mcolor(navy) msymbol(D) msize(medium) ///
            label("Men")), ///
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
    vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4" lag3 = "-3" lag2 = "-2" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
    yline(0, lcolor(gray) lpattern(dash)) ///
    xline(4.5, lcolor(gray) lpattern(dash)) ///
    title("Fertility Effects by Gender", ///
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

    
graph export "$output/figure2_fertility_effects_no_multi.png", replace width(1400) height(900)
graph export "$output/figure2_fertility_effects_no_multi.pdf", replace
}




/*==============================================================================
TABLE 4: EFFECTS BY RESIDENCE DURATION
==============================================================================*/

display ""
display "=== TABLE 4: EFFECTS BY RESIDENCE DURATION ==="

use "$data\main_analysis_data.dta", clear
drop if year<2005
*full
{
eststo clear

* Women - Long-term residents (5+ years)
reghdfe num_children ///
	lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_longterm

* Women - Recent movers (<5 years)
reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_recent

* Men - Long-term residents (5+ years)
reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus  ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag6minus != 1  [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_longterm

* Men - Recent movers (<5 years)
reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8  lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_recent

* Export Table 4
esttab w_longterm w_recent m_longterm m_recent ///
    using "$output/table4_residence_duration_full.tex", replace ///
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
    coeflabels(lag5  "-5" lag4  "-4" lag3  "-3" lag2  "-2" lead0  "0" lead1  "1" lead2  "2" ///
          lead3 "3" lead4 "4" lead5 "5" lead6 "6" ///
          lead7 "7" lead8 "8" lead9 "9" lead10plus "10+") ///
    mgroups("Women" "Men", pattern(1 0 1 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Long-term (5+)" "Recent (<5)" "Long-term (5+)" "Recent (<5)") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Effects by Residence Duration: Number of Children:full") ///
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
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4" lag3 = "-3" lag2 = "-2" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xline(4.5, lcolor(gs8) lpattern(dash)) ///
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
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4" lag3 = "-3" lag2 = "-2" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xline(4.5, lcolor(gs8) lpattern(dash)) ///
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
    title("Mechanism Test: Fertility Effects by Residence Duration", size(vlarge)) ///
    subtitle("Behavioral Change vs Selection", size(large)) ///
    note("● Long-term Residents (5+ years)     ♦ Recent Movers (<5 years)" ///
         "Stronger effects for long-term residents suggest behavioral change rather than selection." ///
         "Donut sample excludes nearby counties.", ///
         size(medium)) ///
    cols(2) ///
    ycommon xcommon ///
    imargin(small) ///
    scheme(s1mono)
    
graph export "$output/figure3_mechanism_test_full.png", replace width(1400) height(700)
graph export "$output/figure3_mechanism_test_full.pdf", replace

}

*dropping multiple casino counties
drop if (tot_casino_no > 1 & _merge == 3)
{
eststo clear

* Women - Long-term residents (5+ years)
reghdfe num_children ///
	lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_longterm

* Women - Recent movers (<5 years)
reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    age age_sq if female == 1 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo w_recent

* Men - Long-term residents (5+ years)
reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus  ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 1 & lag6minus != 1  [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_longterm

* Men - Recent movers (<5 years)
reghdfe num_children ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8  lead9 lead10plus ///
    age age_sq if female == 0 & donut_sample == 1 & acs_sample == 1 & longterm_resident == 0 & lag6minus != 1 [aw=perwt], ///
    absorb(county_id year) vce(cluster county_id)
eststo m_recent

* Export Table 4
esttab w_longterm w_recent m_longterm m_recent ///
    using "$output/table4_residence_duration_no_multi.tex", replace ///
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
    coeflabels(lag5  "-5" lag4  "-4" lag3  "-3" lag2  "-2" lead0  "0" lead1  "1" lead2  "2" ///
          lead3 "3" lead4 "4" lead5 "5" lead6 "6" ///
          lead7 "7" lead8 "8" lead9 "9" lead10plus "10+") ///
    mgroups("Women" "Men", pattern(1 0 1 0) ///
           prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Long-term (5+)" "Recent (<5)" "Long-term (5+)" "Recent (<5)") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Effects by Residence Duration: Number of Children _no_multi") ///
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
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4" lag3 = "-3" lag2 = "-2" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xline(4.5, lcolor(gs8) lpattern(dash)) ///
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
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	vertical ///
    coeflabels(lag5 = "-5" lag4 = "-4" lag3 = "-3" lag2 = "-2" lead0 = "0" lead1 = "1" lead2 = "2" ///
              lead3 = "3" lead4 = "4" lead5 = "5" lead6 = "6" ///
              lead7 = "7" lead8 = "8" lead9 = "9" lead10plus = "10+", labsize(medium)) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xline(4.5, lcolor(gs8) lpattern(dash)) ///
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
    title("Mechanism Test: Fertility Effects by Residence Duration _no_multi", size(vlarge)) ///
    subtitle("Behavioral Change vs Selection", size(large)) ///
    note("● Long-term Residents (5+ years)     ♦ Recent Movers (<5 years)" ///
         "Stronger effects for long-term residents suggest behavioral change rather than selection." ///
         "Donut sample excludes nearby counties.", ///
         size(medium)) ///
    cols(2) ///
    ycommon xcommon ///
    imargin(small) ///
    scheme(s1mono)
    
graph export "$output/figure3_mechanism_test_no_multi.png", replace width(1400) height(700)
graph export "$output/figure3_mechanism_test_no_multi.pdf", replace

}

drop _merge


/*==============================================================================
TABLE 5: POPULATION COMPOSITION TESTS - changed to shortrun
==============================================================================*/


display ""
display "=== TABLE 5: POPULATION COMPOSITION TESTS ==="

use "$data\main_analysis_data.dta", clear
drop if year < 2005 /*because we dont have county fips for acs except 2000*/

{
* Create population composition data at county-year level
preserve

* Create indicator for ACS samples (exclude 2000 Census)
gen acs_sample_comp = 1
replace acs_sample_comp = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)

* Create population variables before collapsing
gen longterm_pop_temp = perwt if longterm_resident == 0 & acs_sample_comp == 1
*keeping this code so I don't have to change the name of a number of variables, but this is shortrun vs. long run
gen total_pop_temp = perwt if acs_sample_comp == 1

* Calculate population by residence type and county-year
collapse (sum) longterm_pop=longterm_pop_temp ///
         (sum) total_pop=total_pop_temp, ///
         by(county_id year casino_county rel_time donut_sample lag6minus lead10plus lag5-lead9)

* Only keep counties with both populations measured
drop if missing(longterm_pop) | missing(total_pop) | total_pop == 0

* Calculate share of long-term residents
gen longterm_share = longterm_pop / total_pop

* Create log long-term population
gen ln_longterm_pop = ln(longterm_pop)

eststo clear

* Event study for log long-term population
reghdfe ln_longterm_pop ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    if donut_sample == 1 & lag6minus != 1, ///
    absorb(county_id year) vce(cluster county_id)
eststo pop_level

* Event study for long-term population share
reghdfe longterm_share ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    if donut_sample == 1 & lag6minus != 1, ///
    absorb(county_id year) vce(cluster county_id)
eststo pop_share

* Export Table 5
esttab pop_level pop_share ///
    using "$output/table5_population_composition.tex", replace ///
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	coeflabels(lag5 "-5" lag4 "-4" lag3 "-3" lag2 "-2" lead0 "0" lead1 "1" lead2 "2" ///
          lead3 "3" lead4 "4" lead5 "5" lead6 "6" ///
          lead7 "7" lead8 "8" lead9 "9" lead10plus "10+") ///
    mtitles("Log Short-term Population" "Short-term Population Share") ///
     stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Population Composition Tests, only 2005+ data") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Tests whether casinos affect size/composition of short-term resident population." ///
            "Long-term = 5+ years in residence. Donut sample excludes nearby counties.")

restore

}

drop if (tot_casino_no > 1 & _merge == 3)

{
* Create population composition data at county-year level
preserve

* Create indicator for ACS samples (exclude 2000 Census)
gen acs_sample_comp = 1
replace acs_sample_comp = 0 if inlist(sample, 200001, 200002, 200003, 200005, 200006, 200007, 200008)

* Create population variables before collapsing
gen longterm_pop_temp = perwt if longterm_resident == 0 & acs_sample_comp == 1
*keeping this code so I don't have to change the name of a number of variables, but this is shortrun vs. long run
gen total_pop_temp = perwt if acs_sample_comp == 1

* Calculate population by residence type and county-year
collapse (sum) longterm_pop=longterm_pop_temp ///
         (sum) total_pop=total_pop_temp, ///
         by(county_id year casino_county rel_time donut_sample lag6minus lead10plus lag5-lead9)

* Only keep counties with both populations measured
drop if missing(longterm_pop) | missing(total_pop) | total_pop == 0

* Calculate share of long-term residents
gen longterm_share = longterm_pop / total_pop

* Create log long-term population
gen ln_longterm_pop = ln(longterm_pop)

eststo clear

* Event study for log long-term population
reghdfe ln_longterm_pop ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    if donut_sample == 1 & lag6minus != 1, ///
    absorb(county_id year) vce(cluster county_id)
eststo pop_level

* Event study for long-term population share
reghdfe longterm_share ///
    lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus ///
    if donut_sample == 1 & lag6minus != 1, ///
    absorb(county_id year) vce(cluster county_id)
eststo pop_share

* Export Table 5
esttab pop_level pop_share ///
    using "$output/table5_population_composition_no_multi.tex", replace ///
    keep(lag5 lag4 lag3 lag2 lead0 lead1 lead2 lead3 lead4 lead5 lead6 lead7 lead8 lead9 lead10plus) ///
	coeflabels(lag5 "-5" lag4 "-4" lag3 "-3" lag2 "-2" lead0 "0" lead1 "1" lead2 "2" ///
          lead3 "3" lead4 "4" lead5 "5" lead6 "6" ///
          lead7 "7" lead8 "8" lead9 "9" lead10plus "10+") ///
    mtitles("Log Short-term Population" "Short-term Population Share") ///
     stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    title("Population Composition Tests: no multi or <2005 data") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Tests whether casinos affect size/composition of short-term resident population." ///
            "Long-term = 5+ years in residence. Donut sample excludes nearby counties.")

restore

}

/*==============================================================================
TABLE 6: SCHOOL POPULATION AND ENROLLMENT EFFECTS
==============================================================================*/


	display ""
	display "=== TABLE 6: SCHOOL EFFECTS ==="

use "$data\population_analysis_data.dta", clear
drop if year<2005

*full dataset
{
preserve

	* Create county-year level school data
	gen school_age_pop_temp = perwt if school_age == 1
	gen school_enrolled_temp = perwt if school_age_enrolled == 1
	gen public_enrolled_temp = perwt if school_age_public == 1

	collapse (sum) school_age_pop=school_age_pop_temp ///
			 (sum) school_enrolled=school_enrolled_temp ///
			 (sum) public_enrolled=public_enrolled_temp, ///
			 by(county_id year donut_sample lag5_pop-lead8plus_pop lag6minus_pop) fast

	* Create log variables
	gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0
	gen ln_school_enrolled = ln(school_enrolled) if school_enrolled > 0
	gen ln_public_enrolled = ln(public_enrolled) if public_enrolled > 0

	eststo clear

	* School-age population
	reghdfe ln_school_age_pop ///
		lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
	eststo school_pop

	* Total school enrollment
	reghdfe ln_school_enrolled ///
		lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
	eststo school_enroll

	* Public school enrollment
	reghdfe ln_public_enrolled ///
		lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
	eststo public_enroll

	* Export Table 6
	esttab school_pop school_enroll public_enroll ///
		using "$output/table6_school_effects_full.tex", replace ///
		keep(lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
		coeflabels(lag5_pop "t-5" lag4_pop "t-4" lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
				  lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
				  lead7_pop "t+7" lead8plus_pop "t+8+") ///
		mtitles("School-Age Pop" "Total Enrollment" "Public Enrollment") ///
		stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
		se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
		title("School Population and Enrollment Effects: only 2005+ data") ///
		addnotes("Standard errors clustered at county level in parentheses." ///
				"All variables in logs. School-age = 5-17 years." ///
				"Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

	restore
}
	
*dropping multiple casino counties
drop if (tot_casino_no > 1 & _merge == 3)
{
preserve

	* Create county-year level school data
	gen school_age_pop_temp = perwt if school_age == 1
	gen school_enrolled_temp = perwt if school_age_enrolled == 1
	gen public_enrolled_temp = perwt if school_age_public == 1

collapse (sum) school_age_pop=school_age_pop_temp ///
		 (sum) school_enrolled=school_enrolled_temp ///
		 (sum) public_enrolled=public_enrolled_temp, ///
		 by(county_id year donut_sample lag5_pop-lead8plus_pop lag6minus_pop)

	* Create log variables
	gen ln_school_age_pop = ln(school_age_pop) if school_age_pop > 0
	gen ln_school_enrolled = ln(school_enrolled) if school_enrolled > 0
	gen ln_public_enrolled = ln(public_enrolled) if public_enrolled > 0

	eststo clear

	* School-age population
	reghdfe ln_school_age_pop ///
		lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
	eststo school_pop

	* Total school enrollment
	reghdfe ln_school_enrolled ///
		lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
	eststo school_enroll

	* Public school enrollment
	reghdfe ln_public_enrolled ///
		lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop ///
		if donut_sample == 1 & lag6minus_pop != 1, absorb(county_id year) vce(cluster county_id)
	eststo public_enroll

	* Export Table 6
	esttab school_pop school_enroll public_enroll ///
		using "$output/table6_school_effects_no_multi.tex", replace ///
		keep(lag5_pop lag4_pop lag3_pop lag2_pop lead0_pop lead1_pop lead2_pop lead3_pop lead4_pop lead5_pop lead6_pop lead7_pop lead8plus_pop) ///
		coeflabels(lag5_pop "t-5" lag4_pop "t-4" lag3_pop "t-3" lag2_pop "t-2" lead0_pop "t" lead1_pop "t+1" lead2_pop "t+2" ///
				  lead3_pop "t+3" lead4_pop "t+4" lead5_pop "t+5" lead6_pop "t+6" ///
				  lead7_pop "t+7" lead8plus_pop "t+8+") ///
		mtitles("School-Age Pop" "Total Enrollment" "Public Enrollment") ///
		stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
		se(%9.3f) b(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
		title("School Population and Enrollment Effects: No multi casino counties") ///
		addnotes("Standard errors clustered at county level in parentheses." ///
				"All variables in logs. School-age = 5-17 years." ///
				"Donut sample excludes nearby counties. *** p<0.01, ** p<0.05, * p<0.1.")

	restore
}

	
/*==============================================================================
TABLE 7: RELIGIOUS ADHERENCE EFFECTS
==============================================================================*/

use religious_analysis_data.dta, clear

eststo clear

* (1) Baseline specification (county + year FE)
reghdfe total_adherents_rate post_treatment ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store relig_baseline

* (2) Medium religiosity counties only (baseline tercile 2)
reghdfe total_adherents_rate post_treatment ///
    if baseline_religiosity_tercile == 2 [aw=population], ///
    absorb(county_id year) vce(cluster county_id)
estimates store relig_medium

* (3) State-year fixed effects (preferred specification)
reghdfe total_adherents_rate post_treatment ///
    [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
estimates store relig_stateyear

* (4) Differenced specification
reghdfe diff_total_adherents diff_post_treatment if year >= 2010 ///
    [aw=population], absorb(year) vce(cluster county_id)
estimates store relig_diff

* Export Table 7
esttab relig_baseline relig_medium relig_stateyear relig_diff ///
    using "$output/table7_religious_adherence.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment diff_post_treatment) ///
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
    reghdfe `outcome' post_treatment ///
        [aw=population], absorb(county_id year) vce(cluster county_id)
    estimates store base_`outcome'
}

* State-year FE specifications
foreach outcome in catholic_rate evangelical_rate mainline_rate southern_baptist_rate {
    reghdfe `outcome' post_treatment ///
        [aw=population], absorb(county_id state_code#year) vce(cluster county_id)
    estimates store sy_`outcome'
}

* Export Table 8
esttab base_catholic_rate sy_catholic_rate base_evangelical_rate sy_evangelical_rate ///
       base_mainline_rate sy_mainline_rate base_southern_baptist_rate sy_southern_baptist_rate ///
    using "$output/table8_denominational_effects.tex", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(post_treatment) ///
    mgroups("Catholic" "Evangelical" "Mainline" "Southern Baptist", ///
           pattern(1 0 1 0 1 0 1 0) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
    mtitles("Baseline" "State-Yr FE" "Baseline" "State-Yr FE" ///
            "Baseline" "State-Yr FE" "Baseline" "State-Yr FE") ///
    stats(N r2 r2_within, fmt(%9.0fc %9.3f) labels("Observations" "R-squared" "R2_within")) ///
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
replace years_exposure = year - treat_year if casino_county == 1 & year >= treat_year & !missing(treat_year)

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
    
graph export "$output/figure4_religious_exposure.png", replace width(1200) height(800)
graph export "$output/figure4_religious_exposure.pdf", replace

restore


/*==============================================================================
TABLE 9: SPILLOVER EFFECTS (ROBUSTNESS)
==============================================================================*/

display ""
display "=== TABLE 9: SPILLOVER EFFECTS ==="

eststo clear

* Fertility spillovers - Women
use "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data\main_analysis_data.dta", clear

*dropping multiple casino counties
drop if year<2005

{
reghdfe num_children casino_post nearby_post age age_sq ///
    if female == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_w

* Fertility spillovers - Men
reghdfe num_children casino_post nearby_post age age_sq ///
    if female == 0 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_m
}
drop if (tot_casino_no > 1 & _merge == 3)

{
reghdfe num_children casino_post nearby_post age age_sq ///
    if female == 1 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_w_nomulti

* Fertility spillovers - Men
reghdfe num_children casino_post nearby_post age age_sq ///
    if female == 0 [aw=perwt], absorb(county_id year) vce(cluster county_id)
estimates store spill_fert_m_nomulti
}


* Population spillovers - Children (need to recreate population data)

use "C:\Users\mkass\IT Advanced Dropbox\Malcolm Kass\Casino-Marriage-Paper-Draft\data\population_analysis_data.dta", clear

*dropping multiple casino counties
drop if year<2005

preserve
gen children_pop_temp = perwt if children == 1
collapse (sum) children_pop=children_pop_temp, ///
         by(county_id year casino_county nearby_county post_treatment post_treatment_n) fast

gen ln_children_pop = ln(children_pop) if children_pop > 0
gen casino_post = casino_county * post_treatment
gen nearby_post = nearby_county * post_treatment_n

reghdfe ln_children_pop casino_post nearby_post, ///
    absorb(county_id year) vce(cluster county_id)
estimates store spill_pop

restore

drop if (tot_casino_no > 1 & _merge == 3)

preserve
gen children_pop_temp = perwt if children == 1
collapse (sum) children_pop=children_pop_temp, ///
         by(county_id year casino_county nearby_county post_treatment post_treatment_n) fast

gen ln_children_pop = ln(children_pop) if children_pop > 0
gen casino_post = casino_county * post_treatment
gen nearby_post = nearby_county * post_treatment_n

reghdfe ln_children_pop casino_post nearby_post, ///
    absorb(county_id year) vce(cluster county_id)
estimates store spill_pop_nomulti

restore


* Religious spillovers (need to recreate religious data

use religious_analysis_data.dta, clear

reghdfe total_adherents_rate casino_post nearby_post ///
    [aw=population], absorb(county_id year) vce(cluster county_id)
estimates store spill_relig


* Export Table 9
esttab spill_fert_w  spill_fert_m spill_pop spill_relig ///
    using "$output/table9_spillover_effects.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_post nearby_post) ///
    coeflabels(casino_post "Casino County × Post" nearby_post "Nearby County × Post") ///
    mtitles("Fertility (W)" "Fertility (M)" "Child Pop" "Religious") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Spillover Effects: Casino vs Nearby Counties: no pre 2005 county") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Tests for spillover effects to nearby counties. Justifies donut design." ///
            "Reference group: control counties. *** p<0.01, ** p<0.05, * p<0.1.")
			
			
esttab spill_fert_w_nomulti  spill_fert_m_nomulti spill_pop_nomulti spill_relig ///
    using "$output/table9_spillover_effects_nomulti.tex", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(casino_post nearby_post) ///
    coeflabels(casino_post "Casino County × Post" nearby_post "Nearby County × Post") ///
    mtitles("Fertility (W)" "Fertility (M)" "Child Pop" "Religious") ///
    stats(N r2_within, fmt(%9.0fc %9.3f) labels("Observations" "Within R-squared")) ///
    title("Spillover Effects: Casino vs Nearby Counties: No multi counties or pre 2005 data") ///
    addnotes("Standard errors clustered at county level in parentheses." ///
            "Tests for spillover effects to nearby counties. Justifies donut design." ///
            "Reference group: control counties. *** p<0.01, ** p<0.05, * p<0.1.")
			

			


/*==============================================================================
FINAL COMPLETION MESSAGE
==============================================================================*/

display ""
display "================================================================================"
display "=== PAPER ANALYSIS COMPLETE ==="
display "================================================================================"
display ""
display "ALL TABLES AND FIGURES CREATED:"
display ""
display "TABLES:"
display "• Table 1: Summary Statistics (table1_summary_stats.tex)"
display "• Table 2: Population Effects (table2_population_effects.tex)"
display "• Table 3: Family Formation Effects (table3_family_formation.tex)"
display "• Table 4: Effects by Residence Duration (table4_residence_duration.tex)"
display "• Table 5: Population Composition Tests (table5_population_composition.tex)"
display "• Table 6: School Effects (table6_school_effects.tex)"
display "• Table 7: Religious Adherence Effects (table7_religious_adherence.tex)"
display "• Table 8: Denominational Effects (table8_denominational_effects.tex)"
display "• Table 9: Spillover Effects (table9_spillover_effects.tex)"
display ""
display "FIGURES:"
display "• Figure 1: Population Effects by Age Group (figure1_population_effects.png/pdf)"
display "• Figure 2: Fertility Effects by Gender (figure2_fertility_effects.png/pdf)"
display "• Figure 3: Mechanism Test (figure3_mechanism_test.png/pdf)"
display "• Figure 4: Religious Exposure Scatter (figure4_religious_exposure.png/pdf)"
display ""
display "PAPER FLOW:"
display "1. Data and Summary Statistics"
display "2. Population Effects (decline in child-rearing and child populations)"
display "3. Family Formation (negligible marriage, strong fertility decline)"
display "4. Selection vs Behavioral Mechanisms (stronger effects for long-term residents)"
display "5. Family-Adjacent Institutions (school and religious decline)"
display "6. Robustness (spillover effects)"
display ""
display "All files saved to: $output"
display "================================================================================"

cap log close