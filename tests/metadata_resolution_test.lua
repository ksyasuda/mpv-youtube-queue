local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(
			(message or "values differ")
				.. string.format("\nexpected: %s\nactual: %s", tostring(expected), tostring(actual))
		)
	end
end

local function assert_truthy(value, message)
	if not value then
		error(message or "expected truthy value")
	end
end

local function load_script(config)
	config = config or {}
	local events = {}
	local command_native_calls = 0
	local properties = config.properties or {}
	local property_numbers = config.property_numbers or {}
	local json_map = config.json_map or {}

	local mp_stub = {
		get_property = function(name)
			return properties[name]
		end,
		get_property_number = function(name)
			return property_numbers[name]
		end,
		set_property_number = function(name, value)
			property_numbers[name] = value
		end,
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
		add_key_binding = function() end,
		register_event = function(name, handler)
			events[name] = handler
		end,
		add_hook = function() end,
		register_script_message = function() end,
		commandv = function() end,
		command_native_async = function(_, callback)
			if callback then
				callback(false, nil, "not implemented in tests")
			end
		end,
		command_native = function(command)
			if command.name == "subprocess" and command.args and command.args[1] == "yt-dlp" then
				command_native_calls = command_native_calls + 1
				if config.subprocess_result then
					return config.subprocess_result(command_native_calls, command)
				end
				return {
					status = 1,
					stdout = "",
				}
			end
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
	package.loaded["history"] = nil
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
			file_info = function(path)
				if path and path:match("^/") then
					return { is_file = true }
				end
				return nil
			end,
			split_path = function(path)
				return path:match("^(.*[/\\])(.-)$")
			end,
			parse_json = function(payload)
				return json_map[payload]
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
	local script = chunk()

	return {
		events = events,
		script = script,
		get_ytdlp_calls = function()
			return command_native_calls
		end,
		set_property = function(name, value)
			properties[name] = value
		end,
	}
end

local unsupported = load_script({
	properties = {
		["osd-ass-cc/0"] = "",
		["osd-ass-cc/1"] = "",
		["path"] = "https://jellyfin.example/items/1",
		["media-title"] = "Jellyfin Episode 1",
		["playlist/0/filename"] = "https://jellyfin.example/items/1",
	},
	property_numbers = {
		["playlist-count"] = 1,
	},
	subprocess_result = function()
		return {
			status = 1,
			stdout = "",
		}
	end,
})

assert_truthy(unsupported.script and unsupported.script._test, "script test helpers should be returned")
unsupported.events["file-loaded"]()

local queue = unsupported.script._test.snapshot_queue()
assert_equal(#queue, 1, "unsupported stream should be queued")
assert_equal(queue[1].video_name, "Jellyfin Episode 1", "fallback metadata should prefer media-title")
assert_equal(unsupported.get_ytdlp_calls(), 1, "first sync should try extractor once")

assert_equal(unsupported.events["playback-restart"], nil, "playback-restart import hook should be removed")
assert_equal(unsupported.get_ytdlp_calls(), 1, "seeking should not retry extractor metadata lookup")

unsupported.script.YouTubeQueue.sync_with_playlist()
assert_equal(unsupported.get_ytdlp_calls(), 1, "cached fallback metadata should prevent repeated extractor calls")

local supported = load_script({
	properties = {
		["osd-ass-cc/0"] = "",
		["osd-ass-cc/1"] = "",
		["path"] = "https://youtube.example/watch?v=abc",
		["playlist/0/filename"] = "https://youtube.example/watch?v=abc",
	},
	property_numbers = {
		["playlist-count"] = 1,
	},
	json_map = {
		supported = {
			channel_url = "https://youtube.example/channel/demo",
			uploader = "Demo Channel",
			title = "Supported Video",
			view_count = 42,
			upload_date = "20260306",
			categories = { "Music" },
			thumbnail = "https://img.example/thumb.jpg",
			channel_follower_count = 1000,
		},
	},
	subprocess_result = function()
		return {
			status = 0,
			stdout = "supported",
		}
	end,
})

supported.script.YouTubeQueue.sync_with_playlist()
local supported_queue = supported.script._test.snapshot_queue()
assert_equal(supported_queue[1].video_name, "Supported Video", "supported urls should keep extractor metadata")
assert_equal(supported.get_ytdlp_calls(), 1, "supported url should call extractor once")

supported.script.YouTubeQueue.sync_with_playlist()
assert_equal(supported.get_ytdlp_calls(), 1, "supported url should reuse cached extractor metadata")

local multi_remote = load_script({
	properties = {
		["osd-ass-cc/0"] = "",
		["osd-ass-cc/1"] = "",
		["path"] = "https://example.test/watch?v=first",
		["playlist/0/filename"] = "https://example.test/watch?v=first",
		["playlist/0/title"] = "Title A mpv",
		["playlist/1/filename"] = "https://example.test/watch?v=second",
		["playlist/1/title"] = "Title B mpv",
	},
	property_numbers = {
		["playlist-count"] = 2,
	},
	json_map = {
		first = {
			channel_url = "https://example.test/channel/a",
			uploader = "Channel A",
			title = "Extractor A",
		},
		second = {
			channel_url = "https://example.test/channel/b",
			uploader = "Channel B",
			title = "Extractor B",
		},
	},
	subprocess_result = function(call_count)
		if call_count == 1 then
			return { status = 0, stdout = "first" }
		end
		return { status = 0, stdout = "second" }
	end,
})

multi_remote.events["file-loaded"]()
local first_pass = multi_remote.script._test.snapshot_queue()
assert_equal(first_pass[1].video_name, "Extractor A", "first current item should resolve extractor metadata")
assert_equal(first_pass[2].video_name, "Title B mpv", "later items can start as placeholders")

assert_equal(multi_remote.events["playback-restart"], nil, "playback-restart import hook should stay removed")
assert_equal(multi_remote.get_ytdlp_calls(), 1, "playback restart should not trigger playlist resync")

multi_remote.set_property("path", "https://example.test/watch?v=second")
multi_remote.events["file-loaded"]()
local second_pass = multi_remote.script._test.snapshot_queue()
assert_equal(second_pass[2].video_name, "Extractor B", "current item should upgrade when it loads")
assert_equal(multi_remote.get_ytdlp_calls(), 2, "each remote item should resolve at most once when current")

print("ok")
