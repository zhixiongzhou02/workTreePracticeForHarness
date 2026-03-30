#!/usr/bin/env bash

set -euo pipefail

# 这层库只负责“worktree 运行时契约”：
# worktree 身份、端口、状态目录、元数据文件、启动入口解析。
# 具体应用怎么跑，交给 scripts/app-start 或显式命令。

task_profile_is_supported() {
  case "${1:-}" in
    review-only | code-only | app-validate)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

task_profile_app_start_policy() {
  case "${1:-}" in
    app-validate)
      printf 'start\n'
      ;;
    review-only | code-only)
      printf 'skip\n'
      ;;
    *)
      return 1
      ;;
  esac
}

task_profile_runtime_isolation_mode() {
  case "${1:-}" in
    review-only)
      printf 'off-by-default\n'
      ;;
    code-only)
      printf 'optional\n'
      ;;
    app-validate)
      printf 'required\n'
      ;;
    *)
      return 1
      ;;
  esac
}

task_profile_description() {
  case "${1:-}" in
    review-only)
      printf '只需要 worktree 隔离，不默认启动运行时实例。\n'
      ;;
    code-only)
      printf '需要 worktree 隔离，可准备运行时契约，但不默认启动应用。\n'
      ;;
    app-validate)
      printf '需要 worktree 隔离和运行时隔离，并默认启动应用进行验证。\n'
      ;;
    *)
      return 1
      ;;
  esac
}

require_git_worktree_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

resolve_repo_root() {
  if require_git_worktree_root >/dev/null 2>&1; then
    require_git_worktree_root
    return
  fi

  if [[ "${HARNESS_WORKTREE_MODE:-prototype}" == "strict-git" ]]; then
    printf '当前模式要求处于真实 git worktree 环境，但 git 根目录解析失败。\n' >&2
    exit 1
  fi

  pwd
}

sanitize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g'
}

short_hash() {
  local input="$1"
  LC_ALL=C printf '%s' "$input" | LC_ALL=C shasum -a 256 | awk '{print substr($1, 1, 8)}'
}

derive_worktree_id() {
  local repo_root base slug suffix
  repo_root="$(resolve_repo_root)"
  base="$(basename "$repo_root")"
  slug="$(sanitize_name "$base")"
  suffix="$(short_hash "$repo_root")"
  printf '%s-%s\n' "$slug" "$suffix"
}

derive_offset() {
  local worktree_id digest
  worktree_id="${1:-$(derive_worktree_id)}"
  digest="$(printf '%s' "$worktree_id" | cksum | awk '{print $1}')"
  printf '%s\n' "$((digest % 100))"
}

