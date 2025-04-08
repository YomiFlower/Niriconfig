local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local map = require("lua.lib.common").map
local cjson = require("cjson")
local Debug = require("lua.lib.debug")
local Gio = require("lgi").Gio
local GLib = require("lgi").GLib

local monitor_order = { "eDP-1", "HDMI-A-1" }

local cache = {
	monitors = {
		timestamp = 0,
		data = {},
		max_age = 5,
	},
	workspaces = {
		hash = "",
		data = {},
		max_entries = 50,
	},
}

local rate_limiter = {
	last_monitor_fetch = 0,
	last_workspace_fetch = 0,
	monitor_interval = 5000,
	workspace_interval = 250,
}

local function get_niri_monitors()
	local current_time = GLib.get_monotonic_time() / 1000000

	if current_time - cache.monitors.timestamp < cache.monitors.max_age then
		return cache.monitors.data
	end

	if current_time - rate_limiter.last_monitor_fetch < (rate_limiter.monitor_interval / 1000) then
		return cache.monitors.data
	end

	rate_limiter.last_monitor_fetch = current_time

	local out, err = astal.exec("niri msg --json outputs")
	if err then
		Debug.error("Workspaces", "Failed to get niri monitors: %s", err)
		return {}
	end

	local success, monitors = pcall(cjson.decode, out)
	if not success then
		Debug.error("Workspaces", "Failed to decode niri monitor data")
		return {}
	end

	local monitor_array = {}
	for _, name in ipairs(monitor_order) do
		if monitors[name] then
			table.insert(monitor_array, {
				name = name,
				id = name:gsub("-", "_"),
				logical = monitors[name].logical,
			})
		end
	end

	cache.monitors.timestamp = current_time
	cache.monitors.data = monitor_array

	return monitor_array
end

local function process_workspace_data()
	local current_time = GLib.get_monotonic_time() / 1000000

	if current_time - rate_limiter.last_workspace_fetch < (rate_limiter.workspace_interval / 1000) then
		return cache.workspaces.data
	end

	rate_limiter.last_workspace_fetch = current_time

	local out, err = astal.exec("niri msg --json workspaces")
	if err then
		Debug.error("Workspaces", "Failed to get workspace data: %s", err)
		return cache.workspaces.data
	end

	local success, workspaces = pcall(cjson.decode, out)
	if not success then
		Debug.error("Workspaces", "Failed to decode workspace data")
		return cache.workspaces.data
	end

	local state_hash = table.concat(
		map(workspaces, function(w)
			return string.format("%s-%d-%s", w.output, w.idx, w.is_active and "1" or "0")
		end),
		"|"
	)

	if cache.workspaces.hash == state_hash then
		return cache.workspaces.data
	end

	local monitors = get_niri_monitors()
	local output_workspaces = {}

	for _, workspace in ipairs(workspaces) do
		output_workspaces[workspace.output] = output_workspaces[workspace.output] or {}
		table.insert(output_workspaces[workspace.output], {
			id = workspace.idx,
			is_active = workspace.is_active,
			workspace_id = workspace.id,
		})
	end

	local workspace_data = {}
	for _, monitor in ipairs(monitors) do
		local monitor_workspaces = output_workspaces[monitor.name] or {}
		table.sort(monitor_workspaces, function(a, b)
			return a.id < b.id
		end)
		table.insert(workspace_data, {
			monitor = monitor.id,
			name = monitor.name,
			workspaces = monitor_workspaces,
		})
	end

	cache.workspaces.hash = state_hash
	cache.workspaces.data = workspace_data

	return workspace_data
end

local function WorkspaceButton(props)
	return Widget.Button({
		class_name = "workspace-button" .. (props.is_active and " active" or ""),
		on_clicked = function()
			local _, err = astal.exec(
				string.format("niri msg action switch-to-workspace-index %d %s", props.id - 1, props.monitor_name)
			)
			if err then
				Debug.error("Workspaces", "Failed to switch workspace: %s", err)
			end
		end,
	})
end

local function MonitorWorkspaces(props)
	local monitor_number = props.name == "HDMI-A-1" and 2 or 1
	return Widget.Box({
		class_name = string.format("monitor-workspaces monitor-%d", monitor_number),
		orientation = "HORIZONTAL",
		spacing = 3,
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 3,
			table.unpack(map(props.workspaces, function(ws)
				return WorkspaceButton({
					id = ws.id,
					monitor = monitor_number,
					monitor_name = props.name,
					is_active = ws.is_active,
					workspace_id = ws.workspace_id,
				})
			end)),
		}),
	})
end

local function create_workspace_variables()
	local workspace_data = Variable(process_workspace_data())
	local monitors_var = Variable(get_niri_monitors())
	local is_destroyed = false

	local workspaces = Variable.derive({ workspace_data, monitors_var }, function(ws_data, monitors)
		if is_destroyed then
			return {}
		end
		return (ws_data and monitors) and ws_data or {}
	end)

	local workspace_source = Gio.Cancellable()
	workspace_data:poll(rate_limiter.workspace_interval, function()
		if is_destroyed or workspace_source:is_cancelled() then
			return nil
		end
		return process_workspace_data()
	end)

	local monitor_source = Gio.Cancellable()
	monitors_var:poll(rate_limiter.monitor_interval, function()
		if is_destroyed or monitor_source:is_cancelled() then
			return nil
		end
		return get_niri_monitors()
	end)

	return {
		workspace_data = workspace_data,
		monitors_var = monitors_var,
		workspaces = workspaces,
		workspace_source = workspace_source,
		monitor_source = monitor_source,
		cleanup = function()
			is_destroyed = true
			workspace_source:cancel()
			monitor_source:cancel()
			workspace_data:drop()
			monitors_var:drop()
			workspaces:drop()
			cache.monitors.data = {}
			cache.workspaces.data = {}
		end,
	}
end

return function()
	local vars = create_workspace_variables()

	return Widget.Box({
		class_name = "Workspaces",
		orientation = "HORIZONTAL",
		spacing = 2,
		bind(vars.workspaces):as(function(ws)
			return map(ws, function(monitor)
				return MonitorWorkspaces({
					monitor = monitor.monitor,
					name = monitor.name,
					workspaces = monitor.workspaces,
				})
			end)
		end),
		setup = function(self)
			self:hook(self, "destroy", function()
				if vars and vars.cleanup then
					vars.cleanup()
					vars = nil
				end
			end)
		end,
	})
end
