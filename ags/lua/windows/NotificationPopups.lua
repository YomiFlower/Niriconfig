local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Debug = require("lua.lib.debug")
local Notifd = astal.require("AstalNotifd")
local Notification = require("lua.widgets.Notification")
local timeout = astal.timeout
local Variable = astal.Variable
local bind = astal.bind

local TIMEOUT_DELAY = 5000

local notifd = Notifd.get_default()
if not notifd then
	Debug.error("NotificationPopups", "Failed to get notification daemon")
end

local function NotificationMap(parent)
	local notifications = Variable({})
	local notif_map = {}
	local timer_vars = {}
	local subscriptions = {}
	local is_destroyed = false

	local function update_notifications()
		if is_destroyed then
			return
		end
		local arr = {}
		for _, widget in pairs(notif_map) do
			table.insert(arr, widget)
		end
		notifications:set(arr)
	end

	local function remove_notification(id)
		if is_destroyed then
			return
		end

		if timer_vars[id] then
			pcall(function()
				timer_vars[id]:drop()
			end)
			timer_vars[id] = nil
		end

		if subscriptions[id] then
			pcall(function()
				subscriptions[id]:unsubscribe()
			end)
			subscriptions[id] = nil
		end

		if notif_map[id] then
			if notif_map[id].destroy then
				notif_map[id]:destroy()
			end
			notif_map[id] = nil
			update_notifications()
		end
	end

	parent:hook(notifd, "notified", function(_, id)
		if is_destroyed then
			return
		end

		local notification = notifd:get_notification(id)
		if not notification then
			Debug.error("NotificationPopups", "Failed to get notification with id: %d", id)
			return
		end

		local timer = Variable(0)
		timer_vars[id] = timer

		notif_map[id] = Notification({
			notification = notification,
			on_hover_lost = function()
				if not is_destroyed then
					remove_notification(id)
				end
			end,
			setup = function(self)
				if is_destroyed then
					return
				end

				subscriptions[id] = timer:subscribe(function()
					if not is_destroyed then
						remove_notification(id)
					end
				end)

				self:hook(self, "destroy", function()
					if subscriptions[id] then
						pcall(function()
							subscriptions[id]:unsubscribe()
						end)
						subscriptions[id] = nil
					end
				end)

				timeout(TIMEOUT_DELAY, function()
					if not is_destroyed and timer_vars[id] then
						timer:set(1)
					end
				end)
			end,
		})

		update_notifications()
	end)

	parent:hook(notifd, "resolved", function(_, id)
		if not is_destroyed then
			remove_notification(id)
		end
	end)

	parent:hook(parent, "destroy", function()
		is_destroyed = true

		for id, sub in pairs(subscriptions) do
			pcall(function()
				sub:unsubscribe()
			end)
		end
		subscriptions = {}

		for id, timer in pairs(timer_vars) do
			pcall(function()
				timer:drop()
			end)
		end
		timer_vars = {}

		for id, notif in pairs(notif_map) do
			if notif.destroy then
				notif:destroy()
			end
		end
		notif_map = {}

		pcall(function()
			notifications:drop()
		end)

		collectgarbage("collect")
	end)

	return notifications
end

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("NotificationPopups", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor

	return Widget.Window({
		class_name = "NotificationPopups",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		setup = function(self)
			local notifs = NotificationMap(self)
			self:add(Widget.Box({
				vertical = true,
				bind(notifs),
			}))
		end,
	})
end
