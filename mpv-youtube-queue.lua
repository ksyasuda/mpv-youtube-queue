-- mpv-youtube-queue.lua
--
-- YouTube 'Add To Queue' for mpv
--
-- Copyright (C) 2023 sudacode
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
local mp = require 'mp'
mp.options = require 'mp.options'
local styleOn = mp.get_property("osd-ass-cc/0")
local styleOff = mp.get_property("osd-ass-cc/1")

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
    display_limit = 6,
    download_directory = "~/videos/YouTube",
    download_quality = "720p",
    downloader = "curl",
    font_name = "JetBrains Mono",
    font_size = 12,
    marked_icon = "⇅",
    show_errors = true,
    ytdlp_file_format = "mp4",
    ytdlp_output_template = "%(uploader)s/%(title)s.%(ext)s"
}

mp.options.read_options(options, "mpv-youtube-queue")

local colors = {
    error = "676EFF",
    selected = "F993BD",
    hover_selected = "FAA9CA",
    cursor = "FDE98B",
    header = "8CFAF1",
    hover = "F2F8F8",
    text = "BFBFBF",
    marked = "C679FF"
}

local notransparent = "\\alpha&H00&"
local semitransparent = "\\alpha&H40&"
local sortoftransparent = "\\alpha&H59&"

local style = {
    error = "{\\c&" .. colors.error .. "&" .. notransparent .. "}",
    selected = "{\\c&" .. colors.selected .. "&" .. semitransparent .. "}",
    hover_selected = "{\\c&" .. colors.hover_selected .. "&\\alpha&H33&}",
    cursor = "{\\c&" .. colors.cursor .. "&" .. notransparent .. "}",
    marked = "{\\c&" .. colors.marked .. "&" .. notransparent .. "}",
    reset = "{\\c&" .. colors.text .. "&" .. sortoftransparent .. "}",
    header = "{\\fn" .. options.font_name .. "\\fs" .. options.font_size * 1.5 ..
        "\\u1\\b1\\c&" .. colors.header .. "&" .. notransparent .. "}",
    hover = "{\\c&" .. colors.hover .. "&" .. semitransparent .. "}",
    font = "{\\fn" .. options.font_name .. "\\fs" .. options.font_size .. "{" ..
        sortoftransparent .. "}"
}

local YouTubeQueue = {}
local video_queue = {}
local MSG_DURATION = 1.5
local display_limit = options.display_limit
local index = 0
local selected_index = 1
local display_offset = 0
local marked_index = nil
local current_video = nil

-- HELPERS {{{

-- surround string with single quotes
local function surround_with_quotes(s) return '\'' .. s .. '\'' end

-- run sleep shell command for n seconds
local function sleep(n) os.execute("sleep " .. tonumber(n)) end

-- returns true if the provided path exists and is a file
local function is_file(filepath)
    local result = os.execute("test -f " .. surround_with_quotes(filepath))
    return result
end

-- returns the filename given a path (e.g. /home/user/file.txt -> file.txt)
local function get_filename(filepath) return string.match(filepath, ".+/(.+)$") end

-- return the directory given a path (e.g. /home/user/file.txt -> /home/user)
local function get_directory(filepath)
    return surround_with_quotes(string.match(filepath, "(.+)/.+"))
end

local function print_osd_message(message, duration, s)
    if s == style.error and not options.show_errors then return end
    if s == nil then s = style.font .. "{" .. notransparent .. "}" end
    if duration == nil then duration = MSG_DURATION end
    mp.osd_message(styleOn .. s .. message .. style.reset .. styleOff .. "\n",
        duration)
end

local function print_current_video()
    local current = YouTubeQueue.get_current_video()
    print_osd_message("Playing: " .. current.video_name .. ' by ' ..
        current.channel_name, 3)
end

local function expanduser(path)
    -- remove trailing slash if it exists
    if string.sub(path, -1) == "/" then path = string.sub(path, 1, -2) end
    if path:sub(1, 1) == "~" then
        local home = os.getenv("HOME")
        if home then
            return home .. path:sub(2)
        else
            return path
        end
    else
        return path
    end
end

local function open_url_in_browser(url)
    local command = options.browser .. " " .. surround_with_quotes(url)
    os.execute(command)
end

local function open_video_in_browser()
    open_url_in_browser(YouTubeQueue.get_current_video().video_url)
end

local function open_channel_in_browser()
    open_url_in_browser(YouTubeQueue.get_current_video().channel_url)
end

-- local function is_valid_ytdlp_url(url)
--     local command = 'yt-dlp --simulate \'' .. url .. '\' >/dev/null 2>&1'
--     local handle = io.popen(command .. "; echo $?")
--     if handle == nil then return false end
--     local result = handle:read("*a")
--     if result == nil then return false end
--     handle:close()
--     return result:gsub("%s+$", "") == "0"
-- end

-- }}}

