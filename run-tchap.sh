#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NODE_BIN="${NODE_BIN:-$HOME/.local/node-v24.21.0/bin}"
PNPM_BIN="${PNPM_BIN:-$HOME/.local/pnpm-10.33.0/bin}"
export PATH="$NODE_BIN:$PNPM_BIN:$PATH"

ensure_node_dependencies() {
    command -v node >/dev/null 2>&1 || { echo "Node.js introuvable dans $NODE_BIN" >&2; exit 1; }
    command -v pnpm >/dev/null 2>&1 || { echo "pnpm introuvable dans $PNPM_BIN" >&2; exit 1; }
    [[ -x node_modules/.bin/webpack ]] || pnpm install --frozen-lockfile
}

cd "$ROOT_DIR"

public_host="${TCHAP_PUBLIC_HOST:-$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n 1)}"
public_host="${public_host:-127.0.0.1}"

mode="${1:-static}"
if (($# > 0)); then shift; fi

start_local_matrix() {
    if [[ "${TCHAP_START_MATRIX:-1}" == "1" ]]; then
        export TCHAP_UID="${TCHAP_UID:-$(id -u)}"
        export TCHAP_GID="${TCHAP_GID:-$(id -g)}"
        scripts/init-local-matrix.sh
        docker compose -f compose.matrix-local.yml up -d
        for _ in {1..60}; do
            if curl -fsS http://127.0.0.1:8008/_matrix/client/versions >/dev/null 2>&1; then
                return 0
            fi
            sleep 1
        done
        echo "Erreur: Matrix local ne repond pas sur le port 8008" >&2
        return 1
    fi
}

configure_client() {
    local config="${TCHAP_CONFIG:-apps/web/config.matrix-local.json}"
    [[ -f "$config" ]] || { echo "Configuration absente: $config" >&2; exit 1; }
    TCHAP_CONFIG_SOURCE="$config" TCHAP_CONFIG_HOST="$public_host" python3 - <<'PY'
import json
import os
from pathlib import Path

source = Path(os.environ["TCHAP_CONFIG_SOURCE"])
host = os.environ["TCHAP_CONFIG_HOST"]
config = json.loads(source.read_text())
homeserver_url = f"http://{host}:8008"

config["default_server_config"]["m.homeserver"]["base_url"] = homeserver_url
config["homeserver_list"][0]["base_url"] = homeserver_url
config["local_email_homeserver"]["base_url"] = homeserver_url
config["enable_presence_by_hs_url"] = {homeserver_url: False}

rendered = json.dumps(config, indent=4, ensure_ascii=False) + "\n"
Path("apps/web/config.json").write_text(rendered)
if Path("dist").is_dir():
    Path("dist/config.json").write_text(rendered)
PY
}

case "$mode" in
    dev)
        ensure_node_dependencies
        start_local_matrix
        configure_client
        echo "Tchap: http://$public_host:8080"
        echo "Comptes: $ROOT_DIR/local-users.txt"
        exec pnpm --dir apps/web start "$@"
        ;;
    static)
        start_local_matrix
        configure_client
        # Port 8080 is used by the Docs Keycloak stack on this workstation.
        port="${PORT:-8082}"
        [[ -f dist/index.html ]] || { echo "Build absent. Lancez: $0 build" >&2; exit 1; }
        echo "Tchap: http://$public_host:$port"
        echo "Comptes: $ROOT_DIR/local-users.txt"
        if TCHAP_RUNNING_URL="http://127.0.0.1:$port/config.json" \
            TCHAP_EXPECTED_HOMESERVER="http://$public_host:8008" python3 - <<'PY'
import json
import os
from urllib.request import urlopen

try:
    with urlopen(os.environ["TCHAP_RUNNING_URL"], timeout=1) as response:
        config = json.load(response)
    homeserver = config["default_server_config"]["m.homeserver"]["base_url"]
    raise SystemExit(0 if homeserver == os.environ["TCHAP_EXPECTED_HOMESERVER"] else 1)
except Exception:
    raise SystemExit(1)
PY
        then
            echo "Tchap est déjà démarré sur http://$public_host:$port"
            exit 0
        fi
        exec python3 scripts/serve-local.py "$port" dist
        ;;
    build)
        ensure_node_dependencies
        export CONFIG="${CONFIG:-dev}"
        export CI="${CI:-true}"
        pnpm scalingo-postbuild "$@"
        configure_client
        ;;
    matrix-stop)
        docker compose -f compose.matrix-local.yml stop
        ;;
    *)
        echo "Usage: $0 [dev|static|build|matrix-stop] [arguments...]" >&2
        exit 2
        ;;
esac
