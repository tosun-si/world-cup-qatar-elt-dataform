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
2. **Invoke Dataform workflow** — Invokes the Dataform workflow config of the environment (released by CI/CD) using `DataformCreateWorkflowInvocationOperator`
3. **Move processed files to cold storage** — Moves the input file to a cold bucket using `GCSToGCSOperator`

The DAG configuration is managed via Airflow Variables, loaded from `world_cup_qatar_elt_dataform_dags/config/variables/{env}/variables.json`.

## Deploy the Airflow DAG to Cloud Composer

The DAG folder and its config variables are deployed to Cloud Composer via Cloud Build (`deploy-dag.yaml`):

```bash
gcloud builds submit \
    --project=$PROJECT_ID \
    --region=$LOCATION \
    --config deploy-dag.yaml \
    --substitutions _DAG_ROOT_FOLDER=$DAG_ROOT_FOLDER,_COMPOSER_ENVIRONMENT=$COMPOSER_ENVIRONMENT,_CONFIG_FOLDER_NAME=$CONFIG_FOLDER_NAME,_ENV=$ENV
```

## CI/CD - Dataform with GitHub Actions

Dataform compilation and releases are handled by GitHub Actions, not by the DAG. Authentication uses **Workload Identity Federation** (no JSON keys), with one GitHub Environment (and one CI/CD service account) per GCP environment.

| Workflow | Trigger | Environment | What it does |
|---|---|---|---|
| `dataform-ci.yaml` | PR to `main` | `dev` | 1. Offline compilation with the Dataform CLI (no GCP access)<br>2. Unit tests with the Dataform CLI (mocked inputs, no table created)<br>3. Compiles the PR head commit with `schemaSuffix: pr_<number>` and runs the whole pipeline, **assertions included**, in isolated datasets |
| `dataform-pr-cleanup.yaml` | PR closed | `dev` | Deletes the `*_pr_<number>` datasets |
| `dataform-release-dev.yaml` | Push to `main` | `dev` | Releases the commit to the `dev` release config |
| `dataform-release-prd.yaml` | Tag `vX.Y.Z`, or manual run (rollback) | `prd` | Releases the tag to the `prd` release config |

The logic lives in `scripts/dataform/` (Dataform REST API v1), so it can also be run locally.

### How a release works

```
release config (dev|prd)  ──  git_commitish + compilation overrides (dev: `_dev` datasets)
        │ releaseCompilationResult
        ▼
workflow config (dev|prd) ◄── invoked by the Airflow DAG
```

`scripts/dataform/release.sh <release config> <git ref>`:

