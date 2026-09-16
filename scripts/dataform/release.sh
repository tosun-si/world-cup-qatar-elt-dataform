#!/usr/bin/env bash
# Releases a git ref to a Dataform release config:
#   1. points the release config to the git ref
#   2. compiles from the release config (its compilation overrides are managed by Terraform)
#   3. promotes the compilation result as the release config's `releaseCompilationResult`
#
# The workflow config invoked by Airflow always executes the `releaseCompilationResult`
# of its release config: promoting a new result is the deployment, and promoting an
# older one is the rollback.
# If the compilation fails, the release config is restored and the currently released
# compilation result is left untouched.
#
# Usage: release.sh <release config id> <git ref>

source "$(dirname "$0")/lib.sh"

readonly RELEASE_CONFIG_ID="${1:?release config id is required}"
readonly GIT_REF="${2:?git ref is required}"
readonly RELEASE_CONFIG="${REPOSITORY_PATH}/releaseConfigs/${RELEASE_CONFIG_ID}"

set_release_config_git_commitish() {
  dataform_api PATCH "${RELEASE_CONFIG}?updateMask=gitCommitish" \
    "$(jq -n --arg ref "$1" '{gitCommitish: $ref}')" >/dev/null
}

previous_git_commitish=$(dataform_api GET "${RELEASE_CONFIG}" | jq -r '.gitCommitish')
echo "Release config ${RELEASE_CONFIG_ID}: ${previous_git_commitish} -> ${GIT_REF}"

released=false
restore_on_failure() {
  if [[ "${released}" != "true" ]]; then
    echo "Release failed, restoring release config ${RELEASE_CONFIG_ID} to ${previous_git_commitish}"
    set_release_config_git_commitish "${previous_git_commitish}"
  fi
}
trap restore_on_failure EXIT

set_release_config_git_commitish "${GIT_REF}"

create_compilation_result "$(jq -n --arg rc "${RELEASE_CONFIG}" '{releaseConfig: $rc}')"

# The API rejects the update if gitCommitish is missing from the body, even with this update mask.
dataform_api PATCH "${RELEASE_CONFIG}?updateMask=releaseCompilationResult" \
  "$(jq -n --arg ref "${GIT_REF}" --arg cr "${COMPILATION_RESULT_NAME}" \
    '{gitCommitish: $ref, releaseCompilationResult: $cr}')" >/dev/null
released=true

github_output "compilation_result_name" "${COMPILATION_RESULT_NAME}"
github_summary "✅ \`${GIT_REF}\` released to the \`${RELEASE_CONFIG_ID}\` release config."