-- QUEUE GETTERS AND SETTERS {{{

function YouTubeQueue.size() return #video_queue end

function YouTubeQueue.get_current_index() return index end

function YouTubeQueue.get_video_queue() return video_queue end

function YouTubeQueue.set_current_index(idx)
    index = idx
    current_video = video_queue[idx]
end

function YouTubeQueue.get_current_video() return current_video end

function YouTubeQueue.get_video_at(idx)
    if idx <= 0 or idx > #video_queue then
        print_osd_message("Invalid video index", MSG_DURATION, style.error)
        return nil
    end
    return video_queue[idx]
end

-- returns the content of the clipboard
function YouTubeQueue.get_clipboard_content()
    local handle = io.popen(options.clipboard_command)
    if handle == nil then
        print_osd_message("Error getting clipboard content", MSG_DURATION,
            style.error)
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    return result
end

function YouTubeQueue.get_video_info(url)
    local command =
        'yt-dlp --print channel_url --print uploader --print title --playlist-items 1 ' ..
        surround_with_quotes(url)
    local handle = io.popen(command)
    if handle == nil then return nil, nil, nil end

    local result = handle:read("*a")
    handle:close()

    -- Split the result into URL, name, and video title
    local channel_url, channel_name, video_name = result:match(
        "(.-)\n(.-)\n(.*)")

    -- Remove trailing whitespace
    if channel_url ~= nil then channel_url = channel_url:gsub("%s+$", "") end
    if channel_name ~= nil then channel_name = channel_name:gsub("%s+$", "") end
    if video_name ~= nil then video_name = video_name:gsub("%s+$", "") end

    return channel_url, channel_name, video_name
end

-- }}}