resolve_runtime() {
  export REPO_ROOT
  export WORKTREE_ID
  export TASK_PROFILE
  export TASK_PROFILE_APP_START_POLICY
  export TASK_PROFILE_RUNTIME_ISOLATION
  export TASK_PROFILE_DESCRIPTION
  export PORT_OFFSET
  export BASE_PORT_OFFSET
  export WORKTREE_MODE
  export WORKTREE_CONTEXT_SOURCE
  export PORT_CONFLICT_MODE
  export PORT_SEARCH_LIMIT
  export PORT_ALLOCATION_SOURCE
  export STATE_ROOT
  export RUN_ROOT
  export DATA_ROOT
  export CACHE_ROOT
  export LOG_ROOT
  export ARTIFACT_ROOT
  export TMP_ROOT
  export APP_PORT
  export API_PORT
  export METRICS_PORT
  export AUX_PORT
  export APP_URL
  export API_URL
  export PORTS_JSON
  export ENV_JSON
  export RUNTIME_ENV_FILE
  export STATUS_JSON
  export APP_PID_FILE
  export APP_PGID_FILE
  export APP_START_COMMAND
  export APP_START_SOURCE
  export APP_READY_URL
  export APP_READY_COMMAND
  export APP_READY_SOURCE
  export APP_READY_TIMEOUT_MS
  export APP_READY_POLL_INTERVAL_MS

  REPO_ROOT="$(resolve_repo_root)"
  WORKTREE_ID="$(derive_worktree_id)"
  BASE_PORT_OFFSET="$(derive_offset "$WORKTREE_ID")"
  PORT_OFFSET="$BASE_PORT_OFFSET"
  WORKTREE_MODE="${HARNESS_WORKTREE_MODE:-prototype}"
  WORKTREE_CONTEXT_SOURCE="prototype-pwd"
  if require_git_worktree_root >/dev/null 2>&1; then
    WORKTREE_CONTEXT_SOURCE="git"
  fi
  PORT_CONFLICT_MODE="${HARNESS_PORT_CONFLICT_MODE:-strict}"
  PORT_SEARCH_LIMIT="${HARNESS_PORT_SEARCH_LIMIT:-20}"
  PORT_ALLOCATION_SOURCE="deterministic"

  STATE_ROOT="$REPO_ROOT/.local/worktrees/$WORKTREE_ID"
  RUN_ROOT="$STATE_ROOT/run"
  DATA_ROOT="$STATE_ROOT/data"
  CACHE_ROOT="$STATE_ROOT/cache"
  LOG_ROOT="$STATE_ROOT/logs"
  ARTIFACT_ROOT="$STATE_ROOT/artifacts"
  TMP_ROOT="$STATE_ROOT/tmp"

  PORTS_JSON="$RUN_ROOT/ports.json"
  ENV_JSON="$RUN_ROOT/env.json"
  RUNTIME_ENV_FILE="$RUN_ROOT/runtime.env"
  STATUS_JSON="$RUN_ROOT/status.json"
  APP_PID_FILE="$RUN_ROOT/app.pid"
  APP_PGID_FILE="$RUN_ROOT/app.pgid"
  APP_START_COMMAND=""
  APP_START_SOURCE="unconfigured"
  APP_READY_URL=""
  APP_READY_COMMAND=""
  APP_READY_SOURCE="unconfigured"
  APP_READY_TIMEOUT_MS="${HARNESS_APP_READY_TIMEOUT_MS:-15000}"
  APP_READY_POLL_INTERVAL_MS="${HARNESS_APP_READY_POLL_INTERVAL_MS:-250}"

  TASK_PROFILE="${HARNESS_TASK_PROFILE:-}"
  if [[ -z "$TASK_PROFILE" && -f "$ENV_JSON" ]]; then
    TASK_PROFILE="$(sed -n '/"taskProfile":[[:space:]]*{/,/}/{s/.*"name":[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ENV_JSON" | head -n 1)"
  fi
  TASK_PROFILE="${TASK_PROFILE:-app-validate}"

  if [[ -n "${HARNESS_PORT_OFFSET:-}" ]]; then
    BASE_PORT_OFFSET="$((HARNESS_PORT_OFFSET % 100))"
    if [[ "$BASE_PORT_OFFSET" -lt 0 ]]; then
      BASE_PORT_OFFSET="$((BASE_PORT_OFFSET + 100))"
    fi
    PORT_OFFSET="$BASE_PORT_OFFSET"
    PORT_ALLOCATION_SOURCE="manual-offset"
  fi

  TASK_PROFILE_APP_START_POLICY="$(task_profile_app_start_policy "$TASK_PROFILE")"
  TASK_PROFILE_RUNTIME_ISOLATION="$(task_profile_runtime_isolation_mode "$TASK_PROFILE")"
  TASK_PROFILE_DESCRIPTION="$(task_profile_description "$TASK_PROFILE")"

  set_ports_from_offset "$PORT_OFFSET"
}

