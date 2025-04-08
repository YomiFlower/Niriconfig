local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local GLib = astal.require("GLib")
local Gtk = astal.require("Gtk")
local Wp = astal.require("AstalWp")
local Variable = astal.Variable
local Debug = require("lua.lib.debug")

local function create_volume_control(type, cleanup_refs, is_destroyed)
	local audio = Wp.get_default().audio
	if not audio then
		Debug.error("AudioControl", "Failed to get audio service")
		return Widget.Box({})
	end

	local device = audio["default_" .. type]
	if not device then
		Debug.error("AudioControl", "No default " .. type .. " device found")
		return Widget.Box({})
	end

	local device_volume = Variable(device.volume * 100)
	local device_mute = Variable(device.mute)
	cleanup_refs["device_volume_" .. type] = device_volume
	cleanup_refs["device_mute_" .. type] = device_mute

	local icon_name = Variable.derive({ device_volume, device_mute }, function(vol, muted)
		if muted then
			return type == "speaker" and "audio-volume-muted-symbolic" or "microphone-disabled-symbolic"
		else
			if type == "speaker" then
				if vol <= 0 then
					return "audio-volume-muted-symbolic"
				elseif vol <= 33 then
					return "audio-volume-low-symbolic"
				elseif vol <= 66 then
					return "audio-volume-medium-symbolic"
				else
					return "audio-volume-high-symbolic"
				end
			else
				if vol <= 0 then
					return "microphone-sensitivity-muted-symbolic"
				elseif vol <= 33 then
					return "microphone-sensitivity-low-symbolic"
				elseif vol <= 66 then
					return "microphone-sensitivity-medium-symbolic"
				else
					return "microphone-sensitivity-high-symbolic"
				end
			end
		end
	end)
	cleanup_refs["icon_name_" .. type] = icon_name

	local volume_scale = Widget.Slider({
		class_name = "volume-slider " .. type .. "-slider",
		draw_value = false,
		hexpand = true,
		width_request = 200,
		orientation = Gtk.Orientation.HORIZONTAL,
		value = device_volume:get(),
		adjustment = Gtk.Adjustment({
			lower = 0,
			upper = 100,
			step_increment = 1,
			page_increment = 10,
		}),
		on_value_changed = function(self)
			if not device then
				return
			end
			local new_value = self:get_value() / 100
			if new_value >= 0 and new_value <= 1 then
				_G.AUDIO_CONTROL_UPDATING = true
				device.volume = new_value
				device_volume:set(self:get_value())
				_G.AUDIO_CONTROL_UPDATING = false
			end
		end,
	})

	return Widget.Box({
		class_name = type .. "-control",
		orientation = "VERTICAL",
		spacing = 8,
		hexpand = true,
		setup = function(self)
			self:hook(device, "notify::volume", function()
				if not _G.AUDIO_CONTROL_UPDATING and not is_destroyed then
					local new_value = device.volume * 100
					device_volume:set(new_value)
					volume_scale:set_value(new_value)
				end
			end)

			self:hook(device, "notify::mute", function()
				if not is_destroyed then
					device_mute:set(device.mute)
				end
			end)
		end,
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 10,
			hexpand = true,
			Widget.Box({
				orientation = "HORIZONTAL",
				Widget.Icon({
					class_name = type .. "-icon",
					icon = icon_name(),
				}),
			}),
			Widget.Label({
				label = type == "speaker" and "Speaker" or "Microphone",
				xalign = 0,
				hexpand = true,
			}),
			Widget.Button({
				class_name = "mute-button",
				on_clicked = function()
					if device then
						device.mute = not device.mute
					end
				end,
				child = Widget.Icon({
					icon = bind(device_mute):as(function(muted)
						return muted
								and (type == "speaker" and "audio-volume-muted-symbolic" or "microphone-disabled-symbolic")
							or (
								type == "speaker" and "audio-volume-high-symbolic"
								or "microphone-sensitivity-high-symbolic"
							)
					end),
				}),
			}),
		}),
		Widget.Box({
			orientation = "HORIZONTAL",
			spacing = 10,
			hexpand = true,
			volume_scale,
			Widget.Label({
				class_name = "volume-percentage",
				label = bind(device_volume):as(function(vol)
					return string.format("%d%%", math.floor(vol or 0))
				end),
				width_chars = 4,
				xalign = 1,
			}),
		}),
	})
end

local function create_device_list(devices, icon_name)
	local buttons = {}
	for _, device in ipairs(devices or {}) do
		table.insert(
			buttons,
			Widget.Button({
				class_name = "device-item",
				hexpand = true,
				child = Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 10,
					hexpand = true,
					Widget.Icon({ icon = icon_name }),
					Widget.Label({
						label = device.description or "Unknown Device",
						hexpand = true,
						xalign = 0,
					}),
				}),
				on_clicked = function()
					device:set_is_default(true)
				end,
			})
		)
	end
	return buttons
