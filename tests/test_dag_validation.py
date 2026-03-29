import json
import os
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT_DIR = Path(__file__).parent.parent
VARIABLES_PATH = ROOT_DIR / "world_cup_qatar_elt_dataform_dags" / "config" / "variables" / "dev" / "variables.json"


@pytest.fixture(autouse=True)
def mock_airflow_variables():
    with open(VARIABLES_PATH) as f:
        variables = json.load(f)

    env_vars = {
        "GCP_PROJECT": "test-project",
        "COMPOSER_LOCATION": "europe-west1",
        "DAGS_FOLDER": str(ROOT_DIR / "world_cup_qatar_elt_dataform_dags" / "dag"),
    }

    with (
        patch.dict(os.environ, env_vars),
        patch("airflow.models.Variable.get", return_value=variables["world_cup_qatar_elt_dataform_dags"]),
    ):
        yield


def test_dag_loads_without_error():
    from world_cup_qatar_elt_dataform_dags.dag.world_cup_qatar_elt_dataform_dag import dag

    assert dag is not None
    assert dag.dag_id == "world_cup_qatar_elt_dataform_dag"


def test_dag_has_expected_tasks():
    from world_cup_qatar_elt_dataform_dags.dag.world_cup_qatar_elt_dataform_dag import dag

    task_ids = [task.task_id for task in dag.tasks]
    assert "load_team_player_stats_raw_to_bq" in task_ids
    assert "invoke_dataform_workflow" in task_ids
    assert "move_file_to_cold" in task_ids


def test_dag_task_dependencies():
    from world_cup_qatar_elt_dataform_dags.dag.world_cup_qatar_elt_dataform_dag import dag

    load_raw = dag.get_task("load_team_player_stats_raw_to_bq")
    invoke_dataform = dag.get_task("invoke_dataform_workflow")
    move_cold = dag.get_task("move_file_to_cold")

    assert "invoke_dataform_workflow" in [t.task_id for t in load_raw.downstream_list]
    assert "move_file_to_cold" in [t.task_id for t in invoke_dataform.downstream_list]


def test_dag_has_expected_task_count():
    from world_cup_qatar_elt_dataform_dags.dag.world_cup_qatar_elt_dataform_dag import dag

    assert len(dag.tasks) == 3
