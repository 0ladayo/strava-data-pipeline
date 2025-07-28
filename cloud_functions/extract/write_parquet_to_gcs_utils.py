import os
from google.cloud import bigquery
import json
import pyarrow
import gcsfs
from write_json_to_gcs_utils import upload_json_object_to_gcs
import pandas as pd

def write_parquet_to_gcs(project_id, stravadata_df, strava_activity_bucket, state_auth_bucket, state_data):
    try:
        dataset_id = os.environ['BIGQUERY_DATASET_ID']
        table_id = os.environ['BIGQUERY_TABLE_ID']
        client_bigquery = bigquery.Client()
        query = (f'SELECT id FROM `{project_id}.{dataset_id}.{table_id}`')
        query_job = client_bigquery.query(query)
        existing_ids = {row['id'] for row in query_job}
        new_stravadata_df = stravadata_df[~stravadata_df['id'].isin(list(existing_ids))]

        if not new_stravadata_df.empty:
            LAST_ACTIVITY_DT = new_stravadata_df['end_datetime'].max().isoformat()
            output_filename = f'activity_{pd.to_datetime(LAST_ACTIVITY_DT).strftime('%Y-%m-%d_%H-%M-%S')}.parquet'
            gcs_path = f'gs://{strava_activity_bucket}/{output_filename}'
            print(f"Writing new data to {gcs_path}...")
            new_stravadata_df.to_parquet(gcs_path, engine = 'pyarrow', index = False)
            state_data['last_activity_dt'] = LAST_ACTIVITY_DT
            print('Successfully wrote new data')
            upload_json_object_to_gcs(state_auth_bucket, 'state.json', state_data)
            print('Successfully updated state.json in GCS.')
            return new_stravadata_df
        else:
            print('No new activities to load after filtering')
            return None

    except Exception as e:
        raise ConnectionError(f'An error occurred during BigQuery deduplication or GCS write: {e}') from e