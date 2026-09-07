#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(git -C "$script_directory" rev-parse --show-toplevel)
cd "$repository_root"

latest_tag=$(git tag -l 'app@[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -n1 || true)
latest_version=${latest_tag#app@}

# Keep application releases independent from server and chart changes.
cliff_arguments=(
  --config "$repository_root/native/cliff.toml"
  --repository "$repository_root"
  --include-path "native/**/*"
  --include-path "mobile/**/*"
  --include-path "once.toml"
  --include-path "mise.toml"
  --include-path "scripts/prepare_sparkle.sh"
  --include-path "scripts/embed_sparkle.sh"
  --include-path "scripts/release/**/*"
  --include-path ".github/workflows/release-applications.yml"
)

export GITHUB_TOKEN=""
export GH_TOKEN=""

if [[ -n "$latest_tag" ]]; then
  range="$latest_tag..HEAD"
  next_tag=$(git cliff "${cliff_arguments[@]}" --bumped-version 2>/dev/null -- "$range" || true)
  release_commit_count=$(git cliff "${cliff_arguments[@]}" --context 2>/dev/null -- "$range" | jq '[.[].commits[] | select(.group != "Documentation" or .breaking)] | length')
else
  next_tag=$(git cliff "${cliff_arguments[@]}" --bumped-version 2>/dev/null || true)
  release_commit_count=$(git cliff "${cliff_arguments[@]}" --context 2>/dev/null | jq '[.[].commits[] | select(.group != "Documentation" or .breaking)] | length')
fi

next_version=${next_tag#app@}
should_release=false

if [[ "$release_commit_count" -eq 0 ]]; then
  next_version=${latest_version:-0.1.0}
elif [[ -z "$latest_tag" ]]; then
  [[ -z "$next_version" ]] && next_version="0.1.0"
  should_release=true
else
  greatest=$(printf '%s\n%s\n' "$latest_version" "$next_version" | sort -V | tail -n1)
  if [[ "$next_version" != "$latest_version" && "$greatest" == "$next_version" ]]; then
    should_release=true
  else
    next_version=$latest_version
  fi
fi

printf 'latest:  %s\nnext:    %s\ncommits: %s\nrelease: %s\n' "${latest_version:-<none>}" "$next_version" "$release_commit_count" "$should_release"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'should-release=%s\nnext-version=%s\nnext-tag=app@%s\n' "$should_release" "$next_version" "$next_version" >> "$GITHUB_OUTPUT"
fi
