resource "google_dataform_repository" "world_cup_elt_dataform_repo" {
  provider = google-beta

  project = var.project_id
  name    = var.dataform_repo_name
  region  = var.region

  service_account = var.service_account_email

  workspace_compilation_overrides {
    default_database = var.project_id
  }
  git_remote_settings {
    url            = "ssh://git@github.com/tosun-si/${var.dataform_repo_name}.git"
    default_branch = "main"
    ssh_authentication_config {
      user_private_key_secret_version = local.github_account_private_ssh_key_secret_version
      host_public_key                 = local.github_account_host_public_ssh_key_value
    }
  }
}

# One release config per environment. CI/CD owns `git_commitish` and the released
# compilation result (see scripts/dataform/release.sh); Terraform owns the compilation overrides.
# No cron schedule: compilation is triggered by CI/CD only.
resource "google_dataform_repository_release_config" "release_configs" {
  provider = google-beta
  for_each = local.dataform_environments

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.world_cup_elt_dataform_repo.name

  name          = each.key
  git_commitish = "main"

  dynamic "code_compilation_config" {
    for_each = each.value.schema_suffix == null ? [] : [each.value]
    content {
      schema_suffix = code_compilation_config.value.schema_suffix
    }
  }

  lifecycle {
    ignore_changes = [git_commitish]
  }
}

# Invoked by Airflow: executes the currently released compilation result of the release config.
# No cron schedule: orchestration is done by Airflow.
resource "google_dataform_repository_workflow_config" "workflow_configs" {
  provider = google-beta
  for_each = local.dataform_environments

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.world_cup_elt_dataform_repo.name

  name           = each.key
  release_config = google_dataform_repository_release_config.release_configs[each.key].id

  invocation_config {
    service_account = var.service_account_email
  }
}

# CI/CD service accounts (created by scripts/setup/setup_ci_cd_iam.sh), one per GitHub environment.
# Predefined role scoped to this repository only: roles/dataform.editor can't update release configs,
# and a repository-level grant keeps the other repositories of the project out of reach.
resource "google_dataform_repository_iam_member" "ci_cd_admin" {
  provider = google-beta
  for_each = local.dataform_environments

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.world_cup_elt_dataform_repo.name

  role   = "roles/dataform.admin"
  member = "serviceAccount:sa-dataform-ci-${each.key}@${var.project_id}.iam.gserviceaccount.com"
}
