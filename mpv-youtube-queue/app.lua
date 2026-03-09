local history_client = require("history_client")
local input = require("input")
local shell = require("shell")
local state = require("state")
local ui = require("ui")
local video_store = require("video_store")

local App = {}

local MSG_DURATION = 1.5
local options = {
	add_to_queue = "ctrl+a",
	download_current_video = "ctrl+d",
	download_selected_video = "ctrl+D",
	move_cursor_down = "ctrl+j",
	move_cursor_up = "ctrl+k",
	move_video = "ctrl+m",
	play_next_in_queue = "ctrl+n",
	open_video_in_browser = "ctrl+o",
	open_channel_in_browser = "ctrl+O",
	play_previous_in_queue = "ctrl+p",
	print_current_video = "ctrl+P",
	print_queue = "ctrl+q",
	remove_from_queue = "ctrl+x",
	play_selected_video = "ctrl+ENTER",
	browser = "firefox",
	clipboard_command = "xclip -o",
	cursor_icon = "➤",
	display_limit = 10,
	download_directory = "~/videos/YouTube",
	download_quality = "720p",
	downloader = "curl",
	font_name = "JetBrains Mono",
	font_size = 12,
	marked_icon = "⇅",
	menu_timeout = 5,
	show_errors = true,
	ytdlp_file_format = "mp4",
	ytdlp_output_template = "%(uploader)s/%(title)s.%(ext)s",
	use_history_db = false,
	backend_host = "http://localhost",
	backend_port = "42069",
	max_title_length = 60,
}

local function normalize_direction(direction)
	return direction and string.upper(direction) or "NEXT"
end

