#!/usr/bin/env bash
# One-shot setup of the IAM for the Dataform CI/CD with GitHub Actions:
#   - restricts the Workload Identity Federation provider to known GitHub owners
#   - creates one CI/CD service account per GitHub environment (dev, prd)
#   - lets each GitHub environment impersonate only its own service account
# The Dataform role of the CI/CD service accounts is granted on the repository by Terraform
# (infra/world_cup_elt_dataform), so run this script before `terraform apply`.
# Idempotent: can be run several times.

set -euo pipefail

readonly PROJECT_ID="gb-poc-373711"
readonly PROJECT_NUMBER="975119474255"
readonly WIF_POOL="gb-github-actions-ci-cd-pool"
readonly WIF_PROVIDER="gb-github-actions-ci-cd-provider"
readonly GITHUB_REPOSITORY="tosun-si/world-cup-qatar-elt-dataform"
readonly DATAFORM_SA="sa-dataform-dev@${PROJECT_ID}.iam.gserviceaccount.com"
readonly DATASET="qatar_fifa_world_cup_dataform"
readonly ASSERTION_DATASET="qatar_fifa_world_cup_dataform_assertions"

# A new service account can take a few seconds to be visible to IAM policies.
wait_for_service_account() {
  local sa_email="$1"
  for _ in $(seq 1 12); do
    if gcloud iam service-accounts describe "${sa_email}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
      sleep 10
      return 0
    fi
    sleep 5
  done
  echo "Service account ${sa_email} not found after 60s" >&2
  return 1
}

echo "### 1. Restrict the WIF provider to known GitHub owners"
gcloud iam workload-identity-pools providers update-oidc "${WIF_PROVIDER}" \
  --workload-identity-pool="${WIF_POOL}" \
  --location=global \
  --project="${PROJECT_ID}" \
  --attribute-condition="assertion.repository_owner in ['tosun-si', 'groupbees']"

echo "### 2. Remove the project-level Dataform roles and custom roles of a previous setup"
for env in dev prd; do
  sa_email="sa-dataform-ci-${env}@${PROJECT_ID}.iam.gserviceaccount.com"
  for role in roles/dataform.editor "projects/${PROJECT_ID}/roles/dataformReleaser" "projects/${PROJECT_ID}/roles/bigqueryDatasetCleaner"; do
    # Fails when the binding doesn't exist: nothing to remove.
    gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${sa_email}" --role="${role}" --all --quiet >/dev/null 2>&1 || true
  done
done
for role_id in dataformReleaser bigqueryDatasetCleaner; do
  if gcloud iam roles describe "${role_id}" --project="${PROJECT_ID}" --format='value(deleted)' 2>/dev/null | grep -qv True; then
    gcloud iam roles delete "${role_id}" --project="${PROJECT_ID}" --quiet >/dev/null
    echo "Deleted custom role ${role_id}"
  fi
done

echo "### 3. CI/CD service accounts"
for env in dev prd; do
  sa_name="sa-dataform-ci-${env}"
  sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"

  if ! gcloud iam service-accounts describe "${sa_email}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud iam service-accounts create "${sa_name}" \
      --project="${PROJECT_ID}" \
      --display-name="Dataform CI/CD - ${env}"
  fi
  wait_for_service_account "${sa_email}"

  # Dataform checks actAs on the repository service account when invoking a workflow.
  gcloud iam service-accounts add-iam-policy-binding "${DATAFORM_SA}" \
    --project="${PROJECT_ID}" \
    --member="serviceAccount:${sa_email}" \
    --role="roles/iam.serviceAccountUser" --quiet >/dev/null
  echo "Granted actAs on ${DATAFORM_SA} to ${sa_email}"

  # Only the jobs of this repository running in the matching GitHub environment can impersonate the SA.
  # The GitHub OIDC `sub` claim is `repo:<owner>/<repo>:environment:<env>` for jobs using an environment.
  gcloud iam service-accounts add-iam-policy-binding "${sa_email}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/subject/repo:${GITHUB_REPOSITORY}:environment:${env}" \
    --quiet >/dev/null
  echo "GitHub environment ${env} can impersonate ${sa_email}"
done

echo "### 4. Deletion of the PR datasets (dev only)"
# Predefined role, restricted by an IAM condition to the datasets created for the PRs.
condition_file=$(mktemp)
trap 'rm -f "${condition_file}"' EXIT
cat > "${condition_file}" <<EOF
title: dataform_pr_datasets_only
description: Datasets created by the Dataform CI for pull requests
expression: >-
  resource.name.startsWith("projects/${PROJECT_ID}/datasets/${DATASET}_pr_") ||
  resource.name.startsWith("projects/${PROJECT_ID}/datasets/${ASSERTION_DATASET}_pr_")
EOF
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:sa-dataform-ci-dev@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataOwner" \
  --condition-from-file="${condition_file}" --quiet >/dev/null
echo "Granted roles/bigquery.dataOwner on the PR datasets to sa-dataform-ci-dev"
