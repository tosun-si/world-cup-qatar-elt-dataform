# World Cup Qatar ELT Dataform

## Project overview

ELT pipeline for Qatar Fifa World Cup player statistics using Dataform, BigQuery, and Google Cloud Platform. Raw data is ingested, transformed through staging and mart layers, and business metrics (top scorers, best passers, best dribblers) are computed.

## Architecture

- **Orchestration**: Apache Airflow (Cloud Composer) with DAGs in `world_cup_qatar_elt_dataform_dags/`
- **Transformation**: Dataform with SQLX definitions in `definitions/`
  - `definitions/staging/` — raw data cleaning
  - `definitions/marts/` — domain transformations and dynamic table/view creation
- **CI/CD**: GitHub Actions for Dataform CI (compilation + isolated run with assertions) and releases (release configs)
- **Infrastructure**: Terraform for Dataform repository provisioning in `infra/`
- **Storage**: GCS for raw files, BigQuery for data warehouse

## CI/CD strategy

Dataform compilation and releases are handled by GitHub Actions (not by the Airflow DAG), with Workload Identity Federation and one GitHub Environment (`dev`, `prd`) per GCP environment. Identifiers come from GitHub Variables (`vars.*`). The logic lives in `scripts/dataform/` (Dataform REST API v1):
- **PR** (`.github/workflows/dataform-ci.yaml`): offline compilation with the Dataform CLI, then compilation of the PR head SHA with `schemaSuffix: pr_<number>` and a full workflow invocation (assertions included) in isolated datasets
- **PR closed** (`.github/workflows/dataform-pr-cleanup.yaml`): deletes the `*_pr_<number>` datasets
- **Push to main** (`.github/workflows/dataform-release-dev.yaml`): releases the commit to the `dev` release config
- **Tag `vX.Y.Z`** (`.github/workflows/dataform-release-prd.yaml`): releases the tag to the `prd` release config; manual run with a previous tag = rollback
- A release = PATCH release config `gitCommitish` → compile from the release config (fail on `compilationErrors`) → PATCH `releaseCompilationResult`
- Release configs and workflow configs (`dev`, `prd`, no cron) are managed by Terraform; CI/CD owns `gitCommitish` and `releaseCompilationResult`
- The DAG invokes the workflow config of its environment (`dataform_workflow_config_id` in `variables.json`)
- Assertions run at invocation time only, never at compilation

## DAG pipeline flow

1. **Load raw data** — `GCSToBigQueryOperator` loads NDJSON from GCS into a BigQuery raw table
2. **Invoke Dataform workflow** — `DataformCreateWorkflowInvocationOperator` invokes the environment's workflow config (released compilation result)
3. **Move processed files** — `GCSToGCSOperator` moves input files to a cold storage bucket

## Key files

- `world_cup_qatar_elt_dataform_dags/dag/world_cup_qatar_elt_dataform_dag.py` — main DAG definition
- `world_cup_qatar_elt_dataform_dags/dag/settings.py` — DAG settings loaded from Airflow Variables
- `world_cup_qatar_elt_dataform_dags/config/variables/dev/variables.json` — dev environment configuration
- `.github/workflows/dataform-*.yaml` — GitHub Actions workflows for Dataform CI and releases
- `scripts/dataform/` — Dataform API scripts used by the workflows (compile, invoke, release, PR cleanup)
- `scripts/setup/setup_ci_cd_iam.sh` — one-shot GCP IAM setup for the CI/CD (WIF condition, CI/CD SAs per env, actAs, conditional BigQuery role); Dataform roles are granted on the repository by Terraform
- `infra/world_cup_elt_dataform/` — Terraform for the Dataform repository, release configs and workflow configs
- `workflow_settings.yaml` — Dataform workflow settings (project, dataset, core version)
- `pyproject.toml` — Python project config using uv with `apache-airflow[google]`

## Development

- Python package manager: **uv**
- Airflow version: 3.1.8 with Google provider
- Dataform core version: 3.0.42 (`workflow_settings.yaml`)
- DAG variables are stored in `config/variables/{env}/variables.json` and loaded via `airflow.models.Variable`

## Local Airflow execution with Docker

The DAG can be tested locally against real GCP resources using the Airflow Docker dev image from a separate project: [airflow-gcp-docker-dev](https://github.com/tosun-si/airflow-gcp-docker-dev).

```bash
# Build the image (from airflow-gcp-docker-dev directory)
docker build -t airflow-dev .

# Run (from this project's root directory)
docker run -it \
    -p 8080:8080 \
    -e GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json \
    -e GCP_PROJECT=gb-poc-373711 \
    -e GOOGLE_CLOUD_PROJECT=gb-poc-373711 \
    -e COMPOSER_LOCATION=europe-west1 \
    -v $HOME/.config/gcloud/application_default_credentials.json:/root/.config/gcloud/application_default_credentials.json \
    -v $(pwd)/world_cup_qatar_elt_dataform_dags:/opt/airflow/dags/world_cup_qatar_elt_dataform_dags \
    -v $(pwd)/world_cup_qatar_elt_dataform_dags/config:/opt/airflow/config \
    airflow-dev
```

- Requires `gcloud auth application-default login` beforehand
- `GOOGLE_CLOUD_PROJECT` env var is needed for ADC credential project resolution
- Airflow UI available at http://localhost:8080 (admin/admin)

## Commands

```bash
# Install dependencies
uv sync

# Run tests
uv run pytest

# Compile Dataform locally (offline)
npx @dataform/cli@3.0.42 compile

# Release / rollback prd (Console: BigQuery > Dataform > repository > Release & scheduling tab)
gh workflow run dataform-release-prd.yaml -f tag=vX.Y.Z

# List compilation results
gcloud dataform compilation-results list \
    --repository=world-cup-qatar-elt-dataform \
    --project=gb-poc-373711 \
    --region=europe-west1

# Deploy the Airflow DAG folder and config variables to Cloud Composer
gcloud builds submit \
    --project=$PROJECT_ID \
    --region=$LOCATION \
    --config deploy-dag.yaml \
    --substitutions _DAG_ROOT_FOLDER=$DAG_ROOT_FOLDER,_COMPOSER_ENVIRONMENT=$COMPOSER_ENVIRONMENT,_CONFIG_FOLDER_NAME=$CONFIG_FOLDER_NAME,_ENV=$ENV
```