function App.new()
	local mp = require("mp")
	local utils = require("mp.utils")
	mp.options = require("mp.options")
	mp.options.read_options(options, "mpv-youtube-queue")

	local style_on = mp.get_property("osd-ass-cc/0") or ""
	local style_off = mp.get_property("osd-ass-cc/1") or ""
	local renderer = ui.create(options)

	local app = {
		video_queue = {},
		index = 0,
		selected_index = 1,
		marked_index = nil,
		current_video = nil,
		destroyer = nil,
		timeout = nil,
	}

	local function sync_current_video()
		app.current_video = app.index > 0 and app.video_queue[app.index] or nil
	end

	local function destroy()
		if app.timeout then
			app.timeout:kill()
		end
		mp.set_osd_ass(0, 0, "")
		app.destroyer = nil
	end

	local function print_osd_message(message, duration, is_error)
		if is_error and not options.show_errors then
			return
		end
		destroy()
		local formatted = style_on
			.. renderer:message_style(is_error)
			.. message
			.. renderer.styles.reset
			.. style_off
			.. "\n"
		mp.osd_message(formatted, duration or MSG_DURATION)
	end
	local videos = video_store.new({
		mp = mp,
		utils = utils,
		options = options,
		notify = print_osd_message,
	})
	local history_api = history_client.new({
		mp = mp,
		options = options,
		notify = print_osd_message,
	})
	local runner = shell.new({
		mp = mp,
		options = options,
		notify = print_osd_message,
		is_file = function(path)
			return videos:is_file(path)
		end,
	})

	local function update_current_index()
		if #app.video_queue == 0 then
			app.index = 0
			app.selected_index = 1
			app.current_video = nil
			return
		end

		local current_url = mp.get_property("path")
		for i, video in ipairs(app.video_queue) do
			if video.video_url == current_url then
				app.index = i
				app.selected_index = i
				app.current_video = video
				return
			end
		end

		app.index = 0
		app.current_video = nil
	end

	local function print_queue(duration)
		if app.timeout then
			app.timeout:kill()
			app.timeout:resume()
		end
		mp.set_osd_ass(0, 0, "")

		if #app.video_queue == 0 then
			print_osd_message("No videos in the queue.", duration, true)
			app.destroyer = destroy
			return
		end

		mp.set_osd_ass(0, 0, renderer:render_queue(app.video_queue, app.index, app.selected_index, app.marked_index))
		if duration then
			mp.add_timeout(duration, destroy)
		end
		app.destroyer = destroy
	end

	local function sync_with_playlist()
		app.video_queue = videos:sync_playlist()
		update_current_index()
		if #app.video_queue > 0 and app.selected_index > #app.video_queue then
			app.selected_index = #app.video_queue
		end
		return #app.video_queue > 0
	end

	function app.get_video_at(idx)
		if idx <= 0 or idx > #app.video_queue then
			print_osd_message("Invalid video index", MSG_DURATION, true)
			return nil
		end
		return app.video_queue[idx]
	end

	function app.print_current_video()
		destroy()
		local current = app.current_video
		if not current then
			return
		end
		if current.video_url ~= "" and videos:is_file(current.video_url) then
			print_osd_message("Playing: " .. current.video_url, 3, false)
			return
		end
		print_osd_message("Playing: " .. current.video_name .. " by " .. current.channel_name, 3, false)
	end

	function app.set_video(direction)
		local normalized = normalize_direction(direction)
		if normalized ~= "NEXT" and normalized ~= "PREV" and normalized ~= "PREVIOUS" then
			print_osd_message("Invalid direction: " .. tostring(direction), MSG_DURATION, true)
			return nil
		end
		local delta = 1
		if normalized == "PREV" or normalized == "PREVIOUS" then
			delta = -1
		end
		if app.index + delta > #app.video_queue or app.index + delta < 1 then
			return nil
		end
		app.index = app.index + delta
		app.selected_index = app.index
		sync_current_video()
		return app.current_video
	end

	function app.is_in_queue(url)
		for _, video in ipairs(app.video_queue) do
			if video.video_url == url then
				return true
			end
		end
		return false
	end

	function app.mark_and_move_video()
		if app.marked_index == nil and app.selected_index ~= app.index then
			app.marked_index = app.selected_index
		elseif app.marked_index ~= nil then
			app.reorder_queue(app.marked_index, app.selected_index)
			app.marked_index = nil
		end
		print_queue()
	end

	function app.reorder_queue(from_index, to_index)
		local ok, result = pcall(state.reorder_queue, {
			queue = app.video_queue,
			current_index = app.index,
			selected_index = app.selected_index,
			marked_index = app.marked_index,
			from_index = from_index,
			to_index = to_index,
		})
		if not ok then
			print_osd_message("Invalid indices for reordering. No changes made.", MSG_DURATION, true)
			return false
		end

		mp.commandv("playlist-move", result.mpv_from, result.mpv_to)
		app.video_queue = result.queue
		app.index = result.current_index
		app.selected_index = result.selected_index
		app.marked_index = result.marked_index
		sync_current_video()
		return true
	end

	function app.print_queue(duration)
		print_queue(duration)
	end

	function app.move_cursor(amount)
		if app.timeout then
			app.timeout:kill()
			app.timeout:resume()
		end
		app.selected_index = app.selected_index - amount
		if #app.video_queue == 0 then
			app.selected_index = 1
		else
			app.selected_index = math.max(1, math.min(app.selected_index, #app.video_queue))
		end
		print_queue()
	end

	function app.play_video_at(idx)
		if idx <= 0 or idx > #app.video_queue then
			print_osd_message("Invalid video index", MSG_DURATION, true)
			return nil
		end
		app.index = idx
		app.selected_index = idx
		sync_current_video()
		mp.set_property_number("playlist-pos", idx - 1)
		app.print_current_video()
		return app.current_video
	end

	function app.play_video(direction)
		local video = app.set_video(direction)
		if not video then
			print_osd_message("No video available.", MSG_DURATION, true)
			return
		end
		if mp.get_property_number("playlist-count", 0) == 0 then
			mp.commandv("loadfile", video.video_url, "replace")
		else
			mp.set_property_number("playlist-pos", app.index - 1)
		end
		app.print_current_video()
	end

	function app.add_to_queue(url, update_internal_playlist)
		local source = videos:normalize_source(input.sanitize_source(url))
		if not source or source == "" then
			source = videos:get_clipboard_content()
			if not source then
				return nil
			end
		end
		if app.is_in_queue(source) then
			print_osd_message("Video already in queue.", MSG_DURATION, true)
			return nil
		end

		local video = videos:resolve_video(source)
		if not video then
			print_osd_message("Error getting video info.", MSG_DURATION, true)
			return nil
		end

		table.insert(app.video_queue, video)
		if not app.current_video then
			app.index = #app.video_queue
			app.selected_index = app.index
			app.current_video = video
			mp.commandv("loadfile", source, "replace")
		elseif update_internal_playlist == nil or update_internal_playlist == 0 then
			mp.commandv("loadfile", source, "append-play")
		end
		print_osd_message("Added " .. video.video_name .. " to queue.", MSG_DURATION, false)
		return video
	end

	function app.download_video_at(idx)
		if idx <= 0 or idx > #app.video_queue then
			return false
		end
		local video = app.video_queue[idx]
		return runner:download_video(video)
	end

	function app.remove_from_queue()
		if app.index == app.selected_index then
			print_osd_message("Cannot remove current video", MSG_DURATION, true)
			return false
		end

		local removed_index = app.selected_index
		local removed_video = app.video_queue[app.selected_index]
		local result = state.remove_queue_item({
			queue = app.video_queue,
			current_index = app.index,
			selected_index = app.selected_index,
			marked_index = app.marked_index,
		})
		app.video_queue = result.queue
		app.index = result.current_index
		app.selected_index = result.selected_index
		app.marked_index = result.marked_index
		mp.commandv("playlist-remove", removed_index - 1)
		sync_current_video()
		if removed_video then
			print_osd_message("Deleted " .. removed_video.video_name .. " from queue.", MSG_DURATION, false)
		end
		print_queue()
		return true
	end

	function app.sync_with_playlist()
		return sync_with_playlist()
	end

	local function toggle_print()
		if app.destroyer then
			app.destroyer()
			return
		end
		print_queue()
	end

	local function open_video_in_browser()
		if app.current_video then
			runner:open_in_browser(app.current_video.video_url)
		end
	end

	local function open_channel_in_browser()
		if app.current_video and app.current_video.channel_url ~= "" then
			runner:open_in_browser(app.current_video.channel_url)
		end
	end

	local function on_end_file(event)
		if event.reason == "eof" and app.current_video then
			history_api:add_video(app.current_video)
		end
	end

	local function on_track_changed()
		update_current_index()
	end

	local function on_file_loaded()
		sync_with_playlist()
		update_current_index()
	end

	app.timeout = mp.add_periodic_timer(options.menu_timeout, destroy)

	mp.add_key_binding(options.add_to_queue, "add_to_queue", app.add_to_queue)
	mp.add_key_binding(options.play_next_in_queue, "play_next_in_queue", function()
		app.play_video("NEXT")
	end)
	mp.add_key_binding(options.play_previous_in_queue, "play_prev_in_queue", function()
		app.play_video("PREV")
	end)
	mp.add_key_binding(options.print_queue, "print_queue", toggle_print)
	mp.add_key_binding(options.move_cursor_up, "move_cursor_up", function()
		app.move_cursor(1)
	end, { repeatable = true })
	mp.add_key_binding(options.move_cursor_down, "move_cursor_down", function()
		app.move_cursor(-1)
	end, { repeatable = true })
	mp.add_key_binding(options.play_selected_video, "play_selected_video", function()
		app.play_video_at(app.selected_index)
	end)
	mp.add_key_binding(options.open_video_in_browser, "open_video_in_browser", open_video_in_browser)
	mp.add_key_binding(options.print_current_video, "print_current_video", app.print_current_video)
	mp.add_key_binding(options.open_channel_in_browser, "open_channel_in_browser", open_channel_in_browser)
	mp.add_key_binding(options.download_current_video, "download_current_video", function()
		app.download_video_at(app.index)
	end)
	mp.add_key_binding(options.download_selected_video, "download_selected_video", function()
		app.download_video_at(app.selected_index)
	end)
	mp.add_key_binding(options.move_video, "move_video", app.mark_and_move_video)
	mp.add_key_binding(options.remove_from_queue, "delete_video", app.remove_from_queue)

	mp.register_event("end-file", on_end_file)
	mp.register_event("track-changed", on_track_changed)
	mp.register_event("file-loaded", on_file_loaded)

	mp.register_script_message("add_to_queue", app.add_to_queue)
	mp.register_script_message("print_queue", app.print_queue)
	mp.register_script_message("add_to_youtube_queue", app.add_to_queue)
	mp.register_script_message("toggle_youtube_queue", toggle_print)
	mp.register_script_message("print_internal_playlist", function()
		local count = mp.get_property_number("playlist-count", 0)
		print("Playlist contents:")
		for i = 0, count - 1 do
			print(string.format("%d: %s", i, mp.get_property(string.format("playlist/%d/filename", i))))
		end
	end)
	mp.register_script_message("reorder_youtube_queue", function(from_index, to_index)
		app.reorder_queue(from_index, to_index)
	end)

	app.YouTubeQueue = app
	app._test = {
		snapshot_queue = function()
			local snapshot = {}
			for i, item in ipairs(app.video_queue) do
				local copied = {}
				for key, value in pairs(item) do
					copied[key] = value
				end
				snapshot[i] = copied
			end
			return snapshot
		end,
	}

	return app
end

return App
