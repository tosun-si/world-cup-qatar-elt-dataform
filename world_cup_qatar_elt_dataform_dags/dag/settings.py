import os
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from airflow.models import Variable


@dataclass
class Settings:
    dag_folder: str = field(init=False)
    dag_default_args: dict = field(init=False)
    project_id: str = field(init=False)
    location: str = field(init=False)

    dataform_dag_id: str = field(init=False)
    dataset: str = field(init=False)
    team_stats_raw_table: str = field(init=False)
    team_stats_table: str = field(init=False)
    team_stats_raw_table_schema_bucket: str = field(init=False)
    team_stats_raw_table_schema_object: str = field(init=False)

    team_stats_input_bucket: str = field(init=False)
    team_stats_source_object: str = field(init=False)
    team_stats_dest_bucket: str = field(init=False)
    team_stats_dest_object: str = field(init=False)

    dataform_repository_id: str = field(init=False)
    dataform_compilation_result_name: str = field(init=False)

    variables: dict = field(init=False)

    def __post_init__(self):
        variables = Variable.get("world_cup_qatar_elt_dataform_dags", deserialize_json=True)

        self.dag_folder = os.getenv("DAGS_FOLDER")
        self.dag_default_args = {
            'depends_on_past': False,
            'email': ['airflow@example.com'],
            'email_on_failure': False,
            'email_on_retry': False,
            'retries': 0,
            'retry_delay': timedelta(minutes=5),
            "start_date": datetime(2024, 1, 1),
        }
        self.project_id = os.getenv("GCP_PROJECT")
        self.location = os.getenv("COMPOSER_LOCATION")

        self.dataform_dag_id = variables["dataform_dag_id"]
        self.dataset = variables["dataset"]
        self.team_stats_raw_table = variables["team_stats_raw_table"]
        self.team_stats_table = variables["team_stats_table"]
        self.team_stats_raw_table_schema_bucket = variables["team_stats_raw_table_schema_bucket"]
        self.team_stats_raw_table_schema_object = variables["team_stats_raw_table_schema_object"]

        self.team_stats_input_bucket = variables["team_stats_input_bucket"]
        self.team_stats_source_object = variables["team_stats_source_object"]
        self.team_stats_dest_bucket = variables["team_stats_dest_bucket"]
        self.team_stats_dest_object = variables["team_stats_dest_object"]

        self.dataform_repository_id = variables["dataform_repository_id"]
        self.dataform_compilation_result_name = variables["dataform_compilation_result_name"]

        self.variables = variables
