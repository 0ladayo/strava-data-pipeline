select
    id as strava_activity_id,
    distance,
    time,
    elevation_gain,
    average_speed,
    start_datetime,
from {{ source('strava_activity', 'strava_activity_table') }}