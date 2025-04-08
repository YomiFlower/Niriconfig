local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Variable = astal.Variable
local bind = astal.bind
local GLib = astal.require("GLib")
local Mpris = astal.require("AstalMpris")
local Tray = astal.require("AstalTray")
local Network = astal.require("AstalNetwork")
local Battery = astal.require("AstalBattery")
local Wp = astal.require("AstalWp")
local Debug = require("lua.lib.debug")

local Workspaces = require("lua.widgets.Workspaces")
local ActiveClient = require("lua.widgets.ActiveClient")
local Vitals = require("lua.widgets.Vitals")

local map = require("lua.lib.common").map

local github_window = nil
local audio_window = nil
local network_window = nil
local battery_window = nil
local display_control_window = nil
local sysinfo_window = nil
local media_window = nil

local function SysTray()
	local tray = Tray.get_default()
	return Widget.Box({
		class_name = "systray-",
		bind(tray, "items"):as(function(items)
			return map(items or {}, function(item)
				return Widget.MenuButton({
					tooltip_markup = bind(item, "tooltip_markup"),
					use_popover = false,
					menu_model = bind(item, "menu-model"),
					action_group = bind(item, "action-group"):as(function(ag)
						return { "dbusmenu", ag }
					end),
					Widget.Icon({
						gicon = bind(item, "gicon"),
					}),
				})
			end)
		end),
	})
end

local function Media(monitor)
	local MEDIA_HIDE_DELAY = 30
	local window_visible = Variable(false)
	local hover_state = Variable(false)
	local is_destroyed = false
	local hide_timer = nil
	local update_timer = nil
	local player_info = Variable({
		title = nil,
		cover = nil,
		playing = false,
		active = false,
	})

	local user_vars = require("user-variables")
	local preferred_players = user_vars.media and user_vars.media.preferred_players or {}
	local mpris = Mpris.get_default()

	local function safe_destroy_window()
		if media_window then
			local win = media_window
			media_window = nil
			win:destroy()
		end
	end

	local function get_active_player()
		if not mpris or is_destroyed then
			return nil
		end
		local players = mpris.players
		if not players then
			return nil
		end

		for _, preferred in ipairs(preferred_players) do
			for _, player in ipairs(players) do
				if player.bus_name:match(preferred) and player.available then
					return player
				end
			end
		end
		return nil
	end

	local function hide_media()
		player_info:set({
			title = nil,
			cover = nil,
			playing = false,
			active = false,
		})
		safe_destroy_window()
	end

	local function start_hide_timer()
		if hide_timer then
			GLib.source_remove(hide_timer)
			hide_timer = nil
		end

		hide_timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, MEDIA_HIDE_DELAY, function()
			if not is_destroyed then
				hide_media()
			end
			hide_timer = nil
			return false
		end)
	end

	local function update_player_info()
		if is_destroyed then
			return
		end

		local player = get_active_player()
		if not player or not player.available then
			hide_media()
			return
		end

		local is_playing = false
		pcall(function()
			is_playing = (player.playback_status == "PLAYING")
		end)

		if not is_playing then
			if not hide_timer then
				start_hide_timer()
			end
			return
		end

		local title = nil
		pcall(function()
			title = player.title
		end)

		local cover = nil
		pcall(function()
			cover = player.cover_art or player.art_url
		end)

		if hide_timer then
			GLib.source_remove(hide_timer)
			hide_timer = nil
		end

		player_info:set({
			title = title,
			cover = cover,
			playing = true,
			active = true,
		})
	end

	update_timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, function()
		if is_destroyed then
			return false
		end
		update_player_info()
		return true
	end)

	local function toggle_media_window()
		if is_destroyed then
			return
		end

		if window_visible:get() and media_window then
			media_window:hide()
			window_visible:set(false)
		else
			if not media_window then
				local MediaControlWindow = require("lua.windows.MediaControl")
				media_window = MediaControlWindow.new(monitor)
			end
			if media_window then
				media_window:show_all()
				window_visible:set(true)
			end
		end
	end

	return Widget.Box({
		class_name = "media-container",
		visible = bind(player_info):as(function(info)
			return info and info.active and info.playing
		end),
		setup = function(self)
			hide_media() -- Start hidden
			self:hook(self, "destroy", function()
				is_destroyed = true
				if hide_timer then
					GLib.source_remove(hide_timer)
					hide_timer = nil
				end
				if update_timer then
					GLib.source_remove(update_timer)
					update_timer = nil
				end
				safe_destroy_window()
				player_info:drop()
				window_visible:drop()
				hover_state:drop()
			end)
		end,
		Widget.EventBox({
			class_name = "media-clickable",
			hexpand = true,
			vexpand = true,
			above_child = true,
			on_button_press_event = toggle_media_window,
			on_enter_notify_event = function()
				if not is_destroyed then
					hover_state:set(true)
				end
				return true
			end,
			on_leave_notify_event = function()
				if not is_destroyed then
					hover_state:set(false)
				end
				return true
			end,
			child = Widget.Box({
				orientation = "HORIZONTAL",
				spacing = 5,
				Widget.Box({
					class_name = "Cover",
					width_request = 24,
					height_request = 24,
					valign = "CENTER",
					css = bind(player_info):as(function(info)
						if info and info.cover then
							return string.format("background-image: url('%s'); background-size: cover;", info.cover)
						end
						return "background-color: #555555;"
					end),
				}),
				Widget.Revealer({
					transition_type = "SLIDE_RIGHT",
					transition_duration = 250,
					reveal_child = bind(hover_state),
					child = Widget.Label({
						label = bind(player_info):as(function(info)
							return (info and info.title) or ""
						end),
						ellipsize = "END",
						max_width_chars = 20,
					}),
				}),
			}),
		}),
	})
