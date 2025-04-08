local astal = require("astal")
local cjson = require("cjson")
local Debug = require("lua.lib.debug")
local GLib = astal.require("GLib")

local M = {}

local cache = {
	data = nil,
	timestamp = 0,
	lifetime = 30,
}

function M.get_cache_info()
	local size = 0
	if cache.data then
		for k, v in pairs(cache.data) do
			size = size + 1
			if type(v) == "table" then
				for _ in pairs(v) do
					size = size + 1
				end
			end
		end
	end

	return {
		has_data = cache.data ~= nil,
		items = size,
		age = GLib.get_monotonic_time() / 1000000 - cache.timestamp,
	}
end

local function get_os_logo(os_id)
	if not os_id then
		return nil
	end

	os_id = os_id:lower()

	local logo_map = {
		["nixos"] = "distributor-logo-nixos",
		["arch"] = "distributor-logo-archlinux",
		["ubuntu"] = "distributor-logo-ubuntu",
		["fedora"] = "distributor-logo-fedora",
		["debian"] = "distributor-logo-debian",
		["kali"] = "distributor-logo-kali",
		["manjaro"] = "distributor-logo-manjaro",
		["opensuse"] = "distributor-logo-opensuse",
		["gentoo"] = "distributor-logo-gentoo",
		["centos"] = "distributor-logo-centos",
		["redhat"] = "distributor-logo-redhat",
		["rhel"] = "distributor-logo-redhat",
		["mint"] = "distributor-logo-linuxmint",
		["elementary"] = "distributor-logo-elementary",
		["pop"] = "distributor-logo-pop-os",
		["zorin"] = "distributor-logo-zorin",
		["void"] = "distributor-logo-void",
		["slackware"] = "distributor-logo-slackware",
		["artix"] = "distributor-logo-artix",
		["endeavour"] = "distributor-logo-endeavouros",
		["garuda"] = "distributor-logo-garuda",
		["solus"] = "distributor-logo-solus",
	}

	return logo_map[os_id] or "distributor-logo"
end

