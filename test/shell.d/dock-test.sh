#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export OMARCHY_PATH="$ROOT"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ROOT="$ROOT" run_node_test <<'JS'
const dock = requireFromRoot('shell/plugins/dock/DockModel.js')
const handoffQml = require('fs').readFileSync(process.env.ROOT + '/shell/plugins/dock/DockWindow.qml', 'utf8')
const hoverExpression = handoffQml.match(/readonly property bool iconsHovered: ([^\n]+)/)[1]
const iconHover = new Function('window', 'return ' + hoverExpression)
const trackBody = handoffQml.match(/function trackIconHover\(icon\) \{([\s\S]*?)\n  \}/)[1]
const trackHover = new Function('window', 'icon', trackBody)
const hideBody = handoffQml.match(/id: hideTimer[\s\S]*?onTriggered: \{([\s\S]*?)\n    \}/)[1]
const finishHide = new Function('window', 'bodyHover', 'edgeHover', 'edgeSensor', 'pinsHover', 'pinGapHover', hideBody)
const handoffOutside = {hovered: false, containsMouse: false}
const handoff = {revealed: true, hoveredIcon: null, menuOpen: false, dragging: false, positionChanging: false}
Object.defineProperty(handoff, 'iconsHovered', {get: () => iconHover(handoff)})
const handoffIcon = {pointerInside: true}, handoffNext = {pointerInside: true}
trackHover(handoff, handoffIcon)
finishHide(handoff, handoffOutside, handoffOutside, handoffOutside, handoffOutside, handoffOutside)
assert(handoff.revealed, 'an app icon keeps the dock visible when edge and body hover have cleared')
trackHover(handoff, handoffNext); handoffIcon.pointerInside = false; trackHover(handoff, handoffIcon)
assertEqual(handoff.hoveredIcon, handoffNext, 'an old slot exit cannot clear a newer icon entry')
finishHide(handoff, handoffOutside, handoffOutside, handoffOutside, handoffOutside, handoffOutside)
assert(handoff.revealed, 'the next icon still holds the dock during handoff')
handoffNext.pointerInside = false; trackHover(handoff, handoffNext)
finishHide(handoff, handoffOutside, handoffOutside, handoffOutside, handoffOutside, handoffOutside)
assert(!handoff.revealed, 'leaving all dock targets still allows auto-hide')


for (const [icon, count, length, extra] of [[66, 12, 742, 0], [36, 29, 1280, 24], [36, 120, 742, 24]]) {
  const fit = dock.fitSlots(icon, 6, count, length, extra)
  assert((fit.iconSize + fit.inset * 2) * count + extra <= length + 0.0001, 'all dock slots fit the available edge: ' + count + ' slots on ' + length)
  assert(fit.iconSize > 0 && fit.iconSize <= icon, 'fitting keeps every icon visible without enlarging requested icons')
}
const dragQml = require('fs').readFileSync(process.env.ROOT + '/shell/plugins/dock/DockWindow.qml', 'utf8')
const method = name => dragQml.match(new RegExp('function ' + name + '\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}'))[1]
const dropWindow = { position: 'left', vertical: true, width: 240, height: 742, gap: 3, shown: true, autohide: false, insertIndex: -1, externalDropArea: null,
  origin: () => ({x: 0, y: 0}), slotIndexAt: () => 5, settleShifts: () => {}, dock: {pinAt: key => { pinnedDrop = key }} }