ensure_runtime_dirs() {
  resolve_runtime
  if [[ "$WORKTREE_MODE" != "prototype" && "$WORKTREE_MODE" != "strict-git" ]]; then
    printf '不支持的 HARNESS_WORKTREE_MODE: %s。仅支持 prototype 或 strict-git。\n' "$WORKTREE_MODE" >&2
    exit 1
  fi
  assert_task_profile_is_supported
  assert_port_mode_is_supported
  # 所有可变运行态统一收敛到当前 worktree 自己的目录下。
  mkdir -p \
    "$RUN_ROOT/pids" \
    "$DATA_ROOT" \
    "$CACHE_ROOT" \
    "$LOG_ROOT" \
    "$ARTIFACT_ROOT" \
    "$TMP_ROOT"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

shell_escape() {
  printf '%q' "$1"
}

set_ports_from_offset() {
  local offset="$1"
  PORT_OFFSET="$offset"
  APP_PORT="$((4100 + offset))"
  API_PORT="$((4200 + offset))"
  METRICS_PORT="$((4300 + offset))"
  AUX_PORT="$((4400 + offset))"
  APP_URL="http://127.0.0.1:$APP_PORT"
  API_URL="http://127.0.0.1:$API_PORT"
}

apply_port_lease_if_present() {
  local app api metrics aux

  if [[ ! -f "$PORTS_JSON" ]]; then
    return 1
  fi

  app="$(sed -n 's/.*"app":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$PORTS_JSON")"
  api="$(sed -n 's/.*"api":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$PORTS_JSON")"
  metrics="$(sed -n 's/.*"metrics":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$PORTS_JSON")"
  aux="$(sed -n 's/.*"aux":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$PORTS_JSON")"

  if [[ -z "$app" || -z "$api" || -z "$metrics" || -z "$aux" ]]; then
    return 1
  fi

  APP_PORT="$app"
  API_PORT="$api"
  METRICS_PORT="$metrics"
  AUX_PORT="$aux"
  APP_URL="http://127.0.0.1:$APP_PORT"
  API_URL="http://127.0.0.1:$API_PORT"
  PORT_OFFSET="$((APP_PORT - 4100))"
  PORT_ALLOCATION_SOURCE="leased"
  return 0
}

apply_app_start_metadata_if_present() {
  local source command

  if [[ ! -f "$ENV_JSON" ]]; then
    return 1
  fi

  source="$(sed -n '/"appStart":[[:space:]]*{/,/}/{s/.*"source":[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ENV_JSON" | head -n 1)"
  command="$(sed -n '/"appStart":[[:space:]]*{/,/}/{s/.*"command":[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ENV_JSON" | head -n 1)"

  if [[ -z "$source" ]]; then
    return 1
  fi

  APP_START_SOURCE="$source"
  APP_START_COMMAND="$command"
  return 0
}

apply_app_ready_metadata_if_present() {
  local source ready_url ready_command

  if [[ ! -f "$ENV_JSON" ]]; then
    return 1
  fi

  source="$(sed -n '/"appReady":[[:space:]]*{/,/}/{s/.*"source":[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ENV_JSON" | head -n 1)"
  ready_url="$(sed -n '/"appReady":[[:space:]]*{/,/}/{s/.*"url":[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ENV_JSON" | head -n 1)"
  ready_command="$(sed -n '/"appReady":[[:space:]]*{/,/}/{s/.*"command":[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ENV_JSON" | head -n 1)"

  if [[ -z "$source" ]]; then
    return 1
  fi

  APP_READY_SOURCE="$source"
  APP_READY_URL="$ready_url"
  APP_READY_COMMAND="$ready_command"
  return 0
}

ports_are_available() {
  local port

  for port in "$APP_PORT" "$API_PORT" "$METRICS_PORT" "$AUX_PORT"; do
    if port_is_listening "$port"; then
      return 1
    fi
  done

  return 0
}

print_port_conflicts() {
  local port

  for port in "$APP_PORT" "$API_PORT" "$METRICS_PORT" "$AUX_PORT"; do
    if port_is_listening "$port"; then
      printf '端口 %s 已被占用，当前 worktree 为 %s\n' "$port" "$WORKTREE_ID" >&2
    fi
  done
}

