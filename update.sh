#!/usr/bin/env bash
# Update DreamHost DNS A records if public IP changes
# Supports multiple domains via .env
# Usage: ./update.sh [-d]   (-d for dry-run)

set -euo pipefail

# Get the script directory so we can call this from anywhere.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing .env file at $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

dreamhost_api() {
  local cmd="$1"
  shift

  local query="key=${API_KEY}&cmd=${cmd}"
  local param
  for param in "$@"; do
    query="${query}&${param}"
  done

  wget -qO- "https://api.dreamhost.com/?${query}"
}

require_api_success() {
  local response="$1"
  local action="$2"

  if [[ "$response" != success* ]]; then
    echo "❌ DreamHost API failed during ${action}: ${response}" >&2
    exit 1
  fi
}

valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# Check for -d option; set dry_run flag.
dry_run=false
while getopts 'd' OPTION; do
  case "$OPTION" in
    d)
      dry_run=true
      ;;
    *)
      echo "Usage: ./update.sh [-d]" >&2
      exit 1
      ;;
  esac
done

# Config check.
if [[ -z "${API_KEY:-}" ]]; then
  echo "❌ Provide an API_KEY in .env" >&2
  exit 1
fi
if [[ -z "${DOMAINS:-}" ]]; then
  echo "❌ Provide DOMAINS in .env (space-separated)" >&2
  exit 1
fi

# Convert space-separated DOMAINS string to an array.
IFS=' ' read -r -a domains <<< "$DOMAINS"

# Get public IP.
public_ip=$(wget -qO- https://icanhazip.com | tr -d '[:space:]')
if ! valid_ipv4 "$public_ip"; then
  echo "❌ Could not determine a valid public IPv4 address: ${public_ip}" >&2
  exit 1
fi

if [[ "$dry_run" == true ]]; then
  echo "DRY RUN Public IP: $public_ip"
fi

# Loop over each domain.
for target_domain in "${domains[@]}"; do
  timestamp=$(date +"%Y-%m-%d %I:%M%p")

  dns_record_ips=()
  while IFS= read -r dns_record_ip; do
    [[ -n "$dns_record_ip" ]] && dns_record_ips+=("$dns_record_ip")
  done < <(
    dreamhost_api dns-list_records "type=A" \
      | awk -F '\t' -v target="$target_domain" '
          $4 == "A" && $3 == target && $5 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $5 }
        '
  )

  if [[ "$dry_run" == true ]]; then
    if [[ ${#dns_record_ips[@]} -gt 0 ]]; then
      echo "DRY RUN DNS Record IPs for $target_domain: ${dns_record_ips[*]}"
    else
      echo "DRY RUN DNS Record IPs for $target_domain: (none)"
    fi
  fi

  needs_add=true
  stale_ips=()

  if [[ ${#dns_record_ips[@]} -gt 0 ]]; then
    for dns_record_ip in "${dns_record_ips[@]}"; do
      if [[ "$dns_record_ip" == "$public_ip" ]]; then
        needs_add=false
      else
        stale_ips+=("$dns_record_ip")
      fi
    done
  fi

  if [[ "$needs_add" == false && ${#stale_ips[@]} -eq 0 ]]; then
    [[ "$dry_run" == false ]] && echo "$timestamp | $target_domain DNS up-to-date"
    continue
  fi

  echo "$timestamp | Reconciling DNS A record(s) for $target_domain to $public_ip"

  if [[ "$dry_run" == true ]]; then
    if [[ "$needs_add" == true ]]; then
      echo "DRY RUN: Would add $public_ip for $target_domain"
    fi
    if [[ ${#stale_ips[@]} -gt 0 ]]; then
      echo "DRY RUN: Would remove stale IP(s) for $target_domain: ${stale_ips[*]}"
    fi
    continue
  fi

  if [[ "$needs_add" == true ]]; then
    add_response=$(dreamhost_api dns-add_record "record=${target_domain}" "type=A" "value=${public_ip}")
    require_api_success "$add_response" "adding A record for ${target_domain}"
    echo "$timestamp | Added DNS A record of value: $public_ip"
  fi

  if [[ ${#stale_ips[@]} -gt 0 ]]; then
    for stale_ip in "${stale_ips[@]}"; do
      remove_response=$(dreamhost_api dns-remove_record "record=${target_domain}" "type=A" "value=${stale_ip}")
      require_api_success "$remove_response" "removing stale A record ${stale_ip} for ${target_domain}"
      echo "$timestamp | Removed stale DNS A record of value: $stale_ip"
    done
  fi
done