-- QUEUE FUNCTIONS {{{
-- Function to get the next video in the queue
-- Returns nil if there are no videos in the queue
function YouTubeQueue.next_in_queue()
    if index < #video_queue then
        index = index + 1
        selected_index = index
        current_video = video_queue[index]
        return current_video
    end
end

function YouTubeQueue.prev_in_queue()
    if index > 1 then
        index = index - 1
        selected_index = index
        current_video = video_queue[index]
        return current_video
    end
end

function YouTubeQueue.is_in_queue(url)
    for _, v in ipairs(video_queue) do
        if v.video_url == url then return true end
    end
    return false
end

-- Function to find the index of the currently playing video
function YouTubeQueue.update_current_index()
    if #video_queue == 0 then return end
    local current_url = mp.get_property("path")
    for i, v in ipairs(video_queue) do
        if v.video_url == current_url then
            index = i
            selected_index = index
            current_video = YouTubeQueue.get_video_at(index)
            return
        end
    end
    -- if not found, reset the index
    index = 0
end

function YouTubeQueue.mark_and_move_video()
    if marked_index == nil and selected_index ~= index then
        -- Mark the currently selected video for moving
        marked_index = selected_index
    else
        -- Move the previously marked video to the selected position
        YouTubeQueue.reorder_queue(marked_index, selected_index)
        -- print_osd_message("Video moved to the selected position.", 1.5)
        marked_index = nil -- Reset the marked index
    end
    -- Refresh the queue display
    YouTubeQueue.print_queue()
end

function YouTubeQueue.reorder_queue(from_index, to_index)
    if from_index == to_index or to_index == index then
        print_osd_message("No changes made.", 1.5)
        return
    end
    -- Check if the provided indices are within the bounds of the video_queue
    if from_index > 0 and from_index <= #video_queue and to_index > 0 and
        to_index <= #video_queue then
        -- Swap the videos between the two provided indices in the video_queue
        local temp_video = video_queue[from_index]
        table.remove(video_queue, from_index)
        table.insert(video_queue, to_index, temp_video)

        -- Swap the videos between the two provided indices in the MPV playlist
        mp.commandv("playlist-move", from_index - 1, to_index - 1)

        -- Redraw the queue after reordering
        YouTubeQueue.print_queue()
    else
        print_osd_message("Invalid indices for reordering. No changes made.",
            MSG_DURATION, style.error)
    end
end

function YouTubeQueue.print_queue(duration)
    local current_index = index
    if duration == nil then duration = 3 end
    if #video_queue > 0 then
        local start_index = math.max(1, selected_index - display_limit / 2)
        local end_index =
            math.min(#video_queue, start_index + display_limit - 1)
        display_offset = start_index - 1

        local message =
            styleOn .. style.header .. "MPV-YOUTUBE-QUEUE{\\u0\\b0}" ..
            style.reset .. style.font .. "\n"
        for i = start_index, end_index do
            local prefix = (i == selected_index) and style.cursor ..
                options.cursor_icon .. " " .. style.reset or
                "   "
            if i == current_index and i == selected_index then
                message =
                    message .. prefix .. style.hover_selected .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset
            elseif i == current_index then
                message = message .. prefix .. style.selected .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset
            elseif i == selected_index then
                message = message .. prefix .. style.hover .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset
            else
                message = message .. prefix .. style.reset .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset
            end
            if i == marked_index then
                message =
                    message .. " " .. style.marked .. options.marked_icon ..
                    style.reset .. "\n"
            else
                message = message .. "\n"
            end
        end
        message = message .. styleOff
        mp.osd_message(message, duration)
    else
        print_osd_message("No videos in the queue or history.", duration,
            style.error)
    end
end

function YouTubeQueue.move_cursor_up()
    if selected_index > 1 then
        selected_index = selected_index - 1
        if selected_index < display_offset + 1 then
            display_offset = display_offset - 1
        end
        YouTubeQueue.print_queue(MSG_DURATION)
    end
end

function YouTubeQueue.move_cursor_down()
    if selected_index < YouTubeQueue.size() then
        selected_index = selected_index + 1
        if selected_index > display_offset + display_limit then
            display_offset = display_offset + 1
        end
        YouTubeQueue.print_queue(MSG_DURATION)
    end
end

function YouTubeQueue.play_video_at(idx)
    local queue = YouTubeQueue.get_video_queue()
    if idx <= 0 or idx > #queue then
        print_osd_message("Invalid video index", MSG_DURATION, style.error)
        return nil
    end
    YouTubeQueue.set_current_index(idx)
    selected_index = index
    mp.set_property_number("playlist-pos", index - 1) -- zero-based index
    return current_video
end

function YouTubeQueue.play_selected_video()
    -- local current_index = YouTubeQueue.get_current_index()
    YouTubeQueue.play_video_at(selected_index)
    YouTubeQueue.print_queue(MSG_DURATION - 0.5)
    sleep(MSG_DURATION)
    print_current_video()
end

-- play the next video in the queue
function YouTubeQueue.play_next_in_queue()
    local next_video = YouTubeQueue.next_in_queue()
    if next_video == nil then
        print_osd_message("No more videos in the queue.", MSG_DURATION,
            style.error)
        return
    end
    local current_index = YouTubeQueue.get_current_index()
    -- if the current video is not the first in the queue, then play the video
    -- else, check if the video is playing and if not play the video with replace
    if YouTubeQueue.size() > 1 then
        mp.set_property_number("playlist-pos", current_index - 1)
    else
        local state = mp.get_property("core-idle")
        if state == "yes" then
            mp.commandv("loadfile", next_video.video_url, "replace")
        end
    end
    print_current_video()
    selected_index = current_index
    sleep(MSG_DURATION)
end

-- add the video to the queue from the clipboard
function YouTubeQueue.add_to_queue(url)
    if url == nil or url == "" then
        url = YouTubeQueue.get_clipboard_content()
        if url == nil or url == "" then
            print_osd_message("Nothing found in the clipboard.", MSG_DURATION,
                style.error)
            return
        end
    end
    if YouTubeQueue.is_in_queue(url) then
        print_osd_message("Video already in queue.", MSG_DURATION, style.error)
        return
    end

    local video, channel_url, channel_name, video_name, video_url
    if is_file(url) then
        video_url = url
        video_name = get_filename(url)
        channel_url = get_directory(url)
        channel_name = get_directory(url)

        video = {
            video_url = video_url,
            video_name = video_name,
            channel_url = channel_url,
            channel_name = channel_name
        }
    else
        channel_url, channel_name, video_name = YouTubeQueue.get_video_info(url)
        if (channel_url == nil or channel_name == nil or video_name == nil) or
            (channel_url == "" or channel_name == "" or video_name == "") then
            print_osd_message("Error getting video info.", MSG_DURATION,
                style.error)
        else
            video = {
                video_url = url,
                video_name = video_name,
                channel_url = channel_url,
                channel_name = channel_name
            }
        end
    end

    table.insert(video_queue, video)
    -- if the queue was empty, start playing the video
    -- otherwise, add the video to the playlist
    if not YouTubeQueue.get_current_video() then
        YouTubeQueue.play_next_in_queue()
    else
        mp.commandv("loadfile", url, "append-play")
        print_osd_message("Added " .. video_name .. " to queue.", MSG_DURATION)
    end
end

-- play the previous video in the queue
function YouTubeQueue.play_previous_video()
    local previous_video = YouTubeQueue.prev_in_queue()
    if previous_video == nil then
        print_osd_message("No previous video available.", MSG_DURATION,
            style.error)
        return
    end
    local current_index = YouTubeQueue.get_current_index()
    mp.set_property_number("playlist-pos", current_index - 1)
    selected_index = current_index
    print_current_video()
    sleep(MSG_DURATION)
end

function YouTubeQueue.download_video_at(idx)
    local o = options
    local v = video_queue[idx]
    local q = o.download_quality:sub(1, -2)
    local dl_dir = expanduser(o.download_directory)
    local command = 'yt-dlp -f \'bestvideo[height<=' .. q .. '][ext=' ..
        options.ytdlp_file_format .. ']+bestaudio/best[height<=' ..
        q .. ']/bestvideo[height<=' .. q ..
        ']+bestaudio/best[height<=' .. q .. ']\' -o "' .. dl_dir ..
        "/" .. options.ytdlp_output_template ..
        '" --downloader ' .. o.downloader .. ' ' .. v.video_url

    -- Run the download command
    local handle = io.popen(command)
    if handle == nil then
        print_osd_message("Error starting download.", MSG_DURATION, style.error)
        return
    end
    print_osd_message("Starting download for " .. v.video_name, MSG_DURATION)
    local result = handle:read("*a")
    handle:close()
    if result == nil then
        print_osd_message("Error starting download.", MSG_DURATION, style.error)
        return
    end

    if result then
        print_osd_message("Finished downloading " .. v.video_name, MSG_DURATION)
    else
        print_osd_message("Error downloading " .. v.video_name, MSG_DURATION,
            style.error)
    end
end

function YouTubeQueue.download_current_video()
    if current_video ~= nil and current_video ~= "" then
        YouTubeQueue.download_video_at(index)
    else
        print_osd_message("No video to download.", MSG_DURATION, style.error)
    end
end

function YouTubeQueue.download_selected_video()
    if selected_index == 1 and current_video == nil then
        print_osd_message("No video to download.", MSG_DURATION, style.error)
        return
    end
    YouTubeQueue.download_video_at(selected_index)
end

function YouTubeQueue.remove_from_queue()
    if index == selected_index then
        print_osd_message("Cannot remove current video", MSG_DURATION,
            style.error)
        return
    end
    table.remove(video_queue, selected_index)
    mp.commandv("playlist-remove", selected_index - 1)
    print_osd_message("Deleted " .. current_video.video_name .. " from queue.",
        MSG_DURATION)
    if selected_index > 1 then selected_index = selected_index - 1 end
    index = index - 1
    YouTubeQueue.print_queue()
end

-- }}}

-- LISTENERS {{{
-- Function to be called when the end-file event is triggered
local function on_end_file(event)
    if event.reason == "eof" then -- The file ended normally
        YouTubeQueue.update_current_index()
    end
end

-- Function to be called when the track-changed event is triggered
local function on_track_changed() YouTubeQueue.update_current_index() end

-- Function to be called when the playback-restart event is triggered
local function on_playback_restart()
    local playlist_size = mp.get_property_number("playlist-count", 0)
    if playlist_size > 1 then
        YouTubeQueue.update_current_index()
    elseif current_video == nil then
        local url = mp.get_property("path")
        YouTubeQueue.add_to_queue(url)
    end
end

-- }}}

-- KEY BINDINGS {{{
mp.add_key_binding(options.add_to_queue, "add_to_queue",
    YouTubeQueue.add_to_queue)
mp.add_key_binding(options.play_next_in_queue, "play_next_in_queue",
    YouTubeQueue.play_next_in_queue)
mp.add_key_binding(options.play_previous_in_queue, "play_previous_video",
    YouTubeQueue.play_previous_video)
mp.add_key_binding(options.print_queue, "print_queue", YouTubeQueue.print_queue)
mp.add_key_binding(options.move_cursor_up, "move_cursor_up",
    YouTubeQueue.move_cursor_up)
mp.add_key_binding(options.move_cursor_down, "move_cursor_down",
    YouTubeQueue.move_cursor_down)
mp.add_key_binding(options.play_selected_video, "play_selected_video",
    YouTubeQueue.play_selected_video)
mp.add_key_binding(options.open_video_in_browser, "open_video_in_browser",
    open_video_in_browser)
mp.add_key_binding(options.print_current_video, "print_current_video",
    print_current_video)
mp.add_key_binding(options.open_channel_in_browser, "open_channel_in_browser",
    open_channel_in_browser)
mp.add_key_binding(options.download_current_video, "download_current_video",
    YouTubeQueue.download_current_video)
mp.add_key_binding(options.download_selected_video, "download_selected_video",
    YouTubeQueue.download_selected_video)
mp.add_key_binding(options.move_video, "move_video",
    YouTubeQueue.mark_and_move_video)
mp.add_key_binding(options.remove_from_queue, "delete_video",
    YouTubeQueue.remove_from_queue)

mp.register_event("end-file", on_end_file)
mp.register_event("track-changed", on_track_changed)
mp.register_event("playback-restart", on_playback_restart)

mp.register_script_message("add_to_queue", YouTubeQueue.add_to_queue)
mp.register_script_message("print_queue", YouTubeQueue.print_queue)
-- }}}
