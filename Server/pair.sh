#!/usr/bin/env bash
# Shows this phone's setup code. Scan it with the iPhone Camera: Slam opens and syncs.
# The code holds the phone's token, so it is printed here only and never saved.
set -euo pipefail
env_file=${1:-$HOME/.config/slam/server.env}
host=$(tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
token=$(grep '^SLAM_PHONE_TOKEN=' "$env_file" | cut -d= -f2-)
printf 'slam://sync?url=https://%s:8444&token=%s' "$host" "$token" |
  docker run --rm -i python:3.12-alpine sh -c 'pip -q install --no-cache-dir --disable-pip-version-check --root-user-action=ignore qrcode==8.0 >/dev/null 2>&1 &&
    python -c "import qrcode, sys; q = qrcode.QRCode(border=2); q.add_data(sys.stdin.read()); q.print_ascii(invert=True)"'
