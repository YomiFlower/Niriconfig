local astal = require("astal")
local cjson = require("cjson")
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")

local CACHE_DIR = GLib.get_user_cache_dir() .. "/astal"
local CACHE_FILE = CACHE_DIR .. "/github-events.json"
local CACHE_MAX_SIZE = 1024 * 1024
local MAX_RETRIES = 3
local RETRY_DELAY = 10
local RATE_CHECK_INTERVAL = 900
local RATE_LIMIT_COOLDOWN = 3600

local state = {
	rate = {
		last_check = 0,
		status = true,
		remaining = 60,
		error_time = 0,
	},
	cache = {
		last_cleanup = 0,
		last_viewed = 0,
	},
}

local Github = {}

local config_path = debug.getinfo(1).source:match("@?(.*/)") .. "../../user-variables.lua"
local user_vars = loadfile(config_path)()

local function ensure_cache_dir()
	if not GLib.file_test(CACHE_DIR, "EXISTS") then
		GLib.mkdir_with_parents(CACHE_DIR, 0755)
	end
end

local function cleanup_cache()
	local current_time = os.time()
	if current_time - state.cache.last_cleanup < 3600 then
		return
	end

	if GLib.file_test(CACHE_FILE, "EXISTS") then
		local size = GLib.file_get_contents(CACHE_FILE)
		if size and #size > CACHE_MAX_SIZE then
			os.remove(CACHE_FILE)
		end
	end

	state.cache.last_cleanup = current_time
end

local function execute_curl(cmd)
	local handle = io.popen(cmd)
	if not handle then
		return nil
	end
	local result = handle:read("*a")
	handle:close()
	return result
end

local function load_cache()
	Debug.debug("GitHub", "Loading cached events")
	if not GLib.file_test(CACHE_FILE, "EXISTS") then
		return nil
	end

	local content = astal.read_file(CACHE_FILE)
	if not content then
		return nil
	end

	local decoded_ok, cache = pcall(cjson.decode, content)
	if not decoded_ok or type(cache) ~= "table" then
		return nil
	end

	return cache.events, cache.last_update or 0
end

local function save_cache(events)
	if not events or type(events) ~= "table" then
		return false
	end
	ensure_cache_dir()
	cleanup_cache()

	local cache = {
		last_update = os.time(),
		events = events,
	}

	local encoded_ok, encoded = pcall(cjson.encode, cache)
	if not encoded_ok then
		return false
	end

	local temp_file = CACHE_FILE .. ".tmp"
	if not pcall(function()
		astal.write_file(temp_file, encoded)
	end) then
		pcall(os.remove, temp_file)
		return false
	end

	if not pcall(function()
		os.rename(temp_file, CACHE_FILE)
	end) then
		pcall(os.remove, temp_file)
		return false
	end
	return true
end

local function check_rate_limit()
	local current_time = os.time()

	if current_time - state.rate.error_time < RATE_LIMIT_COOLDOWN then
		Debug.debug("GitHub", "In rate limit cooldown period")
		return false
	end

	if current_time - state.rate.last_check < RATE_CHECK_INTERVAL then
		Debug.debug("GitHub", "Using cached rate limit status (remaining: %d)", state.rate.remaining)
		return state.rate.status
	end

	local rate_limit_check = execute_curl(table.concat({
		"curl -s --connect-timeout 3 --max-time 5",
		"https://api.github.com/rate_limit",
		"-H 'Accept: application/vnd.github+json'",
	}, " "))

	if not rate_limit_check then
		Debug.warn("GitHub", "Rate limit check failed")
		state.rate.error_time = current_time
		return false
	end

	local rate_ok, rate_data = pcall(cjson.decode, rate_limit_check)
	if not rate_ok or not rate_data or not rate_data.resources or not rate_data.resources.core then
		Debug.warn("GitHub", "Invalid rate limit response")
		state.rate.error_time = current_time
		return false
	end

	local remaining = rate_data.resources.core.remaining
	state.rate.remaining = remaining
	state.rate.last_check = current_time

	if remaining < 10 then
		Debug.warn("GitHub", "Rate limit low")
		state.rate.error_time = current_time
		state.rate.status = false
		return false
	end

	state.rate.status = true
	return true
end

local function fetch_github_events(username, attempt)
	attempt = attempt or 1
	if attempt > MAX_RETRIES then
		Debug.warn("GitHub", "Max retries reached")
		return nil, "max_retries"
	end

	if not check_rate_limit() then
		Debug.warn("GitHub", "Rate limit exceeded")
		return nil, "rate_limit"
	end

	local url = string.format("https://api.github.com/users/%s/received_events", username)
	local output = execute_curl(table.concat({
		"curl -s -S --connect-timeout 3 --max-time 5 --compressed",
		"-H 'Accept: application/json'",
		"-H 'Accept-Encoding: gzip, deflate, br'",
		"-H 'User-Agent: astal-bar'",
		"-H 'Connection: keep-alive'",
		"'" .. url .. "'",
	}, " "))

	if not output then
		if attempt < MAX_RETRIES then
			astal.sleep(RETRY_DELAY * (2 ^ (attempt - 1)))
			return fetch_github_events(username, attempt + 1)
		end
		return nil, "network_error"
	end

	local parse_ok, events = pcall(cjson.decode, output)
	if not parse_ok or type(events) ~= "table" then
		Debug.error("GitHub", "Parse error: %s", parse_ok and "invalid format" or events)
		return nil, "parse_error"
	end

	return events
end

function Github.get_events()
	local cached_events, last_update = load_cache()

	if cached_events then
		return cached_events, last_update
	end

	return Github.update_events()
end

function Github.update_events()
	Debug.debug("GitHub", "Fetching new GitHub events")

	if os.time() - state.rate.error_time < RATE_LIMIT_COOLDOWN then
		Debug.warn("GitHub", "In rate limit cooldown")
		return {}, 0
	end

	local username = user_vars.github and user_vars.github.username or "linuxmobile"
	local events = fetch_github_events(username)
	local current_time = os.time()

	if events and #events > 0 then
		save_cache(events)
		return events, current_time
	end

	return {}, 0
end

function Github.get_last_update_time()
	local _, timestamp = load_cache()
	return timestamp or 0
end

function Github.mark_viewed()
	state.cache.last_viewed = os.time()
end

function Github.format_time(iso_time)
	if not iso_time then
		return "unknown time"
	end

	local timestamp = GLib.DateTime.new_from_iso8601(iso_time, nil)
	if not timestamp then
		return "invalid time"
	end

	local diff = GLib.DateTime.new_now_local():difference(timestamp) / 1000000

	if diff < 60 then
		return "just now"
	elseif diff < 3600 then
		return string.format("%d minutes ago", math.floor(diff / 60))
	elseif diff < 86400 then
		return string.format("%d hours ago", math.floor(diff / 3600))
	else
		return string.format("%d days ago", math.floor(diff / 86400))
	end
end

function Github.format_last_update(timestamp)
	if not timestamp or timestamp == 0 then
		return "Never updated"
	end

	local diff = os.time() - timestamp

	if diff < 60 then
		return "Updated just now"
	elseif diff < 3600 then
		return string.format("Updated %d minutes ago", math.floor(diff / 60))
	elseif diff < 86400 then
		return string.format("Updated %d hours ago", math.floor(diff / 3600))
	else
		return string.format("Updated %d days ago", math.floor(diff / 86400))
	end
end

return Github
