local astal = require("astal")
local Variable = require("astal").Variable
local Gtk = require("astal.gtk3").Gtk
local GLib = astal.require("GLib")
local Debug = require("lua.lib.debug")

local M = {}

function M.src(path)
	if not path then
		Debug.error("Common", "No path provided for src")
		return nil
	end
	local str = debug.getinfo(2, "S").source:sub(2)
	local src = str:match("(.*/)") or str:match("(.*\\)") or "./"
	return src .. path
end

function M.map(array, func)
	if not array then
		Debug.error("Common", "Nil array passed to map")
		return {}
	end
	local new_arr = {}
	for i, v in ipairs(array) do
		new_arr[i] = func(v, i)
	end
	return new_arr
end

function M.file_exists(path)
	if not path then
		Debug.error("Common", "No path provided for file_exists")
		return false
	end
	return GLib.file_test(path, "EXISTS")
end

function M.varmap(initial)
	if not initial then
		Debug.error("Common", "No initial value provided for varmap")
		initial = {}
	end

	local map = initial
	local var = Variable({})

	local function notify()
		local arr = {}
		for _, value in pairs(map) do
			table.insert(arr, value)
		end
		var:set(arr)
	end

	local function delete(key)
		if not key then
			Debug.error("Common", "No key provided for varmap delete")
			return
		end

		if Gtk.Widget:is_type_of(map[key]) then
			map[key]:destroy()
		end

		map[key] = nil
	end

	notify()

	return setmetatable({
		set = function(key, value)
			if not key then
				Debug.error("Common", "No key provided for varmap set")
				return
			end
			delete(key)
			map[key] = value
			notify()
		end,
		delete = function(key)
			delete(key)
			notify()
		end,
		get = function()
			return var:get()
		end,
		subscribe = function(callback)
			if not callback then
				Debug.error("Common", "No callback provided for varmap subscribe")
				return nil
			end
			return var:subscribe(callback)
		end,
		drop = function()
			var:drop()
		end,
	}, {
		__call = function()
			return var()
		end,
	})
end

function M.time(time, format)
	if not time then
		Debug.error("Common", "No time provided for formatting")
		return ""
	end
	format = format or "%H:%M"
	local success, datetime = pcall(function()
		return GLib.DateTime.new_from_unix_local(time):format(format)
	end)
	if not success then
		Debug.error("Common", "Failed to format time")
		return ""
	end
	return datetime
end

return M