write_ports_json() {
  cat >"$PORTS_JSON" <<EOF
{
  "app": $APP_PORT,
  "api": $API_PORT,
  "metrics": $METRICS_PORT,
  "aux": $AUX_PORT,
  "offset": $PORT_OFFSET,
  "mode": "$(json_escape "$PORT_CONFLICT_MODE")",
  "source": "$(json_escape "$PORT_ALLOCATION_SOURCE")"
}
EOF
}

write_env_json() {
  cat >"$ENV_JSON" <<EOF
{
  "worktreeId": "$(json_escape "$WORKTREE_ID")",
  "repoRoot": "$(json_escape "$REPO_ROOT")",
  "taskProfile": {
    "name": "$(json_escape "$TASK_PROFILE")",
    "appStartPolicy": "$(json_escape "$TASK_PROFILE_APP_START_POLICY")",
    "runtimeIsolation": "$(json_escape "$TASK_PROFILE_RUNTIME_ISOLATION")",
    "description": "$(json_escape "$TASK_PROFILE_DESCRIPTION")"
  },
  "worktreeContext": {
    "mode": "$(json_escape "$WORKTREE_MODE")",
    "source": "$(json_escape "$WORKTREE_CONTEXT_SOURCE")"
  },
  "appUrl": "$(json_escape "$APP_URL")",
  "apiUrl": "$(json_escape "$API_URL")",
  "appStart": {
    "source": "$(json_escape "$APP_START_SOURCE")",
    "command": "$(json_escape "$APP_START_COMMAND")"
  },
  "appReady": {
    "source": "$(json_escape "$APP_READY_SOURCE")",
    "url": "$(json_escape "$APP_READY_URL")",
    "command": "$(json_escape "$APP_READY_COMMAND")",
    "timeoutMs": $APP_READY_TIMEOUT_MS,
    "pollIntervalMs": $APP_READY_POLL_INTERVAL_MS
  },
  "portAllocation": {
    "mode": "$(json_escape "$PORT_CONFLICT_MODE")",
    "source": "$(json_escape "$PORT_ALLOCATION_SOURCE")",
    "offset": $PORT_OFFSET,
    "baseOffset": $BASE_PORT_OFFSET,
    "searchLimit": $PORT_SEARCH_LIMIT
  },
  "ports": {
    "app": $APP_PORT,
    "api": $API_PORT,
    "metrics": $METRICS_PORT,
    "aux": $AUX_PORT
  },
  "paths": {
    "stateRoot": "$(json_escape "$STATE_ROOT")",
    "runRoot": "$(json_escape "$RUN_ROOT")",
    "dataRoot": "$(json_escape "$DATA_ROOT")",
    "cacheRoot": "$(json_escape "$CACHE_ROOT")",
    "logRoot": "$(json_escape "$LOG_ROOT")",
    "artifactRoot": "$(json_escape "$ARTIFACT_ROOT")",
    "tmpRoot": "$(json_escape "$TMP_ROOT")"
  }
}
EOF
}

write_status_json() {
  local state started_at app_pid health ready ready_at app_pgid failure_reason
  state="$1"
  started_at="${2:-}"
  app_pid="${3:-null}"
  health="${4:-unknown}"
  ready="${5:-false}"
  ready_at="${6:-}"
  app_pgid="${7:-null}"
  failure_reason="${8:-}"

  cat >"$STATUS_JSON" <<EOF
{
  "taskProfile": "$(json_escape "$TASK_PROFILE")",
  "state": "$(json_escape "$state")",
  "startedAt": "$(json_escape "$started_at")",
  "ready": $ready,
  "readyAt": "$(json_escape "$ready_at")",
  "pids": {
    "app": $app_pid,
    "processGroup": $app_pgid
  },
  "health": "$(json_escape "$health")",
  "failureReason": "$(json_escape "$failure_reason")"
}
EOF
}

