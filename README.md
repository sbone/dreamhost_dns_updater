# dreamhost_dns_updater

Update one or more Dreamhost domain DNS A records if local public IP doesn't match

Depends on `wget`

Uses the [Dreamhost DNS API](https://help.dreamhost.com/hc/en-us/articles/217555707-DNS-API-commands) and [icanhazip.com](http://icanhazip.com/)

## Setup

1. `cp .env.local .env`
2. Fill in your Dreamhost API key ([found here](https://panel.dreamhost.com/?tree=home.api)) and domain(s) in `.env`

## Usage

1. run `./update.sh` (option `-d` flag for a dry run: for testing and debugging)

