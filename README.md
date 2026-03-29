# world-cup-qatar-elt-dataform

This repo shows a real world use case with Dataform, BigQuery and Google Cloud.
The raw and input data are represented by the Qatar Fifa World Cup Players stats,
some transformations are applied with the ELT pattern and Dataform to apply aggregation and business transformations.

![elt_bigquery_dataform.png](diagram/elt_bigquery_dataform.png)

The video in English:

https://youtu.be/c70ry7rrm6w

The video in French:

https://youtu.be/b-6naX68YRg

## Airflow DAG - ELT pipeline orchestration

The pipeline is orchestrated by an Airflow DAG (Cloud Composer) with the following steps:

1. **Load raw data to BigQuery** — Loads NDJSON player stats from GCS into a BigQuery raw table using `GCSToBigQueryOperator`
2. **Invoke Dataform workflow** — Invokes a pre-compiled Dataform pipeline using `DataformCreateWorkflowInvocationOperator`
3. **Move processed files to cold storage** — Moves the input file to a cold bucket using `GCSToGCSOperator`

The DAG configuration is managed via Airflow Variables, loaded from `world_cup_qatar_elt_dataform_dags/config/variables/dev/variables.json`.

## CI/CD - Dataform compilation with GitHub Actions

Dataform compilation is separated from the DAG and handled by GitHub Actions. This provides reproducibility, validation via assertions, and easy rollbacks.

Authentication uses **Workload Identity Federation** (keyless) with a dedicated service account.

CI/CD compiles and runs assertions. The compilation result name is displayed in the GitHub Actions job summary. The developer then updates `variables.json` (`dataform_compilation_result_name` field) to control which version the DAG invokes.

### Feature branch (dev/testing)

Triggered on **pull request** to `main`. Compiles using the PR head commit SHA and runs assertions.

Workflow: `.github/workflows/compile-dataform-feature-branch.yaml`

### Production (git tag)

Triggered on **tag creation** matching `v*` (e.g., `v1.0.0`). Compiles using the tag ref and runs assertions.

Workflow: `.github/workflows/compile-dataform-tag-production.yaml`

### Update the compilation result in variables

After CI/CD outputs the compilation result name (visible in the job summary), update `variables.json`:

```json
"dataform_compilation_result_name": "projects/.../compilationResults/<ID>"
```

### Finding compilation results

From the GCP Console: **BigQuery** > **Dataform** > select the repository > **Compilation results** tab.

Or via gcloud:

```bash
gcloud dataform compilation-results list \
    --repository=world-cup-qatar-elt-dataform \
    --project=gb-poc-373711 \
    --region=europe-west1
```

### Setup

```bash
# Install dependencies with uv
uv sync
```

## Create the Dataform repository with Terraform and synchronize with a GitHub repository

The SSH public host key value must be in the format of a known_hosts file. The value must contain an algorithm and a public key encoded in the base64 format, but without the hostname or IP, in the following format:

The GitHub host public key corresponds to this format.

Retrieve GitHub host public key:

```bash
ssh-keyscan -t rsa github.com
```

Plan:

```bash
gcloud builds submit \
    --project=$PROJECT_ID \
    --region=$LOCATION \
    --config create-dataform-repo-terraform-plan.yaml \
    --substitutions _TF_STATE_BUCKET=$TF_STATE_BUCKET,_TF_STATE_PREFIX=$TF_STATE_PREFIX,_DATAFORM_REPO_NAME=$DATAFORM_REPO_NAME,_DATAFORM_SA=$DATAFORM_SA \
    --verbosity="debug" .
```

Apply:

```bash
gcloud builds submit \
    --project=$PROJECT_ID \
    --region=$LOCATION \
    --config create-dataform-repo-terraform-apply.yaml \
    --substitutions _TF_STATE_BUCKET=$TF_STATE_BUCKET,_TF_STATE_PREFIX=$TF_STATE_PREFIX,_DATAFORM_REPO_NAME=$DATAFORM_REPO_NAME,_DATAFORM_SA=$DATAFORM_SA \
    --verbosity="debug" .
```