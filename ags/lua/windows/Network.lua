local astal = require("astal")
local Widget = require("astal.gtk3.widget")
local bind = astal.bind
local Variable = astal.Variable
local GLib = astal.require("GLib")
local Network = astal.require("AstalNetwork")
local Debug = require("lua.lib.debug")

local network = Network.get_default()
local wifi = network.wifi

if not network or not wifi then
	Debug.error(
		"Network",
		"Failed to initialize network services - Network: %s, WiFi: %s",
		network and "OK" or "NULL",
		wifi and "OK" or "NULL"
	)
end

local function remove_duplicates(list)
	local seen = {}
	local result = {}
	for _, item in ipairs(list) do
		if item.ssid and not seen[item.ssid] then
			table.insert(result, item)
			seen[item.ssid] = true
		end
	end
	return result
end

local function sort_by_priority(list)
	table.sort(list, function(a, b)
		return (a.strength or 0) > (b.strength or 0)
	end)
end

local function connect_to_access_point(access_point)
	if not access_point or not access_point.ssid then
		Debug.error("Network", "Invalid access point data for connection")
		return
	end
	Debug.info("Network", "Attempting to connect to %s (%s)", access_point.ssid, access_point.bssid)
	astal.exec_async(string.format("nmcli device wifi connect %s", access_point.bssid))
end

local function QuickSettings(airplane_mode, is_wifi_enabled)
	local wifi_enabled = Variable.derive({ bind(wifi, "enabled") }, function(enabled)
		return enabled
	end)

	return Widget.Box({
		class_name = "quick-settings-row",
		orientation = "HORIZONTAL",
		spacing = 10,
		hexpand = true,
		Widget.Button({
			class_name = Variable.derive({ airplane_mode }, function(enabled)
				return enabled and "quick-toggle airplane-mode active" or "quick-toggle airplane-mode"
			end)(),
			hexpand = true,
			on_clicked = function()
				local new_state = not airplane_mode:get()
				if new_state then
					wifi.enabled = false
				end
				airplane_mode:set(new_state)
			end,
			child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 5,
				hexpand = true,
				Widget.Icon({
					icon = "airplane-mode-symbolic",
				}),
				Widget.Label({
					label = "Airplane",
					xalign = 0.5,
				}),
			}),
		}),
		Widget.Button({
			class_name = Variable.derive({ wifi_enabled }, function(enabled)
				return enabled and "quick-toggle wifi active" or "quick-toggle wifi"
			end)(),
			hexpand = true,
			on_clicked = function()
				local new_state = not wifi_enabled:get()
				wifi.enabled = new_state
				is_wifi_enabled:set(new_state)
			end,
			child = Widget.Box({
				orientation = "VERTICAL",
				spacing = 5,
				hexpand = true,
				Widget.Icon({
					icon = "network-wireless-symbolic",
				}),
				Widget.Label({
					label = "Wi-Fi",
					xalign = 0.5,
				}),
			}),
		}),
	})
end

local NetworkWindow = {}

