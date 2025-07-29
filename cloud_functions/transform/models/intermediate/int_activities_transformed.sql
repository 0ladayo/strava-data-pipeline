with source_data as (
    select * 
    from {{ ref('stg_strava_activity') }}
),

transformed_data as (
    select
    strava_activity_id,
    round(distance / 1000, 2) as distance_km,
    round(time / 60, 2) as elapsed_time_mins,
    round(elevation_gain / 1000, 4) as elevation_gain_km,
    DATE(start_datetime) as activity_date
    from source_data
)

select * from transformed_data