local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Apps = astal.require("AstalApps")
local dock_config = require("lua.lib.dock-config")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")
local Variable = astal.Variable

local function DockIcon(props)
	if not props.icon then
		Debug.warn("Dock", "Creating dock icon without icon for entry: %s", props.desktop_entry or "unknown")
	end

	return Widget.Button({
		class_name = "dock-icon",
		on_clicked = props.on_clicked,
		Widget.Box({
			orientation = "VERTICAL",
			spacing = 2,
			Widget.Icon({
				icon = props.icon or "application-x-executable",
				pixel_size = 48,
			}),
			Widget.Box({
				class_name = "indicator",
				visible = props.is_running or false,
				hexpand = false,
				halign = "CENTER",
				width_request = 3,
				height_request = 3,
			}),
		}),
	})
end

local apps_singleton = nil

local function get_apps_service()
	if not apps_singleton then
		apps_singleton = Apps.Apps.new()
	end
	return apps_singleton
end

local function DockContainer()
	local apps = get_apps_service()
	if not apps then
		Debug.error("Dock", "Failed to initialize Apps service")
		return Widget.Box({})
	end

	local available_apps = {}
	local pinned_apps = dock_config.pinned_apps
	local update_timeout = nil
	local container_active = true
	local subscription = nil

	local function update_dock_icons(self)
		if not self or not container_active then
			return
		end

		local children = self:get_children()
		if children then
			for _, child in ipairs(children) do
				child:destroy()
				self:remove(child)
			end
		end

		for _, desktop_entry in ipairs(pinned_apps) do
			local app = available_apps[desktop_entry]
			if app then
				self:add(DockIcon({
					icon = app.icon_name,
					is_running = dock_config.is_running(desktop_entry),
					desktop_entry = desktop_entry,
					on_clicked = function()
						if app.launch then
							app:launch()
						end
					end,
				}))
			end
		end

		for entry, app in pairs(available_apps) do
			if dock_config.is_running(entry) and not dock_config.is_pinned(entry) then
				self:add(DockIcon({
					icon = app.icon_name,
					is_running = true,
					desktop_entry = entry,
					on_clicked = function()
						if app.launch then
							app:launch()
						end
					end,
				}))
			end
		end
	end

	local function update_apps_state(self)
		if not self or not container_active then
			return
		end

		dock_config.update_running_apps()
		local app_list = apps:get_list()
		if not app_list then
			return
		end

		available_apps = {}
		for _, app in ipairs(app_list) do
			if app and app.entry then
				available_apps[app.entry] = app
			end
		end

		pinned_apps = dock_config.pinned_apps
		update_dock_icons(self)
		collectgarbage("collect")
	end

	local container = Widget.Box({
		class_name = "dock-container",
		spacing = 8,
		homogeneous = false,
		halign = "CENTER",
		setup = function(self)
			update_timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, function()
				if not container_active then
					return GLib.SOURCE_REMOVE
				end
				update_apps_state(self)
				return GLib.SOURCE_CONTINUE
			end)

			self:hook(self, "destroy", function()
				container_active = false
				if update_timeout then
					GLib.source_remove(update_timeout)
					update_timeout = nil
				end

				if subscription then
					subscription:unsubscribe()
					subscription = nil
				end

				available_apps = {}
				pinned_apps = nil
				collectgarbage("collect")
			end)

			update_apps_state(self)
		end,
	})

	return container
end

local function create_revealer(content)
	if not content then
		Debug.error("Dock", "Attempting to create revealer with nil content")
		return nil
	end

	return Widget.Revealer({
		transition_type = "SLIDE_UP",
		transition_duration = 200,
		reveal_child = true,
		content,
	})
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Dock", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor
	local visible = Variable(true)
	local hide_timeout = nil
	local revealer = nil
	local dock_window = nil
	local detector_window = nil
	local subscription = nil

	local is_cleaned_up = false

	local function cleanup()
		if is_cleaned_up then
			return
		end
		is_cleaned_up = true

		if hide_timeout then
			GLib.source_remove(hide_timeout)
			hide_timeout = nil
		end

		if subscription then
			subscription:unsubscribe()
			subscription = nil
		end

		if visible then
			visible:drop()
		end

		if detector_window then
			detector_window:destroy()
			detector_window = nil
		end

		revealer = nil
		collectgarbage("collect")
	end

	local function show_dock()
		if is_cleaned_up then
			return
		end

		if hide_timeout then
			GLib.source_remove(hide_timeout)
			hide_timeout = nil
		end

		if visible then
			visible:set(true)
		end
	end

	local function hide_dock()
		if is_cleaned_up or not visible then
			return
		end
		visible:set(false)
	end

	local function schedule_hide(delay)
		if is_cleaned_up then
			return
		end

		if hide_timeout then
			GLib.source_remove(hide_timeout)
		end

		hide_timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, delay or 500, function()
			hide_dock()
			hide_timeout = nil
			return GLib.SOURCE_REMOVE
		end)
	end

	dock_window = Widget.Window({
		class_name = "Dock",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM + Anchor.LEFT + Anchor.RIGHT,
		setup = function(self)
			subscription = visible:subscribe(function(value)
				if revealer then
					revealer.reveal_child = value
				end

				if self and not is_cleaned_up then
					if value then
						self:get_style_context():add_class("revealed")
					else
						self:get_style_context():remove_class("revealed")
					end
				end
			end)

			self:hook(self, "destroy", function()
				cleanup()
			end)
		end,
		Widget.EventBox({
			on_hover_lost = function()
				schedule_hide(500)
			end,
			on_hover = show_dock,
			Widget.Box({
				class_name = "dock-wrapper",
				halign = "CENTER",
				hexpand = false,
				setup = function(self)
					local dock_container = DockContainer()
					if dock_container then
						revealer = create_revealer(dock_container)
						if revealer then
							self:add(revealer)
						end
					end
				end,
			}),
		}),
	})

	detector_window = Widget.Window({
		class_name = "DockDetector",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.BOTTOM + Anchor.LEFT + Anchor.RIGHT,
		Widget.EventBox({
			height_request = 1,
			on_hover = show_dock,
		}),
	})

	detector_window:show_all()
	schedule_hide(1000)

	return dock_window
end