write_runtime_env_file() {
  # 这份文件面向 shell 直接消费，供真实应用启动脚本和调试脚本复用。
  cat >"$RUNTIME_ENV_FILE" <<EOF
export REPO_ROOT=$(shell_escape "$REPO_ROOT")
export WORKTREE_ID=$(shell_escape "$WORKTREE_ID")
export TASK_PROFILE=$(shell_escape "$TASK_PROFILE")
export TASK_PROFILE_APP_START_POLICY=$(shell_escape "$TASK_PROFILE_APP_START_POLICY")
export TASK_PROFILE_RUNTIME_ISOLATION=$(shell_escape "$TASK_PROFILE_RUNTIME_ISOLATION")
export PORT_CONFLICT_MODE=$(shell_escape "$PORT_CONFLICT_MODE")
export PORT_ALLOCATION_SOURCE=$(shell_escape "$PORT_ALLOCATION_SOURCE")
export WORKTREE_MODE=$(shell_escape "$WORKTREE_MODE")
export WORKTREE_CONTEXT_SOURCE=$(shell_escape "$WORKTREE_CONTEXT_SOURCE")
export PORT_OFFSET="$PORT_OFFSET"
export BASE_PORT_OFFSET="$BASE_PORT_OFFSET"
export PORT_SEARCH_LIMIT="$PORT_SEARCH_LIMIT"
export APP_PORT="$APP_PORT"
export API_PORT="$API_PORT"
export METRICS_PORT="$METRICS_PORT"
export AUX_PORT="$AUX_PORT"
export APP_URL=$(shell_escape "$APP_URL")
export API_URL=$(shell_escape "$API_URL")
export STATE_ROOT=$(shell_escape "$STATE_ROOT")
export RUN_ROOT=$(shell_escape "$RUN_ROOT")
export DATA_ROOT=$(shell_escape "$DATA_ROOT")
export CACHE_ROOT=$(shell_escape "$CACHE_ROOT")
export LOG_ROOT=$(shell_escape "$LOG_ROOT")
export ARTIFACT_ROOT=$(shell_escape "$ARTIFACT_ROOT")
export TMP_ROOT=$(shell_escape "$TMP_ROOT")
export PORTS_JSON=$(shell_escape "$PORTS_JSON")
export ENV_JSON=$(shell_escape "$ENV_JSON")
export RUNTIME_ENV_FILE=$(shell_escape "$RUNTIME_ENV_FILE")
export STATUS_JSON=$(shell_escape "$STATUS_JSON")
export APP_PID_FILE=$(shell_escape "$APP_PID_FILE")
export APP_PGID_FILE=$(shell_escape "$APP_PGID_FILE")
export APP_START_SOURCE=$(shell_escape "$APP_START_SOURCE")
export APP_START_COMMAND=$(shell_escape "$APP_START_COMMAND")
export APP_READY_SOURCE=$(shell_escape "$APP_READY_SOURCE")
export APP_READY_URL=$(shell_escape "$APP_READY_URL")
export APP_READY_COMMAND=$(shell_escape "$APP_READY_COMMAND")
export APP_READY_TIMEOUT_MS="$APP_READY_TIMEOUT_MS"
export APP_READY_POLL_INTERVAL_MS="$APP_READY_POLL_INTERVAL_MS"
EOF
}

port_is_listening() {
  local port="$1"
  lsof -iTCP:"$port" -sTCP:LISTEN -n -P >/dev/null 2>&1
}

