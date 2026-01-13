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