Object.defineProperty(dropWindow, 'slotSize', {get() { const fit = dock.fitSlots(66, 6, 12 + (this.insertIndex >= 0 ? 1 : 0), 736, 0); return fit.iconSize + fit.inset * 2 }})
const dropBody = { x: 3, get y() { return (742 - this.height) / 2 }, get width() { return dropWindow.slotSize }, get height() { return dropWindow.slotSize * (12 + (dropWindow.insertIndex >= 0 ? 1 : 0)) } }
const moveDrop = new Function('window', 'body', 'Qt', 'screenX', 'screenY', method('moveExternalDrag'))
dropWindow.moveExternalDrag = (x, y) => moveDrop(dropWindow, dropBody, {point: (x,y) => ({x,y})}, x, y)
const initialSlot = dropWindow.slotSize
dropWindow.moveExternalDrag(120, 371)
assert(dropWindow.insertIndex >= 0 && dropWindow.slotSize < initialSlot, 'a crowded dock shows a fitted app-drop preview')
dropWindow.moveExternalDrag(120, 371)
assert(dropWindow.insertIndex >= 0, 'preview shrink cannot reject the stationary drag pointer')
let pinnedDrop = null
const timer = {restart() {}}
dropWindow.endExternalDrag = () => new Function('window', 'collapseTimer', 'hideTimer', method('endExternalDrag'))(dropWindow, timer, timer)
new Function('window', 'screenX', 'screenY', 'key', method('dropExternalDrag'))(dropWindow, 120, 371, 'org.example.Drop')
assertEqual(pinnedDrop, 'org.example.Drop', 'releasing a crowded preview pins the app')
assertEqual(dropWindow.externalDropArea, null, 'the next drag starts with fresh acceptance bounds')

const roomy = dock.fitSlots(36, 6, 4, 1280, 0)
assertEqual(roomy.iconSize, 36, 'a dock that already fits keeps its normal icon size')
assertEqual(roomy.inset, 6, 'a dock that already fits keeps its normal spacing')

const dockSource = require('fs').readFileSync(process.env.ROOT + '/shell/plugins/dock/Dock.qml', 'utf8')
const keyBody = dockSource.match(/function appKey\(key\) \{([^}]+)\}/)[1]
const pulseBody = dockSource.match(/function isLaunching\(key\) \{([^}]+)\}/)[1]
const launchingRoot = { appKey: new Function('key', keyBody), launches: { 'org.example.App': {} } }
const isLaunching = new Function('root', 'key', pulseBody)
assert(isLaunching(launchingRoot, 'org.example.App::window::0xabc'), 'window-instance launch feedback resolves the shared app identity')
assert(!isLaunching(launchingRoot, 'org.example.Other::window::0xdef'), 'launch feedback does not pulse another app')



assertEqual(dock.workspaceBadgeNumber(1), 1, 'first-monitor workspace badges keep their number')
assertEqual(dock.workspaceBadgeNumber(10), 10, 'the tenth workspace never becomes a zero badge')
assertEqual(dock.workspaceBadgeNumber(11), 21, 'monitor two workspace one is labelled 21')
assertEqual(dock.workspaceBadgeNumber(12), 22, 'monitor two workspace two is labelled 22')
assertEqual(dock.workspaceBadgeNumber(20), 30, 'the second block keeps the previous complete numbering')

assertEqual(dock.normalizePosition('left'), 'left', 'dock accepts a valid position')
assertEqual(dock.normalizePosition(' Top '), 'top', 'dock reads a position loosely')
assertEqual(dock.normalizePosition('diagonal'), 'bottom', 'dock falls back to the bottom')
assertEqual(dock.normalizePosition(undefined), 'bottom', 'dock sits at the bottom by default')
assert(dock.isVertical('right') && !dock.isVertical('top'), 'dock runs vertically on the left and right')

assertDeepEqual(
  dock.pinnedIds({ pinned: ['chromium', 'org.gnome.Nautilus.desktop', 'chromium', ''] }, { pinned: ['spotify'] }),
  ['chromium', 'org.gnome.Nautilus'],
  'dock pins each desktop id once, without its .desktop suffix'
)
assertDeepEqual(dock.pinnedIds({}, { pinned: ['spotify'] }), ['spotify'], 'dock falls back to the default pins')
assertDeepEqual(dock.pinnedIds({ pinned: [] }, { pinned: ['spotify'] }), [], 'dock keeps an emptied pin list empty')

const app = (key, id, extra) => Object.assign({ key, id, hasEntry: true, workspaceId: 3 }, extra)
const items = dock.buildItems(['chromium', 'Alacritty'], [
  app('signal', 1),
  app('chromium', 2),
  app('signal', 3),
  app('org.omarchy.agent', 4, { hasEntry: false }),
  app('foot', 5, { workspaceId: -98 })
])
assertDeepEqual(
  items.map(item => [item.key, item.pinned, item.windows.map(window => window.id)]),
  [
    ['chromium', true, [2]],
    ['Alacritty', true, []],
    ['signal', false, [1, 3]]
  ],
  'dock lists pinned apps first, then running apps grouped by app, leaving out helpers and special workspaces'
)

