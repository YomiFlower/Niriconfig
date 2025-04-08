local astal = require("astal")
local Variable = require("astal.variable")
local Debug = require("lua.lib.debug")
local GLib = require("lgi").GLib

local Vitals = {}

local cache = {
	cpu = { value = 0, timestamp = 0 },
	ram = { value = 0, timestamp = 0 },
	prev_cpu_values = nil,
	cache_lifetime = 500,
}

local function parse_cpu_stats(content)
	if not content then
		return nil
	end
	local cpu_line = content:match("^cpu%s+(%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+)")
	if not cpu_line then
		return nil
	end

	local values = {}
	for v in cpu_line:gmatch("%d+") do
		values[#values + 1] = tonumber(v) or 0
	end
	return values
end

local function parse_mem_stats(content)
	if not content then
		return nil
	end

	local stats = {
		total = tonumber(content:match("MemTotal:%s+(%d+)")) or 0,
		free = tonumber(content:match("MemFree:%s+(%d+)")) or 0,
		buffers = tonumber(content:match("Buffers:%s+(%d+)")) or 0,
		cached = tonumber(content:match("Cached:%s+(%d+)")) or 0,
	}

	if stats.total == 0 then
		return nil
	end
	return stats
end

function Vitals:calculate_cpu_usage()
	local current_time = GLib.get_monotonic_time() / 1000
	if current_time - (cache.cpu.timestamp or 0) < cache.cache_lifetime then
		return cache.cpu.value or 0
	end

	local content = astal.read_file("/proc/stat")
	if not content then
		Debug.error("Vitals", "Failed to read /proc/stat")
		return cache.cpu.value or 0
	end

	local values = parse_cpu_stats(content)
	if not values or not values[1] or not values[2] or not values[3] or not values[4] or not values[5] then
		Debug.error("Vitals", "Failed to parse CPU stats")
		return cache.cpu.value or 0
	end

	if not cache.prev_cpu_values then
		cache.prev_cpu_values = values
		cache.cpu.value = 0
		cache.cpu.timestamp = current_time
		return 0
	end

	local prev = cache.prev_cpu_values
	if not prev or not prev[1] or not prev[2] or not prev[3] or not prev[4] or not prev[5] then
		cache.prev_cpu_values = values
		cache.cpu.value = 0
		cache.cpu.timestamp = current_time
		return 0
	end

	local curr_total = (values[1] or 0) + (values[2] or 0) + (values[3] or 0) + (values[4] or 0) + (values[5] or 0)
	local prev_total = (prev[1] or 0) + (prev[2] or 0) + (prev[3] or 0) + (prev[4] or 0) + (prev[5] or 0)
	local total_delta = curr_total - prev_total

	if total_delta <= 0 then
		cache.prev_cpu_values = values
		return cache.cpu.value or 0
	end

	local curr_idle = (values[4] or 0) + (values[5] or 0)
	local prev_idle = (prev[4] or 0) + (prev[5] or 0)
	local idle_delta = curr_idle - prev_idle

	cache.prev_cpu_values = values
	cache.cpu.value = math.floor(((total_delta - idle_delta) / total_delta) * 100 + 0.5)
	cache.cpu.timestamp = current_time

	return cache.cpu.value or 0
end

function Vitals:calculate_ram_usage()
	local current_time = GLib.get_monotonic_time() / 1000
	if current_time - (cache.ram.timestamp or 0) < cache.cache_lifetime then
		return cache.ram.value or 0
	end

	local content = astal.read_file("/proc/meminfo")
	if not content then
		Debug.error("Vitals", "Failed to read /proc/meminfo")
		return cache.ram.value or 0
	end

	local stats = parse_mem_stats(content)
	if not stats or not stats.total or not stats.free or not stats.buffers or not stats.cached then
		Debug.error("Vitals", "Failed to parse memory stats")
		return cache.ram.value or 0
	end

	if stats.total == 0 then
		return cache.ram.value or 0
	end

	local used = (stats.total or 0) - (stats.free or 0) - (stats.buffers or 0) - (stats.cached or 0)
	cache.ram.value = math.floor((used / stats.total) * 100 + 0.5)
	cache.ram.timestamp = current_time

	return cache.ram.value or 0
end

function Vitals:New()
	local instance = {
		cpu_usage = Variable(0):poll(1000, function()
			return self:calculate_cpu_usage()
		end),
		memory_usage = Variable(0):poll(1000, function()
			return self:calculate_ram_usage()
		end),
		disk_usage = Variable(0),
		temperature = Variable(0),
	}

	astal.monitor_file("/proc/stat", function()
		if instance and instance.cpu_usage then
			instance.cpu_usage:set(self:calculate_cpu_usage())
		end
	end)

	astal.monitor_file("/proc/meminfo", function()
		if instance and instance.memory_usage then
			instance.memory_usage:set(self:calculate_ram_usage())
		end
	end)

	setmetatable(instance, self)
	self.__index = self
	return instance
end

function Vitals:start_monitoring()
	if self.cpu_usage then
		self.cpu_usage:start_poll()
	end
	if self.memory_usage then
		self.memory_usage:start_poll()
	end
end

function Vitals:stop_monitoring()
	if self.cpu_usage then
		self.cpu_usage:stop_poll()
	end
	if self.memory_usage then
		self.memory_usage:stop_poll()
	end
end

local instance

function Vitals.get_default()
	if not instance then
		instance = Vitals:New()
		instance:start_monitoring()
	end
	return instance
end

return Vitals
