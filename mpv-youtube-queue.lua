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
local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'
local styleOn = mp.get_property("osd-ass-cc/0")
local styleOff = mp.get_property("osd-ass-cc/1")
local YouTubeQueue = {}
local video_queue = {}
local MSG_DURATION = 1.5
local index = 0
local selected_index = 1
local display_offset = 0
local marked_index = nil
local current_video = nil
local destroyer = nil
local timeout
local debug = false

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
    save_queue = "ctrl+s",
    save_queue_alt = "ctrl+S",
    default_save_method = "unwatched",
    load_queue = "ctrl+l"
}
mp.options.read_options(options, "mpv-youtube-queue")

local function destroy()
    timeout:kill()
    mp.set_osd_ass(0, 0, "")
    destroyer = nil
end

timeout = mp.add_periodic_timer(options.menu_timeout, destroy)

-- STYLE {{{
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
-- }}}

-- HELPERS {{{

-- surround string with single quotes if it does not already have them
local function surround_with_quotes(s)
    if string.sub(s, 0, 1) == '"' and string.sub(s, -1) == '"' then
        return
    else
        return '"' .. s .. '"'
    end
end

local function strip(s) return string.gsub(s, "['\n\r]", "") end

local function print_osd_message(message, duration, s)
    if s == style.error and not options.show_errors then return end
    destroy()
    if s == nil then s = style.font .. "{" .. notransparent .. "}" end
    if duration == nil then duration = MSG_DURATION end
    mp.osd_message(styleOn .. s .. message .. style.reset .. styleOff .. "\n",
        duration)
end

-- returns true if the provided path exists and is a file
local function is_file(filepath)
    local result = utils.file_info(filepath)
    if debug and type(result) == "table" then
        print("IS_FILE() check: " .. tostring(result.is_file))
    end
    if result == nil or type(result) ~= "table" then return false end
    return true
end

-- returns the filename given a path (e.g. /home/user/file.txt -> file.txt)
local function split_path(filepath)
    if is_file(filepath) then return utils.split_path(filepath) end
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
    if current_video and current_video.video_url then
        open_url_in_browser(current_video.video_url)
    end
end

local function open_channel_in_browser()
    if current_video and current_video.channel_url then
        open_url_in_browser(current_video.channel_url)
    end
end

local function _print_internal_playlist()
    local count = mp.get_property_number("playlist-count")
    print("Playlist contents:")
    for i = 0, count - 1 do
        local uri = mp.get_property(string.format("playlist/%d/filename", i))
        print(string.format("%d: %s", i, uri))
    end
end

local function toggle_print()
    if destroyer ~= nil then
        destroyer()
    else
        YouTubeQueue.print_queue()
    end
end

-- Function to remove leading and trailing quotes from the first and last arguments of a command table in-place
local function _remove_command_quotes(s)
    -- if the first character of the first argument is a quote, remove it
    if string.sub(s[1], 1, 1) == "'" or string.sub(s[1], 1, 1) == "\"" then
        s[1] = string.sub(s[1], 2)
    end
    -- if the last character of the last argument is a quote, remove it
    if string.sub(s[#s], -1) == "'" or string.sub(s[#s], -1) == "\"" then
        s[#s] = string.sub(s[#s], 1, -2)
    end
end

-- Function to split the clipboard_command into it's parts and return as a table
local function _split_command(cmd)
    local components = {}
    for arg in cmd:gmatch("%S+") do table.insert(components, arg) end
    _remove_command_quotes(components)
    return components
end

function YouTubeQueue._add_to_history_db(v)
    if not options.use_history_db then return false end
    local url = options.backend_host .. ":" .. options.backend_port ..
        "/add_video"
    local command = {
        "curl", "-X", "POST", url, "-H", "Content-Type: application/json", "-d",
        string.format(
            '{"video_url": "%s", "video_name": "%s", "channel_url": "%s", "channel_name": "%s"}',
            v.video_url, v.video_name, v.channel_url, v.channel_name)
    }
    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = command
    }, function(success, _, err)
        if not success then
            print_osd_message("Failed to send video data to backend: " .. err,
                MSG_DURATION, style.error)
            return false
        end
    end)
    return true
end

-- Returns a list of URLs in the queue from start_index to the end
function YouTubeQueue._get_urls(start_index)
    if start_index < 0 or start_index > #video_queue then return nil end
    local urls = {}
    for i = start_index + 1, #video_queue do
        table.insert(urls, video_queue[i].video_url)
    end
    return urls
end

-- Converts to json
function YouTubeQueue._convert_to_json(key, val)
    if val == nil then return end
    if type(val) ~= "table" then return "{" .. key .. ":" .. val .. "}" end
    local json = string.format('{"%s": [', key)
    for i, v in ipairs(val) do
        json = json .. '"' .. v .. '"'
        if i < #val then json = json .. ", " end
    end
    json = json .. "]}"
    return json
end

-- Saves the remainder of the videos in the queue (all videos after the currently playing
-- video) to the history database
function YouTubeQueue.save_queue(idx)
    if not options.use_history_db then return false end
    if idx == nil then idx = index end
    local url = options.backend_host .. ":" .. options.backend_port ..
        "/save_queue"
    local data = YouTubeQueue._convert_to_json("urls",
        YouTubeQueue._get_urls(idx + 1))
    if data == nil or data == '{"urls": []}' then
        print_osd_message("Failed to save queue: No videos remaining in queue",
            MSG_DURATION, style.error)
        return false
    end
    if debug then print("Data: " .. data) end
    local command = {
        "curl", "-X", "POST", url, "-H", "Content-Type: application/json", "-d",
        data
    }
    if debug then
        print("Saving queue to history")
        print("Command: " .. table.concat(command, " "))
    end
    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = command
    }, function(success, result, err)
        if not success then
            print_osd_message("Failed to save queue: " .. err, MSG_DURATION,
                style.error)
            return false
        end
        if debug then print("Status: " .. result.status) end
        if result.status == 0 then
            if idx > 1 then
                print_osd_message("Queue saved to history from index: " .. idx,
                    MSG_DURATION)
            else
                print_osd_message("Queue saved to history.", MSG_DURATION)
            end
        end
    end)
end

-- loads the queue from the backend
function YouTubeQueue.load_queue()
    if not options.use_history_db then return false end
    local url = options.backend_host .. ":" .. options.backend_port ..
        "/load_queue"
    local command = { "curl", "-X", "GET", url }

    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = command
    }, function(success, result, err)
        if not success then
            print_osd_message("Failed to load queue: " .. err, MSG_DURATION,
                style.error)
            return false
        else
            if result.status == 0 then
                -- split urls based on commas
                local urls = {}
                -- Remove the brackets from json list
                local l = result.stdout:sub(2, -3)
                local item
                for turl in l:gmatch('[^,]+') do
                    item = turl:match("^%s*(.-)%s*$"):gsub('"', "'")
                    table.insert(urls, item)
                end
                for _, turl in ipairs(urls) do
                    YouTubeQueue.add_to_queue(turl)
                end
                print_osd_message("Loaded queue from history.", MSG_DURATION)
            end
        end
    end)
