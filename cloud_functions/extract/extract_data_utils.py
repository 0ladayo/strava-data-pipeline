from datetime import datetime, timedelta

def get_parameter_data(activity, parameter, additional_attr = None, required = True):
    """
    Gets a direct or nested attribute from a Strava activity object.
    If required is True and the data is missing, it raises a ValueError.
    If required is False and the data is missing, it returns None.
    """
    obj = getattr(activity, parameter, None)
    if obj is None:
        if required:
            raise ValueError(f'Required activity parameter "{parameter}" was not found or is None for activity {activity.id}.')
        return None
        
    if additional_attr:
        value = getattr(obj, additional_attr, None)
    else:
        value = obj

    if value is None and required:
        raise ValueError(f'Required activity value for "{parameter}" is None for activity {activity.id}.')
    return value


def get_activity_data(activities):
    all_activities = []
    try:
        for activity in activities:
            start_datetime = get_parameter_data(activity, 'start_date')
            elapsed_time = get_parameter_data(activity, 'elapsed_time')
            elapsed_timedelta = int(elapsed_time) if elapsed_time else None
            data_dict = {
                'id': get_parameter_data(activity, 'id'),
                'distance': get_parameter_data(activity, 'distance'),
                'time': elapsed_timedelta,
                'elevation_high': get_parameter_data(activity, 'elev_high', required=False),
                'elevation_low': get_parameter_data(activity, 'elev_low', required=False),
                'elevation_gain': get_parameter_data(activity, 'total_elevation_gain'),
                'average_speed': get_parameter_data(activity, 'average_speed'),
                'maximum_speed': get_parameter_data(activity, 'max_speed'),
                'start_latitude': get_parameter_data(activity, 'start_latlng', 'lat', required=False),
                'start_longitude': get_parameter_data(activity, 'start_latlng', 'lon', required=False),
                'end_latitude': get_parameter_data(activity, 'end_latlng', 'lat', required=False),
                'end_longitude': get_parameter_data(activity, 'end_latlng', 'lon', required=False),
                'average_cadence': get_parameter_data(activity, 'average_cadence', required=False),
                'start_datetime': start_datetime,
                'end_datetime': start_datetime + timedelta(seconds = elapsed_timedelta) if start_datetime and elapsed_timedelta else None
            }
            all_activities.append(data_dict)
        return all_activities
    except Exception as e:
        raise ConnectionError(f"Could not get the activity data: {e}") from e