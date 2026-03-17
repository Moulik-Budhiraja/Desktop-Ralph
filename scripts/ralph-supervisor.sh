#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PID_FILE="${RALPH_SUPERVISOR_PID_FILE:-/tmp/ralph-supervisor.pid}"
STOP_FILE="${RALPH_SUPERVISOR_STOP_FILE:-/tmp/ralph-supervisor.stop}"
LOG_FILE="${RALPH_SUPERVISOR_LOG_FILE:-/tmp/ralph-supervisor.log}"
WORKDIR="${RALPH_SUPERVISOR_WORKDIR:-$REPO_ROOT}"
MAX_RESTARTS="${RALPH_SUPERVISOR_MAX_RESTARTS:-infinite}"
RESTART_DELAY_SECONDS="${RALPH_SUPERVISOR_RESTART_DELAY_SECONDS:-1}"
CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_SUBCOMMAND="${CODEX_SUBCOMMAND:-exec}"
CODEX_EXTRA_ARGS="${CODEX_EXTRA_ARGS:---dangerously-bypass-approvals-and-sandbox}"
SKILL_PATH="${RALPH_SKILL_PATH:-/Users/moulik/.codex/skills/ralph-ui-chaos/SKILL.md}"

DEFAULT_PROMPT=$(cat <<EOF
Use the local Ralph tooling in ${REPO_ROOT} to create a harmless, playful on-screen spectacle for the user.
Use the skill at ${SKILL_PATH}.
Use this skill to annoy the user with Ralph in a harmless, mischievous way.
Reuse the existing Ralph daemon when possible, keep actions reversible and non-destructive, and do not send messages, submit forms, buy anything, or bypass safeguards.
If you finish a short stunt, start another harmless one instead of stopping immediately.
EOF
)

PROMPT="${RALPH_SUPERVISOR_PROMPT:-$DEFAULT_PROMPT}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") start
  $(basename "$0") stop
  $(basename "$0") status

Environment overrides:
  CODEX_BIN                         Default: codex
  CODEX_SUBCOMMAND                  Default: exec
  CODEX_EXTRA_ARGS                  Extra args split on shell words
  RALPH_SUPERVISOR_PROMPT           Prompt passed to codex exec
  RALPH_SUPERVISOR_MAX_RESTARTS     Default: infinite
  RALPH_SUPERVISOR_RESTART_DELAY_SECONDS Default: 1
  RALPH_SUPERVISOR_WORKDIR          Default: repo root
  RALPH_SUPERVISOR_PID_FILE         Default: /tmp/ralph-supervisor.pid
  RALPH_SUPERVISOR_STOP_FILE        Default: /tmp/ralph-supervisor.stop
  RALPH_SUPERVISOR_LOG_FILE         Default: /tmp/ralph-supervisor.log
  RALPH_SKILL_PATH                  Default: ${SKILL_PATH}

Notes:
  The Ralph daemon already uses a shared per-user socket, so restarted workers can reuse it automatically.
  This supervisor defaults to Codex's no-sandbox, bypass-approvals mode unless CODEX_EXTRA_ARGS overrides it.
EOF
}

is_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE")"
  kill -0 "$pid" 2>/dev/null
}

stop_supervisor() {
  touch "$STOP_FILE"
  if is_running; then
    local pid
    pid="$(cat "$PID_FILE")"
    echo "Stopping Ralph supervisor (pid ${pid})"
    kill "$pid" 2>/dev/null || true
  else
    echo "Ralph supervisor is not running"
  fi
}

status_supervisor() {
  if is_running; then
    echo "Ralph supervisor is running (pid $(cat "$PID_FILE"))"
  else
    echo "Ralph supervisor is not running"
  fi
  echo "Log: $LOG_FILE"
  echo "Stop file: $STOP_FILE"
}

cleanup() {
  rm -f "$PID_FILE"
}

run_worker() {
  local -a extra_args=()
  if [[ -n "$CODEX_EXTRA_ARGS" ]]; then
    # Intentional shell-style splitting for configurable CLI flags.
    read -r -a extra_args <<<"$CODEX_EXTRA_ARGS"
  fi

  (
    cd "$WORKDIR"
    if [[ "${#extra_args[@]}" -gt 0 ]]; then
      "$CODEX_BIN" "$CODEX_SUBCOMMAND" "${extra_args[@]}" "$PROMPT"
    else
      "$CODEX_BIN" "$CODEX_SUBCOMMAND" "$PROMPT"
    fi
  )
}

start_supervisor() {
  if is_running; then
    echo "Ralph supervisor is already running (pid $(cat "$PID_FILE"))"
    return 0
  fi

  rm -f "$STOP_FILE"
  mkdir -p "$(dirname "$LOG_FILE")"

  (
    trap cleanup EXIT

    local restarts=0
    while true; do
      if [[ -f "$STOP_FILE" ]]; then
        echo "[$(date '+%F %T')] stop file detected, exiting" >>"$LOG_FILE"
        break
      fi

      if [[ "$MAX_RESTARTS" != "infinite" && "$restarts" -ge "$MAX_RESTARTS" ]]; then
        echo "[$(date '+%F %T')] reached restart limit (${MAX_RESTARTS}), exiting" >>"$LOG_FILE"
        break
      fi

      echo "[$(date '+%F %T')] launching codex worker #$((restarts + 1))" >>"$LOG_FILE"
      if run_worker >>"$LOG_FILE" 2>&1; then
        echo "[$(date '+%F %T')] worker exited successfully" >>"$LOG_FILE"
      else
        local exit_code=$?
        echo "[$(date '+%F %T')] worker exited with code ${exit_code}" >>"$LOG_FILE"
      fi

      restarts=$((restarts + 1))

      if [[ -f "$STOP_FILE" ]]; then
        echo "[$(date '+%F %T')] stop file detected after worker exit" >>"$LOG_FILE"
        break
      fi

      sleep "$RESTART_DELAY_SECONDS"
    done
  ) &

  local pid=$!
  echo "$pid" >"$PID_FILE"
  echo "Ralph supervisor started (pid ${pid})"
  echo "Log: $LOG_FILE"
}

command="${1:-start}"

case "$command" in
  start)
    start_supervisor
    ;;
  stop)
    stop_supervisor
    ;;
  status)
    status_supervisor
    ;;
  *)
    usage
    exit 1
    ;;
esac
