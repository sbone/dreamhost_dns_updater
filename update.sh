#!/usr/bin/env bash
# Update Dreamhost DNS A records if public IP changes
# Supports multiple domains via .env
# Usage: ./update.sh [-d]   (-d for dry-run)

# Get the script directory so we can call this from anywhere
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR/.env"

# Check for -d option; set dry_run flag
dry_run=false
while getopts 'd' OPTION; do
  case "$OPTION" in
    d)
      dry_run=true
      ;;
    ?)
      dry_run=false
      ;;
  esac
done

# Config check
if [ -z "$API_KEY" ]; then
  echo "❌ Provide an API_KEY in .env"
  exit 1
fi
if [ -z "$DOMAINS" ]; then
  echo "❌ Provide DOMAINS in .env (space-separated)"
  exit 1
fi

# Convert space-separated DOMAINS string to an array
IFS=' ' read -r -a domains <<< "$DOMAINS"

# Get public IP
public_ip=$(wget -O - -q https://icanhazip.com)
if [ "$dry_run" = true ]; then
  echo "DRY RUN Public IP: $public_ip"
fi

# Loop over each domain
for target_domain in "${domains[@]}"; do
  timestamp=$(date +"%Y-%m-%d %I:%M%p")

  # Get current DNS A record for this domain
  dns_record_ip=$(wget -O - -q "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-list_records&type=A" \
                   | grep "\s$target_domain" \
                   | grep -oE "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}")

  if [ "$dry_run" = true ]; then
    echo "DRY RUN DNS Record IP for $target_domain: $dns_record_ip"
  fi

  # Update if IP differs
  if [[ "$public_ip" != "$dns_record_ip" ]]; then
    echo "$timestamp | Updating DNS A record for $target_domain to $public_ip"

    if [ "$dry_run" = false ]; then
      # Add new record
      wget -O- -q "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-add_record&record=$target_domain&type=A&value=$public_ip"
      echo "$timestamp | Added DNS A record of value: $public_ip"

      # Remove old record
      wget -O- -q "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-remove_record&record=$target_domain&type=A&value=$dns_record_ip"
      echo "$timestamp | Removed DNS A record of value: $dns_record_ip"
    else
      echo "DRY RUN: Would add $public_ip and remove $dns_record_ip for $target_domain"
    fi
  else
    [ "$dry_run" = false ] && echo "$timestamp | $target_domain DNS up-to-date"
  fi
done