preflight_ports() {
  local attempt next_offset

  # 如果上一次成功分配过端口，优先尝试复用，减少端口漂移。
  if apply_port_lease_if_present && ports_are_available; then
    return 0
  fi

  set_ports_from_offset "$BASE_PORT_OFFSET"
  PORT_ALLOCATION_SOURCE="${PORT_ALLOCATION_SOURCE:-deterministic}"

  if ports_are_available; then
    return 0
  fi

  if [[ "$PORT_CONFLICT_MODE" == "strict" ]]; then
    print_port_conflicts
    printf '端口分配模式为 strict，检测到冲突后停止启动。\n' >&2
    exit 1
  fi

  # soft 模式用于人工本地调试：在受控范围内尝试后续 offset。
  if [[ "$PORT_CONFLICT_MODE" != "soft" ]]; then
    printf '不支持的 HARNESS_PORT_CONFLICT_MODE: %s。仅支持 strict 或 soft。\n' "$PORT_CONFLICT_MODE" >&2
    exit 1
  fi

  for ((attempt = 1; attempt <= PORT_SEARCH_LIMIT; attempt++)); do
    next_offset="$(((BASE_PORT_OFFSET + attempt) % 100))"
    set_ports_from_offset "$next_offset"
    if ports_are_available; then
      PORT_ALLOCATION_SOURCE="soft-fallback"
      return 0
    fi
  done

  print_port_conflicts
  printf 'soft 模式已尝试 %s 个候选 offset，仍未找到可用端口。\n' "$PORT_SEARCH_LIMIT" >&2
  exit 1
}

resolve_app_start_command() {
  local repo_script
  repo_script="$REPO_ROOT/scripts/app-start"

  # 最高优先级是显式覆盖，适合临时实验或外部编排。
  if [[ -n "${HARNESS_APP_START_COMMAND:-}" ]]; then
    APP_START_COMMAND="$HARNESS_APP_START_COMMAND"
    APP_START_SOURCE="env"
    return 0
  fi

  if [[ -x "$repo_script" ]] && "$repo_script" --is-configured >/dev/null 2>&1; then
    APP_START_COMMAND="$repo_script"
    APP_START_SOURCE="repo-script"
    return 0
  fi

  APP_START_COMMAND=""
  APP_START_SOURCE="unconfigured"
  return 1
}

resolve_app_ready_contract() {
  local repo_script
  repo_script="$REPO_ROOT/scripts/app-start"

  APP_READY_URL=""
  APP_READY_COMMAND=""
  APP_READY_SOURCE="unconfigured"

  if [[ -n "${HARNESS_APP_READY_COMMAND:-}" ]]; then
    APP_READY_COMMAND="$HARNESS_APP_READY_COMMAND"
    APP_READY_SOURCE="env-command"
    return 0
  fi

  if [[ -n "${HARNESS_APP_READY_URL:-}" ]]; then
    APP_READY_URL="$HARNESS_APP_READY_URL"
    APP_READY_SOURCE="env-url"
    return 0
  fi

  if [[ "$APP_START_SOURCE" == "repo-script" && -x "$repo_script" ]]; then
    if APP_READY_COMMAND="$("$repo_script" --print-ready-command 2>/dev/null)"; then
      if [[ -n "$APP_READY_COMMAND" ]]; then
        APP_READY_SOURCE="repo-script-command"
        return 0
      fi
    fi

    if APP_READY_URL="$("$repo_script" --print-ready-url 2>/dev/null)"; then
      if [[ -n "$APP_READY_URL" ]]; then
        APP_READY_SOURCE="repo-script-url"
        return 0
      fi
    fi
  fi

  if [[ "$APP_START_SOURCE" == "unconfigured" ]]; then
    return 1
  fi

  if [[ -n "$APP_URL" ]]; then
    APP_READY_URL="$APP_URL"
    APP_READY_SOURCE="default-app-url"
    return 0
  fi

  return 1
}

readiness_check_success() {
  if [[ -n "$APP_READY_COMMAND" ]]; then
    sh -lc "$APP_READY_COMMAND" >/dev/null 2>&1
    return $?
  fi

  if [[ -n "$APP_READY_URL" ]]; then
    curl -fsS "$APP_READY_URL" >/dev/null 2>&1
    return $?
  fi

  return 1
}

