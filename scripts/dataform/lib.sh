#!/usr/bin/env bash
# Shared helpers for the Dataform CI/CD scripts, based on the Dataform REST API v1.
#
# Required env vars: GCP_PROJECT_ID, GCP_REGION, DATAFORM_REPOSITORY

set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_REGION:?GCP_REGION is required}"
: "${DATAFORM_REPOSITORY:?DATAFORM_REPOSITORY is required}"

readonly DATAFORM_API="https://dataform.googleapis.com/v1"
readonly REPOSITORY_PATH="projects/${GCP_PROJECT_ID}/locations/${GCP_REGION}/repositories/${DATAFORM_REPOSITORY}"
readonly WORKFLOW_SETTINGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/workflow_settings.yaml"

# Calls the Dataform API and fails on any HTTP error, printing the error body.
# Usage: dataform_api <METHOD> <path relative to /v1> [json body]
dataform_api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(
    --silent --show-error --fail-with-body
    -X "${method}" "${DATAFORM_API}/${path}"
    -H "Authorization: Bearer $(gcloud auth print-access-token)"
    -H "Content-Type: application/json"
  )
  if [[ -n "${body}" ]]; then
    args+=(-d "${body}")
  fi
  local response
  if ! response=$(curl "${args[@]}"); then
    echo "Dataform API error on ${method} ${path}: ${response}" >&2
    return 1
  fi
  echo "${response}"
}

# Reads a top-level key from workflow_settings.yaml (flat YAML, no yq needed).
workflow_setting() {
  awk -F': *' -v key="$1" '$1 == key { print $2 }' "${WORKFLOW_SETTINGS_FILE}"
}

github_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$1=$2" >> "${GITHUB_OUTPUT}"
  fi
}

github_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$1" >> "${GITHUB_STEP_SUMMARY}"
  else
    echo "$1"
  fi
}

# Creates a compilation result and fails if Dataform reports compilation errors.
# The API returns HTTP 200 even when the SQLX code doesn't compile: errors are
# only listed in the `compilationErrors` field, so they must be checked explicitly.
# Usage: create_compilation_result <json body>
# Sets: COMPILATION_RESULT_NAME
create_compilation_result() {
  local result error_count
  result=$(dataform_api POST "${REPOSITORY_PATH}/compilationResults" "$1")

  error_count=$(jq '.compilationErrors // [] | length' <<<"${result}")
  if (( error_count > 0 )); then
    jq -r '.compilationErrors[] | "::error file=\(.path // "")::\(.actionTarget.name // "compilation") - \(.message | gsub("\n"; " "))"' <<<"${result}"
    echo "Dataform compilation failed with ${error_count} error(s)" >&2
    return 1
  fi

  COMPILATION_RESULT_NAME=$(jq -r '.name' <<<"${result}")

  github_summary "### Dataform compilation result"
  github_summary ""
  github_summary "| Field | Value |"
  github_summary "|---|---|"
  github_summary "| Source | \`$(jq -r '.gitCommitish // .releaseConfig' <<<"${result}")\` |"
  github_summary "| Resolved commit SHA | \`$(jq -r '.resolvedGitCommitSha // "-"' <<<"${result}")\` |"
  github_summary "| Dataform core version | \`$(jq -r '.dataformCoreVersion // "-"' <<<"${result}")\` |"
  github_summary "| Compilation overrides | \`$(jq -c '.codeCompilationConfig // {}' <<<"${result}")\` |"
  github_summary "| Compilation result | \`${COMPILATION_RESULT_NAME}\` |"
  github_summary ""
}

# Invokes a compilation result (tables, views and assertions), waits for the end
# of the execution and fails if any action failed.
# Usage: invoke_and_wait <compilation result name> [timeout in seconds]
invoke_and_wait() {
  local compilation_result="$1" timeout_seconds="${2:-1800}"
  local invocation_name state deadline actions

  invocation_name=$(dataform_api POST "${REPOSITORY_PATH}/workflowInvocations" \
    "$(jq -n --arg cr "${compilation_result}" '{compilationResult: $cr}')" | jq -r '.name')
  echo "Workflow invocation: ${invocation_name}"

  # If the GitHub job is cancelled (e.g. a new push on the PR), cancel the invocation too.
  trap 'dataform_api POST "${invocation_name}:cancel" "{}" >/dev/null || true' INT TERM

  deadline=$(( SECONDS + timeout_seconds ))
  while true; do
    state=$(dataform_api GET "${invocation_name}" | jq -r '.state')
    echo "State: ${state}"
    case "${state}" in
      SUCCEEDED | FAILED | CANCELLED) break ;;
    esac
    if (( SECONDS > deadline )); then
      dataform_api POST "${invocation_name}:cancel" "{}" >/dev/null
      echo "::error::Workflow invocation timed out after ${timeout_seconds}s and was cancelled"
      return 1
    fi
    # Background sleep + wait so the cancel trap fires immediately.
    sleep 10 &
    wait $!
  done
  trap - INT TERM

  actions=$(dataform_api GET "${invocation_name}:query?pageSize=1000")

  github_summary "### Dataform workflow invocation: ${state}"
  github_summary ""
  github_summary "| Action | State |"
  github_summary "|---|---|"
  jq -r '.workflowInvocationActions[] | "| `\(.target.schema).\(.target.name)` | \(.state) |"' <<<"${actions}" \
    | while read -r line; do github_summary "${line}"; done
  github_summary ""

  jq -r '.workflowInvocationActions[]
    | select(.state == "FAILED")
    | "::error title=\(.target.name)::\(.failureReason // "failed" | gsub("\n"; " "))"' <<<"${actions}"

  [[ "${state}" == "SUCCEEDED" ]]
}
