#!/usr/bin/env bash

set -euo pipefail

runtime_dir="${HIVE_CLICKHOUSE_RUNTIME_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/hive/clickhouse}"
pid_file="${runtime_dir}/clickhouse.pid"

if [[ ! -f "${pid_file}" ]]; then
  exit 0
fi

pid="$(<"${pid_file}")"

if kill -0 "${pid}" >/dev/null 2>&1; then
  kill "${pid}"
  for _attempt in $(seq 1 30); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

rm -f "${pid_file}"
