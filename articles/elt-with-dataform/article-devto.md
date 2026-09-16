---
title: ELT with Dataform on Google Cloud
published: false
description: A real-world ELT pipeline with Dataform and BigQuery — staging and mart layers, JavaScript includes, dynamic tables and views, GitHub sync over SSH and Terraform provisioning.
tags: dataform, bigquery, googlecloud, dataengineering
series: Dataform on Google Cloud
canonical_url: https://medium.com/google-cloud/elt-with-dataform-on-google-cloud-e69fb8484510
cover_image: https://miro.medium.com/v2/resize:fit:1400/1*u91Q9NTao0sNYH3-bE2I1A.png
---

> *This article was originally published on [Medium (Google Cloud Community)](https://medium.com/google-cloud/elt-with-dataform-on-google-cloud-e69fb8484510).*

## 1. Explanation of the use case presented in this article

In a previous article, I demonstrated how to build an [ELT pipeline using dbt on Google Cloud](https://medium.com/google-cloud/elt-with-dbt-on-cloud-run-job-0fcadce4eb1f). In this article, we'll explore the same use case — this time using **Dataform**, Google Cloud's native solution for managing SQL-based data workflows.

One of the key advantages of Dataform on Google Cloud is that it's a fully managed, serverless service, natively integrated with BigQuery.

As with the dbt-focused article, I'll use a football-related, real-world ELT pipeline that includes both **staging** and **mart** layers. I'll walk through how to create a Dataform repository manually, link it with a GitHub repository, and then automate the entire setup using **Terraform**. This approach enables a GitOps workflow, where the GitHub repository becomes the single source of truth for managing your Dataform resources.

Here is the diagram of this use case:

![Architecture of the ELT pipeline with Dataform, BigQuery, Cloud Build and Terraform](https://miro.medium.com/v2/resize:fit:1400/1*u91Q9NTao0sNYH3-bE2I1A.png)

I also created a video on this topic on my **GCP YouTube** channel. Feel free to [**subscribe**](https://www.youtube.com/@GCPLearning-ce9bg) to the channel to support my work for the Google Cloud community.

**English version:**

{% embed https://youtu.be/c70ry7rrm6w %}

**French version:**

{% embed https://youtu.be/b-6naX68YRg %}

### 🔧 CI/CD layer

- The CI/CD pipeline is implemented using **Cloud Build** and **Infrastructure as Code (IaC)** with **Terraform**.
- It automates the creation of the **Dataform repository** and establishes a link with a **GitHub repository**, enabling a GitOps-driven workflow.

### 📦 Applicative ELT pipeline

- **Data ingestion**: raw files are loaded into **BigQuery** using `bq load`.
- **Staging layer**: reads raw data and applies initial **data cleaning and standardization**.
- **Mart layer**: transforms cleaned data into **business-ready domain models**, applying domain-specific logic.
- **Dynamic views generation**: creates **views for player statistics**, dynamically generated from the domain data.
- **Dynamic tables generation**: builds **country-specific tables** to expose **player statistics by country**.

## 2. Usual structure of a Dataform project

Dataform is fully managed and deeply integrated with BigQuery, making it seamless to use within the Google Cloud ecosystem. When getting started, the Dataform console makes it easy to generate boilerplate code and a project structure, helping you ramp up quickly.

On the Dataform main page, the first step is to click the **"Create repository"** button to start a new project.

![Dataform main page with the Create repository button](https://miro.medium.com/v2/resize:fit:1400/1*0nxuhqCGrxHna1Wlg8O89Q.png)

In the repository creation menu, you can assign any name, select the `europe-west1` region, and specify a service account with the necessary permissions — typically `Dataform Editor` and `BigQuery Data Editor` to get started. For production setups, use more restricted roles aligned with the principle of least privilege.

![Dataform repository creation form](https://miro.medium.com/v2/resize:fit:1400/1*IHbiVCXp8fmp1l9tN4DxEA.png)

Then click on **"Go to repositories"**:

![Repository created, Go to repositories button](https://miro.medium.com/v2/resize:fit:1400/1*7LtkjD7Dao2PO5ix4Kn7TQ.png)

Click on **"Create development workspace"**:

![Create development workspace button](https://miro.medium.com/v2/resize:fit:1400/1*gU2VEwcYsPwDyFHAm_pmhw.png)

![Development workspace creation form](https://miro.medium.com/v2/resize:fit:1400/1*u1Uq19V7LV-tiKphLvd6NA.png)

Then open the created workspace:

![List of development workspaces](https://miro.medium.com/v2/resize:fit:1400/1*O0gKBq2NIOgNVRIoXXXO4Q.png)

Click on **"Initialize workspace"**:

![Initialize workspace button](https://miro.medium.com/v2/resize:fit:1400/1*CECN-4UM7NrRswKuOtBzYA.png)

After this step, Dataform generates the example project structure. Next, open the `workflow_settings.yaml` file and click on **"Install Packages"** to set up the required dependencies.

![workflow_settings.yaml file with the Install Packages button](https://miro.medium.com/v2/resize:fit:1400/1*BdUknBNxx-tb7n2tcMBpug.png)

The boilerplate project provides code that's ready to run out of the box. It includes:

- a `workflow_settings.yaml` configuration file
- a `definitions/` folder containing sample models
- an `includes/` folder for reusable JavaScript functions

You can execute the pipeline directly by clicking **"Start execution" → "Execute actions"** in the UI.

![Start execution menu in the workspace](https://miro.medium.com/v2/resize:fit:1400/1*ilinRT_dMs5j9MMBb6GBXA.png)

In the **"Selection of actions"** panel, choose **all actions** for this example, then click on **"Start execution"** to run the pipeline.

![Selection of actions panel](https://miro.medium.com/v2/resize:fit:1400/1*k6WAc2-jc0XkdNdsusvAJg.png)

Click on **"Details"**:

![Execution started notification with the Details link](https://miro.medium.com/v2/resize:fit:1400/1*3hgrTB8df2RccTk0IlJgBw.png)

The execution is successful:

![Successful workflow execution](https://miro.medium.com/v2/resize:fit:1400/1*4eXmkPblYmdE31PKDWLgjw.png)

By clicking on **"View details"**, you can access the **compiled SQL queries** that Dataform generates from your models.

![Compiled SQL query of an action](https://miro.medium.com/v2/resize:fit:1400/1*4_PEwNdoyh7H613qPSUURQ.png)

You can also view the **compiled dependency graph**, which visualizes the relationships between models and their execution order.

![Compiled dependency graph](https://miro.medium.com/v2/resize:fit:1400/1*aQK91eIKVZqzeUOv6UAVLA.png)

In the next section, we'll walk through our use case and explore a more realistic, real-world scenario.

## 3. Structure of the project presented in this use case

![Project structure](https://miro.medium.com/v2/resize:fit:1400/1*HGS1sFgQPO5dsJ3KZU0NbQ.png)

### 3.1 Dataform configuration

The `workflow_settings.yaml` file, located at the root of the GitHub repo and of the Dataform project, defines key configuration parameters:

- the GCP project ID
- the location (region) where the Dataform workflow runs
- the BigQuery dataset used to store the Dataform-generated tables
- the BigQuery dataset used to store assertion results
- the Dataform core version used for execution

```yaml
defaultProject: gb-poc-373711
defaultLocation: europe-west1
defaultDataset: qatar_fifa_world_cup_dataform
defaultAssertionDataset: qatar_fifa_world_cup_dataform_assertions
dataformCoreVersion: 3.0.42
```

### 3.2 Definitions and models

The `definitions` folder contains all the Dataform models, organized into **staging** and **mart** layers.

![Definitions folder with staging and marts sub-folders](https://miro.medium.com/v2/resize:fit:1400/1*QsQN2c7vKckjcTZTj0ThzA.png)

Dataform models are defined using either **SQLX** or **JavaScript** files.

### 3.3 Staging layer

In the **staging layer**, the SQLX file cleans the raw data and applies light transformations, typically producing **BigQuery views** as output.

The `team_players_stat_raw_cleaned.sqlx` file:

```sql
config {
    type: "view",
    columns: {
        goalsScored: "Goal scored for the player.",
        assistsProvided: "Assists provided by the player.",
        appearances: "Appearances for the player."
    }
}

SELECT
    nationality,
    SAFE_CAST(goalsScored AS INT64) AS goalsScored,
    SAFE_CAST(assistsProvided AS INT64) AS assistsProvided,
    SAFE_CAST(dribblesPerNinety AS FLOAT64) AS dribblesPerNinety,
    SAFE_CAST(appearances AS INT64) AS appearances,
    SAFE_CAST(totalDuelsWonPerNinety AS FLOAT64) AS totalDuelsWonPerNinety,
    SAFE_CAST(interceptionsPerNinety AS FLOAT64) AS interceptionsPerNinety,
    SAFE_CAST(tacklesPerNinety AS FLOAT64) AS tacklesPerNinety,
    brandSponsorAndUsed,
    club,
    savePercentage,
    IF(savePercentage <> "-", TRUE, FALSE) AS isGoalKeeperStatsExist,
    fifaRanking,
    position,
    playerName,
    cleanSheets,
    nationalTeamKitSponsor,
    nationalTeamJerseyNumber,
    playerDob
FROM `qatar_fifa_world_cup_dataform.team_players_stat_raw`
```

Similar to dbt, the `config` block in a Dataform model lets you define settings specific to that model. For example:

- `type`: how the model is materialized (e.g. a **view**).
- `columns`: **documentation and descriptions** for specific columns.

The rest of the model is a standard BigQuery SQL query that defines the transformation logic.

### 3.4 Mart layer

The `team_players_stat.sqlx` file:

```sql
config {
  type: "table",
  description: "Description of the table.",
  columns: team_player_stat_columns_descriptions.columns_descriptions,
  bigquery: {
    partitionBy: {
      field: "ingestionDate",
      dataType: "timestamp",
      granularity: "day"
    },
    clusterBy: ["teamName"]
  }
}

WITH

team_players_stat_raw AS (
    SELECT * FROM ${ref("team_players_stat_raw_cleaned")}
),

goalKeepersStats AS (
    SELECT
        nationality,
        STRUCT(
            playerName,
            appearances,
            savePercentage,
            cleanSheets
        ) AS goalKeeperStatsStruct
    FROM team_players_stat_raw
    WHERE isGoalKeeperStatsExist IS TRUE
),

goalKeeperStatsPerTeam AS (
    SELECT
        nationality,
        ARRAY_AGG(goalKeeperStatsStruct ORDER BY goalKeeperStatsStruct.savePercentage DESC LIMIT 1)[OFFSET(0)] AS stats
    FROM goalKeepersStats
    GROUP BY
        nationality
)

SELECT
    statRaw.nationality AS teamName,
    nationalTeamKitSponsor,
    fifaRanking,
    SUM(goalsScored) AS teamTotalGoals,
    CURRENT_TIMESTAMP() AS ingestionDate,
    goalKeeperStatsPerTeam.stats AS goalKeeper,
    ${team_players_stat_functions.build_player_stats(
      "goalsScored",
      "appearances",
      "brandSponsorAndUsed",
      "club",
      "position",
      "playerDob",
      "playerName"
    )}
    AS topScorers,
    ${team_players_stat_functions.build_player_stats(
      "assistsProvided",
      "appearances",
      "brandSponsorAndUsed",
      "club",
      "position",
      "playerDob",
      "playerName"
    )}
    AS bestPassers,
    ${team_players_stat_functions.build_player_stats(
      "dribblesPerNinety",
      "appearances",
      "brandSponsorAndUsed",
      "club",
      "position",
      "playerDob",
      "playerName"
    )}
    AS bestDribblers,
    ${team_players_stat_functions.build_player_stats(
      "appearances",
      "appearances",
      "brandSponsorAndUsed",
      "club",
      "position",
      "playerDob",
      "playerName"
    )}
    AS playersMostAppearances,
    ${team_players_stat_functions.build_player_stats(
      "totalDuelsWonPerNinety",
      "appearances",
      "brandSponsorAndUsed",
      "club",
      "position",
      "playerDob",
      "playerName"
    )}
    AS playersMostDuelsWon,
    ${team_players_stat_functions.build_player_stats(
      "interceptionsPerNinety",
      "appearances",
      "brandSponsorAndUsed",
      "club",
      "position",
      "playerDob",
      "playerName"
    )}
    AS playersMostInterception,
    ${team_players_stat_functions.build_player_stats(
      "tacklesPerNinety",
      "appearances",
      "brandSponsorAndUsed",
      "club",
      "position",
      "playerDob",
      "playerName"
    )}
    AS playersMostSuccessfulTackles
FROM team_players_stat_raw statRaw
JOIN goalKeeperStatsPerTeam ON statRaw.nationality = goalKeeperStatsPerTeam.nationality
GROUP BY
    statRaw.nationality,
    nationalTeamKitSponsor,
    fifaRanking,
    goalKeeperStatsPerTeam.stats
```

For the mart step, the `config` block declares a **table** as the model type:

```js
config {
  type: "table",
  description: "Description of the table.",
  columns: team_player_stat_columns_descriptions.columns_descriptions,
  bigquery: {
    partitionBy: {
      field: "ingestionDate",
      dataType: "timestamp",
      granularity: "day"
    },
    clusterBy: ["teamName"]
  }
}
```

We also added clustering and partitioning options in the `bigquery` block to improve performance and reduce cost.

### 3.5 Mart step: column descriptions

Instead of embedding the column descriptions directly in the SQLX model, we extracted them into a separate JavaScript file. This is particularly useful when descriptions are long, as it keeps the model clean and readable.

You have two options for column descriptions: embed them in the SQLX model, or move them to a JS file. When descriptions are verbose, I recommend the JS file for clarity, maintainability and readability.

In the `config` block, the `columns` parameter directly references the JavaScript constant that holds the descriptions:

```js
columns: team_player_stat_columns_descriptions.columns_descriptions,
```

This constant is declared in the `team_player_stat_columns_descriptions.js` file, in the `includes` folder. The nested objects (`top_scorers_columns`, `best_passers_columns`, …) are declared in the same file and describe the fields of each `STRUCT`:

```js
const top_scorers_columns = {
    description: "An object containing the top scorers fields.",
    columns: {
        goals: "Total number of goals scored by the top scorers.",
        players: {
            description: "List of top-scoring players",
            columns: {
                playerName: "Name of the top-scoring player.",
                playerDob: "Date of birth of the player.",
                position: "Playing position of the player.",
                club: "Club that the player is affiliated with.",
                brandSponsorAndUsed: "Brand sponsor of the player's gear.",
                appearances: "Number of matches the player has played in."
            }
        }
    }
};

// ... same pattern for the other statistics

const columns_descriptions = {
    teamName: "Name of the national football team.",
    teamTotalGoals: "Total number of goals scored by the team in the tournament.",
    fifaRanking: "Current FIFA ranking of the national team.",
    nationalTeamKitSponsor: "Official sponsor providing kits for the national team.",
    topScorers: top_scorers_columns,
    bestPassers: best_passers_columns,
    bestDribblers: best_dribblers_columns,
    goalKeeper: goal_keeper_columns,
    playersMostAppearances: players_most_appearances_columns,
    playersMostDuelsWon: players_most_duels_won_columns,
    playersMostInterception: players_most_interceptions_columns,
    playersMostSuccessfulTackles: players_most_successful_tackles_columns
};

module.exports = {
    columns_descriptions
};
```

### 3.6 Mart step: reusable function to compute player statistics

Most player statistics — such as top scorers and best passers — are computed the same way. To avoid duplicating code, I created a reusable function that encapsulates this logic.

In Dataform, one way to define reusable logic is to create a JavaScript file in the `includes` folder. Here, the `team_players_stat_functions.js` file holds this function:

```js
function build_player_stats(statIndicator, appearances, brandSponsorAndUsed, club, position, playerDob, playerName) {
    return `
    STRUCT(
      MAX(${statIndicator}) AS ${statIndicator},
      ARRAY_AGG(
        IF(
          ${statIndicator} = 0 OR ${statIndicator} = 0.00,
          NULL,
          STRUCT(
            ${appearances},
            ${brandSponsorAndUsed},
            ${club},
            ${position},
            ${playerDob},
            ${playerName}
          )
        )
        ORDER BY ${statIndicator} DESC LIMIT 1
      )[OFFSET(0)] AS players
    )
  `;
}

module.exports = {build_player_stats};
```

The `build_player_stats` function takes the column names as parameters and injects them into the generated SQL. To make it available in SQLX or JavaScript models, it must be exported with `module.exports`.

I gave more details on this use case and its data modeling in the [article I previously wrote on **dbt**](https://medium.com/google-cloud/elt-with-dbt-on-cloud-run-job-0fcadce4eb1f), which covers the same context.

### 3.7 Mart step: dynamic tables and views

One great feature of Dataform is the ability to write models in JavaScript instead of SQLX when needed. This is particularly useful when you need to generate logic or structure dynamically.

That's exactly what we demonstrate here: after computing the domain data, we dynamically generate one view per statistic and one table per country. JavaScript models are well suited for this kind of logic, letting us create models programmatically with more flexibility.

The `stat_dynamic_tables_and_views.js` file:

```js
const statViews =
    [
        {
            columnToSelect: "goalKeeper",
            viewName: "goal_keeper"
        },
        {
            columnToSelect: "topScorers",
            viewName: "top_scorers"
        },
        {
            columnToSelect: "bestPassers",
            viewName: "best_passers"
        }
    ];

const statPerCountryTables = [
    {
        countryName: "France",
        tableName: "france_players"
    },
    {
        countryName: "Argentina",
        tableName: "argentina_players"
    }
]

statViews.forEach((view) => {
    publish(view.viewName + "_stat").query(
        ctx => `
            SELECT ${view.columnToSelect}
            FROM ${ctx.ref("team_players_stat")}
        `
    );
});

statPerCountryTables.forEach((table) => {
    publish(table.tableName + "_stat",
        {
            type: "table"
        })
        .query(
            ctx => `
                SELECT *
                FROM ${ctx.ref("team_players_stat")}
                WHERE teamName = "${table.countryName}"
            `
        );
});
```

We declare two `const` arrays — one for the views and one for the tables — and loop over each with `forEach`. The `publish` function then defines each view and table dynamically.

Below is the diagram of the ELT pipeline built with Dataform, with the data lineage showing how each component connects across the workflow.

![Dataform dependency graph and data lineage of the pipeline](https://miro.medium.com/v2/resize:fit:1400/1*wGgaMCYcdJTlNuyRmq30nQ.png)

## 4. Connect the GitHub repo to the Dataform repo from the console

In real-world projects, Dataform code is typically managed in GitHub repositories. Dataform can synchronize a repository over either **HTTPS** or **SSH**.

I prefer **SSH**, as it's both more secure and more convenient with GitHub. In this example, I had already added an SSH key to my GitHub **account**, which lets me reuse it across multiple repositories. You could also add a key at the **repository level** (deploy key), but managing it at the account level is more practical in my case.

To retrieve the **GitHub SSH public host key** in the format expected by a `known_hosts` file, run:

```bash
ssh-keyscan -t rsa github.com
```

It displays GitHub's public host key:

```text
# github.com:22 SSH-2.0-4c545346
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
```

Make sure to copy the entire value, starting from `ssh-rsa` (or `ssh-ed25519`) all the way to the end of the line, without the `github.com` hostname.

Next, you need the **private key** of your SSH key pair, which Dataform uses to authenticate with your GitHub repository.

Use one of the following commands, depending on the type of key you generated:

```bash
cat ~/.ssh/id_rsa
# or
cat ~/.ssh/id_ed25519
```

> ⚠️ **Be careful** — never share this private key. It must be kept secure at all times.

Store the private key as a **secret** in **Secret Manager**. Dataform reads it from there to establish the SSH connection with your GitHub repository.

Open the Dataform repository you created earlier and go to the **Settings** tab. From there, click on **"Connect with Git"** to link your repository to a Git provider such as GitHub.

![Connect with Git button in the repository settings](https://miro.medium.com/v2/resize:fit:1400/1*6bqMzcqpA-5PnAiGVF0KdQ.png)

Then fill in the **Git connection** form:

- the **SSH URL** of the remote GitHub repository
- the **default branch** (e.g. `main`)
- the **secret version** containing your private SSH key (from Secret Manager)
- the **SSH public host key**, in `known_hosts` format (from `ssh-keyscan`)

To let Dataform read the private key from Secret Manager, grant the `Secret Manager Secret Accessor` role (`roles/secretmanager.secretAccessor`) to the Dataform service agent:

```text
service-{PROJECT_NUMBER}@gcp-sa-dataform.iam.gserviceaccount.com
```

![Git connection form over SSH](https://miro.medium.com/v2/resize:fit:1400/1*wWYF6xZdgZa7JJbwlfkJdg.png)

The connection is successful:

![Repository successfully connected to GitHub](https://miro.medium.com/v2/resize:fit:1400/1*MbGF3dovsv1ozMoI1erqOA.png)

When you create a new Dataform workspace, it automatically pulls the files and project structure from the linked GitHub repository, using the configured default branch (typically `main`).

![New workspace created from the GitHub repository](https://miro.medium.com/v2/resize:fit:1400/1*WOalYHAPOKboLGBaQbjb9Q.png)

![Workspace content synchronized from GitHub](https://miro.medium.com/v2/resize:fit:1400/1*FsSYzroRXm6v2J3o01OkkQ.png)

## 5. Connect the GitHub repo to the Dataform repo with Terraform

In this section, we automate the GitHub repository link with **Terraform** instead of configuring it manually. This aligns with **GitOps best practices**, where **Git is the single source of truth** for infrastructure and configuration.

The Terraform code structure:

![Terraform code structure in the infra folder](https://miro.medium.com/v2/resize:fit:1400/1*eSX-PUIPB5y_OK72cTQYJA.png)

The `infra` folder contains all the Terraform configuration files.

The `backend.tf` file defines the **remote state backend**, which uses **Google Cloud Storage (GCS)** to persist the Terraform state:

```hcl
terraform {
  backend "gcs" {
  }
}
```

The `versions.tf` file pins the Terraform and **Google Cloud provider** versions:

```hcl
terraform {
  required_version = ">= 1.9.8"

  required_providers {
    google      = "= 6.14.0"
    google-beta = "= 6.14.0"
  }
}
```

Input variables are declared in the `variables.tf` file to keep the configuration flexible:

```hcl
variable "project_id" {
  type = string
}

variable "region" {
  description = "Location for load balancer and Cloud Run resources"
  default     = "europe-west1"
}

variable "dataform_repo_name" {
  description = "Dataform repo name."
  type        = string
}

variable "service_account_email" {
  description = "Service Account email for the creation of the Dataform repo."
  type        = string
}
```

The `locals.tf` file declares constants such as the **SSH public host key** and the **Secret Manager secret version** of the private SSH key. These locals centralize values used across the Terraform configuration.

```hcl
locals {
  github_account_host_public_ssh_key_value      = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="
  github_account_private_ssh_key_secret_version = "projects/975119474255/secrets/github_account_mazlum_tosun_private_key/versions/latest"
}
```

The `main.tf` file creates the **Dataform repository** and configures the connection to the **GitHub repository** over SSH:

```hcl
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
```

## Conclusion

This article presented a real-world ELT pipeline built with **Dataform**, covering key concepts such as **staging and mart layers**, concrete data **transformations**, **column documentation**, and **JavaScript functions** for dynamic logic.

It also included a DevOps and IaC part, so you can reproduce a complete, hands-on setup that follows modern best practices.

Dataform is a powerful choice for teams working with **BigQuery**, thanks to its **fully managed experience** and **tight integration with GCP**. Its support for a **GitOps workflow** — where GitHub repositories are the single source of truth — makes it even more appealing for collaborative, production-grade data projects.

Personally, I find using a **programming language like JavaScript** for dynamic logic far more effective than Jinja templating. JavaScript may not be the default choice for data engineers, but it offers better readability and more power when implementing complex or repetitive logic across your models.

All the code presented in this article is available in this GitHub repository:

{% embed https://github.com/tosun-si/world-cup-qatar-elt-dataform %}

---

If you enjoyed this article, follow me for more content on Google Cloud, BigQuery, Dataform, DevOps and data engineering:

- [dev.to](https://dev.to/mazlum_tosun)
- [Medium](https://medium.com/@mazlum.tosun)
- [YouTube](https://bit.ly/gcp-learning-mazlum-gb)
- [X](https://x.com/MazlumTosun3)
- [LinkedIn](https://www.linkedin.com/in/mazlum-tosun-900b1812)
