import json
from google.cloud import secretmanager

def access_secret_version(project_id, secret_id, version_id = 'latest'):
    """
    Access the payload for the given secret version.
    """
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/{version_id}"
        response = client.access_secret_version(request={'name': name})
        payload = response.payload.data.decode('UTF-8')
        secrets = json.loads(payload)
        return secrets
    except Exception as e:
        raise ConnectionError(f"error accessing secret: {e}") from e

def get_required_secret(secrets, secret_name):
    """Gets a required secret credentials or raises an error."""
    value = secrets.get(secret_name)
    if value is None:
        raise ValueError(f'Required secret {secret_name} is not set in secret manager')
    return value