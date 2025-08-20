with activities as (
    select *
    from {{ ref('int_activities_transformed') }}
),

monthly_summary as (
    select 
    DATE_TRUNC(activity_date, MONTH) as period,
    'Monthly' as granularity,
    sum(distance_km) as total_distance_km,
    sum(elevation_gain_km) as total_elevation_gain_km,
    count(strava_activity_id) as total_runs,
    case
    when sum(distance_km) > 0 then
    round(sum(elapsed_time_mins) / sum(distance_km), 2)
    else 0
    end as average_pace_mins_per_km

    from activities
    group by period, granularity
)

Select * from monthly_summary