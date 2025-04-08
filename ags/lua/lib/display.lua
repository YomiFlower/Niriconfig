local astal = require("astal")
local Variable = astal.Variable
local exec = astal.exec
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")
local UserVariables = require("user-variables")

local Display = {}

function Display:init_night_light_state()
	local function check_gammastep_status()
		local success, ps_out = pcall(exec, "pgrep gammastep")
		if success and ps_out and ps_out ~= "" then
			self.night_light_enabled:set(true)
		else
			self.night_light_enabled:set(false)
		end
	end

	pcall(check_gammastep_status)
end

function Display:New()
	local initial_temp = (UserVariables.display and UserVariables.display.night_light_temp_initial) or 3500
	local normalized_temp = (initial_temp - 2500) / 4000

	local instance = {
		brightness = Variable.new(tonumber(exec("brightnessctl get")) / 255 or 0.75),
		night_light_enabled = Variable.new(false),
		night_light_temp = Variable.new(normalized_temp),
		update_timeout = nil,
		initialized = false,
	}
	setmetatable(instance, self)
	self.__index = self

	instance:init_night_light_state()
	instance.initialized = true

	return instance
end

function Display:set_brightness(value)
	if value < 0 or value > 1 then
		Debug.error("Display", "Invalid brightness value: %f", value)
		return false
	end

	local percentage = math.floor(value * 100)
	local _, err = exec(string.format("brightnessctl set %d%%", percentage))
	if err then
		Debug.error("Display", "Failed to set brightness: %s", err)
		return false
	end

	self.brightness:set(value)
	return true
end

function Display:apply_night_light()
	if not self.initialized then
		return
	end
	local temp = math.floor(2500 + (self.night_light_temp:get() * 4000))
	pcall(function()
		GLib.spawn_command_line_async(string.format("gammastep -O %d", temp))
	end)
end

function Display:toggle_night_light()
	if not self.initialized then
		Debug.error("Display", "Display not properly initialized")
		return
	end

	local new_state = not self.night_light_enabled:get()

	pcall(function()
		GLib.spawn_command_line_async("pkill gammastep")
	end)

	GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, function()
		if not self.initialized then
			return GLib.SOURCE_REMOVE
		end

		if new_state then
			self:apply_night_light()
		else
			pcall(function()
				GLib.spawn_command_line_async("gammastep -x")
			end)
		end

		if self.night_light_enabled then
			self.night_light_enabled:set(new_state)
		end

		return GLib.SOURCE_REMOVE
	end)
end

function Display:set_night_light_temp(value)
	if value < 0 or value > 1 then
		Debug.error("Display", "Invalid temperature value: %f", value)
		return false
	end

	self.night_light_temp:set(value)

	if self.night_light_enabled:get() then
		if self.update_timeout then
			GLib.source_remove(self.update_timeout)
			self.update_timeout = nil
		end

		self.update_timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, function()
			pcall(function()
				GLib.spawn_command_line_async("pkill gammastep")
			end)
			GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, function()
				self:apply_night_light()
				return GLib.SOURCE_REMOVE
			end)
			self.update_timeout = nil
			return GLib.SOURCE_REMOVE
		end)
	end

	return true
end

function Display:cleanup()
	if self.update_timeout then
		GLib.source_remove(self.update_timeout)
		self.update_timeout = nil
	end

	if self.night_light_enabled and self.night_light_enabled:get() then
		pcall(function()
			GLib.spawn_command_line_async("pkill gammastep")
			GLib.spawn_command_line_async("gammastep -x")
		end)
	end

	if self.brightness then
		self.brightness:drop()
		self.brightness = nil
	end
	if self.night_light_enabled then
		self.night_light_enabled:drop()
		self.night_light_enabled = nil
	end
	if self.night_light_temp then
		self.night_light_temp:drop()
		self.night_light_temp = nil
	end

	self.initialized = false
end

local instance = nil
function Display.get_default()
	if not instance then
		instance = Display:New()
	end
	return instance
end

function Display.cleanup_singleton()
	if instance then
		instance:cleanup()
		instance = nil
	end
end

return Display
