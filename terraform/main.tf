provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_project_region
  zone    = var.gcp_project_zone
}

data "google_project" "project" {}

resource "google_project_service" "required_apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "strava_pipeline" {
  account_id   = "strava-service-account"
  display_name = "Service Account for Strava Data Pipeline"
  project      = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_project_iam_member" "strava_pipeline_permissions" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/run.admin",
    "roles/cloudfunctions.developer",
    "roles/iam.serviceAccountUser"
  ])

  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.strava_pipeline.email}"
}


resource "google_project_iam_member" "gcs_eventarc_permissions" {
  project = var.gcp_project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "service_agent_invokers" {
  for_each = toset([
    "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com",
    "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
  ])

  project = var.gcp_project_id
  role    = "roles/run.invoker"
  member  = each.key
}

resource "google_secret_manager_secret" "strava_credentials" {
  secret_id = "strava-client-secrets"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_topic" "strava_activity_events" {
  name    = var.pubsub_topic_id
  project = var.gcp_project_id
  depends_on = [google_project_service.required_apis]
}

resource "google_cloudbuild_trigger" "webhook_receiver_build_trigger" {
  location = var.gcp_project_region
  name     = "webhook-receiver-build-trigger"
  service_account = google_service_account.strava_pipeline.id

  repository_event_config {
    repository =  "projects/${var.gcp_project_id}/locations/${var.gcp_project_region}/connections/github-connection/repositories/0ladayo-strava-data-pipeline"
    
    push {
      branch = "^main$"
    }
  }
  
  filename = "cloud_functions/pubsub/webhook-receiver.cloudbuild.yml"

  included_files = ["cloud_functions/pubsub/**"]

  substitutions = {
  _LOCATION   = var.gcp_project_region
  _PROJECT_ID = var.gcp_project_id
  _SECRET_MANAGER_ID = google_secret_manager_secret.strava_credentials.secret_id
  _TOPIC_ID = google_pubsub_topic.strava_activity_events.name
  _SERVICE_ACCOUNT_EMAIL = google_service_account.strava_pipeline.email
  }
}

resource "google_pubsub_topic_iam_member" "strava_pipeline_publisher" {
  project = var.gcp_project_id
  topic   = google_pubsub_topic.strava_activity_events.id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_secret_manager_secret_iam_member" "strava_secret_accessor" {
  project   = google_secret_manager_secret.strava_credentials.project
  secret_id = google_secret_manager_secret.strava_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_storage_bucket" "state_storage" {
  name                        = "${var.gcs_bucket_name}-${var.gcp_project_id}"
  location                    = var.gcp_project_region
  project                     = var.gcp_project_id
  uniform_bucket_level_access = true
  force_destroy               = false
}

resource "google_storage_bucket_iam_member" "state_storage_object_viewer" {
  bucket = google_storage_bucket.state_storage.name
  role = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_storage_bucket" "strava_activity_storage" {
  name                        = "${var.gcs_bucket_name_ii}-${var.gcp_project_id}"
  location                    = var.gcp_project_region
  project                     = var.gcp_project_id
  uniform_bucket_level_access = true
  force_destroy               = false
}

resource "google_storage_bucket_iam_member" "strava_activity_storage_writer" {
  bucket = google_storage_bucket.strava_activity_storage.name
  role = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_cloudbuild_trigger" "activity_extractor_build_trigger" {
  location = var.gcp_project_region
  name     = "activity-extractor-build-trigger"
  service_account = google_service_account.strava_pipeline.id

  repository_event_config {
    repository =  "projects/${var.gcp_project_id}/locations/${var.gcp_project_region}/connections/github-connection/repositories/0ladayo-strava-data-pipeline"
    
    push {
      branch = "^main$"
    }
  }
  
  filename = "cloud_functions/extract/activity-extractor.cloudbuild.yml"

  included_files = ["cloud_functions/extract/**"]

  substitutions = {
  _LOCATION   = var.gcp_project_region
  _PROJECT_ID = var.gcp_project_id
  _TOPIC_ID = google_pubsub_topic.strava_activity_events.name
  _STATE_AUTH_BUCKET = var.gcs_bucket_name
  _STRAVA_ACTIVITY_BUCKET = var.gcs_bucket_name_ii
  _SECRET_MANAGER_ID = google_secret_manager_secret.strava_credentials.secret_id
  _SERVICE_ACCOUNT_EMAIL = google_service_account.strava_pipeline.email
  }
}