local function parse_fastfetch_data(raw_data)
	if not raw_data or type(raw_data) ~= "table" then
		Debug.error("SysInfo", "Invalid raw data")
		return {}
	end

	local niri_version = "unknown"
	local niri_handle, niri_err = io.popen("niri -V")
	if niri_handle then
		local version = niri_handle:read("*l")
		niri_handle:close()
		if version then
			niri_version = version:match("niri%s+(.+)") or "unknown"
		end
	end

	local parsed = {}

	local found_wm_name = nil

	for _, item in ipairs(raw_data) do
		if item.type == "WM" and item.result and item.result.prettyName then
			found_wm_name = item.result.prettyName
			break
		end
	end

	for _, item in ipairs(raw_data) do
		if item.type and item.result then
			if item.type == "Title" then
				parsed.title = {
					name = item.result.userName,
					separator = item.result.hostName,
				}
			elseif item.type == "OS" then
				parsed.os = {
					name = item.result.name,
					version = item.result.version,
					codename = item.result.codename,
					type = item.result.id,
				}

				parsed.os.icon_name = get_os_logo(item.result.id)
			elseif item.type == "Kernel" then
				parsed.kernel = {
					name = item.result.name,
					version = item.result.release,
				}
			elseif item.type == "Uptime" then
				local uptime = nil

				if type(item.result.uptime) == "number" then
					uptime = item.result.uptime
				elseif type(item.result.uptime) == "string" then
					uptime = tonumber(item.result.uptime)
				elseif item.result.seconds then
					uptime = tonumber(item.result.seconds)
				end

				if uptime then
					if uptime > 31536000 then
						Debug.error("SysInfo", "Unreasonable uptime detected: " .. uptime .. " seconds, adjusting")

						local handle = io.popen("cat /proc/uptime")
						if handle then
							local proc_uptime = handle:read("*l")
							handle:close()
							if proc_uptime then
								uptime = tonumber(proc_uptime:match("^%S+"))
							end
						end

						if not uptime or uptime > 31536000 then
							uptime = 0
							Debug.error("SysInfo", "Failed to get reasonable uptime, defaulting to 0")
						end
					end

					local seconds = uptime
					local days = math.floor(seconds / 86400)
					seconds = seconds - days * 86400
					local hours = math.floor(seconds / 3600)
					seconds = seconds - hours * 3600
					local minutes = math.floor(seconds / 60)

					local uptime_text = ""
					if days > 0 then
						uptime_text = days .. " day" .. (days > 1 and "s" or "")
						if hours > 0 or minutes > 0 then
							uptime_text = uptime_text .. ", "
						end
					end

					if hours > 0 then
						uptime_text = uptime_text .. hours .. " hour" .. (hours > 1 and "s" or "")
						if minutes > 0 then
							uptime_text = uptime_text .. ", "
						end
					end

					if minutes > 0 or (days == 0 and hours == 0) then
						uptime_text = uptime_text .. minutes .. " minute" .. (minutes > 1 and "s" or "")
					end

					parsed.uptime = {
						seconds = uptime,
						formatted = uptime_text,
					}
				else
					Debug.error("SysInfo", "Failed to parse uptime from fastfetch data")
					parsed.uptime = {
						seconds = 0,
						formatted = "Unknown",
					}
				end
			elseif item.type == "Packages" then
				parsed.packages = {
					total = item.result.all,
					formatted = tostring(item.result.all),
				}
			elseif item.type == "Terminal" then
				parsed.terminal = {
					name = item.result.prettyName,
					version = item.result.version,
				}
			elseif item.type == "Display" then
				if item.result and #item.result > 0 then
					local displays = {}
					for i, display in ipairs(item.result) do
						table.insert(
							displays,
							string.format("%s (%dx%d)", display.name, display.output.width, display.output.height)
						)
					end

					parsed.display = {
						server = "Wayland",
						compositor = table.concat(displays, ", "),
					}
				end
			elseif item.type == "DE" then
				if item.result and item.result.name and item.result.name ~= "Unknown" then
					parsed.de = {
						name = item.result.name,
						version = item.result.version or "",
					}
				else
					parsed.de = {
						name = found_wm_name or "Wayland Compositor",
						version = niri_version,
					}
				end
			elseif item.type == "WM" then
				parsed.wm = {
					name = item.result.prettyName,
					version = niri_version,
				}
			elseif item.type == "CPU" then
				parsed.cpu = {
					name = item.result.cpu,
					cores = item.result.cores.physical,
					threads = item.result.cores.logical,
					frequency = string.format("%.1f GHz", item.result.frequency.max / 1000),
				}
			elseif item.type == "GPU" then
				if item.result[1] then
					local gpu = item.result[1]
					parsed.gpu = {
						name = string.format("%s %s (%s)", gpu.vendor, gpu.name, gpu.type),
						driver = gpu.driver,
						type = gpu.type,
					}
				end
			elseif item.type == "Memory" then
				parsed.memory = {
					total = string.format("%.1f GB", item.result.total / (1024 * 1024 * 1024)),
					used = string.format("%.1f GB", item.result.used / (1024 * 1024 * 1024)),
					percentage = math.floor((item.result.used / item.result.total) * 100),
				}
			elseif item.type == "Disk" then
				if item.result[1] then
					parsed.disk = {
						total = string.format("%.1f GB", item.result[1].bytes.total / (1024 * 1024 * 1024)),
						used = string.format("%.1f GB", item.result[1].bytes.used / (1024 * 1024 * 1024)),
						percentage = math.floor((item.result[1].bytes.used / item.result[1].bytes.total) * 100),
					}
				end
			end
		end
	end

	if not parsed.de then
		parsed.de = {
			name = found_wm_name or "Wayland Compositor",
			version = niri_version,
		}
	end

	return parsed
end

local function execute_fastfetch()
	local handle, err = io.popen(
		[[fastfetch --structure Title:Break:OS:Host:Kernel:Uptime:Packages:Shell:Display:DE:WM:Terminal:CPU:GPU:Memory:Disk:Battery:PowerAdapter:Locale:Break --format json]]
	)
	if not handle then
		Debug.error("SysInfo", "Failed to execute fastfetch: " .. (err or "unknown error"))
		return nil
	end

	local output
	local success, read_err = pcall(function()
		output = handle:read("*a")
	end)

	handle:close()

	if not success then
		Debug.error("SysInfo", "Failed to read fastfetch output: " .. (read_err or "unknown error"))
		return nil
	end

	if not output or output == "" then
		Debug.error("SysInfo", "Empty fastfetch output")
		return nil
	end

	local decode_success, data = pcall(cjson.decode, output)
	if not decode_success or type(data) ~= "table" then
		Debug.error("SysInfo", "Failed to parse fastfetch JSON")
		return nil
	end

	return data
end

function M.get_info()
	local current_time = GLib.get_monotonic_time() / 1000000

	if cache.data and (current_time - cache.timestamp) < cache.lifetime then
		return cache.data
	end

	local raw_data = execute_fastfetch()
	if not raw_data then
		return cache.data or {}
	end

	cache.data = parse_fastfetch_data(raw_data)
	cache.timestamp = current_time

	return cache.data
end

function M.refresh()
	cache.data = nil
	cache.timestamp = 0
	return M.get_info()
end

function M.cleanup()
	if cache.data then
		for k in pairs(cache.data) do
			if type(cache.data[k]) == "table" then
				cache.data[k] = nil
			end
		end
		cache.data = nil
	end
	cache.timestamp = 0
	collectgarbage("collect")
end

return M
