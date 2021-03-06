
-- ------------------------------------------------------------------
-- Title: Query for static variables
-- Description: This query extracts static variables for all patients (age, gender, ethnicity, ..) around admission (such that it can be used by our model!)
-- Comments: static information which was not known at icu entry we considered as SPOILER --> it still could be useful for demographic description in paper
-- >> MODIFIED VERSION 
-- SOURCE: https://github.com/MIT-LCP/mimic-code/blob/master/concepts/demographics/icustay-detail.sql
-- AUTHOR (of this version): Michael Moor, October 2018

-- ------------------------------------------------------------------

-- This query extracts useful demographic/administrative information for patient ICU stays
DROP MATERIALIZED VIEW IF EXISTS icustay_static CASCADE;
CREATE MATERIALIZED VIEW icustay_static as

SELECT ie.subject_id, ie.hadm_id, ie.icustay_id

-- patient level factors
, pat.gender
-- SPOILER --, pat.dod  --(don't use date of death, as we only want to use info that is known at admission!)s

--, round(cast(adm_w.Weight_Admit as numeric), 2) as Weight_Admit
--, adm_w.Weight_Admit
--, adm_h2.Height 

-- hospital level factors
, adm.admittime
-- SPOILER --, adm.dischtime 
-- SPOILER --, ROUND( (CAST(EXTRACT(epoch FROM adm.dischtime - adm.admittime)/(60*60*24) AS numeric)), 4) AS los_hospital
, ROUND( (CAST(EXTRACT(epoch FROM adm.admittime - pat.dob)/(60*60*24*365.242) AS numeric)), 4) AS admission_age
, adm.ethnicity, adm.admission_type
, adm.admission_location
, ie.first_careunit

-- SPOILER --, adm.hospital_expire_flag
, DENSE_RANK() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS hospstay_seq -- >>>>>> IS THIS SPOILED?
, CASE
    WHEN DENSE_RANK() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) = 1 THEN 1
    ELSE 0 END AS first_hosp_stay

-- icu level factors
, ie.intime
, ie.outtime
-- SPOILER --, ROUND( (CAST(EXTRACT(epoch FROM ie.outtime - ie.intime)/(60*60*24) AS numeric)), 4) AS los_icu
, DENSE_RANK() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) AS icustay_seq

-- first ICU stay *for the current hospitalization*
, CASE
    WHEN DENSE_RANK() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) = 1 THEN 1
    ELSE 0 END AS first_icu_stay

FROM icustays ie
INNER JOIN admissions adm
    ON ie.hadm_id = adm.hadm_id
-- for admission weight:
--left join adm_w
--    on ie.icustay_id = adm_w.icustay_id
--left join adm_h2
--    on ie.icustay_id = adm_h2.icustay_id

INNER JOIN patients pat
    ON ie.subject_id = pat.subject_id    
WHERE adm.has_chartevents_data = 1
ORDER BY ie.subject_id, adm.admittime, ie.intime;





