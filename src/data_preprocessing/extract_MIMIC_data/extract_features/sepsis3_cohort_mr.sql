drop table if exists sepsis3_cohort_mr cascade;
create table sepsis3_cohort_mr as
with serv as

(
    select hadm_id, curr_service
    , ROW_NUMBER() over (partition by hadm_id order by transfertime) as rn
    from services
)

, t1 as
(
select ie.icustay_id, ie.hadm_id
    , ie.intime, ie.outtime
    , round((cast(adm.admittime as date) - cast(pat.dob as date)) / 365.242, 4) as age
    , pat.gender
    , adm.ethnicity
    , ie.dbsource
    -- used to get first ICUSTAY_ID
    , ROW_NUMBER() over (partition by ie.subject_id order by intime) as rn

    -- exclusions
    , s.curr_service as first_service
    , adm.HAS_CHARTEVENTS_DATA

    -- suspicion of infection using POE
    , case when spoe.suspected_infection_time is not null then 1 else 0 end
        as suspected_of_infection_poe
    , spoe.suspected_infection_time as suspected_infection_time_poe
    , extract(EPOCH from ie.intime - spoe.suspected_infection_time)
          / 60.0 / 60.0 / 24.0 as suspected_infection_time_poe_days
    -- , spoe.specimen as specimen_poe
    -- , spoe.positiveculture as positiveculture_poe
    -- , spoe.antibiotic_time as antibiotic_time_poe

from icustays ie
inner join admissions adm
    on ie.hadm_id = adm.hadm_id
inner join patients pat
    on ie.subject_id = pat.subject_id
left join serv s
    on ie.hadm_id = s.hadm_id
    and s.rn = 1
left join SI_flag spoe -- 'hadm_id', 'suspected_infection_time', 'si_start', 'si_end'
  on ie.hadm_id = spoe.hadm_id
)
select
    t1.hadm_id, t1.icustay_id
  , t1.intime, t1.outtime

  -- set de-identified ages to median of 91.4
  , case when age > 89 then 91.4 else age end as age
  , gender
  , ethnicity
  , first_service
  , dbsource

  -- suspicion using POE
  , suspected_of_infection_poe
  , suspected_infection_time_poe
  , suspected_infection_time_poe_days
  -- , specimen_poe
  -- , positiveculture_poe
  -- , antibiotic_time_poe

  -- exclusions
  , case when t1.rn = 1 then 0 else 1 end as exclusion_secondarystay_INACTIVE
  , case when t1.age <= 14 then 1 else 0 end as exclusion_nonadult -- CHANGED FROM ORIGINAL! <=16
  , case when t1.dbsource != 'metavision' then 1 else 0 end as exclusion_carevue
  , case when t1.suspected_infection_time_poe is not null  -- CHANGED FROM ORIGINAL!
          and t1.suspected_infection_time_poe < t1.intime then 1
      else 0 end as exclusion_suspicion_before_intime_INACTIVE
  , case when t1.suspected_infection_time_poe is not null  -- CHANGED FROM ORIGINAL!
          and t1.suspected_infection_time_poe > t1.intime + interval '4' hour then 1
      else null end as exclusion_suspicion_after_intime_plus_4_INACTIVE
  , case when t1.HAS_CHARTEVENTS_DATA = 0 then 1
         when t1.intime is null then 1
         when t1.outtime is null then 1
      else 0 end as exclusion_bad_data
  -- the above flags are used to summarize patients excluded
  -- below flag is used to actually exclude patients in future queries
  , case when
          t1.age <= 14 -- CHANGED FROM ORIGINAL! <=16
          or t1.HAS_CHARTEVENTS_DATA = 0
          or t1.intime is null
          or t1.outtime is null
          or t1.dbsource != 'metavision'
            then 1
        else 0 end as excluded

from t1
order by t1.icustay_id;