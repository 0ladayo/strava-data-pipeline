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

resource "google_artifact_registry_repository" "webhook_receiver_repo" {
  location      = var.gcp_project_region
  repository_id = "strava-pipeline-webhook-receiver-repo"
  format        = "DOCKER"
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
  
  filename = "cloudbuild.yml"

  included_files = ["cloud_functions/pubsub/**"]

  substitutions = {
  _REPO_ID    = google_artifact_registry_repository.webhook_receiver_repo.repository_id
  _LOCATION   = var.gcp_project_region
  _PROJECT_ID = var.gcp_project_id
  _SECRET_MANAGER_ID = google_secret_manager_secret.strava_credentials.secret_id
  _TOPIC_ID = google_pubsub_topic.strava_activity_events.name
  __SERVICE_ACCOUNT_EMAIL = google_service_account.strava_pipeline.email
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