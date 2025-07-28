from google.cloud import storage
import json

def upload_json_object_to_gcs(bucket_name, destination_blob_name, json_object):
    """Uploads a JSON object to a Google Cloud Storage bucket.
    """
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        json_string = json.dumps(json_object, indent=2)
        blob.upload_from_string(json_string, content_type='application/json')
        print(f"JSON object uploaded to gs://{bucket_name}/{destination_blob_name}")
        return True
    except Exception as e:
        raise ConnectionError(f"Failed to upload '{destination_blob_name}' to bucket '{bucket_name}': {e}") from e