import os
import pandas as pd
from google.cloud import bigquery
import pandas_gbq
import gcsfs
import pyarrow


def main(event, context):
    try:
        project_id = os.environ['GCP_PROJECT_ID']
        dataset_id = os.environ['BIGQUERY_DATASET_ID']
        table_id = os.environ['BIGQUERY_TABLE_ID']
        strava_activity_bucket = event['bucket']
        latest_file_name = event['name']
    except KeyError as e:
        raise ValueError(f'Missing required environment variable or event attribute: {e}') from e
 
    try:
        gcs_path = f'gs://{strava_activity_bucket}/{latest_file_name}'
        df = pd.read_parquet(gcs_path)
    except Exception as e:
        raise ConnectionError(f'Failed to read parquet file from {gcs_path}') from e

    try:
        destination_table = f'{dataset_id}.{table_id}'
        client_bigquery = bigquery.Client()
        query = (f'SELECT id FROM `{project_id}.{destination_table}`')
        query_job = client_bigquery.query(query)
        existing_ids = {row['id'] for row in query_job}
        
        new_data_df = df[~df['id'].isin(list(existing_ids))]

        if not new_data_df.empty:
            pandas_gbq.to_gbq(new_data_df, destination_table, project_id=project_id, if_exists='append')
            print(f'Successfully appended {len(new_data_df)} new rows to {destination_table}')
        else:
            print(f'No new data to append after deduplication.')

    except Exception as e:
        raise ConnectionError(f'Failed to write data to BigQuery table {destination_table}') from e

    return 'Function executed successfully'