import os
from stravalib.client import Client
from write_json_to_gcs_utils import upload_json_object_to_gcs

def refresh_access_token(STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, REFRESH_TOKEN, state_data, state_auth_bucket):
    """Refresh the access token and immediately upload the updated state to GCS."""
    try:
        client = Client()
        refresh_response = client.refresh_access_token(
            client_id = STRAVA_CLIENT_ID,
            client_secret = STRAVA_CLIENT_SECRET,
            refresh_token = REFRESH_TOKEN,
        )
        state_data['access_token'] = refresh_response['access_token']
        state_data['expires_at'] = str(refresh_response['expires_at'])
        upload_json_object_to_gcs(state_auth_bucket, 'state.json', state_data)
        print('Token refreshed successfully!')
        return refresh_response['access_token'], state_data
        
    except Exception as e:
        raise ConnectionError(f'Error refreshing token: {e}') from e