#!/usr/bin/env bash
# Compiles the PR head commit into isolated datasets (suffix `_pr_<number>`) and
# runs the whole pipeline on BigQuery, assertions included.
#
# Usage: run_pr_pipeline.sh <pr number> <git commit sha>

source "$(dirname "$0")/lib.sh"

readonly PR_NUMBER="${1:?PR number is required}"
readonly GIT_COMMIT_SHA="${2:?git commit SHA is required}"

create_compilation_result "$(jq -n \
  --arg sha "${GIT_COMMIT_SHA}" \
  --arg suffix "pr_${PR_NUMBER}" \
  '{gitCommitish: $sha, codeCompilationConfig: {schemaSuffix: $suffix}}')"

invoke_and_wait "${COMPILATION_RESULT_NAME}"
