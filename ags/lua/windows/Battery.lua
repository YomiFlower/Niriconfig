local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local Battery = astal.require("AstalBattery")
local PowerProfiles = astal.require("AstalPowerProfiles")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")

local CONSERVATION_MODE_PATH = "/sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/VPC2004:00/conservation_mode"

local function getConservationMode()
	local content, err = astal.read_file(CONSERVATION_MODE_PATH)
	if err then
		Debug.error("Battery", "Failed to read conservation mode: %s", err)
		return false
	end
	return tonumber(content) == 1
end

local function getBatteryDevice()
	local upower = Battery.UPower.new()
	if not upower then
		Debug.error("Battery", "Failed to initialize UPower")
		return nil
	end

	local devices = upower:get_devices()
	if not devices then
		Debug.error("Battery", "Failed to get battery devices")
		return nil
	end

	for _, device in ipairs(devices) do
		if device:get_is_battery() and device:get_power_supply() then
			return device
		end
	end

	local display_device = upower:get_display_device()
	if not display_device then
		Debug.error("Battery", "No battery device found")
		return nil
	end
	return display_device
end

local function formatTime(seconds)
	if seconds <= 0 then
		return "Fully charged"
	end

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		return string.format("%d:%02d hours", hours, minutes)
	else
		return string.format("%d minutes", minutes)
	end
end

