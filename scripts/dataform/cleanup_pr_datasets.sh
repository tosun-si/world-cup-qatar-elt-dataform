#!/usr/bin/env bash
# Deletes the BigQuery datasets created for a PR by run_pr_pipeline.sh.
#
# Usage: cleanup_pr_datasets.sh <pr number>

source "$(dirname "$0")/lib.sh"

readonly PR_NUMBER="${1:?PR number is required}"

for base_dataset in "$(workflow_setting defaultDataset)" "$(workflow_setting defaultAssertionDataset)"; do
  dataset="${GCP_PROJECT_ID}:${base_dataset}_pr_${PR_NUMBER}"
  if bq show --format=none "${dataset}" >/dev/null 2>&1; then
    bq rm --recursive --force --dataset "${dataset}"
    echo "Deleted dataset ${dataset}"
  else
    echo "Dataset ${dataset} doesn't exist, nothing to delete"
  fi
done
