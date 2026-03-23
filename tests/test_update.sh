#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "expected output to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "expected output to not contain: $needle"
  fi
}

assert_file_contains() {
  local path="$1"
  local needle="$2"

  if ! grep -Fqx "$needle" "$path"; then
    fail "expected $path to contain line: $needle"
  fi
}

assert_file_empty() {
  local path="$1"

  if [[ -s "$path" ]]; then
    fail "expected $path to be empty"
  fi
}

create_mock_bin() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"

  cat > "$bin_dir/date" <<'EOF'
#!/usr/bin/env bash
echo "2026-03-23 10:00AM"
EOF

  cat > "$bin_dir/wget" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url="${@: -1}"

extract_param() {
  local name="$1"
  printf '%s\n' "$url" | sed -n "s/.*[?&]${name}=\([^&]*\).*/\1/p"
}

if [[ "$url" == "https://icanhazip.com" ]]; then
  printf '%s\n' "${MOCK_PUBLIC_IP}"
  exit 0
fi

if [[ "$url" == *"cmd=dns-list_records"* ]]; then
  cat "${MOCK_DNS_LIST_FILE}"
  exit 0
fi

if [[ "$url" == *"cmd=dns-add_record"* ]]; then
  record="$(extract_param record)"
  value="$(extract_param value)"
  printf 'add:%s:%s\n' "$record" "$value" >> "${MOCK_CALLS_FILE}"

  while IFS='|' read -r expected_record expected_value response; do
    [[ -z "$expected_record" ]] && continue
    if [[ "$expected_record" == "$record" && "$expected_value" == "$value" ]]; then
      printf '%s\n' "$response"
      exit 0
    fi
  done < "${MOCK_ADD_RESPONSES_FILE}"

  printf 'error\tunexpected add request for %s=%s\n' "$record" "$value"
  exit 0
fi

if [[ "$url" == *"cmd=dns-remove_record"* ]]; then
  record="$(extract_param record)"
  value="$(extract_param value)"
  printf 'remove:%s:%s\n' "$record" "$value" >> "${MOCK_CALLS_FILE}"

  while IFS='|' read -r expected_record expected_value response; do
    [[ -z "$expected_record" ]] && continue
    if [[ "$expected_record" == "$record" && "$expected_value" == "$value" ]]; then
      printf '%s\n' "$response"
      exit 0
    fi
  done < "${MOCK_REMOVE_RESPONSES_FILE}"

  printf 'error\tunexpected remove request for %s=%s\n' "$record" "$value"
  exit 0
fi

printf 'error\tunexpected wget URL: %s\n' "$url"
exit 0
EOF

  chmod 755 "$bin_dir/date" "$bin_dir/wget"
}

create_case_dir() {
  CASE_DIR=$(mktemp -d)
  mkdir -p "$CASE_DIR/bin"
  cp "$REPO_ROOT/update.sh" "$CASE_DIR/update.sh"
  chmod 755 "$CASE_DIR/update.sh"
  create_mock_bin "$CASE_DIR/bin"
  : > "$CASE_DIR/mock_calls.log"
  : > "$CASE_DIR/add_responses.txt"
  : > "$CASE_DIR/remove_responses.txt"
}

write_env() {
  local domains="$1"

  cat > "$CASE_DIR/.env" <<EOF
API_KEY=test-key
DOMAINS="$domains"
EOF
}

