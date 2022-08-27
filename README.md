# dreamhost_dns_updater

Update a Dreamhost domain's DNS A record if local public IP doesn't match

Depends on `wget`

Uses the [Dreamhost DNS API](https://help.dreamhost.com/hc/en-us/articles/217555707-DNS-API-commands) and [icanhazip.com](http://icanhazip.com/)

You can find your Dreamhost API Key [here](https://panel.dreamhost.com/?tree=home.api) in your Admin Panel.

usage: `./update.sh $dreamhost_api_key $domain_to_update`

