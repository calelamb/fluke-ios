#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
client_dir="$repo_root/Packages/FlukeKit/Tests/FlukeKitTests/Fixtures"
manifest="$repo_root/contracts/api-fixtures.sha256"
api_root="${FLUKE_API_ROOT:-}"
api_root_explicit=false
check_upstream=true

while (($# > 0)); do
  case "$1" in
    --client)
      client_dir="$2"
      shift 2
      ;;
    --manifest)
      manifest="$2"
      shift 2
      ;;
    --api-root)
      api_root="$2"
      api_root_explicit=true
      shift 2
      ;;
    --no-upstream)
      check_upstream=false
      shift
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$client_dir" || ! -f "$manifest" ]]; then
  printf 'Fixture directory or canonical manifest is missing\n' >&2
  exit 1
fi

verification_root="$(mktemp -d "${TMPDIR:-/tmp}/fluke-contract-verification.XXXXXX")"
trap 'rm -rf "$verification_root"' EXIT

awk '{print $2}' "$manifest" | LC_ALL=C sort >"$verification_root/expected-files"
find "$client_dir" -maxdepth 1 -type f -name '*.json' -exec basename {} \; \
  | LC_ALL=C sort >"$verification_root/client-files"

if ! cmp -s "$verification_root/expected-files" "$verification_root/client-files"; then
  unexpected="$(comm -13 "$verification_root/expected-files" "$verification_root/client-files")"
  missing="$(comm -23 "$verification_root/expected-files" "$verification_root/client-files")"
  [[ -z "$unexpected" ]] || printf 'unexpected packaged fixture: %s\n' "$unexpected" >&2
  [[ -z "$missing" ]] || printf 'missing packaged fixture: %s\n' "$missing" >&2
  exit 1
fi

if ! (cd "$client_dir" && shasum -a 256 -c "$manifest" >/dev/null); then
  printf 'checksum mismatch in packaged API fixtures\n' >&2
  exit 1
fi

if $check_upstream && [[ -z "$api_root" && -d "$repo_root/../fluke-api/contracts/fixtures" ]]; then
  api_root="$repo_root/../fluke-api"
fi

if $check_upstream && [[ -n "$api_root" ]]; then
  api_fixtures="$api_root/contracts/fixtures"
  if [[ ! -d "$api_fixtures" ]]; then
    if $api_root_explicit || [[ -n "${FLUKE_API_ROOT:-}" ]]; then
      printf 'Explicit API fixture directory is missing: %s\n' "$api_fixtures" >&2
      exit 1
    fi
  else
    # identify.json is intentionally not packaged: the shipping app has no
    # server-identification client (identification is on-device only).
    find "$api_fixtures" -maxdepth 1 -type f -name '*.json' ! -name 'identify.json' \
      -exec basename {} \; \
      | LC_ALL=C sort >"$verification_root/api-files"
    if ! cmp -s "$verification_root/client-files" "$verification_root/api-files"; then
      printf 'upstream fixture set differs from packaged fixture set\n' >&2
      exit 1
    fi
    while IFS= read -r fixture; do
      if ! cmp -s "$client_dir/$fixture" "$api_fixtures/$fixture"; then
        printf 'upstream fixture bytes differ: %s\n' "$fixture" >&2
        exit 1
      fi
    done <"$verification_root/client-files"
  fi
fi

printf 'Contract fixtures match the canonical manifest'
[[ -z "$api_root" ]] || printf ' and upstream API checkout'
printf '\n'