run_update() {
  local args=("$@")

  set +e
  if [[ ${#args[@]} -gt 0 ]]; then
    OUTPUT=$(
      cd "$CASE_DIR" && \
      PATH="$CASE_DIR/bin:$PATH" \
      MOCK_PUBLIC_IP="$MOCK_PUBLIC_IP" \
      MOCK_DNS_LIST_FILE="$CASE_DIR/dns_list.txt" \
      MOCK_ADD_RESPONSES_FILE="$CASE_DIR/add_responses.txt" \
      MOCK_REMOVE_RESPONSES_FILE="$CASE_DIR/remove_responses.txt" \
      MOCK_CALLS_FILE="$CASE_DIR/mock_calls.log" \
      ./update.sh "${args[@]}" 2>&1
    )
  else
    OUTPUT=$(
      cd "$CASE_DIR" && \
      PATH="$CASE_DIR/bin:$PATH" \
      MOCK_PUBLIC_IP="$MOCK_PUBLIC_IP" \
      MOCK_DNS_LIST_FILE="$CASE_DIR/dns_list.txt" \
      MOCK_ADD_RESPONSES_FILE="$CASE_DIR/add_responses.txt" \
      MOCK_REMOVE_RESPONSES_FILE="$CASE_DIR/remove_responses.txt" \
      MOCK_CALLS_FILE="$CASE_DIR/mock_calls.log" \
      ./update.sh 2>&1
    )
  fi
  STATUS=$?
  set -e
}

finish_case() {
  rm -rf "$CASE_DIR"
}

test_up_to_date_exact_match_only() {
  create_case_dir
  trap finish_case RETURN
  write_env "example.com"
  MOCK_PUBLIC_IP="9.9.9.9"
  cat > "$CASE_DIR/dns_list.txt" <<'EOF'
A	9.9.9.9	example.com	-
A	5.5.5.5	foo.example.com	-
EOF

  run_update

  [[ "$STATUS" -eq 0 ]] || fail "expected success"
  assert_contains "$OUTPUT" "example.com DNS up-to-date"
  assert_not_contains "$OUTPUT" "foo.example.com"
  assert_file_empty "$CASE_DIR/mock_calls.log"
}

test_adds_current_and_removes_multiple_stale_records() {
  create_case_dir
  trap finish_case RETURN
  write_env "example.com"
  MOCK_PUBLIC_IP="9.9.9.9"
  cat > "$CASE_DIR/dns_list.txt" <<'EOF'
A	1.1.1.1	example.com	-
A	2.2.2.2	example.com	-
A	9.9.9.9	api.example.com	-
EOF
  cat > "$CASE_DIR/add_responses.txt" <<'EOF'
example.com|9.9.9.9|success	added
EOF
  cat > "$CASE_DIR/remove_responses.txt" <<'EOF'
example.com|1.1.1.1|success	removed
example.com|2.2.2.2|success	removed
EOF

  run_update

  [[ "$STATUS" -eq 0 ]] || fail "expected success"
  assert_contains "$OUTPUT" "Added DNS A record of value: 9.9.9.9"
  assert_contains "$OUTPUT" "Removed stale DNS A record of value: 1.1.1.1"
  assert_contains "$OUTPUT" "Removed stale DNS A record of value: 2.2.2.2"
  assert_file_contains "$CASE_DIR/mock_calls.log" "add:example.com:9.9.9.9"
  assert_file_contains "$CASE_DIR/mock_calls.log" "remove:example.com:1.1.1.1"
  assert_file_contains "$CASE_DIR/mock_calls.log" "remove:example.com:2.2.2.2"
}

test_removes_stale_without_adding_when_current_ip_exists() {
  create_case_dir
  trap finish_case RETURN
  write_env "example.com"
  MOCK_PUBLIC_IP="9.9.9.9"
  cat > "$CASE_DIR/dns_list.txt" <<'EOF'
A	9.9.9.9	example.com	-
A	1.1.1.1	example.com	-
EOF
  cat > "$CASE_DIR/remove_responses.txt" <<'EOF'
example.com|1.1.1.1|success	removed
EOF

  run_update

  [[ "$STATUS" -eq 0 ]] || fail "expected success"
  assert_not_contains "$OUTPUT" "Added DNS A record"
  assert_contains "$OUTPUT" "Removed stale DNS A record of value: 1.1.1.1"
  assert_not_contains "$(cat "$CASE_DIR/mock_calls.log")" "add:"
}

test_dry_run_makes_no_api_changes() {
  create_case_dir
  trap finish_case RETURN
  write_env "example.com"
  MOCK_PUBLIC_IP="9.9.9.9"
  cat > "$CASE_DIR/dns_list.txt" <<'EOF'
A	1.1.1.1	example.com	-
A	2.2.2.2	example.com	-
EOF

  run_update -d

  [[ "$STATUS" -eq 0 ]] || fail "expected success"
  assert_contains "$OUTPUT" "DRY RUN: Would add 9.9.9.9 for example.com"
  assert_contains "$OUTPUT" "DRY RUN: Would remove stale IP(s) for example.com: 1.1.1.1 2.2.2.2"
  assert_file_empty "$CASE_DIR/mock_calls.log"
}

test_api_failure_stops_execution() {
  create_case_dir
  trap finish_case RETURN
  write_env "example.com"
  MOCK_PUBLIC_IP="9.9.9.9"
  cat > "$CASE_DIR/dns_list.txt" <<'EOF'
A	1.1.1.1	example.com	-
EOF
  cat > "$CASE_DIR/add_responses.txt" <<'EOF'
example.com|9.9.9.9|error	add failed
EOF

  run_update

  [[ "$STATUS" -ne 0 ]] || fail "expected failure"
  assert_contains "$OUTPUT" "DreamHost API failed during adding A record for example.com"
  assert_not_contains "$OUTPUT" "Removed stale DNS A record"
  assert_not_contains "$OUTPUT" "Added DNS A record"
}

main() {
  local tests=(
    test_up_to_date_exact_match_only
    test_adds_current_and_removes_multiple_stale_records
    test_removes_stale_without_adding_when_current_ip_exists
    test_dry_run_makes_no_api_changes
    test_api_failure_stops_execution
  )

  local test_name
  for test_name in "${tests[@]}"; do
    "$test_name"
    echo "PASS: $test_name"
  done
}

main "$@"
