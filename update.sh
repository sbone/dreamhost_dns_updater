#!/usr/bin/env bash

# Update a Dreamhost domain's DNS A record if local public IP doesn't match
# usage: ./update.sh $dreamhost_api_key $domain_to_update

api_key=$1
target_domain=$2

if [ -n "$api_key" ]; then
	echo "api_key set";
else
	echo "Provide an api_key";
	exit 1;
fi
if [ -n "$target_domain" ]; then
	echo "Domain to update: $target_domain"
else
	echo "Provide a target_domain";
	exit 1;
fi

public_ip="`wget -O - -q icanhazip.com`"

dns_record_ip="`wget -O- - -q "https://api.dreamhost.com/?key=$api_key&cmd=dns-list_records&type=A" | grep "\s$target_domain" | grep -oE "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"`"

echo "Public IP: $public_ip"
echo "DNS Record IP: $dns_record_ip"

if [ $public_ip != $dns_record_ip ]; then
	echo "Updating DNS A record to $public_ip"
	wget -O- - -q "https://api.dreamhost.com/?key=$api_key&cmd=dns-add_record&record=$target_domain&type=A&value=$public_ip"
	echo "Added DNS A record of value: $public_ip"

	wget -O- - -q "https://api.dreamhost.com/?key=$api_key&cmd=dns-remove_record&record=$target_domain&type=A&value=$dns_record_ip"
	echo "Removed DNS A record of value: $dns_record_ip"
else
	echo "DNS up-to-date; see ya!"
fi