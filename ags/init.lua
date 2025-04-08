local astal = require("astal")
local App = require("astal.gtk3.app")
local Debug = require("lua.lib.debug")

Debug.info("App", "Starting astal-bar")
Debug.info("App", "Modules loaded successfully")

local Desktop = require("lua.windows.Desktop")
local Bar = require("lua.windows.Bar")
local Dock = require("lua.windows.Dock")
local NotificationPopups = require("lua.windows.NotificationPopups")
local OSD = require("lua.windows.OSD")
local src = require("lua.lib.common").src

Debug.info("App", "Components loaded successfully")

Debug.set_config({
	log_to_file = true,
	log_to_console = false,
	max_file_size = 1024 * 1024,
	log_level = Debug.LEVELS.DEBUG,
})

local scss = src("scss/style.scss")
local css = "/tmp/style.css"

astal.exec("sass " .. scss .. " " .. css)

local user_vars = loadfile(src("user-variables.lua"))()
local monitor_config = user_vars.monitor or {
	mode = "primary",
	specific_monitor = 1,
}

App:start({
	instance_name = "kaneru",
	css = css,
	on_second_instance = function()
		Debug.warn("App", "Another instance attempted to start")
	end,
	request_handler = function(msg, res)
		Debug.debug("App", "Request received: %s", msg)
		res("ok")
	end,
	main = function()
		if #App.monitors == 0 then
			Debug.error("App", "No monitors detected")
			return
		end

		local function get_target_monitor()
			if monitor_config.mode == "specific" then
				local monitor = App.monitors[monitor_config.specific_monitor]
				if not monitor then
					Debug.warn("App", "Specified monitor not found, falling back to primary")
					return App.monitors[1]
				end
				return monitor
			else
				return App.monitors[1]
			end
		end

		local function create_windows(monitor)
			if not monitor then
				Debug.error("App", "Invalid monitor provided")
				return false
			end

			local windows = {
				-- desktop = Desktop(monitor),
				bar = Bar(monitor),
				-- dock = Dock(monitor),
				notifications = NotificationPopups(monitor),
				osd = OSD(monitor),
			}

			for name, window in pairs(windows) do
				if not window then
					Debug.error("App", "Failed to create " .. name)
					return false
				end
				window.gdkmonitor = monitor
			end

			return true
		end

		if monitor_config.mode == "all" then
			for _, monitor in ipairs(App.monitors) do
				if not create_windows(monitor) then
					Debug.error("App", "Failed to create windows for monitor")
					return
				end
			end
		else
			local target_monitor = get_target_monitor()
			if not create_windows(target_monitor) then
				Debug.error("App", "Failed to create windows for target monitor")
				return
			end
		end
	end,
})
