from google.cloud import storage
import json

def read_json_from_gcs(bucket_name, file_path):
    """
    Reads a JSON file from a GCS bucket.
    """
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_path)
        json_bytes= blob.download_as_bytes()
        data = json.loads(json_bytes)
        return data
    except Exception as e:
        raise ConnectionError(f"Failed to read '{file_path}' from bucket '{bucket_name}': {e}") from e