end

local function Time(format)
	local time = Variable(""):poll(1000, function()
		local success, datetime = pcall(function()
			return GLib.DateTime.new_now_local():format(format)
		end)
		return success and datetime or ""
	end)

	return Widget.Label({
		class_name = "clock-button",
		label = bind(time),
		setup = function(self)
			self:hook(self, "destroy", function()
				time:drop()
			end)
		end,
	})
end

local function GithubActivity()
	local window_visible = Variable(false)

	local function toggle_github_window()
		if window_visible:get() and github_window then
			github_window:hide()
			window_visible:set(false)
		else
			if not github_window then
				local GithubWindow = require("lua.windows.Github")
				github_window = GithubWindow.new()
			end
			github_window:show_all()
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "github-button",
		on_clicked = toggle_github_window,
		child = Widget.Icon({
			icon = os.getenv("PWD") .. "/icons/github-symbolic.svg",
			tooltip_text = "GitHub Activity",
		}),
	})
end

local function AudioControl(monitor)
	local audio = Wp.get_default().audio
	local speaker = audio and audio.default_speaker
	local mic = audio and audio.default_microphone
	local window_visible = Variable(false)

	local function toggle_audio_window()
		if window_visible:get() and audio_window then
			audio_window:hide()
			window_visible:set(false)
		else
			if not audio_window then
				local AudioControlWindow = require("lua.windows.AudioControl")
				audio_window = AudioControlWindow.new(monitor)
			end
			if audio_window then
				audio_window:show_all()
			end
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "audio-button",
		on_clicked = toggle_audio_window,
		Widget.Box({
			spacing = 10,
			Widget.Icon({
				icon = bind(mic, "volume-icon"),
				tooltip_text = bind(mic, "volume"):as(function(v)
					return string.format("Microphone Volume: %.0f%%", (v or 0) * 100)
				end),
			}),
			Widget.Icon({
				tooltip_text = bind(speaker, "volume"):as(function(v)
					return string.format("Audio Volume: %.0f%%", (v or 0) * 100)
				end),
				icon = bind(speaker, "volume-icon"),
			}),
		}),
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
			end)
		end,
	})
end

local function DisplayControl(monitor)
	local window_visible = Variable(false)

	local function toggle_display_window()
		if window_visible:get() and display_control_window then
			display_control_window:hide()
			window_visible:set(false)
		else
			if not display_control_window then
				local DisplayControlWindow = require("lua.windows.DisplayControl")
				display_control_window = DisplayControlWindow.new(monitor)
			end
			if display_control_window then
				display_control_window:show_all()
			end
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "display-button",
		on_clicked = toggle_display_window,
		child = Widget.Icon({
			icon = "video-display-symbolic",
			tooltip_text = "Display Settings",
		}),
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
			end)
		end,
	})
end

