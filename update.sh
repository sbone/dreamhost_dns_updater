#!/usr/bin/env bash

# Update a Dreamhost domain's DNS A record if local public IP doesn't match
# usage: ./update.sh
# options: -d "dry run" for testing and debugging

# Get the script directory so we can call this from anywhere
# https://stackoverflow.com/a/246128
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "$SCRIPT_DIR/.env"

# check for -d option; set var accordingly
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

api_key="$API_KEY"
target_domain="$DOMAIN"
timestamp=`date +"%Y-%m-%d %I:%M%p"`

# config check; message and exit if there's a problem
if [ -z "$api_key" ]; then
	echo "❌ Provide an api_key";
	exit 1;
fi
if [ -z "$target_domain" ]; then
	echo "❌ Provide a target_domain";
	exit 1;
fi

# get your current public IP
public_ip="`wget -O - -q icanhazip.com`"
if [ -z $dry_run ]; then
  echo "DRY RUN Public IP: $public_ip"
fi

# extract the pertinent A record's IP address
dns_record_ip="`wget -O- - -q "https://api.dreamhost.com/?key=$api_key&cmd=dns-list_records&type=A" | grep "\s$target_domain" | grep -oE "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"`"
if [ -z "$dry_run" ]; then
  echo "DRY RUN DNS Record IP: $dns_record_ip"
fi

# if the IPs don't match, we need to update Dreamhost, otherwise just bounce.
if [ $public_ip != $dns_record_ip ]; then
	echo "$timestamp | Updating DNS A record to $public_ip"
  if [ -z "$dry_run" ]; then
    wget -O- - -q "https://api.dreamhost.com/?key=$api_key&cmd=dns-add_record&record=$target_domain&type=A&value=$public_ip"
    echo "$timestamp | Added DNS A record of value: $public_ip"
  else
    echo "DRY RUN: $timestamp | Added DNS A record of value: $public_ip"
  fi

  if [ -z "$dry_run" ]; then
    wget -O- - -q "https://api.dreamhost.com/?key=$api_key&cmd=dns-remove_record&record=$target_domain&type=A&value=$dns_record_ip"
    echo "$timestamp | Removed DNS A record of value: $dns_record_ip"
  else
    echo "DRY RUN: $timestamp | Removed DNS A record of value: $dns_record_ip"
  fi
	exit 0;
else

  if [ -z "$dry_run" ]; then
    echo "DNS up-to-date; see ya!"
  else
    echo "DRY RUN: DNS up-to-date; see ya!"
  fi
	exit 0;
fi
