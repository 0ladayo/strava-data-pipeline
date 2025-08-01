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
    "cloudresourcemanager.googleapis.com",
    "workflows.googleapis.com",
    "workflowexecutions.googleapis.com",
    "logging.googleapis.com"
  ])

  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "strava_pipeline" {
  account_id   = "strava-service-account"
  display_name = "Service Account for Strava Data Pipeline"
  project      = data.google_project.project.project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_project_iam_member" "strava_pipeline_permissions" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/run.admin",
    "roles/cloudfunctions.developer",
    "roles/iam.serviceAccountUser",
    "roles/bigquery.jobUser",
    "roles/eventarc.eventReceiver",
    "roles/eventarc.admin",
    "roles/workflows.invoker"
  ])

  project = data.google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.strava_pipeline.email}"
}


resource "google_project_iam_member" "gcs_eventarc_permissions" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "service_agent_invokers" {
  for_each = toset([
    "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com",
    "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com",
    "serviceAccount:service-${data.google_project.project.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
  ])

  project = data.google_project.project.project_id
  role    = "roles/run.invoker"
  member  = each.key
}

resource "google_secret_manager_secret" "strava_credentials" {
  secret_id = "strava-client-secrets"
  project   = data.google_project.project.project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_topic" "strava_activity_events" {
  name    = var.pubsub_topic_id
  project = data.google_project.project.project_id
  depends_on = [google_project_service.required_apis]
}

resource "google_cloudbuild_trigger" "webhook_receiver_build_trigger" {
  location = var.gcp_project_region
  name     = "webhook-receiver-build-trigger"
  service_account = google_service_account.strava_pipeline.id

  repository_event_config {
    repository =  "projects/${data.google_project.project.project_id}/locations/${var.gcp_project_region}/connections/github-connection/repositories/0ladayo-strava-data-pipeline"
    
    push {
      branch = "^main$"
    }
  }
  
  filename = "cloud_functions/pubsub/webhook-receiver.cloudbuild.yml"

  included_files = ["cloud_functions/pubsub/**"]

  substitutions = {
  _LOCATION   = var.gcp_project_region
  _PROJECT_ID = data.google_project.project.project_id
  _SECRET_MANAGER_ID = google_secret_manager_secret.strava_credentials.secret_id
  _TOPIC_ID = google_pubsub_topic.strava_activity_events.name
  _SERVICE_ACCOUNT_EMAIL = google_service_account.strava_pipeline.email
  }
}

resource "google_pubsub_topic_iam_member" "strava_pipeline_publisher" {
  project = data.google_project.project.project_id
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
  name                        = "${var.gcs_bucket_name}-${data.google_project.project.project_id}"
  location                    = var.gcp_project_region
  project                     = data.google_project.project.project_id
  uniform_bucket_level_access = true
  force_destroy               = false
}

resource "google_storage_bucket_iam_member" "state_storage_object_viewer" {
  bucket = google_storage_bucket.state_storage.name
  role = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_storage_bucket" "strava_activity_storage" {
  name                        = "${var.gcs_bucket_name_ii}-${data.google_project.project.project_id}"
  location                    = var.gcp_project_region
  project                     = data.google_project.project.project_id
  uniform_bucket_level_access = true
  force_destroy               = false
}

resource "google_storage_bucket_iam_member" "strava_pipeline_storage_admin" {
  for_each = toset([
    google_storage_bucket.state_storage.name,
    google_storage_bucket.strava_activity_storage.name
  ])

  bucket = each.key
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_cloudbuild_trigger" "activity_extractor_build_trigger" {
  location = var.gcp_project_region
  name     = "activity-extractor-build-trigger"
  service_account = google_service_account.strava_pipeline.id

  repository_event_config {
    repository =  "projects/${data.google_project.project.project_id}/locations/${var.gcp_project_region}/connections/github-connection/repositories/0ladayo-strava-data-pipeline"
    
    push {
      branch = "^main$"
    }
  }
  
  filename = "cloud_functions/extract/activity-extractor.cloudbuild.yml"

  included_files = ["cloud_functions/extract/**"]

  substitutions = {
  _LOCATION   = var.gcp_project_region
  _PROJECT_ID = data.google_project.project.project_id
  _TOPIC_ID = google_pubsub_topic.strava_activity_events.name
  _STATE_AUTH_BUCKET = google_storage_bucket.state_storage.name
  _STRAVA_ACTIVITY_BUCKET = google_storage_bucket.strava_activity_storage.name
  _SECRET_MANAGER_ID = google_secret_manager_secret.strava_credentials.secret_id
  _BIGQUERY_DATASET_ID = google_bigquery_dataset.strava_activities.dataset_id
  _BIGQUERY_TABLE_ID = google_bigquery_table.activity_data.table_id
  _SERVICE_ACCOUNT_EMAIL = google_service_account.strava_pipeline.email
  }
}

resource "google_bigquery_dataset" "strava_activities" {
  dataset_id                 = var.bigquery_dataset_id
  friendly_name              = "strava activities Dataset"
  location                   = var.gcp_project_region
  project                    = data.google_project.project.project_id
  delete_contents_on_destroy = false

  depends_on = [google_project_service.required_apis]
}

