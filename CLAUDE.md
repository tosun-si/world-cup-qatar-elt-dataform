# World Cup Qatar ELT Dataform

## Project overview

ELT pipeline for Qatar Fifa World Cup player statistics using Dataform, BigQuery, and Google Cloud Platform. Raw data is ingested, transformed through staging and mart layers, and business metrics (top scorers, best passers, best dribblers) are computed.

## Architecture

- **Orchestration**: Apache Airflow (Cloud Composer) with DAGs in `world_cup_qatar_elt_dataform_dags/`
- **Transformation**: Dataform with SQLX definitions in `definitions/`
  - `definitions/staging/` — raw data cleaning
  - `definitions/marts/` — domain transformations and dynamic table/view creation
- **CI/CD**: Cloud Build for Dataform compilation and assertion validation
- **Infrastructure**: Terraform for Dataform repository provisioning in `infra/`
- **Storage**: GCS for raw files, BigQuery for data warehouse

## CI/CD strategy

Dataform compilation is handled by GitHub Actions (not by the Airflow DAG), using Workload Identity Federation for keyless GCP authentication:
- **Feature branches** (`.github/workflows/compile-dataform-feature-branch.yaml`): triggered on PR to main, compiles with commit SHA and runs assertions
- **Production tags** (`.github/workflows/compile-dataform-tag-production.yaml`): triggered on `v*` tag creation, compiles with tag ref and runs assertions
- CI/CD outputs the compilation result name in the job summary — the developer then updates `variables.json` with the desired version
- The compilation result name is stored in `variables.json` (`dataform_compilation_result_name` field), version-controlled and explicitly chosen

## DAG pipeline flow

1. **Load raw data** — `GCSToBigQueryOperator` loads NDJSON from GCS into a BigQuery raw table
2. **Invoke Dataform workflow** — `DataformCreateWorkflowInvocationOperator` invokes the pre-compiled Dataform pipeline
3. **Move processed files** — `GCSToGCSOperator` moves input files to a cold storage bucket

## Key files

- `world_cup_qatar_elt_dataform_dags/dag/world_cup_qatar_elt_dataform_dag.py` — main DAG definition
- `world_cup_qatar_elt_dataform_dags/dag/settings.py` — DAG settings loaded from Airflow Variables
- `world_cup_qatar_elt_dataform_dags/config/variables/dev/variables.json` — dev environment configuration
- `.github/workflows/compile-dataform-feature-branch.yaml` — GitHub Actions workflow for feature branch compilation
- `.github/workflows/compile-dataform-tag-production.yaml` — GitHub Actions workflow for production tag compilation
- `workflow_settings.yaml` — Dataform workflow settings (project, dataset, core version)
- `pyproject.toml` — Python project config using uv with `apache-airflow[google]`

## Development

- Python package manager: **uv**
- Airflow version: 3.1.8 with Google provider
- Dataform core version: 3.0.8
- DAG variables are stored in `config/variables/{env}/variables.json` and loaded via `airflow.models.Variable`

## Commands

```bash
# Install dependencies
uv sync

# Run tests
uv run pytest

# Dataform compilation is handled by GitHub Actions (on PR and tag creation)
# List compilation results (Console: BigQuery > Dataform > repository > Compilation results tab)
gcloud dataform compilation-results list \
    --repository=world-cup-qatar-elt-dataform \
    --project=gb-poc-373711 \
    --region=europe-west1
```
