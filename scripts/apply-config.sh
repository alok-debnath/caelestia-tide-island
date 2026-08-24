#!/usr/bin/env bash
# Apply the two settings the notch integration needs that live in user config
# files rather than in the QML trees, so they cannot be shipped as patches.
#
#   ~/.config/caelestia/shell.json     osd.enabled = false
#       Caelestia's own OSD is turned off because volume and brightness are
#       rendered in the notch instead. Without this both appear at once.
#
#   ~/.config/tide-island/userconfig.json   islandTopMargin = 0
#       The notch has to sit flush against the top border for the blob to fuse
#       with it. Any margin leaves the island floating as a separate pill.
#
# Both files are edited in place, key by key: anything else you have set in
# them is preserved, and re-running changes nothing.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require python3

: "${CAELESTIA_SHELL_JSON:=${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json}"
: "${TIDE_USER_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/tide-island/userconfig.json}"

apply_json_key() {
    local file=$1 path=$2 value=$3
    python3 - "$file" "$path" "$value" <<'PY'
import collections
import json
import os
import sys

path, keypath, raw = sys.argv[1], sys.argv[2], sys.argv[3]
value = json.loads(raw)

if os.path.exists(path):
    with open(path) as f:
        text = f.read().strip()
    data = json.loads(text, object_pairs_hook=collections.OrderedDict) if text else collections.OrderedDict()
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = collections.OrderedDict()

node = data
keys = keypath.split(".")
for key in keys[:-1]:
    if not isinstance(node.get(key), dict):
        node[key] = collections.OrderedDict()
    node = node[key]

if node.get(keys[-1]) == value:
    print(f"unchanged: {keypath} = {raw}")
    sys.exit(0)

node[keys[-1]] = value
with open(path, "w") as f:
    json.dump(data, f, indent=4, sort_keys=True)
    f.write("\n")
print(f"set: {keypath} = {raw}")
PY
}

log "configuring $CAELESTIA_SHELL_JSON"
apply_json_key "$CAELESTIA_SHELL_JSON" "osd.enabled" "false"

log "configuring $TIDE_USER_CONFIG"
apply_json_key "$TIDE_USER_CONFIG" "islandTopMargin" "0"

log "done"
