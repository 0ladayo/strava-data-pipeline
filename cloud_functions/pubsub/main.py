import os
from secrets_utils import access_secret_version, get_required_secret
from google.cloud import pubsub_v1

try:
    secret_id = os.environ['SECRET_MANAGER_ID']
    topic_id = os.environ['TOPIC_ID']
    project_id = os.environ['GCP_PROJECT_ID']
except Exception as e:
    raise ValueError(f"Missing required environment variable: {e}") 

publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(project_id, topic_id)

def main(request):
    """
    HTTP Cloud Function to act as a Strava webhook.
    - Handles Strava's subscription verification GET request.
    - Handles new activity POST requests by publishing a message to Pub/Sub.
    """
    if request.method == 'GET':
        secrets = access_secret_version(project_id, secret_id)
        VERIFY_TOKEN = get_required_secret(secrets, 'strava_verify_token')
        mode = request.args.get('hub.mode')
        challenge = request.args.get('hub.challenge')
        verify_token = request.args.get('hub.verify_token')
        
        if mode == 'subscribe' and verify_token == VERIFY_TOKEN:
            response = {"hub.challenge": challenge}
            return response
        else:
            return 'Forbidden', 403

    elif request.method == 'POST':
        try:
            print("Webhook received. Publishing message to Pub/Sub...")
            publisher.publish(topic_path, b'New activity created')
            print(f"Message successfully queued for publishing to {topic_path}.")
            return 'OK', 200
        except Exception as e:
            print(f"An error occurred while queueing the message for Pub/Sub: {e}")
            return 'Error publishing message', 500

    else:
        return 'Method Not Allowed', 405