with activities as (
    select *
    from {{ ref('int_activities_transformed') }}
),

weekly_summary as (
    select 
    DATE_TRUNC(activity_date, WEEK) as week_start,
    sum(distance_km) as total_distance_km,
    sum(elevation_gain_km) as total_elevation_gain_km,
    count(strava_activity_id) as total_runs,
    case
    when sum(distance_km) > 0 then
    round(sum(elapsed_time_mins) / sum(distance_km), 2)
    else 0
    end as average_pace_mins_per_km

    from activities
    group by 1
)

Select * from weekly_summary