local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")
local Display = require("lua.lib.display")
local Theme = require("lua.lib.theme")

local function BrightnessControl()
	local display = Display.get_default()
	local brightness_var = Variable.derive({ display.brightness }, function(val)
		return string.format("%.0f%%", val * 100)
	end)

	return Widget.Box({
		class_name = "brightness-card",
		orientation = "VERTICAL",
		spacing = 12,
		hexpand = true,
		setup = function(self)
			self:hook(self, "destroy", function()
				brightness_var:drop()
			end)
		end,
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 10,
			hexpand = true,
			Widget.Icon({
				icon = "display-brightness-symbolic",
				class_name = "setting-icon",
			}),
			Widget.Label({
				label = "Brightness",
				xalign = 0,
				hexpand = true,
				class_name = "setting-title",
			}),
			Widget.Label({
				label = bind(display.brightness):as(function(val)
					return string.format("%.0f%%", val * 100)
				end),
				xalign = 1,
				class_name = "setting-value",
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 14,
			hexpand = true,
			Widget.Icon({
				icon = "display-brightness-low-symbolic",
				class_name = "slider-icon",
			}),
			Widget.Slider({
				class_name = "brightness-slider",
				hexpand = true,
				draw_value = false,
				value = display.brightness:get(),
				on_value_changed = function(self)
					local value = self:get_value()
					display:set_brightness(value)
				end,
			}),
			Widget.Icon({
				icon = "display-brightness-high-symbolic",
				class_name = "slider-icon",
			}),
		}),
	})
end

local function QuickToggles()
	local display = Display.get_default()
	local theme = Theme.get_default()
	local vars = {
		night_light_class = Variable.derive({ display.night_light_enabled }, function(enabled)
			return enabled and "quick-toggle night-light active" or "quick-toggle night-light"
		end),
		dark_mode_class = Variable.derive({ theme.is_dark }, function(enabled)
			return enabled and "quick-toggle dark-mode active" or "quick-toggle dark-mode"
		end),
		temp_label = Variable.derive({ display.night_light_temp }, function(val)
			local temp = 2500 + (val * 4000)
			return string.format("%.0fK", temp)
		end),
	}

	return Widget.Box({
		class_name = "quick-toggles-card",
		orientation = "VERTICAL",
		spacing = 12,
		hexpand = true,
		setup = function(self)
			self:hook(self, "destroy", function()
				for _, var in pairs(vars) do
					if var then
						var:drop()
					end
				end
			end)
		end,
		Widget.Box({
			class_name = "toggles-row",
			orientation = "HORIZONTAL",
			spacing = 10,
			hexpand = true,
			Widget.Button({
				class_name = bind(vars.night_light_class),
				hexpand = true,
				on_clicked = function()
					display:toggle_night_light()
				end,
				child = Widget.Box({
					orientation = "VERTICAL",
					spacing = 5,
					hexpand = true,
					Widget.Icon({
						icon = "night-light-symbolic",
						class_name = "toggle-icon",
					}),
					Widget.Label({
						label = "Night Light",
						xalign = 0.5,
						class_name = "toggle-label",
					}),
				}),
			}),
			Widget.Button({
				class_name = bind(vars.dark_mode_class),
				hexpand = true,
				on_clicked = function()
					theme:toggle_theme()
				end,
				child = Widget.Box({
					orientation = "VERTICAL",
					spacing = 5,
					hexpand = true,
					Widget.Icon({
						icon = "dark-mode-symbolic",
						class_name = "toggle-icon",
					}),
					Widget.Label({
						label = "Dark Mode",
						xalign = 0.5,
						class_name = "toggle-label",
					}),
				}),
			}),
		}),
		Widget.Revealer({
			transition_duration = 200,
			transition_type = "SLIDE_DOWN",
			reveal_child = bind(display.night_light_enabled),
			hexpand = true,
			child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 12,
				hexpand = true,
				class_name = "color-temperature-controls",
				Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 10,
					hexpand = true,
					Widget.Label({
						label = "Color Temperature",
						xalign = 0,
						hexpand = true,
						class_name = "subsetting-title",
					}),
					Widget.Label({
						label = bind(vars.temp_label),
						xalign = 1,
						class_name = "setting-value",
					}),
				}),
				Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 14,
					hexpand = true,
					Widget.Icon({
						icon = "temperature-cold",
						class_name = "slider-icon",
					}),
					Widget.Slider({
						class_name = "gamma-slider",
						hexpand = true,
						draw_value = false,
						value = display.night_light_temp:get(),
						on_value_changed = function(self)
							local value = self:get_value()
							display:set_night_light_temp(value)
						end,
					}),
					Widget.Icon({
						icon = "temperature-warm",
						class_name = "slider-icon",
					}),
				}),
				Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 5,
					hexpand = true,
					Widget.Label({
						label = "Cool",
						xalign = 0,
						class_name = "slider-label",
					}),
					Widget.Box({ hexpand = true }),
					Widget.Label({
						label = "Warm",
						xalign = 1,
						class_name = "slider-label",
					}),
				}),
			}),
		}),
	})
end

local function Settings(close_window)
	return Widget.Box({
		class_name = "settings",
		hexpand = true,
		Widget.Button({
			label = "Display Settings",
			hexpand = true,
			class_name = "settings-button",
			on_clicked = function()
				if close_window then
					close_window()
				end
				GLib.spawn_command_line_async("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center display")
			end,
		}),
	})
end

local DisplayControlWindow = {}

function DisplayControlWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("DisplayControl", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local display = Display.get_default()
	if not display or not display.initialized then
		Debug.error("DisplayControl", "Display system not properly initialized")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local window
	local is_closing = false

	local function close_window()
		if window and not is_closing then
			is_closing = true
			window:hide()
			is_closing = false
		end
	end

	local function SectionContainer(widget)
		return Widget.Box({
			class_name = "section-container",
			orientation = "VERTICAL",
			spacing = 12,
			hexpand = true,
			widget,
		})
	end

	window = Widget.Window({
		class_name = "DisplayControlWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		setup = function(self)
			self:hook(self, "destroy", function()
				if display then
					display:cleanup()
				end
				Display.cleanup_singleton()
			end)
		end,
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 16,
			css = "padding: 20px;",
			hexpand = true,
			SectionContainer(BrightnessControl()),
			SectionContainer(QuickToggles()),
			Widget.Box({ vexpand = true }),
			Settings(close_window),
		}),
	})

	return window
end

return DisplayControlWindow
