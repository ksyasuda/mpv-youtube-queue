local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(
			(message or "values differ")
				.. string.format("\nexpected: %s\nactual: %s", tostring(expected), tostring(actual))
		)
	end
end

local function assert_nil(value, message)
	if value ~= nil then
		error((message or "expected nil") .. string.format("\nactual: %s", tostring(value)))
	end
end

local function assert_falsy(value, message)
	if value then
		error(message or "expected falsy value")
	end
end

local function load_script()
	local bindings = {}
	local mp_stub = {
		get_property = function()
			return ""
		end,
		get_property_number = function(_, default)
			return default
		end,
		set_property_number = function() end,
		set_osd_ass = function() end,
		osd_message = function() end,
		add_periodic_timer = function()
			return {
				kill = function() end,
				resume = function() end,
			}
		end,
		add_timeout = function()
			return {
				kill = function() end,
				resume = function() end,
			}
		end,
		add_key_binding = function(_, _, name)
			bindings[name] = true
		end,
		register_event = function() end,
		register_script_message = function() end,
		commandv = function() end,
		command_native_async = function(_, callback)
			if callback then
				callback(false, nil, "not implemented in tests")
			end
		end,
		command_native = function()
			return {
				status = 0,
				stdout = "",
			}
		end,
	}

	package.loaded["mp"] = nil
	package.loaded["mp.options"] = nil
	package.loaded["mp.utils"] = nil
	package.loaded["mp.assdraw"] = nil
	package.loaded["app"] = nil
	package.loaded["history_client"] = nil
	package.loaded["input"] = nil
	package.loaded["json"] = nil
	package.loaded["shell"] = nil
	package.loaded["state"] = nil
	package.loaded["ui"] = nil
	package.loaded["video_store"] = nil

	package.preload["mp"] = function()
		return mp_stub
	end

	package.preload["mp.options"] = function()
		return {
			read_options = function() end,
		}
	end

	package.preload["mp.utils"] = function()
		return {
			file_info = function()
				return nil
			end,
			split_path = function(path)
				return path:match("^(.*[/\\])(.-)$")
			end,
			parse_json = function()
				return nil
			end,
		}
	end

	package.preload["mp.assdraw"] = function()
		return {
			ass_new = function()
				return {
					text = "",
					append = function(self, value)
						self.text = self.text .. value
					end,
				}
			end,
		}
	end

	local chunk = assert(loadfile("mpv-youtube-queue/main.lua"))
	return chunk(), bindings
end

local script, bindings = load_script()

assert_nil(script.YouTubeQueue.save_queue, "queue save API should be removed")
assert_nil(script.YouTubeQueue.load_queue, "queue load API should be removed")
assert_falsy(bindings.save_queue, "save_queue binding should be removed")
assert_falsy(bindings.save_queue_alt, "save_queue_alt binding should be removed")
assert_falsy(bindings.load_queue, "load_queue binding should be removed")
assert_equal(type(script.YouTubeQueue.add_to_queue), "function", "queue add API should remain")