assert(!dock.isDockWindow(app('foot', 6, { workspaceId: 0 })), 'dock leaves out windows without a regular workspace')
assert(
  dock.isDockWindow(app('xeyes', 7, { hasEntry: false, workspaceId: -99, minimized: true })),
  'dock keeps a minimized window without a desktop entry, so it can come back'
)
assertEqual(dock.dropIndex(2, 0, 40, 6), 2, 'dock keeps a barely dragged app in its slot')
assertEqual(dock.dropIndex(2, 85, 40, 6), 4, 'dock lands a dragged app as many slots on as the pointer went')
assertEqual(dock.dropIndex(2, -500, 40, 6), 0, 'dock lands an app dragged past the start in the first slot')
assertEqual(dock.dropIndex(2, 500, 40, 6), 5, 'dock lands an app dragged past the end in the last slot')

const allPins = ['chromium', 'Alacritty', 'spotify-not-installed', 'signal']
const pinned = { chromium: true, Alacritty: true, signal: true }
assertDeepEqual(
  dock.pinsInOrder(['signal', 'chromium', 'Alacritty', 'slack'], pinned, allPins),
  ['signal', 'chromium', 'Alacritty', 'spotify-not-installed'],
  'dock saves pins in its order, keeping pins it does not show'
)
assertDeepEqual(
  dock.pinsInOrder(['chromium', 'slack', 'Alacritty', 'signal'], Object.assign({ slack: true }, pinned), allPins),
  ['chromium', 'slack', 'Alacritty', 'signal', 'spotify-not-installed'],
  'dock pins a running app dragged in among the pins'
)

assertDeepEqual(
  dock.orderWithKeyAt(['chromium', 'Alacritty', 'signal'], 'obsidian', 1),
  ['chromium', 'obsidian', 'Alacritty', 'signal'],
  'dock puts an app dropped from the app grid where it lands'
)
assertDeepEqual(
  dock.orderWithKeyAt(['chromium', 'Alacritty', 'signal'], 'chromium', 2),
  ['Alacritty', 'signal', 'chromium'],
  'dock moves an app it already shows to where it is dropped'
)
assertDeepEqual(
  dock.orderWithKeyAt(['chromium', 'slack', 'signal'], 'slack', 3),
  ['chromium', 'signal', 'slack'],
  'dock puts an app kept in the dock at the end'
)

const terminalEntries = [
  { id: 'nvim', execString: 'nvim %F', command: ['nvim', '%F'], runInTerminal: true },
  { id: 'HEY TUI', execString: 'xdg-terminal-exec --app-id=org.omarchy.hey -e hey tui', command: ['xdg-terminal-exec', '--app-id=org.omarchy.hey', '-e', 'hey', 'tui'], runInTerminal: false },
  { id: 'btop', execString: '/usr/bin/btop', command: ['/usr/bin/btop'], runInTerminal: true }
]
assertEqual(dock.claimingEntryId('org.omarchy.nvim', terminalEntries), 'nvim', 'dock gives Neovim launched by the TUI launcher its own entry')
assertEqual(dock.claimingEntryId('org.omarchy.btop', terminalEntries), 'btop', 'dock matches a terminal entry by its program name')
assertEqual(dock.claimingEntryId('org.omarchy.hey', terminalEntries), 'HEY TUI', 'dock matches an entry that hands the terminal its app id')
assertEqual(dock.claimingEntryId('org.omarchy.agent', terminalEntries), '', 'dock leaves an app id no entry claims unclaimed')
assertEqual(dock.claimingEntryId('Alacritty', terminalEntries), '', 'dock leaves a terminal of its own to its own entry')

