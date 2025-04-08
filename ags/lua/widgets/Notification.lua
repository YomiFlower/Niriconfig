local Widget = require("astal.gtk3").Widget
local Gtk = require("astal.gtk3").Gtk
local Astal = require("astal.gtk3").Astal
local map = require("lua.lib.common").map
local time = require("lua.lib.common").time
local file_exists = require("lua.lib.common").file_exists
local Debug = require("lua.lib.debug")

local function is_icon(icon)
	if not icon then
		return false
	end
	if icon:match("^file://") then
		return false
	end
	return Astal.Icon.lookup_icon(icon) ~= nil
end

return function(props)
	if not props.notification then
		Debug.error("Notification", "No notification data provided")
		return nil
	end

	local n = props.notification

	local image_path = nil
	local app_icon = n:get_app_icon()

	if app_icon and app_icon:match("^file://") then
		image_path = app_icon:gsub("^file://", "")
		if image_path and not file_exists(image_path) then
			Debug.error("Notification", "Image file not found: %s", image_path)
		end
		app_icon = nil
	end

	local header = Widget.Box({
		class_name = "header",
		(app_icon or n:get_desktop_entry()) and Widget.Icon({
			class_name = "app-icon",
			icon = app_icon or n:get_desktop_entry(),
		}),
		Widget.Label({
			class_name = "app-name",
			halign = "START",
			ellipsize = "END",
			label = n:get_app_name() or "Unknown",
		}),
		Widget.Label({
			class_name = "time",
			hexpand = true,
			halign = "END",
			label = time(n:get_time()),
		}),
		Widget.Button({
			on_clicked = function()
				local success, err = pcall(function()
					n:dismiss()
				end)
				if not success then
					Debug.error("Notification", "Failed to dismiss notification: %s", err)
				end
			end,
			Widget.Icon({ icon = "window-close-symbolic" }),
		}),
	})

	local content = Widget.Box({
		class_name = "content",
		(image_path and file_exists(image_path)) and Widget.Box({
			valign = "START",
			class_name = "image",
			css = string.format("background-image: url('%s')", image_path),
		}),
		image_path and is_icon(image_path) and Widget.Box({
			valign = "START",
			class_name = "icon-image",
			Widget.Icon({
				icon = image_path,
				hexpand = true,
				vexpand = true,
				halign = "CENTER",
				valign = "CENTER",
			}),
		}),
		Widget.Box({
			vertical = true,
			Widget.Label({
				class_name = "summary",
				halign = "START",
				xalign = 0,
				ellipsize = "END",
				label = n:get_summary(),
			}),
			Widget.Label({
				class_name = "body",
				wrap = true,
				use_markup = true,
				halign = "START",
				xalign = 0,
				justify = "FILL",
				label = n:get_body(),
			}),
		}),
	})

	local actions_box = #n:get_actions() > 0
		and Widget.Box({
			class_name = "actions",
			map(n:get_actions(), function(action)
				local label, id = action.label, action.id
				return Widget.Button({
					hexpand = true,
					on_clicked = function()
						local success, err = pcall(function()
							return n:invoke(id)
						end)
						if not success then
							Debug.error("Notification", "Failed to invoke action: %s", err)
						end
					end,
					Widget.Label({
						label = label,
						halign = "CENTER",
						hexpand = true,
					}),
				})
			end),
		})

	return Widget.EventBox({
		class_name = string.format("Notification %s", string.lower(n:get_urgency())),
		setup = props.setup,
		on_hover_lost = props.on_hover_lost,
		Widget.Box({
			vertical = true,
			header,
			Gtk.Separator({ visible = true }),
			content,
			actions_box,
		}),
	})
end
