-- Dock actions run against current compositor state, not a cached UI model.
-- Keeping a move and its focus together also avoids clicks racing subprocesses.
o.dock = {}
local generation = 0

function o.dock.activate(address, workspace, action)
  local window = hl.get_window("address:" .. address)
  if not window or not window.mapped or workspace < 1 then return end
  generation = generation + 1
  local request = generation
  local current = window.workspace
  local minimized = current and current.name == "special:minimized"
  local target = "address:" .. address

  local function raise()
    if request ~= generation then return end
    local live = hl.get_window(target)
    if not live or not live.mapped or live.hidden then return end
    hl.dispatch(hl.dsp.focus({ window = target }))
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = target }))
  end

  if minimized or action == "move" then
    hl.dispatch(hl.dsp.window.move({ window = target, workspace = tostring(workspace), follow = false }))
    -- The workspace mode applies floating geometry on the next event-loop tick.
    hl.timer(raise, { type = "oneshot", timeout = 20 })
  elseif current and current.id ~= workspace then
    hl.dispatch(hl.dsp.focus({ workspace = tostring(current.id) }))
    raise()
  elseif action == "toggle" and window.active then
    -- The shared hidden workspace may still belong to another output. Its
    -- monitor determines the animation destination, so align it first.
    local monitor = current and current.monitor
    if monitor then
      for _, hidden in ipairs(hl.get_workspaces()) do
        if hidden.name == "special:minimized" and hidden.monitor
            and hidden.monitor.name ~= monitor.name then
          hl.dispatch(hl.dsp.workspace.move({ workspace = "special:minimized", monitor = monitor.name }))
          break
        end
      end
    end
    for _, tag in ipairs(window.tags or {}) do
      if tag:match("^omarchy%-minimized%-from%-") then
        hl.dispatch(hl.dsp.window.tag({ window = target, tag = "-" .. tag:gsub("%*$", "") }))
      end
    end
    hl.dispatch(hl.dsp.window.tag({ window = target, tag = "+omarchy-minimized-from-" .. workspace }))
    hl.dispatch(hl.dsp.window.move({ window = target, workspace = "special:minimized", follow = false }))
    hl.dispatch(hl.dsp.focus({ workspace = tostring(workspace) }))
  else
    raise()
  end
end
