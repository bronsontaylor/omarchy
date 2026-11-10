#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const overview = requireFromRoot('shell/plugins/window-overview/OverviewModel.js')
const windows = [
  {address: 'a', workspace: {id: 2}, wayland: {title: 'One'}},
  {address: 'b', workspace: {id: 2}, wayland: {title: 'Two'}},
  {address: 'dialog', workspace: {id: 2}, wayland: {parent: {}}},
  {address: 'other', workspace: {id: 3}, wayland: {}},
  {address: 'minimized', workspace: {id: -99}, wayland: {}}
]
assertDeepEqual(overview.windowsOnWorkspace(windows, 2).map(w => w.address), ['a', 'b'], 'overview selects top-level windows only on its workspace')
assertEqual(overview.selectionAfterChange(windows, 1, [windows[1]]), 0, 'selection follows window identity after a preceding window closes')
assertEqual(overview.selectionAfterChange(windows, 1, [windows[0]]), 0, 'closing the selected window selects a remaining window')
assertEqual(overview.selectionAfterChange(windows, 1, []), -1, 'empty overview has no selection')
JS

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/bin"
export HOME="$tmp/home" OMARCHY_PATH="$ROOT" PATH="$tmp/bin:$ROOT/bin:$PATH"
export OVERVIEW_CALLS="$tmp/calls"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$OVERVIEW_CALLS"\n' >"$tmp/bin/hyprctl"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$OVERVIEW_CALLS"\n' >"$tmp/bin/omarchy-shell"
printf '#!/bin/bash\necho "${OVERVIEW_LAYOUT:-dwindle}"\n' >"$tmp/bin/omarchy-hyprland-workspace-layout-current"
chmod +x "$tmp/bin/"*

[[ $(omarchy-hyprland-window-overview middle-click) == "off" ]] || fail "overview middle-click is opt-in"
omarchy-hyprland-window-overview middle-click on
[[ $(omarchy-hyprland-window-overview middle-click) == "on" ]] || fail "overview middle-click preference persists"
omarchy-hyprland-window-overview middle-click toggle
[[ $(omarchy-hyprland-window-overview middle-click) == "off" ]] || fail "overview middle-click toggles off"
if omarchy-hyprland-window-overview middle-click invalid; then fail "overview rejects invalid toggle values"; fi
: >"$OVERVIEW_CALLS"
omarchy-hyprland-window-overview
[[ ! -s $OVERVIEW_CALLS ]] || fail "overview leaves tiled workspaces alone"
OVERVIEW_LAYOUT=floating omarchy-hyprland-window-overview
grep -qxF 'shell toggle omarchy.window-overview' "$OVERVIEW_CALLS" || fail "floating workspace invokes the overview lifecycle"
pass "overview triggers are opt-in and preserve tiled workspace input"

mkdir -p "$HOME/.local/state/omarchy/toggles"
touch "$HOME/.local/state/omarchy/toggles/window-overview-middle-click"
ROOT="$ROOT" lua <<'LUA'
local floating, binds, unbinds = false, 0, 0
local callback, up, dispatched
package.preload["default.hypr.paths"] = function() return { home = os.getenv("HOME") } end
package.preload["default.hypr.workspace-modes"] = function()
  return { is_floating = function() return floating end, on_change = function(fn) callback = fn end }
end
hl = {
  get_active_workspace = function() return { id = 2 } end,
  on = function() end,
  bind = function()
    binds = binds + 1
    return { unbind = function() unbinds = unbinds + 1 end }
  end,
  gesture = function(spec) if spec.fingers == 3 and spec.direction == "up" then up = spec end end,
  dispatch = function(value) dispatched = value end,
  dsp = { exec_cmd = function(command) return command end, workspace = { toggle_special = function(name) return name end } },
}
dofile(os.getenv("ROOT") .. "/default/hypr/window-overview.lua")
assert(binds == 0, "tiled workspace keeps middle-click")
floating = true; callback(); callback()
assert(binds == 1, "floating workspace binds once")
floating = false; callback()
assert(unbinds == 1, "leaving floating releases middle-click")
dofile(os.getenv("ROOT") .. "/default/hypr/gestures.lua")
assert(up.action == "special" and up.workspace_name == "qconsole", "disabled overview preserves default swipe")
local flag = assert(io.open(os.getenv("HOME") .. "/.local/state/omarchy/toggles/window-overview-three-finger-up", "w")); flag:close()
dofile(os.getenv("ROOT") .. "/default/hypr/gestures.lua")
up.action(); assert(dispatched == "qconsole", "tiled swipe keeps the console")
floating = true; up.action()
assert(dispatched == "omarchy-hyprland-window-overview", "enabled floating swipe opens overview")
LUA
pass "middle-click is released on tiling and swipe preserves the stock console action"