local function BatteryInfo(cleanup_refs)
	local bat = getBatteryDevice()
	if not bat then
		Debug.error("Battery", "Cannot create BatteryInfo: no battery device")
		return Widget.Box({})
	end

	cleanup_refs.battery_state = Variable.derive({ bind(bat, "state") }, function(state)
		if not state then
			return "Unknown"
		end
		return state:gsub("^%l", string.upper):gsub("-", " ")
	end)

	cleanup_refs.battery_capacity = Variable.derive({ bind(bat, "capacity") }, function(capacity)
		if not capacity then
			return "N/A"
		end
		return string.format("%.1f%%", capacity * 100)
	end)

	return Widget.Box({
		class_name = "battery-details",
		orientation = "VERTICAL",
		spacing = 5,
		hexpand = true,
		Widget.Box({
			orientation = "HORIZONTAL",
			hexpand = true,
			Widget.Label({ label = "Status:" }),
			Widget.Label({
				label = bind(cleanup_refs.battery_state),
				xalign = 1,
				hexpand = true,
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			hexpand = true,
			Widget.Label({ label = "Health:" }),
			Widget.Label({
				label = bind(cleanup_refs.battery_capacity),
				xalign = 1,
				hexpand = true,
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			hexpand = true,
			Widget.Label({ label = "Charge cycles:" }),
			Widget.Label({
				label = bind(bat, "charge-cycles"):as(function(cycles)
					return tostring(cycles or "N/A")
				end),
				xalign = 1,
				hexpand = true,
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			hexpand = true,
			Widget.Label({ label = "Power draw:" }),
			Widget.Label({
				label = bind(bat, "energy-rate"):as(function(rate)
					if not rate then
						Debug.error("Battery", "Failed to get power draw rate")
						return "N/A"
					end
					return string.format("%.1f W", rate)
				end),
				xalign = 1,
				hexpand = true,
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			hexpand = true,
			Widget.Label({ label = "Voltage:" }),
			Widget.Label({
				label = bind(bat, "voltage"):as(function(voltage)
					if not voltage then
						Debug.error("Battery", "Failed to get battery voltage")
						return "N/A"
					end
					return string.format("%.1f V", voltage)
				end),
				xalign = 1,
				hexpand = true,
			}),
		}),
	})
end

local function PowerProfile(on_destroy_ref)
	local power = PowerProfiles.get_default()
	if not power then
		Debug.error("Battery", "Failed to initialize PowerProfiles")
		return Widget.Box({})
	end

	local function updateButtons(box, active_profile)
		if not box or not active_profile then
			Debug.error("Battery", "Invalid arguments for updateButtons")
			return
		end
		for _, child in ipairs(box:get_children()) do
			local button_profile = child:get_label():lower():gsub(" ", "-")
			if button_profile == active_profile then
				child:get_style_context():add_class("active")
			else
				child:get_style_context():remove_class("active")
			end
		end
	end

	local buttons_box = Widget.Box({
		class_name = "power-mode-buttons",
		orientation = "HORIZONTAL",
		spacing = 10,
		hexpand = true,
		Widget.Button({
			class_name = "power-mode-button",
			label = "Power Saver",
			hexpand = true,
			on_clicked = function()
				if not power then
					return
				end
				power.active_profile = "power-saver"
			end,
		}),
		Widget.Button({
			class_name = "power-mode-button",
			label = "Balanced",
			hexpand = true,
			on_clicked = function()
				if not power then
					return
				end
				power.active_profile = "balanced"
			end,
		}),
		Widget.Button({
			class_name = "power-mode-button",
			label = "Performance",
			hexpand = true,
			on_clicked = function()
				if not power then
					return
				end
				power.active_profile = "performance"
			end,
		}),
		setup = function(self)
			if power and power.active_profile then
				updateButtons(self, power.active_profile)
			end
		end,
	})

	local profile_var = Variable.derive({ bind(power, "active-profile") }, function(profile)
		updateButtons(buttons_box, profile)
		return profile
	end)

	on_destroy_ref.profile_var = profile_var

	local bat = getBatteryDevice()
	local auto_profile = Variable.derive({ bind(bat, "state") }, function(state)
		if not state or not power or not power.active_profile then
			return nil
		end

		if state == "CHARGING" and power.active_profile ~= "performance" then
			power.active_profile = "performance"
		elseif state == "DISCHARGING" and power.active_profile ~= "balanced" then
			power.active_profile = "balanced"
		end
		return power.active_profile
	end)

	on_destroy_ref.auto_profile = auto_profile

	return Widget.Box({
		class_name = "power-profiles-section",
		orientation = "VERTICAL",
		spacing = 10,
		hexpand = true,
		Widget.Label({
			label = "Power Mode",
			xalign = 0,
			css = "font-weight: 600; font-size: 16px;",
		}),
		buttons_box,
	})
end

local function ConservationMode()
	local conservation_var = Variable(getConservationMode())

	local function updateButtonState(button)
		local is_active = getConservationMode()
		conservation_var:set(is_active)

		if is_active then
			button:get_style_context():add_class("active")
		else
			button:get_style_context():remove_class("active")
		end
	end

	local button = Widget.Button({
		class_name = "conservation-mode-button",
		hexpand = true,
		on_clicked = function(self)
			local new_state = not conservation_var:get()
			local value = new_state and "1" or "0"

			astal.write_file_async(CONSERVATION_MODE_PATH, value, function(err)
				if err then
					Debug.error("Battery", "Failed to set conservation mode: %s", err)
					updateButtonState(self)
				else
					if new_state then
						self:get_style_context():add_class("active")
					else
						self:get_style_context():remove_class("active")
					end
				end
			end)
		end,
		child = Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 10,
			hexpand = true,
			Widget.Icon({
				icon = "battery-good-symbolic",
			}),
			Widget.Box({
				orientation = "VERTICAL",
				spacing = 2,
				hexpand = true,
				Widget.Label({
					label = "Battery Conservation Mode",
					xalign = 0,
				}),
				Widget.Label({
					label = "Limit battery charge to 80% to extend battery lifespan",
					xalign = 0,
					css = "font-size: 12px; opacity: 0.7;",
				}),
			}),
			Widget.Icon({
				icon = Variable.derive({ conservation_var }, function(enabled)
					return enabled and "emblem-ok-symbolic" or "emblem-important-symbolic"
				end)(),
			}),
		}),
		setup = function(self)
			updateButtonState(self)
		end,
	})

	astal.monitor_file(CONSERVATION_MODE_PATH, function(_, event)
		if event == "CHANGED" then
			updateButtonState(button)
		end
	end)

	return Widget.Box({
		class_name = "conservation-mode-section",
		orientation = "VERTICAL",
		spacing = 10,
		hexpand = true,
		Widget.Label({
			label = "Battery Settings",
			xalign = 0,
			css = "font-weight: 600; font-size: 16px;",
		}),
		button,
	})
end

local function Settings(close_window)
	return Widget.Box({
		class_name = "settings-section",
		hexpand = true,
		Widget.Button({
			class_name = "settings-button",
			label = "Power & battery settings",
			hexpand = true,
			on_clicked = function()
				if close_window then
					close_window()
				end
				GLib.spawn_command_line_async("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center power")
			end,
		}),
	})
end

local BatteryWindow = {}

function BatteryWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Battery", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local window
	local cleanup_refs = {}
	local is_destroyed = false
	local is_closing = false

	local function close_window()
		if window and not is_closing and not is_destroyed then
			is_closing = true
			window:hide()
			is_closing = false
		end
	end

	local bat = getBatteryDevice()
	if not bat then
		Debug.error("Battery", "Cannot initialize: no battery device")
		return nil
	end

	cleanup_refs.time_info = Variable.derive({ bind(bat, "state") }, function(state)
		if not state then
			return "Unknown"
		end

		if state == "PENDING_CHARGE" and getConservationMode() then
			return "Conservation mode enabled, waiting to charge"
		end

		if state == "CHARGING" or state == "DISCHARGING" then
			local time = state == "CHARGING" and bat:get_time_to_full() or bat:get_time_to_empty()
			if not time then
				return "Calculating..."
			end
			if time > 0 then
				return formatTime(time)
			end
			return "Calculating..."
		end
		return tostring(state)
	end)

	local power = PowerProfiles.get_default()
	cleanup_refs.profile_var = Variable.derive({ bind(power, "active-profile") }, function(profile)
		return profile
	end)

	cleanup_refs.auto_profile = Variable.derive({ bind(bat, "state") }, function(state)
		if not bat or not power then
			return
		end
		if state == "CHARGING" then
			power.active_profile = "performance"
		elseif state == "DISCHARGING" then
			power.active_profile = "balanced"
		end
		return state
	end)

	cleanup_refs.conservation_var = Variable(getConservationMode())

	window = Widget.Window({
		class_name = "BatteryWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		setup = function(self)
			self:hook(self, "destroy", function()
				if is_destroyed then
					return
				end
				is_destroyed = true

				for _, ref in pairs(cleanup_refs) do
					if type(ref) == "table" and ref.drop then
						ref:drop()
					end
				end

				cleanup_refs = nil
				collectgarbage("collect")
			end)
		end,
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 15,
			css = "padding: 18px;",
			hexpand = true,
			Widget.Box({
				class_name = "battery-main-info",
				hexpand = true,
				Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 10,
					hexpand = true,
					Widget.Icon({
						icon = bind(bat, "battery-icon-name"),
						css = "font-size: 48px;",
					}),
					Widget.Box({
						orientation = "VERTICAL",
						hexpand = true,
						Widget.Label({
							label = bind(bat, "percentage"):as(function(p)
								if not p then
									return "Battery N/A"
								end
								return string.format("Battery %.0f%%", p * 100)
							end),
							xalign = 0,
							css = "font-size: 18px; font-weight: bold;",
						}),
						Widget.Label({
							label = bind(cleanup_refs.time_info),
							xalign = 0,
							css = "font-size: 14px;",
						}),
					}),
				}),
			}),
			Widget.Box({
				class_name = "battery-info-container",
				orientation = "VERTICAL",
				spacing = 10,
				hexpand = true,
				BatteryInfo(cleanup_refs),
			}),
			PowerProfile(cleanup_refs),
			ConservationMode(),
			Settings(close_window),
		}),
	})

	if cleanup_refs.conservation_var then
		astal.monitor_file(CONSERVATION_MODE_PATH, function(_, event)
			if event == "CHANGED" and not is_destroyed then
				cleanup_refs.conservation_var:set(getConservationMode())
			end
		end)
	end

	return window
end

return BatteryWindow
