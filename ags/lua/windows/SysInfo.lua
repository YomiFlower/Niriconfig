local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local Debug = require("lua.lib.debug")
local SysInfo = require("lua.lib.sysinfo")

local function create_info_row(label, value)
	if not label then
		return nil
	end
	return Widget.Box({
		orientation = "HORIZONTAL",
		spacing = 10,
		hexpand = true,
		Widget.Label({
			label = label .. ":",
			class_name = "info-label",
			xalign = 0,
		}),
		Widget.Label({
			label = value or "Unknown",
			class_name = "info-value",
			xalign = 0,
			hexpand = true,
		}),
	})
end

local SysInfoWindow = {}

function SysInfoWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("SysInfo", "Failed to initialize: gdkmonitor is nil")
		return nil
	end

	local info = SysInfo.get_info()
	if not info then
		Debug.error("SysInfo", "Failed to get system information")
		return nil
	end

	local Anchor = astal.require("Astal").WindowAnchor

	local distro_name = info.os and info.os.name or "Unknown"
	local distro_version = info.os and info.os.version or "Unknown"
	local distro_codename = info.os and info.os.codename or "Unknown"
	local wm_name = info.wm and info.wm.name or "Unknown"
	local wm_version = info.wm and info.wm.version or "Unknown"
	local username = info.title and info.title.name or "unknown"
	local hostname = info.title and info.title.separator or "unknown"
	local terminal_name = info.terminal and info.terminal.name or "Unknown"
	local cpu_name = info.cpu and info.cpu.name or "Unknown"
	local gpu_name = info.gpu and info.gpu.name or "Unknown"
	local memory_used = info.memory and info.memory.used or "Unknown"
	local memory_total = info.memory and info.memory.total or "Unknown"
	local de_name = info.de and info.de.name or "Unknown"
	local uptime = info.uptime and info.uptime.formatted or "Unknown"
	local display_compositor = info.display and info.display.compositor or "Unknown"

	local distro_icon = (info.os and info.os.icon_name) or "computer-symbolic"

	return Widget.Window({
		class_name = "SysInfoWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 20,
			css = "padding: 20px;",
			Widget.Box({
				orientation = "HORIZONTAL",
				spacing = 20,
				Widget.Box({
					orientation = "VERTICAL",
					spacing = 10,
					Widget.Box({
						orientation = "HORIZONTAL",
						spacing = 10,
						Widget.Icon({
							class_name = "distro-logo",
							icon = distro_icon,
							pixel_size = 64,
						}),
						Widget.Box({
							orientation = "VERTICAL",
							spacing = 5,
							Widget.Label({
								label = distro_name,
								class_name = "distro-name",
								xalign = 0,
							}),
							Widget.Label({
								label = distro_version,
								class_name = "distro-version",
								xalign = 0,
							}),
							Widget.Label({
								label = distro_codename,
								class_name = "distro-codename",
								xalign = 0,
							}),
						}),
					}),
				}),
				Widget.Box({
					orientation = "VERTICAL",
					spacing = 10,
					create_info_row("WM", wm_name),
					create_info_row("Version", wm_version),
				}),
			}),
			Widget.Box({
				orientation = "VERTICAL",
				spacing = 10,
				create_info_row("User", string.format("%s@%s", username, hostname)),
				create_info_row("Terminal", terminal_name),
				create_info_row("CPU", cpu_name),
				create_info_row("GPU", gpu_name),
				create_info_row("Memory", string.format("%s / %s", memory_used, memory_total)),
				create_info_row("WM", de_name),
				create_info_row("Uptime", uptime),
				create_info_row("Display", string.format("%s", display_compositor)),
			}),
		}),
	})
end

function SysInfoWindow.refresh(window)
	if not window then
		return nil
	end

	SysInfo.refresh()
	local new_window = SysInfoWindow.new(window.gdkmonitor)

	if new_window then
		local old_position = window:get_position()
		new_window:move(old_position.x, old_position.y)
		window:destroy()
		return new_window
	end

	return window
end

function SysInfoWindow.destroy(window)
	if window then
		window:destroy()
		window = nil
	end

	SysInfo.cleanup()
	collectgarbage("collect")
end

return SysInfoWindow
