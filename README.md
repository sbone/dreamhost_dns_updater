# dreamhost_dns_updater

Update one or more DreamHost DNS A records when your public IP changes.

The script uses the [DreamHost DNS API](https://help.dreamhost.com/hc/en-us/articles/217555707-DNS-API-commands) and [icanhazip.com](http://icanhazip.com/) to reconcile the configured hostnames to your current public IPv4 address.

## Requirements

- `bash`
- `wget`
- `awk`

## Setup

Copy the example env file:

```bash
cp .env.example .env
```

Then fill in your DreamHost API key and domain list in `.env`.

You can find your DreamHost API key in the [DreamHost panel](https://panel.dreamhost.com/?tree=home.api).

## Usage

Run the updater:

```bash
./update.sh
```

Run a dry run without making API changes:

```bash
./update.sh -d
```

## Tests

The test suite is a single Bash script with mocked `wget` and `date`, so it does not hit DreamHost or require extra test dependencies.

Run it with:

```bash
./tests/test_update.sh
```

The tests cover:

- exact hostname matching, including nearby subdomains
- adding the current IP when it is missing
- removing multiple stale A records
- removing stale records without re-adding the current IP
- dry-run behavior
- stopping on DreamHost API failures
