terraform {
  backend "gcs" {
    bucket  = "strava-data-project-467107-tf-state"
    prefix  = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}