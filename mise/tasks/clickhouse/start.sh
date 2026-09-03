#!/usr/bin/env bash

set -euo pipefail

runtime_dir="${HIVE_CLICKHOUSE_RUNTIME_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/hive/clickhouse}"
http_port="${HIVE_CLICKHOUSE_PORT:-8123}"
native_port="${HIVE_CLICKHOUSE_NATIVE_PORT:-9000}"
interserver_port="${HIVE_CLICKHOUSE_INTERSERVER_PORT:-9009}"
mysql_port="${HIVE_CLICKHOUSE_MYSQL_PORT:-9004}"
postgresql_port="${HIVE_CLICKHOUSE_POSTGRESQL_PORT:-9005}"
pid_file="${runtime_dir}/clickhouse.pid"
log_file="${runtime_dir}/clickhouse.log"

if curl --silent --fail --max-time 1 "http://127.0.0.1:${http_port}/ping" >/dev/null 2>&1; then
  exit 0
fi

if [[ -f "${pid_file}" ]]; then
  pid="$(<"${pid_file}")"
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    rm -f "${pid_file}"
  fi
fi

mkdir -p \
  "${runtime_dir}/config.d" \
  "${runtime_dir}/data" \
  "${runtime_dir}/format_schema" \
  "${runtime_dir}/logs" \
  "${runtime_dir}/tmp" \
  "${runtime_dir}/user_files"

if [[ ! -f "${pid_file}" ]]; then
  clickhouse server \
    --daemon \
    --pid-file="${pid_file}" \
    --log-file="${log_file}" \
    --errorlog-file="${runtime_dir}/clickhouse-error.log" \
    -- \
    --path="${runtime_dir}/data" \
    --tmp_path="${runtime_dir}/tmp" \
    --user_files_path="${runtime_dir}/user_files" \
    --format_schema_path="${runtime_dir}/format_schema" \
    --listen_host=127.0.0.1 \
    --http_port="${http_port}" \
    --tcp_port="${native_port}" \
    --interserver_http_port="${interserver_port}" \
    --mysql_port="${mysql_port}" \
    --postgresql_port="${postgresql_port}" \
    --keep_alive_timeout=10
fi

for _attempt in $(seq 1 60); do
  if curl --silent --fail --max-time 1 "http://127.0.0.1:${http_port}/ping" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "ClickHouse did not become ready. See ${log_file}." >&2
exit 1