assertDeepEqual(
  dock.orderItems([{ key: 'chromium' }, { key: 'signal' }, { key: 'slack' }, { key: 'foot' }], ['slack', 'gone', 'chromium']).map(item => item.key),
  ['slack', 'chromium', 'signal', 'foot'],
  'dock keeps its own order, with apps that join going at the end'
)
const foot = [
  { workspaceId: 2, minimized: false, activated: false },
  { workspaceId: -99, minimized: true, activated: false },
  { workspaceId: 4, minimized: false, activated: false }
]
assertEqual(dock.pickWindow(foot, 4), 2, 'dock brings forward the window on the workspace in front of the user first')
assertEqual(dock.pickWindow(foot, 3), 1, 'dock restores a minimized window before leaving for another workspace')
assertEqual(dock.pickWindow(foot.map((w, i) => Object.assign({}, w, { activated: i === 2 })), 4), 1, 'dock cycles from the window here to the minimized one')
assertEqual(dock.pickWindow([], 4), -1, 'dock has no window to pick for an app that is not running')

const instances = dock.buildItems(['chromium'], [
  app('chromium', 1, { address: 'a', workspaceId: 2 }),
  app('chromium', 2, { address: 'b', workspaceId: 1 })
], true)
assertEqual(instances.length, 3, 'instances keep the pinned launcher and both window identities')
assertDeepEqual(dock.orderItems(instances, [], true).map(i => i.windows.map(w => w.id)), [[], [2], [1]], 'instances sort by workspace')
const minimized = instances[1]
minimized.windows[0].minimized = true
assertDeepEqual(dock.orderItems(instances, instances.map(i => i.key), true).map(i => i.key), instances.map(i => i.key), 'minimizing alone does not rearrange instances')

assert(dock.isMinimizedWorkspace('special:minimized'), 'legacy minimized windows remain recognized')
assert(dock.isMinimizedWorkspace('special:minimized-output-DP-2'), 'per-output minimized windows remain in the dock')
assert(dock.isMinimizedWorkspace('special:minimized-output-1'), 'a staged restore stays in the dock')
assert(!dock.isMinimizedWorkspace('special:scratchpad'), 'other special workspaces stay excluded')

const held = { key: 'M', windows: [{ minimized: true, workspaceId: -99 }] }
const liveA = { key: 'A', windows: [{ workspaceId: 5 }] }
const liveB = { key: 'B', windows: [{ workspaceId: 3 }] }
assertDeepEqual(dock.orderItems([liveA, held, liveB], ['A', 'M', 'B'], true).map(i => i.key), ['B', 'M', 'A'], 'workspace changes sort live windows around a fixed minimized slot')
assert(instances[1].appPinned && !instances[1].pinned, 'a pinned app instance keeps its menu pin state separate from launcher placement')


const folded = [
  { index: 0, center: 24, enabled: false },
  { index: 1, center: 24, enabled: false },
  { index: 2, center: 24, enabled: true },
  { index: 3, center: 72, enabled: true }
]
assertEqual(dock.nearestDropIndex(2, 48, folded), 3, 'dragging beside collapsed pins lands on the visible next app')
assertEqual(dock.nearestDropIndex(2, -500, folded), 2, 'dragging across hidden pins cannot save an invisible landing slot')
assertEqual(dock.nearestDropIndex(3, -48, folded), 2, 'backward dragging uses actual visible slot centers')
const expanded = folded.map((slot, i) => ({ index: i, center: i * 48 + 24, enabled: true }))
assertEqual(dock.nearestDropIndex(3, -144, expanded), 0, 'expanded launchers retain normal full-row drag destinations')

JS