resource "google_bigquery_table" "activity_data" {
  dataset_id          = google_bigquery_dataset.strava_activities.dataset_id
  table_id            = var.bigquery_table_id
  project             = data.google_project.project.project_id
  deletion_protection = true

  schema = jsonencode([
    {
      name        = "id"
      type        = "INTEGER"
      mode        = "REQUIRED"
      description = "The unique identifier for the activity"
    },
    {
      name = "distance"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name        = "time"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Elapsed time in seconds"
    },
    {
      name = "elevation_high"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "elevation_low"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "elevation_gain"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "average_speed"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "maximum_speed"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "start_latitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "start_longitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "end_latitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "end_longitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "average_cadence"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name        = "start_datetime"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "The start time of the activity"
    },
    {
      name        = "end_datetime"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "The end time of the activity"
    }
  ])
}

resource "google_bigquery_dataset_iam_member" "strava_pipeline_bigquery_permissions" {
  dataset_id = google_bigquery_dataset.strava_activities.dataset_id
  project    = google_bigquery_dataset.strava_activities.project
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_cloudbuild_trigger" "activity_loader_build_trigger" {
  location = var.gcp_project_region
  name     = "activity-loader-build-trigger"
  service_account = google_service_account.strava_pipeline.id

  repository_event_config {
    repository =  "projects/${data.google_project.project.project_id}/locations/${var.gcp_project_region}/connections/github-connection/repositories/0ladayo-strava-data-pipeline"
    
    push {
      branch = "^main$"
    }
  }
  
  filename = "cloud_functions/load/activity-loader.cloudbuild.yml"

  included_files = ["cloud_functions/load/**"]

  substitutions = {
  _LOCATION   = var.gcp_project_region
  _PROJECT_ID = data.google_project.project.project_id
  _STRAVA_ACTIVITY_BUCKET = google_storage_bucket.strava_activity_storage.name
  _BIGQUERY_DATASET_ID = google_bigquery_dataset.strava_activities.dataset_id
  _BIGQUERY_TABLE_ID = google_bigquery_table.activity_data.table_id
  _SERVICE_ACCOUNT_EMAIL = google_service_account.strava_pipeline.email
  }
}

resource "google_artifact_registry_repository" "strava-transformation-repository" {
  project       = data.google_project.project.project_id
  location      = var.gcp_project_region
  repository_id = "strava-pipeline-transformation-repository"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_member" "dbt_repo_writer" {
  project = google_artifact_registry_repository.strava-transformation-repository.project
  location = google_artifact_registry_repository.strava-transformation-repository.location
  repository = google_artifact_registry_repository.strava-transformation-repository.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_artifact_registry_repository_iam_member" "dbt_repo_reader" {
  location   = google_artifact_registry_repository.strava-transformation-repository.location
  repository = google_artifact_registry_repository.strava-transformation-repository.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_cloudbuild_trigger" "dbt_image_build_trigger" {
  name            = "dbt-image-build-trigger"
  location        = var.gcp_project_region
  project         = data.google_project.project.project_id
  service_account = google_service_account.strava_pipeline.id

  repository_event_config {
    repository = "projects/${data.google_project.project.project_id}/locations/${var.gcp_project_region}/connections/github-connection/repositories/0ladayo-strava-data-pipeline"
    push {
      branch = "^main$"
    }
  }
  
  filename = "cloud_functions/transform/dbt-transformation.cloudbuild.yml"

  included_files = [
    "cloud_functions/transform/**"
  ]

  substitutions = {
    _LOCATION       = var.gcp_project_region
    _PROJECT_ID     = data.google_project.project.project_id
    _REPO_ID        = google_artifact_registry_repository.strava-transformation-repository.repository_id
    _BIGQUERY_DATASET_ID = google_bigquery_dataset.strava_activities.dataset_id
  }
}

resource "google_workflows_workflow" "dbt_transformation_workflow" {
  name            = "dbt-transformation-workflow"
  region          = var.gcp_project_region
  project         = data.google_project.project.project_id
  description     = "executes the dbt cloud run job when a BigQuery load job completes."
  service_account = google_service_account.strava_pipeline.email

  source_contents = <<-EOF
  main:
    params: [event]
    steps:
      - init:
          assign:
            - project_id: ${data.google_project.project.project_id}
            - job_location: ${var.gcp_project_region}
            - job_name: "dbt-run-job"
      
      - check_event_type:
          switch:
            - condition: $${event.data.protoPayload.serviceData.jobCompletedEvent.eventName == "load_job_completed"}
              next: execute_dbt_job
          next: end 
          
      - execute_dbt_job:
          call: googleapis.run.v2.projects.locations.jobs.run
          args:
            name: $${"projects/" + project_id + "/locations/" + job_location + "/jobs/" + job_name}
            body: {}
          result: job_execution
      - finish:
          return: $${job_execution}
  EOF
}

resource "google_eventarc_trigger" "bigquery_load_event_trigger" {
  name     = "bigquery-load-event-trigger"
  location = var.gcp_project_region
  
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }
  matching_criteria {
    attribute = "serviceName"
    value     = "bigquery.googleapis.com"
  }
  matching_criteria {
    attribute = "methodName"
    value     = "jobservice.jobcompleted"
  }
  destination {
    workflow = google_workflows_workflow.dbt_transformation_workflow.id
  }
  service_account = google_service_account.strava_pipeline.id

  depends_on = [google_project_service.required_apis]
}