sleep_for_poll_interval() {
  awk "BEGIN { printf \"%.3f\", $APP_READY_POLL_INTERVAL_MS / 1000 }" | {
    read -r seconds
    sleep "$seconds"
  }
}

wait_for_app_readiness() {
  local started_at="$1"
  local app_pid="$2"
  local app_pgid="$3"
  local elapsed_ms=0
  local ready_at

  while [[ "$elapsed_ms" -le "$APP_READY_TIMEOUT_MS" ]]; do
    if ! is_pid_running "$app_pid"; then
      write_status_json "failed" "$started_at" "null" "failed" "false" "" "null" "app_exited_before_ready"
      return 1
    fi

    if readiness_check_success; then
      ready_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      write_status_json "ready" "$started_at" "$app_pid" "ready" "true" "$ready_at" "$app_pgid" ""
      return 0
    fi

    sleep_for_poll_interval
    elapsed_ms="$((elapsed_ms + APP_READY_POLL_INTERVAL_MS))"
  done

  stop_process_group "$app_pgid" "$app_pid" >/dev/null 2>&1 || true
  rm -f "$APP_PID_FILE" "$APP_PGID_FILE"
  write_status_json "failed" "$started_at" "null" "failed" "false" "" "null" "readiness_timeout"
  return 1
}

launch_app_process() {
  local app_start_command="$1"
  local app_log="$2"

  : >"$app_log"

  if command -v setsid >/dev/null 2>&1; then
    (
      cd "$REPO_ROOT"
      exec setsid env \
        WORKTREE_ID="$WORKTREE_ID" \
        APP_PORT="$APP_PORT" \
        API_PORT="$API_PORT" \
        METRICS_PORT="$METRICS_PORT" \
        AUX_PORT="$AUX_PORT" \
        STATE_ROOT="$STATE_ROOT" \
        DATA_ROOT="$DATA_ROOT" \
        CACHE_ROOT="$CACHE_ROOT" \
        LOG_ROOT="$LOG_ROOT" \
        ARTIFACT_ROOT="$ARTIFACT_ROOT" \
        TMP_ROOT="$TMP_ROOT" \
        APP_URL="$APP_URL" \
        API_URL="$API_URL" \
        APP_READY_URL="$APP_READY_URL" \
        APP_READY_COMMAND="$APP_READY_COMMAND" \
        APP_READY_SOURCE="$APP_READY_SOURCE" \
        sh -lc "$app_start_command" >>"$app_log" 2>&1
    ) &
    LAUNCHED_APP_PID="$!"
    return 0
  fi

  (
    cd "$REPO_ROOT"
    env \
      WORKTREE_ID="$WORKTREE_ID" \
      APP_PORT="$APP_PORT" \
      API_PORT="$API_PORT" \
      METRICS_PORT="$METRICS_PORT" \
      AUX_PORT="$AUX_PORT" \
      STATE_ROOT="$STATE_ROOT" \
      DATA_ROOT="$DATA_ROOT" \
      CACHE_ROOT="$CACHE_ROOT" \
      LOG_ROOT="$LOG_ROOT" \
      ARTIFACT_ROOT="$ARTIFACT_ROOT" \
      TMP_ROOT="$TMP_ROOT" \
      APP_URL="$APP_URL" \
      API_URL="$API_URL" \
      APP_READY_URL="$APP_READY_URL" \
      APP_READY_COMMAND="$APP_READY_COMMAND" \
      APP_READY_SOURCE="$APP_READY_SOURCE" \
      sh -lc "$app_start_command" >>"$app_log" 2>&1
  ) &
  LAUNCHED_APP_PID="$!"
}

print_port_allocation_summary() {
  cat <<EOF
TASK_PROFILE: $TASK_PROFILE
TASK_PROFILE_APP_START_POLICY: $TASK_PROFILE_APP_START_POLICY
TASK_PROFILE_RUNTIME_ISOLATION: $TASK_PROFILE_RUNTIME_ISOLATION
WORKTREE_MODE: $WORKTREE_MODE
WORKTREE_CONTEXT_SOURCE: $WORKTREE_CONTEXT_SOURCE
PORT_CONFLICT_MODE: $PORT_CONFLICT_MODE
PORT_ALLOCATION_SOURCE: $PORT_ALLOCATION_SOURCE
PORT_OFFSET: $PORT_OFFSET
EOF
}

