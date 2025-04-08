local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Debug = require("lua.lib.debug")

return function(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Desktop", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor

	local desktop = Widget.Window({
		class_name = "DesktopFrame",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.LEFT + Anchor.RIGHT + Anchor.BOTTOM,
		exclusivity = "EXCLUSIVE",
		layer = "BACKGROUND",
		click_through = true,
		child = Widget.Box({
			class_name = "desktop-frame",
		}),
	})

	return desktop
end