end

-- }}}

-- QUEUE GETTERS AND SETTERS {{{

function YouTubeQueue.get_video_at(idx)
    if idx <= 0 or idx > #video_queue then
        print_osd_message("Invalid video index", MSG_DURATION, style.error)
        return nil
    end
    return video_queue[idx]
end

-- returns the content of the clipboard
function YouTubeQueue.get_clipboard_content()
    local command = _split_command(options.clipboard_command)
    local res = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = command
    })

    if res.status ~= 0 then
        print_osd_message("Failed to get clipboard content", MSG_DURATION,
            style.error)
        return nil
    end

    local content = res.stdout:match("^%s*(.-)%s*$") -- Trim leading/trailing spaces
    if content:match("^https?://") then
        return content
    elseif content:match("^file://") or utils.file_info(content) then
        return content
    else
        print_osd_message("Clipboard content is not a valid URL or file path",
            MSG_DURATION, style.error)
        return nil
    end
end

function YouTubeQueue.get_video_info(url)
    print_osd_message("Getting video info...", MSG_DURATION * 2)
    local res = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = {
            "yt-dlp", "--print", "channel_url", "--print", "uploader",
            "--print", "title", "--playlist-items", "1", url
        }
    })

    if res.status ~= 0 then
        print_osd_message("Failed to get video info", MSG_DURATION, style.error)
        return nil
    end

    local channel_url, uploader, title = res.stdout:match("(.*)\n(.*)\n(.*)\n")
    if channel_url == nil or uploader == nil or title == nil or channel_url ==
        "" or uploader == "" or title == "" then
        print_osd_message("Failed to get video info", MSG_DURATION, style.error)
        return nil
    end

    destroy()

    return channel_url, uploader, title
end

function YouTubeQueue.print_current_video()
    destroy()
    local current = current_video
    if current and current.vidro_url ~= "" and is_file(current.video_url) then
        print_osd_message("Playing: " .. current.video_url, 3)
    else
        if current and current.video_url then
            print_osd_message("Playing: " .. current.video_name .. ' by ' ..
                current.channel_name, 3)
        end
    end
