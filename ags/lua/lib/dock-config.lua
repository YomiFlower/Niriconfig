local astal = require("astal")
local Apps = astal.require("AstalApps")
local cjson = require("cjson")
local Debug = require("lua.lib.debug")

local M = {}
local apps = Apps.Apps.new()
if not apps then
	Debug.error("DockConfig", "Failed to initialize Apps service")
end

M.pinned_apps = {}
M.running_apps = {}

local config_path = debug.getinfo(1).source:match("@?(.*/)") .. "../../user-variables.lua"
local success, user_vars = pcall(loadfile, config_path)
if not success or not user_vars then
	Debug.error("DockConfig", "Failed to load config file: %s", config_path)
	return M
end

user_vars = user_vars()
if not user_vars then
	Debug.error("DockConfig", "Failed to execute config file")
	return M
end

astal.monitor_file(config_path, function(_, _)
	local new_config = loadfile(config_path)()
	if new_config and new_config.dock and new_config.dock.pinned_apps then
		M.initialize_pinned_apps(new_config.dock.pinned_apps)
	end
end)

local function find_desktop_entry(name)
	local app_list = apps:get_list()
	if not app_list then
		Debug.error("DockConfig", "Failed to get application list")
		return nil
	end

	for _, app in ipairs(app_list) do
		if
			app
			and app.entry
			and (app.name and app.name:lower():match(name:lower()) or app.entry:lower():match(name:lower()))
		then
			return app.entry
		end
	end
	return nil
end

local function get_running_windows()
	local out, err = astal.exec("niri msg --json windows")
	if err then
		Debug.error("DockConfig", "Failed to get window list: %s", err)
		return {}
	end

	local success, windows = pcall(function()
		return cjson.decode(out)
	end)

	if not success then
		Debug.error("DockConfig", "Failed to parse window list")
		return {}
	end

	return windows or {}
end

function M.update_running_apps()
	local windows = get_running_windows()
	local running = {}
	local app_list = apps:get_list()
	if not app_list then
		Debug.error("DockConfig", "Failed to get application list for running apps")
		return
	end

	for _, window in ipairs(windows) do
		if window.app_id then
			for _, app in ipairs(app_list) do
				if
					app
					and app.entry
					and (
						app.entry:lower():match(window.app_id:lower())
						or (app.wm_class and app.wm_class:lower():match(window.app_id:lower()))
					)
				then
					running[app.entry] = true
					break
				end
			end
		end
	end

	M.running_apps = running
end

function M.initialize_pinned_apps(pinned_apps)
	M.pinned_apps = {}
	local apps_to_check = pinned_apps or user_vars.dock.pinned_apps
	if not apps_to_check then
		Debug.error("DockConfig", "No pinned apps configuration found")
		return
	end

	for _, name in ipairs(apps_to_check) do
		local desktop_entry = find_desktop_entry(name)
		if desktop_entry then
			table.insert(M.pinned_apps, desktop_entry)
		end
	end
end

function M.is_running(desktop_entry)
	return M.running_apps[desktop_entry] or false
end

function M.is_pinned(desktop_entry)
	for _, entry in ipairs(M.pinned_apps) do
		if entry == desktop_entry then
			return true
		end
	end
	return false
end

M.initialize_pinned_apps()

astal.interval(2000, function()
	M.update_running_apps()
end)

return M
