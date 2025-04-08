local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Mpris = astal.require("AstalMpris")
local Gtk = astal.require("Gtk")
local GLib = astal.require("GLib")
local Variable = astal.Variable
local Debug = require("lua.lib.debug")

local function format_time(seconds)
	if not seconds or type(seconds) ~= "number" then
		return "0:00"
	end
	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%d:%02d", minutes, secs)
end

local function AlbumImage(player)
	return Widget.Box({
		class_name = "album-image",
		width_request = 150,
		height_request = 150,
		hexpand = true,
		halign = "CENTER",
		css = bind(player, "cover-art"):as(function(cover)
			return cover and string.format("background-image: url('%s'); background-size: cover;", cover) or ""
		end),
	})
end

local function MediaInfo(player)
	return Widget.Box({
		class_name = "media-info",
		orientation = "VERTICAL",
		spacing = 5,
		hexpand = true,
		Widget.Label({
			class_name = "media-title",
			label = bind(player, "title"):as(function(title)
				return title or "No Title"
			end),
			xalign = 0,
			ellipsize = "END",
		}),
		Widget.Label({
			class_name = "media-artist",
			label = bind(player, "artist"):as(function(artist)
				return artist or "Unknown Artist"
			end),
			xalign = 0,
			ellipsize = "END",
		}),
		Widget.Label({
			class_name = "media-album",
			visible = bind(player, "album"):as(function(album)
				return album and album ~= ""
			end),
			label = bind(player, "album"),
			xalign = 0,
			ellipsize = "END",
		}),
	})
end

local function ProgressTracker(player)
	local position_var = Variable(0)
	local timer_id
	local is_seeking = false

	return Widget.Box({
		class_name = "progress-tracker",
		orientation = "HORIZONTAL",
		spacing = 10,
		hexpand = true,
		setup = function(self)
			timer_id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, function()
				if not is_seeking and player and player.available then
					if player["playback-status"] == "PLAYING" then
						position_var:set(tonumber(player.position) or 0)
					end
				end
				return true
			end)

			self:hook(self, "destroy", function()
				if timer_id then
					GLib.source_remove(timer_id)
					timer_id = nil
				end
				position_var:drop()
			end)
		end,
		Widget.Label({
			label = bind(position_var):as(format_time),
			width_chars = 5,
		}),
		Widget.Box({
			hexpand = true,
			Widget.Slider({
				class_name = "progress-slider",
				hexpand = true,
				draw_value = false,
				adjustment = Gtk.Adjustment({
					lower = 0,
					upper = 100,
					step_increment = 1,
				}),
				value = bind(position_var):as(function(pos)
					if is_seeking then
						return nil
					end
					local length = tonumber(player.length) or 1
					return ((tonumber(pos) or 0) / length) * 100
				end),
				on_button_press_event = function()
					is_seeking = true
					return false
				end,
				on_button_release_event = function(self)
					if player and player.available then
						local length = tonumber(player.length) or 1
						local new_position = (self:get_value() / 100) * length
						player.position = new_position
						position_var:set(new_position)
					end
					is_seeking = false
					return false
				end,
			}),
		}),
		Widget.Label({
			label = bind(player, "length"):as(format_time),
			width_chars = 5,
		}),
	})
end

local function ProgressBar(player)
	return ProgressTracker(player)
end

local function PlaybackControls(player)
	local is_busy = false

	local function perform_action(action)
		if is_busy or not player or not player.available then
			return
		end

		is_busy = true
		action()

		GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, function()
			is_busy = false
			return false
		end)
	end

	return Widget.Box({
		class_name = "playback-controls",
		orientation = "HORIZONTAL",
		spacing = 20,
		halign = "CENTER",
		Widget.Button({
			sensitive = bind(player, "can-go-previous"),
			on_clicked = function()
				perform_action(function()
					player:previous()
				end)
			end,
			child = Widget.Icon({
				icon = "media-skip-backward-symbolic",
				pixel_size = 16,
			}),
		}),
		Widget.Button({
			on_clicked = function()
				perform_action(function()
					if player["playback-status"] == "PLAYING" then
						player:pause()
					else
						player:play()
					end
				end)
			end,
			child = Widget.Icon({
				icon = bind(player, "playback-status"):as(function(status)
					return status == "PLAYING" and "media-playback-pause-symbolic" or "media-playback-start-symbolic"
				end),
				pixel_size = 24,
			}),
		}),
		Widget.Button({
			sensitive = bind(player, "can-go-next"),
			on_clicked = function()
				perform_action(function()
					player:next()
				end)
			end,
			child = Widget.Icon({
				icon = "media-skip-forward-symbolic",
				pixel_size = 16,
			}),
		}),
	})
end

local MediaControlWindow = {}

function MediaControlWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("MediaControl", "No monitor available")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local user_vars = require("user-variables")
	local mpris = Mpris.get_default()
	local cleanup_refs = {}
	local is_destroyed = false

	local function get_active_player()
		if not mpris then
			return nil
		end

		local success, players = pcall(function()
			return mpris:get_players()
		end)

		if not success or not players or #players == 0 then
			return nil
		end

		local preferred_players = user_vars.media and user_vars.media.preferred_players or {}
		for _, preferred in ipairs(preferred_players) do
			for _, player in ipairs(players) do
				if player.bus_name:match(preferred) and player.available then
					return player
				end
			end
		end

		for _, player in ipairs(players) do
			if player.available then
				return player
			end
		end
		return nil
	end

	local initial_player = get_active_player()
	if not initial_player or not initial_player.available then
		return nil
	end

	cleanup_refs.window_state = Variable({
		player = initial_player,
		available = true,
		position = 0,
		length = initial_player.length or 0,
	})

	cleanup_refs.poll_id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, function()
		if is_destroyed then
			return false
		end

		local current_player = get_active_player()
		if current_player and current_player.available then
			if current_player.bus_name ~= cleanup_refs.window_state:get().player.bus_name then
				cleanup_refs.window_state:set({
					player = current_player,
					available = true,
					length = current_player.length or 0,
				})
			end
		else
			cleanup_refs.window_state:set({
				player = nil,
				available = false,
				length = 0,
			})
		end
		return true
	end)

	local window = Widget.Window({
		class_name = "MediaControlWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP,
		setup = function(self)
			self:hook(self, "destroy", function()
				if is_destroyed then
					return
				end
				is_destroyed = true

				if cleanup_refs.poll_id then
					GLib.source_remove(cleanup_refs.poll_id)
					cleanup_refs.poll_id = nil
				end
				if cleanup_refs.window_state then
					cleanup_refs.window_state:drop()
					cleanup_refs.window_state = nil
				end
				cleanup_refs = nil
				collectgarbage("collect")
			end)
		end,
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 15,
			css = "padding: 20px;",
			bind(cleanup_refs.window_state):as(function(state)
				if not state.available or not state.player then
					return Widget.Box()
				end

				return Widget.Box({
					orientation = "HORIZONTAL",
					spacing = 24,
					AlbumImage(state.player),
					Widget.Box({
						orientation = "VERTICAL",
						spacing = 16,
						hexpand = true,
						MediaInfo(state.player),
						Widget.Box({
							orientation = "VERTICAL",
							spacing = 12,
							valign = "END",
							vexpand = true,
							ProgressBar(state.player),
							PlaybackControls(state.player),
						}),
					}),
				})
			end),
		}),
	})

	return window
end

return MediaControlWindow
