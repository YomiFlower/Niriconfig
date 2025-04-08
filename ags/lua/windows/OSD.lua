local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Wp = astal.require("AstalWp")
local bind = astal.bind
local Debug = require("lua.lib.debug")
local GLib = astal.require("GLib")
local Variable = require("astal.variable")

local SHOW_TIMEOUT = 1500

local function create_volume_indicator(device, class_name)
	return Widget.Box({
		class_name = class_name,
		visible = false,
		Widget.Box({
			class_name = "indicator",
			Widget.Icon({
				icon = bind(device, "volume-icon"),
			}),
			Widget.Label({
				label = bind(device, "volume"):as(function(vol)
					return string.format("%d%%", math.floor((vol or 0) * 100))
				end),
			}),
		}),
		Widget.Box({
			class_name = "slider-container",
			Widget.Slider({
				class_name = "volume-slider",
				hexpand = true,
				width_request = 150,
				value = bind(device, "volume"),
				on_dragged = function(slider)
					device.volume = slider.value
				end,
			}),
		}),
	})
end

local function create_mute_indicator(device, class_name)
	return Widget.Box({
		class_name = class_name .. "-mute",
		visible = false,
		Widget.Icon({
			icon = bind(device, "volume-icon"),
		}),
		Widget.Label({
			label = "Muted",
		}),
	})
end

local function create_osd_widget(cleanup_refs, window_ref)
	local speaker = Wp.get_default().audio.default_speaker
	local mic = Wp.get_default().audio.default_microphone

	if not speaker or not mic then
		Debug.error(
			"OSD",
			"Failed to get audio devices - Speaker: %s, Mic: %s",
			speaker and "OK" or "NULL",
			mic and "OK" or "NULL"
		)
	end

	return Widget.Box({
		class_name = "OSD",
		vertical = true,
		css = "min-width: 300px; min-height: 50px;",
		setup = function(self)
			local is_destroyed = false
			local speaker_vol = create_volume_indicator(speaker, "volume-indicator")
			local speaker_mute = create_mute_indicator(speaker, "volume-indicator")
			local mic_vol = create_volume_indicator(mic, "mic-indicator")
			local mic_mute = create_mute_indicator(mic, "mic-indicator")

			self:add(speaker_vol)
			self:add(speaker_mute)
			self:add(mic_vol)
			self:add(mic_mute)

			local current_visible_widget = nil

			local function hide_all()
				if is_destroyed then
					return
				end
				speaker_vol.visible = false
				mic_vol.visible = false
				speaker_mute.visible = false
				mic_mute.visible = false
				window_ref.visible = false
				current_visible_widget = nil
			end

			hide_all()

			local function update_visible_widget(widget)
				if is_destroyed or current_visible_widget == widget then
					return
				end

				speaker_vol.visible = false
				mic_vol.visible = false
				speaker_mute.visible = false
				mic_mute.visible = false

				widget.visible = true
				current_visible_widget = widget
			end

			local function show_osd(widget)
				if is_destroyed or _G.AUDIO_CONTROL_UPDATING then
					return
				end

				if not window_ref.visible then
					window_ref.visible = true
					update_visible_widget(widget)
				else
					update_visible_widget(widget)
				end

				if cleanup_refs.timer_id then
					GLib.source_remove(cleanup_refs.timer_id)
					cleanup_refs.timer_id = nil
				end

				cleanup_refs.timer_id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SHOW_TIMEOUT, function()
					if not is_destroyed then
						hide_all()
					end
					cleanup_refs.timer_id = nil
					return GLib.SOURCE_REMOVE
				end)
			end

			cleanup_refs.speaker_volume = Variable.derive({ bind(speaker, "volume") }, function(vol)
				return vol
			end)

			cleanup_refs.speaker_mute = Variable.derive({ bind(speaker, "mute") }, function(muted)
				return muted
			end)

			cleanup_refs.mic_volume = Variable.derive({ bind(mic, "volume") }, function(vol)
				return vol
			end)

			cleanup_refs.mic_mute = Variable.derive({ bind(mic, "mute") }, function(muted)
				return muted
			end)

			cleanup_refs.speaker_volume:subscribe(function()
				show_osd(speaker_vol)
			end)

			cleanup_refs.speaker_mute:subscribe(function(muted)
				show_osd(muted and speaker_mute or speaker_vol)
			end)

			cleanup_refs.mic_volume:subscribe(function()
				show_osd(mic_vol)
			end)

			cleanup_refs.mic_mute:subscribe(function(muted)
				show_osd(muted and mic_mute or mic_vol)
			end)

			self:hook(self, "destroy", function()
				is_destroyed = true

				if cleanup_refs.speaker_volume then
					cleanup_refs.speaker_volume:drop()
				end
				if cleanup_refs.speaker_mute then
					cleanup_refs.speaker_mute:drop()
				end
				if cleanup_refs.mic_volume then
					cleanup_refs.mic_volume:drop()
				end
				if cleanup_refs.mic_mute then
					cleanup_refs.mic_mute:drop()
				end
			end)
		end,
	})
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("OSD", "Failed to initialize OSD: gdkmonitor is nil")
		return nil
	end

	local cleanup_refs = {}
	local is_destroyed = false
	local Anchor = astal.require("Astal").WindowAnchor

	local window = Widget.Window({
		class_name = "OSDWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM,
		visible = false,
		setup = function(self)
			self:add(create_osd_widget(cleanup_refs, self))
		end,
		on_destroy = function()
			if is_destroyed then
				return
			end
			is_destroyed = true

			if cleanup_refs.timer_id then
				GLib.source_remove(cleanup_refs.timer_id)
			end

			for key, ref in pairs(cleanup_refs) do
				if type(ref) == "table" and ref.drop then
					ref:drop()
				elseif type(ref) == "number" then
					GLib.source_remove(ref)
				end
				cleanup_refs[key] = nil
			end

			cleanup_refs = nil
			collectgarbage("collect")
		end,
	})

	return window
end