function NetworkWindow.new(gdkmonitor)
	if not gdkmonitor then
		Debug.error("Network", "Failed to initialize: gdkmonitor is nil")
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

	cleanup_refs.airplane_mode = Variable(false)
	cleanup_refs.is_enabled = Variable(wifi and wifi.enabled or false)
	cleanup_refs.is_scanning = Variable(false)
	cleanup_refs.networks_ready = Variable(false)
	cleanup_refs.show_networks = Variable(false)
	cleanup_refs.cached_networks = Variable({})

	local function start_scan()
		if wifi.enabled then
			cleanup_refs.is_scanning:set(true)
			cleanup_refs.networks_ready:set(false)
			cleanup_refs.cached_networks:set({})

			local scan_result = wifi:scan()
			if not scan_result then
				if not wifi or wifi.state == "ERROR" then
					Debug.error(
						"Network",
						"Critical: Failed to initiate network scan - WiFi state: %s",
						tostring(wifi and wifi.state or "unknown")
					)
				end
			end

			cleanup_refs.scan_timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, function()
				if is_destroyed then
					return false
				end
				cleanup_refs.cached_networks:set(wifi.access_points or {})
				cleanup_refs.is_scanning:set(false)
				cleanup_refs.networks_ready:set(true)
				cleanup_refs.scan_timer = nil
				return false
			end)
		end
	end

	local networks_list = Variable.derive(
		{ cleanup_refs.networks_ready, cleanup_refs.cached_networks },
		function(ready, networks)
			if not wifi.enabled then
				return {
					Widget.Label({
						label = "Wi-Fi is disabled",
						xalign = 0.5,
					}),
				}
			end

			if not ready then
				return {
					Widget.Label({
						label = "Scanning for networks...",
						xalign = 0.5,
					}),
				}
			end

			local list = {}
			if networks then
				for _, ap in ipairs(networks) do
					if ap and ap.ssid and ap.ssid ~= "" then
						table.insert(list, ap)
					end
				end
			end

			list = remove_duplicates(list)
			sort_by_priority(list)

			if #list == 0 then
				return {
					Widget.Label({
						label = "No networks found",
						xalign = 0.5,
					}),
				}
			end

			local buttons = {}
			for _, item in ipairs(list) do
				local is_active = wifi.active_access_point and wifi.active_access_point.ssid == item.ssid

				table.insert(
					buttons,
					Widget.Button({
						class_name = "network-item" .. (is_active and " active" or ""),
						hexpand = true,
						on_clicked = function()
							connect_to_access_point(item)
						end,
						child = Widget.Box({
							orientation = "HORIZONTAL",
							spacing = 10,
							hexpand = true,
							Widget.Icon({ icon = item.icon_name or "network-wireless-symbolic" }),
							Widget.Label({
								label = item.ssid or "",
								xalign = 0,
								hexpand = true,
							}),
							Widget.Label({
								label = item.strength and string.format("%d%%", item.strength) or "N/A",
								xalign = 1,
							}),
						}),
					})
				)
			end
			return buttons
		end
	)

	window = Widget.Window({
		class_name = "NetworkWindow",
		gdkmonitor = gdkmonitor,
		anchor = Anchor.TOP + Anchor.RIGHT,
		width_request = 350,
		child = Widget.Box({
			orientation = "VERTICAL",
			spacing = 15,
			css = "padding: 15px;",
			hexpand = true,
			{
				QuickSettings(cleanup_refs.airplane_mode, cleanup_refs.is_enabled),
			},
			{
				Widget.Box({
					class_name = "current-network",
					orientation = "VERTICAL",
					spacing = 5,
					hexpand = true,
					Widget.Box({
						orientation = "HORIZONTAL",
						spacing = 10,
						hexpand = true,
						Widget.Icon({
							icon = bind(wifi, "icon-name"),
						}),
						Widget.Label({
							label = Variable.derive({ bind(wifi, "ssid") }, function(ssid)
								return ssid or "Not Connected"
							end)(),
							xalign = 0,
							hexpand = true,
						}),
					}),
					Widget.Box({
						class_name = "network-details",
						orientation = "VERTICAL",
						spacing = 5,
						hexpand = true,
						Widget.Box({
							orientation = "HORIZONTAL",
							hexpand = true,
							Widget.Label({ label = "Signal Strength:" }),
							Widget.Label({
								label = Variable.derive({ bind(wifi, "strength") }, function(strength)
									if not strength then
										return "N/A"
									end
									if strength >= 80 then
										return "Excellent"
									end
									if strength >= 60 then
										return "Good"
									end
									if strength >= 40 then
										return "Fair"
									end
									return "Weak"
								end)(),
								xalign = 1,
								hexpand = true,
							}),
						}),
						Widget.Box({
							orientation = "HORIZONTAL",
							hexpand = true,
							Widget.Label({ label = "Frequency:" }),
							Widget.Label({
								label = Variable.derive({ bind(wifi, "frequency") }, function(freq)
									return freq and string.format("%.1f GHz", freq / 1000) or "N/A"
								end)(),
								xalign = 1,
								hexpand = true,
							}),
						}),
						Widget.Box({
							orientation = "HORIZONTAL",
							hexpand = true,
							Widget.Label({ label = "Bandwidth:" }),
							Widget.Label({
								label = Variable.derive({ bind(wifi, "bandwidth") }, function(bw)
									return bw and string.format("%d Mbps", bw) or "N/A"
								end)(),
								xalign = 1,
								hexpand = true,
							}),
						}),
					}),
				}),
			},
			{
				Widget.Box({
					class_name = "networks-section",
					orientation = "VERTICAL",
					spacing = 10,
					hexpand = true,
					Widget.Box({
						class_name = "networks-container",
						orientation = "VERTICAL",
						spacing = 5,
						hexpand = true,
						Widget.Button({
							class_name = "network-selector",
							hexpand = true,
							child = Widget.Box({
								orientation = "HORIZONTAL",
								spacing = 10,
								hexpand = true,
								Widget.Icon({ icon = "network-wireless-symbolic" }),
								Widget.Box({
									hexpand = true,
									Widget.Label({
										label = Variable.derive({ cleanup_refs.is_scanning }, function(scanning)
											return scanning and "Scanning..." or "Available Networks"
										end)(),
										xalign = 0,
										hexpand = true,
									}),
								}),
								Widget.Icon({
									icon = "pan-down-symbolic",
									class_name = Variable.derive({ cleanup_refs.show_networks }, function(shown)
										return shown and "expanded" or ""
									end)(),
								}),
							}),
							on_clicked = function()
								cleanup_refs.show_networks:set(not cleanup_refs.show_networks:get())
								if cleanup_refs.show_networks:get() then
									start_scan()
								else
									cleanup_refs.is_scanning:set(false)
									cleanup_refs.networks_ready:set(false)
									cleanup_refs.cached_networks:set({})
								end
							end,
						}),
						Widget.Revealer({
							transition_duration = 200,
							transition_type = "SLIDE_DOWN",
							reveal_child = cleanup_refs.show_networks(),
							hexpand = true,
							child = Widget.Box({
								class_name = "networks-list-container",
								orientation = "VERTICAL",
								hexpand = true,
								Widget.Scrollable({
									vscrollbar_policy = "AUTOMATIC",
									hscrollbar_policy = "NEVER",
									class_name = "network-list",
									hexpand = true,
									child = Widget.Box({
										orientation = "VERTICAL",
										spacing = 5,
										hexpand = true,
										networks_list(),
									}),
								}),
							}),
						}),
					}),
				}),
			},
			{
				Widget.Box({
					class_name = "settings",
					hexpand = true,
					Widget.Button({
						label = "Network Settings",
						hexpand = true,
						on_clicked = function()
							close_window()
							GLib.spawn_command_line_async("env XDG_CURRENT_DESKTOP=GNOME gnome-control-center wifi")
						end,
					}),
				}),
			},
		}),
		setup = function(self)
			self:hook(self, "destroy", function()
				if is_destroyed then
					return
				end
				is_destroyed = true

				if cleanup_refs.scan_timer then
					GLib.source_remove(cleanup_refs.scan_timer)
				end

				for _, ref in pairs(cleanup_refs) do
					if type(ref) == "table" and ref.drop then
						ref:drop()
					end
				end

				cleanup_refs = nil
				collectgarbage("collect")
			end)
		end,
	})

	return window
end

return NetworkWindow
