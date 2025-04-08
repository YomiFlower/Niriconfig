local astal = require("astal")
local Variable = require("astal.variable")
local exec = astal.exec
local Debug = require("lua.lib.debug")
local GLib = astal.require("GLib")

local Theme = {}

function Theme:New()
	local instance = {
		is_dark = Variable.new(false),
	}
	setmetatable(instance, self)
	self.__index = self

	instance:update_theme_state()

	instance.is_dark:watch({ "bash", "-c", "dconf watch /org/gnome/desktop/interface/color-scheme" }, function(out)
		GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, function()
			instance:update_theme_state()
			return GLib.SOURCE_REMOVE
		end)
		return out:match("prefer%-dark") ~= nil
	end)

	return instance
end

function Theme:update_theme_state()
	local current_theme = self:get_current_theme_mode()
	self.is_dark:set(current_theme == "dark")
end

function Theme:get_current_theme_mode()
	local out, err = exec("dconf read /org/gnome/desktop/interface/color-scheme")
	if err then
		Debug.error("Theme", "Failed to read dconf theme setting: %s", err)
		return "light"
	end
	return out:match("prefer%-dark") and "dark" or "light"
end

function Theme:toggle_theme()
	local current_state = self.is_dark:get()
	local new_state = not current_state
	local scheme = new_state and "prefer-dark" or "prefer-light"

	pcall(function()
		exec("niri msg action do-screen-transition")
	end)

	local _, err = exec(string.format("dconf write /org/gnome/desktop/interface/color-scheme \"'%s'\"", scheme))
	if err then
		Debug.error("Theme", "Failed to set theme: %s", err)
		return
	end

	GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, function()
		self:update_theme_state()
		return GLib.SOURCE_REMOVE
	end)
end

function Theme:cleanup()
	if self.is_dark then
		self.is_dark:drop()
	end
end

local instance = nil
function Theme.get_default()
	if not instance then
		instance = Theme:New()
	end
	return instance
end

function Theme.cleanup_singleton()
	if instance then
		instance:cleanup()
		instance = nil
	end
end

return Theme