end

-- }}}

-- QUEUE FUNCTIONS {{{

-- Function to set the next or previous video in the queue as the current video
-- direction can be "NEXT" or "PREV".  If nil, "next" is assumed
-- Returns nil if there are no more videos in the queue
function YouTubeQueue.set_video(direction)
    local amt
    direction = string.upper(direction)
    if (direction == "NEXT" or direction == nil) then
        amt = 1
    elseif (direction == "PREV" or direction == "PREVIOUS") then
        amt = -1
    else
        print_osd_message("Invalid direction: " .. direction, MSG_DURATION,
            style.error)
        return nil
    end
    if index + amt > #video_queue or index + amt == 0 then return nil end
    index = index + amt
    selected_index = index
    current_video = video_queue[index]
    return current_video
end

function YouTubeQueue.is_in_queue(url)
    for _, v in ipairs(video_queue) do
        if v.video_url == url then return true end
    end
    return false
end

-- Function to find the index of the currently playing video
function YouTubeQueue.update_current_index(update_history)
    if debug then print("Updating current index") end
    if #video_queue == 0 then return end
    if update_history == nil then update_history = false end
    local current_url = mp.get_property("path")
    for i, v in ipairs(video_queue) do
        if v.video_url == current_url then
            index = i
            selected_index = index
            current_video = YouTubeQueue.get_video_at(index)
            if update_history then
                YouTubeQueue._add_to_history_db(current_video)
            end
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
        -- move the video from the from_index to to_index in the internal playlist.
        -- playlist-move is 0-indexed
        if from_index < to_index and to_index == #video_queue then
            mp.commandv("playlist-move", from_index - 1, to_index)
            if to_index > index then index = index - 1 end
        elseif from_index < to_index then
            mp.commandv("playlist-move", from_index - 1, to_index)
            if to_index > index then index = index - 1 end
        else
            mp.commandv("playlist-move", from_index - 1, to_index - 1)
        end

        -- Remove from from_index and insert at to_index into YouTubeQueue
        local temp_video = video_queue[from_index]
        table.remove(video_queue, from_index)
        table.insert(video_queue, to_index, temp_video)
    else
        print_osd_message("Invalid indices for reordering. No changes made.",
            MSG_DURATION, style.error)
    end
end

function YouTubeQueue.print_queue(duration)
    timeout:kill()
    mp.set_osd_ass(0, 0, "")
    timeout:resume()
    local ass = assdraw.ass_new()
    local current_index = index
    if #video_queue > 0 then
        local half_limit = math.floor(options.display_limit / 2)
        local start_index, end_index

        if selected_index <= half_limit then
            start_index = 1
        else
            start_index = selected_index - half_limit
        end

        end_index = start_index + options.display_limit - 1
        if end_index > #video_queue then end_index = #video_queue end

        ass:append(
            style.header .. "MPV-YOUTUBE-QUEUE{\\u0\\b0}" .. style.reset ..
            style.font .. "\n")
        local message
        for i = start_index, end_index do
            local prefix = (i == selected_index) and style.cursor ..
                options.cursor_icon .. "\\h" .. style.reset or
                "\\h\\h\\h"
            if i == current_index and i == selected_index then
                message = prefix .. style.hover_selected .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset
            elseif i == current_index then
                message = prefix .. style.selected .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset
            elseif i == selected_index then
                message = prefix .. style.hover .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset
            else
                message = prefix .. style.reset .. i .. ". " ..
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
            ass:append(style.font .. message)
        end
        mp.set_osd_ass(0, 0, ass.text)
        if duration ~= nil then
            mp.add_timeout(duration, function() destroy() end)
        end
    else
        print_osd_message("No videos in the queue or history.", duration,
            style.error)
    end
    destroyer = destroy
end

function YouTubeQueue.move_cursor(amt)
    timeout:kill()
    timeout:resume()
    selected_index = selected_index - amt
    if selected_index < 1 then
        selected_index = 1
    elseif selected_index > #video_queue then
        selected_index = #video_queue
    end
    if amt == 1 and selected_index > 1 and selected_index < display_offset + 1 then
        display_offset = display_offset - math.abs(selected_index - amt)
    elseif amt == -1 and selected_index < #video_queue and selected_index >
        display_offset + options.display_limit then
        display_offset = display_offset + math.abs(selected_index - amt)
    end
    YouTubeQueue.print_queue()
end

function YouTubeQueue.play_video_at(idx)
    if idx <= 0 or idx > #video_queue then
        print_osd_message("Invalid video index", MSG_DURATION, style.error)
        return nil
    end
    index = idx
    selected_index = idx
    current_video = video_queue[index]
    mp.set_property_number("playlist-pos", index - 1) -- zero-based index
    YouTubeQueue.print_current_video()
    return current_video
end

-- play the next video in the queue
function YouTubeQueue.play_video(direction)
    direction = string.upper(direction)
    local video = YouTubeQueue.set_video(direction)
    if video == nil then
        print_osd_message("No video available.", MSG_DURATION, style.error)
        return
    end
    current_video = video
    selected_index = index
    -- if the current video is not the first in the queue, then play the video
    -- else, check if the video is playing and if not play the video with replace
    if direction == "NEXT" and #video_queue > 1 then
        YouTubeQueue.play_video_at(index)
    elseif direction == "NEXT" and #video_queue == 1 then
        local state = mp.get_property("core-idle")
        -- yes if the video is loaded but not currently playing
        if state == "yes" then
            mp.commandv("loadfile", video.video_url, "replace")
        end
    elseif direction == "PREV" or direction == "PREVIOUS" then
        mp.set_property_number("playlist-pos", index - 1)
    end
    YouTubeQueue.print_current_video()
end

-- add the video to the queue from the clipboard or call from script-message
-- updates the internal playlist by default, pass 0 to disable
function YouTubeQueue.add_to_queue(url, update_internal_playlist)
    if update_internal_playlist == nil then update_internal_playlist = 0 end
    if url == nil or url == "" then
        url = YouTubeQueue.get_clipboard_content()
        if url == nil then return end
    end
    if YouTubeQueue.is_in_queue(url) then
        print_osd_message("Video already in queue.", MSG_DURATION, style.error)
        return
    end

    local video, channel_url, channel_name, video_name
    url = strip(url)
    if not is_file(url) then
        channel_url, channel_name, video_name = YouTubeQueue.get_video_info(url)
        if (channel_url == nil or channel_name == nil or video_name == nil) or
            (channel_url == "" or channel_name == "" or video_name == "") then
            print_osd_message("Error getting video info.", MSG_DURATION,
                style.error)
            return
        else
            video = {
                video_url = url,
                video_name = video_name,
                channel_url = channel_url,
                channel_name = channel_name
            }
        end
    else
        channel_url, video_name = split_path(url)
        if channel_url == nil or video_name == nil or channel_url == "" or
            video_name == "" then
            print_osd_message("Error getting video info.", MSG_DURATION,
                style.error)
            return
        end
        video = {
            video_url = url,
            video_name = video_name,
            channel_url = channel_url,
            channel_name = "Local file"
        }
    end

    table.insert(video_queue, video)
    -- if the queue was empty, start playing the video
    -- otherwise, add the video to the playlist
    if not current_video then
        YouTubeQueue.play_video("NEXT")
    elseif update_internal_playlist == 0 then
        mp.commandv("loadfile", url, "append-play")
    end
    print_osd_message("Added " .. video_name .. " to queue.", MSG_DURATION)
end

function YouTubeQueue.download_video_at(idx)
    if idx < 0 or idx > #video_queue then return end
    local v = video_queue[idx]
    if is_file(v.video_url) then
        print_osd_message("Current video is a local file... doing nothing.",
            MSG_DURATION, style.error)
        return
    end
    local o = options
    local q = o.download_quality:sub(1, -2)
    local dl_dir = expanduser(o.download_directory)

    print_osd_message("Downloading " .. v.video_name .. "...", MSG_DURATION)
    -- Run the download command
    mp.command_native_async({
        name = "subprocess",
        capture_stderr = true,
        detach = true,
        args = {
            "yt-dlp", "-f",
            "bestvideo[height<=" .. q .. "][ext=" .. options.ytdlp_file_format ..
            "]+bestaudio/best[height<=" .. q .. "]/bestvideo[height<=" .. q ..
            "]+bestaudio/best[height<=" .. q .. "]", "-o",
            dl_dir .. "/" .. options.ytdlp_output_template, "--downloader",
            o.downloader, "--", v.video_url
        }
    }, function(success, _, err)
        if success then
            print_osd_message("Finished downloading " .. v.video_name .. ".",
                MSG_DURATION)
        else
            print_osd_message("Error downloading " .. v.video_name .. ": " ..
                err, MSG_DURATION, style.error)
        end
    end)
end

function YouTubeQueue.remove_from_queue()
    if index == selected_index then
        print_osd_message("Cannot remove current video", MSG_DURATION,
            style.error)
        return
    end
    table.remove(video_queue, selected_index)
    mp.commandv("playlist-remove", selected_index - 1)
    if current_video and current_video.video_name then
        print_osd_message("Deleted " .. current_video.video_name ..
            " from queue.", MSG_DURATION)
    end
    if selected_index > 1 then selected_index = selected_index - 1 end
    index = index - 1
    YouTubeQueue.print_queue()
end

-- }}}

