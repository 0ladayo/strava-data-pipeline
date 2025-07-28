import os
from secrets_utils import access_secret_version, get_required_secret
import gcsfs
from datetime import datetime, timedelta, timezone
from read_json_from_gcs_utils import read_json_from_gcs
import json
from refresh_access_token_utils import refresh_access_token
from stravalib.client import Client
from extract_data_utils import get_activity_data
import pandas as pd
from write_parquet_to_gcs_utils import write_parquet_to_gcs

def main(event, context):
    try:
        project_id = os.environ['GCP_PROJECT_ID']
        secret_id = os.environ['SECRET_MANAGER_ID']
        strava_activity_bucket = os.environ['STRAVA_ACTIVITY_BUCKET']
        state_auth_bucket = os.environ['STATE_AUTH_BUCKET']
    except Exception as e:
        raise ValueError(f"Missing required environment variable: {e}") from e

    secrets = access_secret_version(project_id, secret_id)
    STRAVA_CLIENT_ID = int(get_required_secret(secrets, 'client_id'))
    STRAVA_CLIENT_SECRET = get_required_secret(secrets, 'client_secret')
    REFRESH_TOKEN = get_required_secret(secrets, 'refresh_token')

    state_data = read_json_from_gcs(state_auth_bucket, 'state.json')

    if state_data:
        EXPIRES_AT = state_data['expires_at']
        EXPIRES_AT_DT = datetime.fromtimestamp(int(EXPIRES_AT), tz=timezone.utc)
        LAST_ACTIVITY_DT = state_data['last_activity_dt']
    else:
        raise ValueError('state.json is empty or invalid')

    try:
        if datetime.now(timezone.utc) > EXPIRES_AT_DT:
            ACCESS_TOKEN, state_data = refresh_access_token(STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, REFRESH_TOKEN, state_data,  state_auth_bucket)
        else:
            ACCESS_TOKEN = state_data['access_token']
    except Exception as e:
        raise ConnectionError('Could not obtain a valid access token') from e

    try:
        client = Client(access_token = ACCESS_TOKEN)
        activities = client.get_activities(after = LAST_ACTIVITY_DT)
    except Exception as e:
        raise ConnectionError('Error getting Strava activities') from e

    all_activities = get_activity_data(activities)
    stravadata_df = pd.DataFrame(all_activities)

    if stravadata_df.empty:
        return 'No new activities found'

    else:
        try:
            write_parquet_to_gcs(project_id, stravadata_df, strava_activity_bucket, state_auth_bucket, state_data)
        except Exception as e:
            raise IOError('Failed to write data to GCS') from e

        return 'Function executed successfully.'