end

local AudioControlWindow = {}

function AudioControlWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("AudioControl", "No monitor available")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local window
	local is_destroyed = false
	local cleanup_refs = {}

	local function close_window()
		if window and not is_destroyed then
			window:hide()
		end
	end

	cleanup_refs.show_output_devices = Variable(false)
	cleanup_refs.show_input_devices = Variable(false)

	local expanded_output_class = Variable.derive({ cleanup_refs.show_output_devices }, function(shown)
		return shown and "expanded" or ""
	end)
	cleanup_refs.expanded_output_class = expanded_output_class

	local expanded_input_class = Variable.derive({ cleanup_refs.show_input_devices }, function(shown)
		return shown and "expanded" or ""
	end)
	cleanup_refs.expanded_input_class = expanded_input_class

	local audio = Wp.get_default().audio
	if not audio then
		Debug.error("AudioControl", "Failed to get audio service for devices")
		return nil
	end

	window = Widget.Window({
		class_name = "AudioControlWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		width_request = 350,
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
			css = "padding: 15px;",
			hexpand = true,
			Widget.Box({
				class_name = "volume-controls-container",
				orientation = "VERTICAL",
				spacing = 10,
				hexpand = true,
				create_volume_control("speaker", cleanup_refs, is_destroyed),
				create_volume_control("microphone", cleanup_refs, is_destroyed),
			}),
			Widget.Box({
				class_name = "device-controls",
				orientation = "VERTICAL",
				spacing = 15,
				hexpand = true,
				Widget.Box({
					class_name = "section-header",
					orientation = "HORIZONTAL",
					hexpand = true,
					Widget.Label({
						label = "Devices",
						xalign = 0,
						hexpand = true,
					}),
				}),
				Widget.Box({
					class_name = "devices-container",
					orientation = "VERTICAL",
					spacing = 10,
					hexpand = true,
					Widget.Button({
						class_name = "device-selector",
						hexpand = true,
						on_clicked = function()
							if cleanup_refs.show_input_devices:get() then
								cleanup_refs.show_input_devices:set(false)
							end
							cleanup_refs.show_output_devices:set(not cleanup_refs.show_output_devices:get())
						end,
						child = Widget.Box({
							orientation = "HORIZONTAL",
							spacing = 10,
							hexpand = true,
							Widget.Icon({ icon = "audio-speakers-symbolic" }),
							Widget.Box({
								hexpand = true,
								Widget.Label({
									label = "Audio Output",
									xalign = 0,
									hexpand = true,
								}),
							}),
							Widget.Icon({
								icon = "pan-down-symbolic",
								class_name = expanded_output_class(),
							}),
						}),
					}),
					Widget.Revealer({
						transition_duration = 200,
						transition_type = "SLIDE_DOWN",
						reveal_child = bind(cleanup_refs.show_output_devices),
						hexpand = true,
						child = Widget.Box({
							orientation = "VERTICAL",
							spacing = 5,
							class_name = "device-list outputs-list",
							hexpand = true,
							bind(audio, "speakers"):as(function(speakers)
								return create_device_list(speakers, "audio-speakers-symbolic")
							end),
						}),
					}),
					Widget.Button({
						class_name = "device-selector",
						hexpand = true,
						on_clicked = function()
							if cleanup_refs.show_output_devices:get() then
								cleanup_refs.show_output_devices:set(false)
							end
							cleanup_refs.show_input_devices:set(not cleanup_refs.show_input_devices:get())
						end,
						child = Widget.Box({
							orientation = "HORIZONTAL",
							spacing = 10,
							hexpand = true,
							Widget.Icon({ icon = "audio-input-microphone-symbolic" }),
							Widget.Box({
								hexpand = true,
								Widget.Label({
									label = "Audio Input",
									xalign = 0,
									hexpand = true,
								}),
							}),
							Widget.Icon({
								icon = "pan-down-symbolic",
								class_name = expanded_input_class(),
							}),
						}),
					}),
					Widget.Revealer({
						transition_duration = 200,
						transition_type = "SLIDE_DOWN",
						reveal_child = bind(cleanup_refs.show_input_devices),
						hexpand = true,
						child = Widget.Box({
							orientation = "VERTICAL",
							spacing = 5,
							class_name = "device-list inputs-list",
							hexpand = true,
							bind(audio, "microphones"):as(function(microphones)
								return create_device_list(microphones, "audio-input-microphone-symbolic")
							end),
						}),
					}),
				}),
			}),
			Widget.Box({
				class_name = "settings",
				hexpand = true,
				Widget.Button({
					label = "Sound Settings",
					hexpand = true,
					on_clicked = function()
						close_window()
						GLib.spawn_command_line_async("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center sound")
					end,
				}),
			}),
		}),
	})

	return window
end

return AudioControlWindow
