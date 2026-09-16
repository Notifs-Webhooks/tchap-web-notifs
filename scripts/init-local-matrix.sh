#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

image="ghcr.io/element-hq/synapse:develop@sha256:926d95954cba30a2568dbe907da6628d8e10e06f2b19901f0ec61eb2993be450"
data_dir="$ROOT_DIR/.tchap-matrix"
uid="${TCHAP_UID:-$(id -u)}"
gid="${TCHAP_GID:-$(id -g)}"

mkdir -p "$data_dir"

if [[ ! -f "$data_dir/homeserver.yaml" ]]; then
    echo "Initialisation du serveur Matrix local..."
    docker run --rm \
        -e UID="$uid" -e GID="$gid" \
        -e SYNAPSE_SERVER_NAME=localhost \
        -e SYNAPSE_REPORT_STATS=no \
        -v "$data_dir:/data" \
        "$image" generate
fi

if ! grep -q '^registration_shared_secret:' "$data_dir/homeserver.yaml"; then
    MATRIX_CONFIG="$data_dir/homeserver.yaml" python3 - <<'PY'
import os
import secrets
from pathlib import Path

path = Path(os.environ["MATRIX_CONFIG"])
with path.open("a") as stream:
    stream.write(f"\nregistration_shared_secret: {secrets.token_urlsafe(48)}\n")
PY
fi

# This Tchap client still loads MXC avatars through the unauthenticated
# /_matrix/media/v3 routes. Recent Synapse images default to authenticated
# media and return 404 on those legacy routes, so keep them enabled locally.
MATRIX_CONFIG="$data_dir/homeserver.yaml" python3 - <<'PY'
import os
import re
from pathlib import Path

path = Path(os.environ["MATRIX_CONFIG"])
config = path.read_text()
pattern = r"(?m)^enable_authenticated_media:\s*.*$"
if re.search(pattern, config):
    updated = re.sub(pattern, "enable_authenticated_media: false", config)
else:
    updated = config.rstrip() + "\n\nenable_authenticated_media: false\n"
if updated != config:
    path.write_text(updated)
PY

docker compose -f compose.matrix-local.yml up -d
for _ in {1..60}; do
    if curl -fsS http://127.0.0.1:8008/_matrix/client/versions >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
curl -fsS http://127.0.0.1:8008/_matrix/client/versions >/dev/null

if [[ ! -f "$data_dir/.users-initialized" ]]; then
    echo "Création des comptes Matrix Alice et Bob..."
    bootstrap_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
    docker exec tchap-matrix-local register_new_matrix_user \
        -u local-bootstrap -p "$bootstrap_password" -a \
        -c /data/homeserver.yaml http://localhost:8008 >/dev/null

    MATRIX_BOOTSTRAP_PASSWORD="$bootstrap_password" python3 - <<'PY'
import json
import os
from urllib.request import Request, urlopen

base = "http://127.0.0.1:8008"

def request(path, payload, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    method = "PUT" if token else "POST"
    req = Request(base + path, json.dumps(payload).encode(), headers, method=method)
    with urlopen(req, timeout=15) as response:
        return json.load(response)

login = request("/_matrix/client/v3/login", {
    "type": "m.login.password",
    "identifier": {"type": "m.id.user", "user": "local-bootstrap"},
    "password": os.environ["MATRIX_BOOTSTRAP_PASSWORD"],
})
token = login["access_token"]

users = [
    ("alice", "Alice", "alice@local.test", "AliceLocal2026!"),
    ("bob", "Bob", "bob@local.test", "BobLocal2026!"),
]
for localpart, displayname, email, password in users:
    request(f"/_synapse/admin/v2/users/@{localpart}:localhost", {
        "password": password,
        "displayname": displayname,
        "admin": False,
        "deactivated": False,
        "threepids": [{"medium": "email", "address": email}],
    }, token)
PY
    touch "$data_dir/.users-initialized"
fi
