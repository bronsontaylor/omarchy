-- Touchpad gestures. See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
--
-- Hyprland rejects a second gesture on the same fingers and direction, so
-- overriding one of these means unsetting it first:
--   hl.gesture({ fingers = 3, direction = "up", action = "unset" })
-- Or turn them all off with omarchy_default_gestures = false in hyprland.lua.

-- Swipe through workspaces, empty ones included. Workspace switches aren't
-- animated, so the switch lands when the swipe ends rather than dragging the
-- workspace along under the fingers.
hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ workspace = "r-1" })) end })
hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ workspace = "r+1" })) end })

-- Push up for the AI console, and pull down for the Omarchy menu.
local paths = require("default.hypr.paths")
local overview_swipe = io.open(paths.home .. "/.local/state/omarchy/toggles/window-overview-three-finger-up", "r")
if overview_swipe then
  overview_swipe:close()
  hl.gesture({ fingers = 3, direction = "up", action = function()
    local modes = require("default.hypr.workspace-modes")
    local workspace = hl.get_active_workspace()
    if workspace and modes.is_floating(workspace.id) then
      hl.dispatch(hl.dsp.exec_cmd("omarchy-hyprland-window-overview"))
    else
      hl.dispatch(hl.dsp.workspace.toggle_special("qconsole"))
    end
  end })
else
  hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "qconsole" })
end
hl.gesture({ fingers = 3, direction = "down", action = function() hl.dispatch(hl.dsp.global("omarchy:menu.root")) end })

-- Four fingers take the active window along to the neighbouring workspace.
hl.gesture({ fingers = 4, direction = "left", action = function() hl.dispatch(hl.dsp.window.move({ workspace = "r-1" })) end })
hl.gesture({ fingers = 4, direction = "right", action = function() hl.dispatch(hl.dsp.window.move({ workspace = "r+1" })) end })
hl.gesture({ fingers = 4, direction = "down", action = "fullscreen" })
