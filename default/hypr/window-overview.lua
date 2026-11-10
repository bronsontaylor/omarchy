-- Bind middle-click only while a floating workspace is focused. Tiled apps
-- retain their normal middle-click behavior (paste, open link, close tab, ...).
local paths = require("default.hypr.paths")
local modes = require("default.hypr.workspace-modes")
local enabled = io.open(paths.home .. "/.local/state/omarchy/toggles/window-overview-middle-click", "r")
if not enabled then return end
enabled:close()

local binding = nil
local function update()
  local workspace = hl.get_active_workspace()
  local floating = workspace and modes.is_floating(workspace.id)
  if floating and not binding then
    binding = hl.bind("mouse:274", hl.dsp.exec_cmd("omarchy-hyprland-window-overview"))
  elseif not floating and binding then
    binding:unbind()
    binding = nil
  end
end

modes.on_change(update)
hl.on("workspace.active", update)
hl.on("monitor.focused", update)
update()