-- LISTENERS {{{
-- Function to be called when the end-file event is triggered
-- This function is called when the current file ends or when moving to the
-- next or previous item in the internal playlist
local function on_end_file(event)
    if debug then print("End file event triggered: " .. event.reason) end
    if event.reason == "eof" then -- The file ended normally
        YouTubeQueue.update_current_index(true)
    end
end

-- Function to be called when the track-changed event is triggered
local function on_track_changed()
    if debug then print("Track changed event triggered.") end
    YouTubeQueue.update_current_index()
end

local function on_file_loaded()
    if debug then print("Load file event triggered.") end
    YouTubeQueue.update_current_index(true)
end

-- Function to be called when the playback-restart event is triggered
local function on_playback_restart()
    if debug then print("Playback restart event triggered.") end
    if current_video == nil then
        local url = mp.get_property("path")
        YouTubeQueue.add_to_queue(url)
        YouTubeQueue._add_to_history_db(current_video)
    end
end

-- }}}

-- KEY BINDINGS {{{
mp.add_key_binding(options.add_to_queue, "add_to_queue",
    YouTubeQueue.add_to_queue)
mp.add_key_binding(options.play_next_in_queue, "play_next_in_queue",
    function() YouTubeQueue.play_video("NEXT") end)
mp.add_key_binding(options.play_previous_in_queue, "play_prev_in_queue",
    function() YouTubeQueue.play_video("PREV") end)
mp.add_key_binding(options.print_queue, "print_queue", toggle_print)
mp.add_key_binding(options.move_cursor_up, "move_cursor_up",
    function() YouTubeQueue.move_cursor(1) end,
    { repeatable = true })
mp.add_key_binding(options.move_cursor_down, "move_cursor_down",
    function() YouTubeQueue.move_cursor(-1) end,
    { repeatable = true })
mp.add_key_binding(options.play_selected_video, "play_selected_video",
    function() YouTubeQueue.play_video_at(selected_index) end)
mp.add_key_binding(options.open_video_in_browser, "open_video_in_browser",
    open_video_in_browser)
mp.add_key_binding(options.print_current_video, "print_current_video",
    YouTubeQueue.print_current_video)
mp.add_key_binding(options.open_channel_in_browser, "open_channel_in_browser",
    open_channel_in_browser)
mp.add_key_binding(options.download_current_video, "download_current_video",
    function() YouTubeQueue.download_video_at(index) end)
mp.add_key_binding(options.download_selected_video, "download_selected_video",
    function() YouTubeQueue.download_video_at(selected_index) end)
mp.add_key_binding(options.move_video, "move_video",
    YouTubeQueue.mark_and_move_video)
mp.add_key_binding(options.remove_from_queue, "delete_video",
    YouTubeQueue.remove_from_queue)
mp.add_key_binding(options.save_queue, "save_queue", function()
    if options.default_save_method == "unwatched" then
        YouTubeQueue.save_queue(index)
    else
        YouTubeQueue.save_queue(0)
    end
end)
mp.add_key_binding(options.save_queue_alt, "save_queue_alt", function()
    if options.default_save_method == "unwatched" then
        YouTubeQueue.save_queue(0)
    else
        YouTubeQueue.save_queue(index)
    end
end)
mp.add_key_binding(options.load_queue, "load_queue", YouTubeQueue.load_queue)

mp.register_event("end-file", on_end_file)
mp.register_event("track-changed", on_track_changed)
mp.register_event("playback-restart", on_playback_restart)
mp.register_event("file-loaded", on_file_loaded)

-- keep for backwards compatibility
mp.register_script_message("add_to_queue", YouTubeQueue.add_to_queue)
mp.register_script_message("print_queue", YouTubeQueue.print_queue)

mp.register_script_message("add_to_youtube_queue", YouTubeQueue.add_to_queue)
mp.register_script_message("toggle_youtube_queue", toggle_print)
mp.register_script_message("print_internal_playlist", _print_internal_playlist)
mp.register_script_message("reorder_youtube_queue", YouTubeQueue.reorder_queue)
-- }}}