local function Wifi(monitor)
	local network = Network.get_default()
	local window_visible = Variable(false)
	local wifi_state = Variable.derive({ bind(network, "wifi") }, function(wifi)
		return wifi
	end)

	local function toggle_network_window()
		if window_visible:get() and network_window then
			network_window:hide()
			window_visible:set(false)
		else
			if not network_window then
				local NetworkWindow = require("lua.windows.Network")
				network_window = NetworkWindow.new(monitor)
			end
			if network_window then
				network_window:show_all()
			end
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "wifi-button",
		visible = bind(wifi_state):as(function(v)
			return v ~= nil
		end),
		on_clicked = toggle_network_window,
		bind(wifi_state):as(function(w)
			return Widget.Icon({
				tooltip_text = bind(w, "ssid"):as(tostring),
				class_name = "Wifi",
				icon = bind(w, "icon-name"),
			})
		end),
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
				wifi_state:drop()
			end)
		end,
	})
end

local function BatteryLevel(monitor)
	local bat = Battery.get_default()
	local window_visible = Variable(false)
	local battery_state = Variable.derive({ bind(bat, "is-present") }, function(present)
		return present
	end)

	local function toggle_battery_window()
		if window_visible:get() and battery_window then
			battery_window:hide()
			window_visible:set(false)
		else
			if not battery_window then
				local BatteryWindow = require("lua.windows.Battery")
				battery_window = BatteryWindow.new(monitor)
			end
			if battery_window then
				battery_window:show_all()
			end
			window_visible:set(true)
		end
	end

	return Widget.Button({
		class_name = "battery-button",
		visible = bind(battery_state),
		on_clicked = toggle_battery_window,
		Widget.Box({
			Widget.Icon({
				icon = bind(bat, "battery-icon-name"),
				css = "padding-right: 5pt;",
			}),
			Widget.Label({
				label = bind(bat, "percentage"):as(function(p)
					return tostring(math.floor(p * 100)) .. " %"
				end),
			}),
		}),
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
				battery_state:drop()
			end)
		end,
	})
end

local function SysInfo(monitor)
	local window_visible = Variable(false)
	local user_vars = require("user-variables")
	local profile_pic_path = user_vars.profile and user_vars.profile.picture or nil

	local function toggle_sysinfo_window()
		if window_visible:get() and sysinfo_window then
			sysinfo_window:hide()
			window_visible:set(false)
		else
			if not sysinfo_window then
				local SysInfoWindow = require("lua.windows.SysInfo")
				sysinfo_window = SysInfoWindow.new(monitor)
			end
			if sysinfo_window then
				sysinfo_window:show_all()
			end
			window_visible:set(true)
		end
	end

	local child
	if profile_pic_path and require("lua.lib.common").file_exists(profile_pic_path) then
		child = Widget.Box({
			class_name = "profile-image",
			css = string.format("background-image: url('%s');", profile_pic_path),
			tooltip_text = "System Information",
		})
	else
		child = Widget.Icon({
			icon = "computer-symbolic",
			tooltip_text = "System Information",
		})
	end

	return Widget.Button({
		class_name = "sysinfo-button",
		on_clicked = toggle_sysinfo_window,
		child = child,
		setup = function(self)
			self:hook(self, "destroy", function()
				window_visible:drop()
			end)
		end,
	})
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Bar", "No monitor available")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor

	return Widget.Window({
		class_name = "Bar",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.LEFT + Anchor.RIGHT,
		exclusivity = "EXCLUSIVE",
		on_destroy = function()
			if github_window then
				github_window:destroy()
			end
			if audio_window then
				audio_window:destroy()
			end
			if network_window then
				network_window:destroy()
			end
			if battery_window then
				battery_window:destroy()
			end
			if display_control_window then
				display_control_window:destroy()
			end
			if sysinfo_window then
				sysinfo_window:destroy()
			end
			if media_window then
				media_window:destroy()
			end
		end,
		Widget.CenterBox({
			Widget.Box({
				halign = "START",
				class_name = "left-box",
				ActiveClient(),
			}),
			Widget.Box({
				class_name = "center-box",
				Workspaces(),
				Media(gdkmonitor),
			}),
			Widget.Box({
				class_name = "right-box",
				halign = "END",
				GithubActivity(),
				SysTray(),
				AudioControl(gdkmonitor),
				DisplayControl(gdkmonitor),
				Wifi(gdkmonitor),
				BatteryLevel(gdkmonitor),
				Time("%A %d, %H:%M"),
				SysInfo(gdkmonitor),
			}),
		}),
	})
end