# Exercise the action decision against live-state shaped Lua objects. Dispatch
# clicks focus existing windows and can restore windows minimized elsewhere.
ROOT="$ROOT" lua - <<'LUA'
local windows = {
  ["address:0xa"] = { mapped = true, hidden = false, active = true, workspace = { id = 2, name = "2" }, tags = {} },
  ["address:0xb"] = { mapped = true, hidden = false, active = false, workspace = { id = 3, name = "3" }, tags = {} },
}
local calls, timers = {}, {}
local function dispatch(kind) return function(args) return { kind = kind, args = args } end end
hl = {
  get_window = function(target) return windows[target] end,
  get_workspace = function() return nil end,
  window_rule = function() end,
  workspace_rule = function() end,
  dispatch = function(call) table.insert(calls, call) end,
  timer = function(callback) table.insert(timers, callback) end,
  dsp = { workspace = { move = dispatch("workspace-move") }, focus = dispatch("focus"), window = { move = dispatch("move"), tag = dispatch("tag"), alter_zorder = dispatch("raise") } },
}
o = {}
dofile(os.getenv("ROOT") .. "/default/hypr/dock.lua")
o.dock.activate("0xa", 2, "focus")
assert(calls[1].kind == "focus" and calls[2].kind == "raise", "active click keeps the window focused without minimizing")
calls = {}
o.dock.activate("0xa", 2, "toggle")
assert(calls[1].kind == "focus" and calls[2].kind == "raise", "legacy toggle requests no longer minimize")
calls = {}
o.dock.activate("0xb", 2, "toggle")
assert(calls[1].kind == "focus" and calls[1].args.workspace == "3", "remote click switches workspace before focusing")
windows["address:0xa"].workspace = { id = -99, name = "special:minimized" }
calls = {}
o.dock.activate("0xa", 2, "toggle")
assert(calls[1].kind == "move" and calls[1].args.workspace == "2", "minimized click restores to the clicked workspace")
o.dock.activate("0xb", 3, "focus")
local count = #calls
timers[1]()
assert(#calls == count, "a stale restore callback cannot steal focus from a newer click")

-- Cross-monitor restores settle while hidden, then use the normal reveal.
calls, timers = {}, {}
local destination = { id = 1, name = "eDP-1" }
hl.get_workspace = function() return { monitor = destination } end
windows["address:0xa"].monitor = { id = 2, name = "DP-2" }
hl.dispatch = function(call)
  table.insert(calls, call)
  if call.kind == "move" then
    windows[call.args.window].workspace = { name = call.args.workspace }
  end
end
o.dock.activate("0xa", 2, "focus")
assert(calls[1].kind == "tag" and calls[1].args.tag == "+omarchy-dock-restore", "placement disables motion only for the restoring window")
assert(calls[2].args.workspace == "special:minimized-output-1", "cross-monitor placement happens on a hidden destination workspace")
timers[1]()
assert(calls[3].args.tag == "-omarchy-dock-restore" and calls[4].args.workspace == "2", "normal animations return before the window is revealed")
timers[2]()
assert(calls[5].kind == "focus" and calls[6].kind == "raise", "restored window receives focus after placement")

calls, timers = {}, {}
windows["address:0xa"].workspace = { name = "special:minimized" }
o.dock.activate("0xa", 2, "focus")
o.dock.activate("0xa", 3, "focus")
local before = #calls
timers[1]()
assert(#calls == before, "an older placement cannot override a second restore click")
timers[2]()
assert(calls[#calls].args.workspace == "3", "the latest restore destination wins")

calls, timers = {}, {}
windows["address:0xa"].workspace = { name = "special:minimized" }
o.dock.activate("0xa", 2, "focus")
windows["address:0xa"].workspace = { name = "4" }
timers[1]()
assert(calls[#calls].args.tag == "-omarchy-dock-restore", "a manual move cancels placement and restores animation rules")

hl.get_workspace = function() return nil end
windows["address:0xa"].workspace = { id = -100, name = "special:minimized-output-DP-2" }
calls = {}
o.dock.activate("0xa", 2, "toggle")
assert(calls[1].kind == "move" and calls[1].args.workspace == "2", "per-output minimized windows restore normally")

LUA
pass "dock clicks use compositor state and discard stale focus callbacks"

home="$TMPDIR/home"
mkdir -p "$home/.config/omarchy"
mock_bin="$TMPDIR/bin"
mkdir -p "$mock_bin"
printf '#!/bin/bash\nexit 0\n' >"$mock_bin/omarchy-shell"
chmod +x "$mock_bin/omarchy-shell"
omarchy_dock() { HOME="$home" PATH="$mock_bin:$ROOT/bin:$PATH" omarchy-dock "$@"; }

[[ $(omarchy_dock position) == "bottom" ]] || fail "dock position defaults to bottom"
omarchy_dock position left >/dev/null
jq -e '.dock.position == "left" and .version == 1' "$home/.config/omarchy/shell.json" >/dev/null ||
  fail "dock position is saved" "$(cat "$home/.config/omarchy/shell.json")"
[[ $(omarchy_dock position) == "left" ]] || fail "dock position reads back"
if omarchy_dock position diagonal 2>/dev/null; then
  fail "dock position rejects anything but top, bottom, left, and right"
fi
pass "dock position is set and read through omarchy-dock"

default_pins=$(jq -r '.dock.pinned[]' "$ROOT/config/omarchy/shell.json" | paste -sd " ")
[[ -n $default_pins && $(omarchy_dock pinned | paste -sd " ") == "$default_pins" ]] || fail "dock pins start from the defaults"
omarchy_dock unpin spotify >/dev/null
omarchy_dock pin com.example.App.desktop >/dev/null
omarchy_dock pin com.example.App >/dev/null
jq -e '
  .dock.pinned[-1] == "com.example.App" and
  (.dock.pinned | index("spotify")) == null and
  (.dock.pinned | map(select(. == "com.example.App")) | length) == 1 and
  .dock.position == "left"
' "$home/.config/omarchy/shell.json" >/dev/null ||
  fail "dock pins and unpins apps once each" "$(cat "$home/.config/omarchy/shell.json")"
pass "dock pins and unpins apps through omarchy-dock"

omarchy_dock pinned signal chromium.desktop signal >/dev/null
[[ $(omarchy_dock pinned | paste -sd ' ') == "signal chromium" ]] ||
  fail "dock pin order is set in one go" "$(cat "$home/.config/omarchy/shell.json")"
pass "dock pin order is set through omarchy-dock pinned"

[[ $(omarchy_dock autohide) == "off" ]] || fail "dock auto-hide starts off"
omarchy_dock autohide toggle >/dev/null
jq -e '.dock.autohide == true' "$home/.config/omarchy/shell.json" >/dev/null || fail "dock auto-hide toggles on"
[[ $(omarchy_dock autohide) == "on" ]] || fail "dock auto-hide reads back"
omarchy_dock autohide off >/dev/null
jq -e '.dock.autohide == false' "$home/.config/omarchy/shell.json" >/dev/null || fail "dock auto-hide turns off"
if omarchy_dock autohide sometimes 2>/dev/null; then
  fail "dock auto-hide takes only on, off, or toggle"
fi
pass "dock auto-hide is set through omarchy-dock autohide"

omarchy_dock icon-size 48 >/dev/null
omarchy_dock magnification 25 >/dev/null
[[ $(omarchy_dock collapse-pinned) == "off" ]] || fail "pins start expanded"
omarchy_dock collapse-pinned toggle >/dev/null
[[ $(omarchy_dock collapse-pinned) == "on" ]] || fail "pin collapse toggles and reads back"
if omarchy_dock collapse-pinned sometimes 2>/dev/null; then fail "invalid pin collapse value accepted"; fi
omarchy_dock shelf on >/dev/null
omarchy_dock instances toggle >/dev/null
jq -e '.dock.iconSize == 48 and .dock.magnification == 25 and .dock.shelf and .dock.instances' "$home/.config/omarchy/shell.json" >/dev/null || fail "dock preferences persist together"
omarchy_dock icon-size 66 >/dev/null
[[ $(omarchy_dock icon-size) == 66 ]] || fail "dock accepts the largest size choice"
for value in -1 67 invalid 100000000000000000000000; do
  if omarchy_dock icon-size "$value" 2>/dev/null; then fail "dock rejects invalid icon sizes"; fi
done
pins_before=$(omarchy_dock pinned)
omarchy_dock reset >/dev/null
[[ $(omarchy_dock pinned) == "$pins_before" && $(omarchy_dock icon-size) == 36 && $(omarchy_dock magnification) == 15 && $(omarchy_dock instances) == "off" && $(omarchy_dock collapse-pinned) == "off" ]] || fail "dock reset restores behavior without losing pinned apps"
pass "dock appearance settings validate, persist and reset without changing pins"

# Minimizing moves a window to the dock's hidden workspace without following
# it, then focuses the workspace it left, so the next window opens there and
# not beside the minimized one.
cat >"$mock_bin/hyprctl" <<STUB
#!/bin/bash
case "\$1" in
  clients) printf '[{"address":"0xabc","workspace":{"id":3}}]\n' ;;
  activewindow) printf '{"address":"0xdef","workspace":{"id":5}}\n' ;;
  dispatch) printf '%s\n' "\$2" >>"$TMPDIR/hyprctl.log" ;;
esac
STUB
chmod +x "$mock_bin/hyprctl"
printf '#!/bin/bash\n[[ $1 == 9 ]] && echo dwindle || echo floating\n' >"$mock_bin/omarchy-hyprland-workspace-layout-current"
chmod +x "$mock_bin/omarchy-hyprland-workspace-layout-current"
minimize() { PATH="$mock_bin:$ROOT/bin:$PATH" omarchy-hyprland-window-minimize "$@"; }

minimize 0xabc
grep -qxF 'hl.dsp.window.tag({ tag = "+omarchy-minimized-from-3", window = "address:0xabc" })' "$TMPDIR/hyprctl.log" ||
  fail "minimize remembers the workspace the window left" "$(cat "$TMPDIR/hyprctl.log")"
grep -qxF 'hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:0xabc" })' "$TMPDIR/hyprctl.log" ||
  fail "minimize moves the window to the dock's hidden workspace" "$(cat "$TMPDIR/hyprctl.log")"
[[ $(tail -1 "$TMPDIR/hyprctl.log") == 'hl.dsp.focus({ workspace = "3" })' ]] ||
  fail "minimize focuses the workspace the window left" "$(cat "$TMPDIR/hyprctl.log")"
: >"$TMPDIR/hyprctl.log"
minimize
grep -qF 'hl.dsp.window.tag({ tag = "+omarchy-minimized-from-5", window = "address:0xdef" })' "$TMPDIR/hyprctl.log" &&
  grep -qF 'address:0xdef' "$TMPDIR/hyprctl.log" && [[ $(tail -1 "$TMPDIR/hyprctl.log") == 'hl.dsp.focus({ workspace = "5" })' ]] ||
  fail "minimize takes the active window when given none" "$(cat "$TMPDIR/hyprctl.log")"
pass "minimize sends a window to the dock and keeps focus on its workspace"

cat >"$mock_bin/hyprctl" <<STUB
#!/bin/bash
case "\$1" in
  clients) printf '[{"address":"0xabc","workspace":{"id":7},"tags":["omarchy-minimized-from-3"]}]\n' ;;
  dispatch) printf '%s\n' "\$2" >>"$TMPDIR/hyprctl.log" ;;
esac
STUB
: >"$TMPDIR/hyprctl.log"
minimize 0xabc
grep -qxF 'hl.dsp.window.tag({ tag = "-omarchy-minimized-from-3", window = "address:0xabc" })' "$TMPDIR/hyprctl.log" ||
  fail "minimize forgets the previous workspace" "$(cat "$TMPDIR/hyprctl.log")"
grep -qxF 'hl.dsp.window.tag({ tag = "+omarchy-minimized-from-7", window = "address:0xabc" })' "$TMPDIR/hyprctl.log" ||
  fail "minimize remembers the workspace it leaves this time" "$(cat "$TMPDIR/hyprctl.log")"
pass "minimize remembers only the workspace the window is leaving"

# A tiled workspace has no dock to bring a window back from, so nothing there
# is minimized.
cat >"$mock_bin/hyprctl" <<STUB
#!/bin/bash
case "\$1" in
  activewindow) printf '{"address":"0x999","workspace":{"id":9}}\n' ;;
  dispatch) printf '%s\n' "\$2" >>"$TMPDIR/hyprctl.log" ;;
esac
STUB
: >"$TMPDIR/hyprctl.log"
minimize
[[ ! -s $TMPDIR/hyprctl.log ]] || fail "minimize leaves windows on a tiled workspace alone" "$(cat "$TMPDIR/hyprctl.log")"
pass "minimize leaves windows on a tiled workspace alone"