print_app_start_summary() {
  cat <<EOF
APP_START_SOURCE: $APP_START_SOURCE
APP_READY_SOURCE: $APP_READY_SOURCE
EOF
}

print_runtime_paths() {
  cat <<EOF
STATE_ROOT: $STATE_ROOT
LOG_ROOT: $LOG_ROOT
EOF
}

print_urls() {
  cat <<EOF
APP_URL: $APP_URL
API_URL: $API_URL
EOF
}

print_identity_summary() {
  cat <<EOF
WORKTREE_ID: $WORKTREE_ID
REPO_ROOT: $REPO_ROOT
EOF
}

print_ports_summary() {
  cat <<EOF
APP_PORT: $APP_PORT
API_PORT: $API_PORT
METRICS_PORT: $METRICS_PORT
AUX_PORT: $AUX_PORT
EOF
}

print_summary() {
  print_identity_summary
  print_urls
  print_ports_summary
  print_port_allocation_summary
  print_app_start_summary
  print_runtime_paths
}

assert_port_mode_is_supported() {
  if [[ "$PORT_CONFLICT_MODE" != "strict" && "$PORT_CONFLICT_MODE" != "soft" ]]; then
    printf '不支持的 HARNESS_PORT_CONFLICT_MODE: %s。仅支持 strict 或 soft。\n' "$PORT_CONFLICT_MODE" >&2
    exit 1
  fi
}

assert_task_profile_is_supported() {
  if ! task_profile_is_supported "$TASK_PROFILE"; then
    printf '不支持的 HARNESS_TASK_PROFILE: %s。仅支持 review-only、code-only 或 app-validate。\n' "$TASK_PROFILE" >&2
    exit 1
  fi
}

should_start_app_for_task_profile() {
  [[ "$TASK_PROFILE_APP_START_POLICY" == "start" ]]
}

read_status_field() {
  local field="$1"
  if [[ ! -f "$STATUS_JSON" ]]; then
    printf '\n'
    return
  fi

  sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" "$STATUS_JSON" | head -n 1
}

read_status_bool_field() {
  local field="$1"
  if [[ ! -f "$STATUS_JSON" ]]; then
    printf '\n'
    return
  fi

  sed -E -n "s/.*\"$field\": (true|false).*/\\1/p" "$STATUS_JSON" | head -n 1
}

read_status_pid_field() {
  local field="$1"
  if [[ ! -f "$STATUS_JSON" ]]; then
    printf '\n'
    return
  fi

  sed -E -n "s/.*\"$field\": ([0-9]+|null).*/\\1/p" "$STATUS_JSON" | head -n 1
}

is_pid_running() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 1
  fi

  kill -0 "$pid" >/dev/null 2>&1
}

read_app_pid() {
  if [[ -f "$APP_PID_FILE" ]]; then
    tr -d '[:space:]' <"$APP_PID_FILE"
    return
  fi

  printf '\n'
}

read_app_pgid() {
  if [[ -f "$APP_PGID_FILE" ]]; then
    tr -d '[:space:]' <"$APP_PGID_FILE"
    return
  fi

  printf '\n'
}

stop_process_group() {
  local app_pgid="$1"
  local app_pid="$2"

  if [[ -n "$app_pgid" ]] && kill -0 "-$app_pgid" >/dev/null 2>&1; then
    kill "-$app_pgid" >/dev/null 2>&1 || true
    return 0
  fi

  if [[ -n "$app_pid" ]] && is_pid_running "$app_pid"; then
    kill "$app_pid" >/dev/null 2>&1 || true
    return 0
  fi

  return 1
}
