#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
service_name="homeassistant-nut-proxy.service"
run_user="${SUDO_USER:-$(id -un)}"

if [[ ! -x "$project_dir/.venv/bin/python" ]]; then
    echo "Missing virtual environment. Run python3 -m venv .venv and .venv/bin/pip install -r requirements.txt first." >&2
    exit 1
fi
"$project_dir/.venv/bin/python" -c 'import paho.mqtt.client'

unit_file="$(mktemp)"
trap 'rm -f -- "$unit_file"' EXIT
"$project_dir/.venv/bin/python" - "$project_dir" "$run_user" "$unit_file" <<'PY'
import pathlib
import sys

project_dir, run_user, output = sys.argv[1:]
if any(character in project_dir for character in '\n\r'):
    raise SystemExit('The project path must not contain line breaks.')
def quote(value):
    # Escape systemd quoted strings and literal specifier/variable markers.
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%').replace('$', '$$') + '"'

template = (pathlib.Path(project_dir) / 'homeassistant-nut-proxy.service').read_text()
unit = template.replace('@RUN_USER@', run_user)
unit = unit.replace('@PROJECT_DIR@', project_dir.replace('%', '%%'))
unit = unit.replace('@PYTHON@', quote(project_dir + '/.venv/bin/python'))
unit = unit.replace('@SCRIPT@', quote(project_dir + '/ups_monitor.py'))
pathlib.Path(output).write_text(unit)
PY

if [[ "$EUID" -eq 0 ]]; then
    as_root=()
else
    as_root=(sudo)
fi

"${as_root[@]}" install -m 0644 "$unit_file" "/etc/systemd/system/$service_name"
"${as_root[@]}" systemctl daemon-reload
"${as_root[@]}" systemctl enable "$service_name"
"${as_root[@]}" systemctl restart "$service_name"
"${as_root[@]}" systemctl --no-pager --full status "$service_name"
