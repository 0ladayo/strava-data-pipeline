# Strava Data Pipeline

This project is a data pipeline that extracts data from the Strava API, loads it into Google BigQuery, and then transforms it using dbt. The entire infrastructure is deployed on Google Cloud Platform (GCP) and managed with Terraform.

## Architecture

The data pipeline is built on a serverless architecture using various GCP services. The main components are:

-   **Terraform:** The slow changing infrastructure is defined as a code using Terraform.
-   **Strava API:** The source of the data. The pipeline uses a webhook to receive real-time updates for new activities.
-   **Google Cloud Functions:** These are used for the individual processing steps of the pipeline:
    -   **Webhook Receiver:** A Cloud Function that receives webhook events from Strava.
    -   **Activity Extractor:** A Cloud Function that fetches detailed activity data from the Strava API.
    -   **Activity Loader:** A Cloud Function that loads the extracted data from Cloud Storage into BigQuery.
-   **Google Pub/Sub:** A messaging service that decouples the different stages of the pipeline.
-   **Google Cloud Storage:** Used as a staging area to store the raw activity data before it is loaded into BigQuery.
-   **Google BigQuery:** A data warehouse used to store and analyze the Strava activity data.
-   **dbt (Data Build Tool):** Used to transform the data within BigQuery after it has been loaded. The dbt models are executed as a Cloud Run job.
-   **Google Cloud Build:** Used for CI/CD. Cloud Build automatically builds and deploys the Cloud Functions and the dbt Docker image when changes are pushed to the main branch.
-   **Google Secret Manager:** Used to store the Strava API credentials.
-   **Google Eventarc & Workflows:** Used to orchestrate the dbt transformation job. An Eventarc trigger listens for BigQuery load job completion events and triggers a Workflow that runs the dbt Cloud Run job.

## ELT Process

The ELT (Extract, Load, Transform) process is as follows:

1.  **Extract:**
    -   A webhook event is sent from Strava to the `webhook-receiver` Cloud Function.
    -   The `webhook-receiver` function publishes the full event payload to a Pub/Sub topic.
    -   The `activity-extractor` function is triggered by this message. It reads a timestamp from a state file, calls the Strava API to fetch all new activities since that time, and saves the data as a Parquet file to a Google Cloud Storage bucket.

2.  **Load:**
    -   The `activity-loader` Cloud Function is triggered when a new Parquet file is uploaded to the Cloud Storage bucket.
    -   This function reads the data from the Parquet file and loads it into the main BigQuery table.

3.  **Transform:**
    -   An Eventarc trigger is configured to listen for "load job completed" events in BigQuery.
    -   When a load job finishes, the trigger invokes a Google Workflow.
    -   The Workflow starts a Cloud Run job that runs a dbt command to transform the raw data in BigQuery. The transformed data is stored in a set of tables within the same BigQuery dataset.

## Infrastructure

All the necessary cloud infrastructure for this project is managed as code using Terraform. The Terraform files are located in the `terraform/` directory.

-   **`main.tf`**: This file contains the core infrastructure definitions, including the GCP services like Cloud Functions, Pub/Sub, BigQuery, and Cloud Storage buckets.
-   **`variables.tf`**: This file defines the variables used in the Terraform configuration, such as the GCP project ID and region.
-   **`backend.tf`**: This file configures the Terraform backend, which is where Terraform stores its state. It is configured to use a Google Cloud Storage bucket for remote state storage.

## Deployment

To deploy this project, you will need to have the following prerequisites:

-   [Terraform](https://www.terraform.io/downloads.html)
-   A GCP project with billing enabled
-   A Strava account and API application

### Configuration

1.  **Set up Strava API Credentials:**
    -   Create a Strava API application to get your client ID, client secret, and refresh token.
    -   Store these credentials in GCP Secret Manager with the secret ID `strava-client-secrets`. The secret should be a JSON string with the keys `client_id`, `client_secret`, and `refresh_token`.

2.  **Configure Terraform Variables:**
    -   Create a file named `terraform.tfvars` in the `terraform/` directory.
    -   Add the following variables to this file:
        ```hcl
        gcp_project_id     = "your-gcp-project-id"
        gcp_project_region = "your-gcp-region"
        gcp_project_zone   = "your-gcp-zone"
        gcs_bucket_name    = "state_bucket_name"
        gcs_bucket_name_ii = "activity_data_bucket_name"
        pubsub_topic_id    = "your-pubsub-topic-id"
        bigquery_dataset_id = "your-bigquery-dataset-id"
        bigquery_table_id  = "your-bigquery-table-id"
        ```

### Deploy the Infrastructure

1.  **Initialize Terraform:**
    ```bash
    cd terraform
    terraform init
    ```

2.  **Plan the Deployment:**
    ```bash
    terraform plan
    ```

3.  **Apply the Configuration:**
    ```bash
    terraform apply
    ```

### Strava Webhook Setup

After the infrastructure and functions are deployed, you must create a webhook subscription so Strava can send events to your pipeline.

**Get the Webhook URL:**
Get the URL for your `webhook-receiver` function from the Google Cloud Console.

**Create the Webhook Subscription:**
Run the following curl command in your terminal. Replace the placeholder values with your actual Strava credentials and the function URL from the previous step.

```bash
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
     -F client_id=YOUR_CLIENT_ID \
     -F client_secret=YOUR_CLIENT_SECRET \
     -F callback_url=YOUR_FUNCTION_URL \
     -F verify_token=YOUR_VERIFY_TOKEN
