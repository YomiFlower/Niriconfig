local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Variable = astal.Variable
local bind = astal.bind
local cjson = require("cjson")
local utf8 = require("lua-utf8")
local Debug = require("lua.lib.debug")
local GLib = require("lgi").GLib

local SANITIZE_PATTERN = "[%z\1-\31\127]"

local WindowCache = {
	data = {},
	timestamp = 0,
}

local function sanitize_utf8(text)
	if not text then
		return ""
	end
	return utf8.gsub(text, SANITIZE_PATTERN, "")
end

local function truncate_text(text, length)
	if not text then
		return ""
	end
	local sanitized = sanitize_utf8(text)
	return utf8.len(sanitized) > length and utf8.sub(sanitized, 1, length) .. "..." or sanitized
end

local DEBOUNCE_THRESHOLD = 100000
local POLL_INTERVAL = 450

local function get_active_window()
	local current_time = GLib.get_monotonic_time()

	if (current_time - WindowCache.timestamp) < DEBOUNCE_THRESHOLD then
		return WindowCache.data
	end

	local out, err = astal.exec("niri msg --json windows")
	if err then
		Debug.error("ActiveClient", "Failed to get window data: %s", err)
		return WindowCache.data
	end

	local success, windows = pcall(cjson.decode, out)
	if not success then
		Debug.error("ActiveClient", "Failed to decode window data")
		return WindowCache.data
	end

	for _, window in ipairs(windows) do
		if window.is_focused then
			WindowCache.data = window
			WindowCache.timestamp = current_time
			return window
		end
	end

	WindowCache.data = {}
	WindowCache.timestamp = current_time
	return WindowCache.data
end

local function create_window_variable()
	local var = Variable({})
	local source_id

	local function poll_callback()
		var:set(get_active_window())
		return GLib.SOURCE_CONTINUE
	end

	source_id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, POLL_INTERVAL, poll_callback)

	return var, source_id
end

return function()
	local window_var, timer_id = create_window_variable()

	local app_id_transform = function(window)
		return sanitize_utf8(window.app_id or "Desktop")
	end

	local title_transform = function(window)
		return truncate_text(window.title or "niri", 40)
	end

	local app_id_var = Variable.derive({ bind(window_var) }, app_id_transform)
	local title_var = Variable.derive({ bind(window_var) }, title_transform)

	return Widget.Box({
		class_name = "ActiveClient",
		setup = function(self)
			self:hook(self, "destroy", function()
				if timer_id then
					GLib.source_remove(timer_id)
					timer_id = nil
				end
				window_var:drop()
				app_id_var:drop()
				title_var:drop()
				WindowCache.data = {}
				WindowCache.timestamp = 0
			end)
		end,
		Widget.Box({
			orientation = "VERTICAL",
			Widget.Label({
				class_name = "app-id",
				label = bind(app_id_var),
				halign = "START",
			}),
			Widget.Label({
				class_name = "window-title",
				label = bind(title_var),
				halign = "START",
				ellipsize = "END",
			}),
		}),
	})
end