1. points the release config to the git ref
2. compiles from the release config and **fails on compilation errors** (the API returns HTTP 200 even when the code doesn't compile)
3. promotes the result as the release config's `releaseCompilationResult`

The DAG invokes the workflow config of its environment (`dataform_workflow_config_id` in `variables.json`), which always executes the released compilation result. Releasing a new version doesn't require redeploying the DAG.

If the compilation fails, the release config is restored and the currently released version is left untouched.

### Rollback

Run the `Dataform release - prd` workflow manually with the previous tag:

```bash
gh workflow run dataform-release-prd.yaml -f tag=v1.2.0
```

### Assertions

- `team_players_stat_raw_cleaned`: `nonNull` and `uniqueKey` on `nationality` + `playerName`
- `team_players_stat`: `uniqueKey` on `teamName`, `nonNull` and `rowConditions` on the team stats
- `assert_no_team_dropped_by_goal_keeper_join`: no team is lost by the join on goalkeeper stats

Assertions are executed at invocation time (not at compilation): in the PR pipeline, and in each Airflow run.

### Unit tests

`definitions/tests/` contains unit tests (`type: "test"`) of the staging model: the raw table is replaced by inline data and the output is compared with the expected rows. They test the SQL logic, whereas assertions test the data.

Unit tests are only run by the Dataform CLI (not by workflow invocations). They run queries on BigQuery but create no table:

```bash
echo '{"projectId": "gb-poc-373711", "location": "europe-west1"}' > .df-credentials.json  # uses ADC, gitignored
npx @dataform/cli@3.0.42 test
```

### Setup

Release and workflow configs are created by Terraform (`infra/world_cup_elt_dataform`). The `prd` workflow config fails until a first tag is released.

GitHub **repository variables**:

| Variable | Example |
|---|---|
| `GCP_PROJECT_ID` | `gb-poc-373711` |
| `GCP_REGION` | `europe-west1` |
| `DATAFORM_REPOSITORY` | `world-cup-qatar-elt-dataform` |
| `WORKLOAD_IDENTITY_PROVIDER` | `projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>` |

GitHub **environments** `dev` and `prd` (with required reviewers on `prd`), each with the variable `CI_CD_SERVICE_ACCOUNT`.

```bash
gh variable set GCP_PROJECT_ID --body gb-poc-373711
gh variable set GCP_REGION --body europe-west1
gh variable set DATAFORM_REPOSITORY --body world-cup-qatar-elt-dataform
gh variable set WORKLOAD_IDENTITY_PROVIDER --body "projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>"
gh variable set CI_CD_SERVICE_ACCOUNT --env dev --body sa-dataform-ci-dev@<project>.iam.gserviceaccount.com
gh variable set CI_CD_SERVICE_ACCOUNT --env prd --body sa-dataform-ci-prd@<project>.iam.gserviceaccount.com
```

GCP IAM, done by `scripts/setup/setup_ci_cd_iam.sh` (idempotent):

- the WIF provider is restricted to known GitHub owners with an attribute condition, otherwise any GitHub repository can get a federated token from the pool
- one CI/CD service account per environment (`sa-dataform-ci-dev`, `sa-dataform-ci-prd`), each impersonable only by the jobs of this repository running in the matching GitHub environment. No custom attribute mapping is needed: for a job using an environment, the GitHub OIDC `sub` claim is `repo:<owner>/<repo>:environment:<env>`:

```bash
gcloud iam service-accounts add-iam-policy-binding sa-dataform-ci-prd@<project>.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<pool>/subject/repo:tosun-si/world-cup-qatar-elt-dataform:environment:prd"
```

- roles of the CI/CD service accounts, predefined roles only:
  - `roles/dataform.admin` **on the Dataform repository** (Terraform, `google_dataform_repository_iam_member`): `roles/dataform.editor` can't update a release config (`dataform.releaseConfigs.update`), and the repository-level grant keeps the other repositories of the project out of reach
  - `roles/iam.serviceAccountUser` on the Dataform service account of the repository: Dataform checks `actAs` on invocations
  - `dev` only: `roles/bigquery.jobUser`, to run the unit tests
  - `dev` only: `roles/bigquery.dataOwner` with an IAM condition restricting it to the PR datasets, to delete them:

```text
resource.name.startsWith("projects/<project>/datasets/qatar_fifa_world_cup_dataform_pr_") ||
resource.name.startsWith("projects/<project>/datasets/qatar_fifa_world_cup_dataform_assertions_pr_")
```

Run the script before `terraform apply`: the repository-level grants reference the CI/CD service accounts.

The Composer service account needs `roles/dataform.editor` and `roles/iam.serviceAccountUser` on the Dataform service account.

### Finding compilation results

From the GCP Console: **BigQuery** > **Dataform** > select the repository > **Compilation results** / **Release & scheduling** tabs.

### Local setup

```bash
# Install dependencies with uv
uv sync
```

## Local Airflow execution with Docker

For local testing of the DAG against real GCP resources, use the Airflow Docker dev image from the [airflow-gcp-docker-dev](https://github.com/tosun-si/airflow-gcp-docker-dev) project.

### Build the Docker image

```bash
cd /path/to/airflow-gcp-docker-dev
docker build -t airflow-dev .
```

### Run the DAG locally

From this project's root directory:

```bash
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

Then access the Airflow UI at http://localhost:8080 (default credentials: `admin` / `admin`).

Prerequisites:
- Authenticate locally with `gcloud auth application-default login`
- `GOOGLE_CLOUD_PROJECT` is required for the Google Cloud SDK to resolve the project from ADC credentials

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