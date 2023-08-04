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
local YouTubeQueue = {}
local video_queue = {}
local current_video = nil
local index = 0
local selected_index = 1
local MSG_DURATION = 1.5
local styleOn = mp.get_property("osd-ass-cc/0")
local styleOff = mp.get_property("osd-ass-cc/1")

local options = {
    add_to_queue = "ctrl+a",
    play_next_in_queue = "ctrl+n",
    play_previous_in_queue = "ctrl+p",
    print_queue = "ctrl+q",
    move_selection_up = "ctrl+UP",
    move_selection_down = "ctrl+DOWN",
    play_selected_video = "ctrl+ENTER",
    open_video_in_browser = "ctrl+o",
    open_channel_in_browser = "ctrl+O",
    print_current_video = "ctrl+P",
    browser = "firefox",
    clipboard_command = "xclip -o",
    display_limit = 6,
    cursor_icon = "🠺",
    font_size = 14,
    font_name = "JetBrains Mono"
}

local colors = {
    error = "676EFF",
    selected = "F993BD",
    hover_selected = "FAA9CA",
    cursor = "FDE98B",
    header = "8CFAF1",
    hover = "F2F8F8",
    text = "BFBFBF"
}

local notransparent = "\\alpha&H00&"
local semitransparent = "\\alpha&H4D&"
local transparent = "\\alpha&H73&"

local style = {
    error = "{\\c&" .. colors.error .. "&" .. notransparent .. "}",
    selected = "{\\c&" .. colors.selected .. "&" .. semitransparent .. "}",
    hover_selected = "{\\c&" .. colors.hover_selected .. "&\\alpha&H33&}",
    cursor = "{\\c&" .. colors.cursor .. "&" .. notransparent .. "}",
    reset = "{\\c&" .. colors.text .. "&" .. transparent .. "}",
    header = "{\\fn" .. options.font_name .. "\\fs" .. options.font_size * 1.5 ..
        "\\u1\\b1\\c&" .. colors.header .. "&" .. notransparent .. "}",
    hover = "{\\c&" .. colors.hover .. "&" .. semitransparent .. "}",
    font = "{\\fn" .. options.font_name .. "\\fs" .. options.font_size .. "{" ..
        transparent .. "}"
}

mp.options.read_options(options, "mpv-youtube-queue")

local display_limit = options.display_limit
local display_offset = 0

-- HELPERS {{{

-- run sleep shell command for n seconds
local function sleep(n) os.execute("sleep " .. tonumber(n)) end

local function print_osd_message(message, duration, s)
    if not s then s = style.font .. "{" .. notransparent .. "}" end
    mp.osd_message(styleOn .. s .. message .. style.reset .. styleOff .. "\n",
        duration)
end

local function print_current_video()
    print_osd_message("Playing: " .. current_video.video_name .. ' by ' ..
        current_video.video_name, 3)
end

local function get_video_info(url)
    local command =
        'yt-dlp --print channel_url --print uploader --print title --playlist-items 1 ' ..
        url
    local handle = io.popen(command)
    if not handle then return nil, nil, nil end

    local result = handle:read("*a")
    handle:close()

    -- Split the result into URL, name, and video title
    local channel_url, channel_name, video_name = result:match(
        "(.-)\n(.-)\n(.*)")

    -- Remove trailing whitespace
    if channel_url then channel_url = channel_url:gsub("%s+$", "") end
    if channel_name then channel_name = channel_name:gsub("%s+$", "") end
    if video_name then video_name = video_name:gsub("%s+$", "") end

    return channel_url, channel_name, video_name
end

local function is_valid_ytdlp_url(url)
    local command = 'yt-dlp --simulate \'' .. url .. '\' >/dev/null 2>&1'
    local handle = io.popen(command .. "; echo $?")
    if not handle then return false end
    local result = handle:read("*a")
    if not result then return false end
    handle:close()
    return result:gsub("%s+$", "") == "0"
end

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

-- }}}

-- QUEUE FUNCTIONS {{{

function YouTubeQueue.add_to_queue(video) table.insert(video_queue, video) end

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
    for _, v in ipairs(video_queue) do if v.url == url then return true end end
    return false
end

-- Function to find the index of the currently playing video
function YouTubeQueue.update_current_index()
    local current_url = mp.get_property("path")
    if #video_queue == 0 then return end
    for i, v in ipairs(video_queue) do
        if v.url == current_url then
            index = i
            return
        end
    end
    -- if not found, reset the index
    index = 0
    selected_index = index
    current_video = YouTubeQueue.get_video_at(index)
end

-- Function to be called when the end-file event is triggered
function YouTubeQueue.on_end_file(event)
    if event.reason == "eof" then -- The file ended normally
        YouTubeQueue.update_current_index()
    end
end

-- Function to be called when the track-changed event is triggered
function YouTubeQueue.on_track_changed() YouTubeQueue.update_current_index() end

-- Function to be called when the playback-restart event is triggered
function YouTubeQueue.on_playback_restart() YouTubeQueue.update_current_index() end

function YouTubeQueue.print_queue(duration)
    local current_index = index
    if not duration then duration = 3 end
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
                "    "
            if i == current_index and i == selected_index then
                mp.msg.log("info", "YES")
                message =
                    message .. prefix .. style.hover_selected .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset ..
                    "\n"
            elseif i == current_index then
                message = message .. prefix .. style.selected .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset ..
                    "\n"
            elseif i == selected_index then
                message = message .. prefix .. style.hover .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset ..
                    "\n"
            else
                message = message .. prefix .. style.reset .. i .. ". " ..
                    video_queue[i].video_name .. " - (" ..
                    video_queue[i].channel_name .. ")" .. style.reset ..
                    "\n"
            end
        end
        message = message .. styleOff
        mp.osd_message(message, duration)
    else
        print_osd_message("No videos in the queue or history.", duration,
            style.error)
    end
end

-- }}}

-- MAIN FUNCTIONS {{{

-- returns the content of the clipboard
local function get_clipboard_content()
    local handle = io.popen(options.clipboard_command)
    if not handle then
        print_osd_message("Error getting clipboard content", MSG_DURATION,
            style.error)
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    return result
end

local function move_selection_up()
    if selected_index > 1 then
        selected_index = selected_index - 1
        if selected_index < display_offset + 1 then
            display_offset = display_offset - 1
        end
        YouTubeQueue.print_queue(MSG_DURATION)
    end
end

local function move_selection_down()
    if selected_index < YouTubeQueue.size() then
        selected_index = selected_index + 1
        if selected_index > display_offset + display_limit then
            display_offset = display_offset + 1
        end
        YouTubeQueue.print_queue(MSG_DURATION)
    end
end

local function play_video_at(idx)
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

local function play_selected_video()
    -- local current_index = YouTubeQueue.get_current_index()
    play_video_at(selected_index)
    YouTubeQueue.print_queue(MSG_DURATION - 0.5)
    sleep(MSG_DURATION)
    print_current_video()
end

-- play the next video in the queue
local function play_next_in_queue()
    local next_video = YouTubeQueue.next_in_queue()
    if not next_video or next_video == "" then
        print_osd_message("No more videos in the queue.", MSG_DURATION,
            style.error)
        return
    end
    local next_video_url = next_video.url
    local current_index = YouTubeQueue.get_current_index()
    if YouTubeQueue.size() > 1 then
        mp.set_property_number("playlist-pos", current_index - 1)
    else
        mp.commandv("loadfile", next_video_url, "replace")
    end
    print_current_video()
    selected_index = current_index
    sleep(MSG_DURATION)
end

-- add the video to the queue from the clipboard
local function add_to_queue()
    local url = get_clipboard_content()
    if not url then
        print_osd_message("Nothing found in the clipboard.", MSG_DURATION,
            style.error)
        return
    end
    if YouTubeQueue.is_in_queue(url) then
        print_osd_message("Video already in queue.", MSG_DURATION, style.error)
        return
        -- elseif not is_valid_ytdlp_url(url) then
        --     mp.osd_message("Invalid URL.")
        --     return
    end
    local channel_url, channel_name, video_name = get_video_info(url)
    if (not channel_url or not channel_name or not video_name) or
        (channel_url == "" or channel_name == "" or video_name == "") then
        print_osd_message("Error getting video info.", MSG_DURATION, style.error)
        return
    end

    YouTubeQueue.add_to_queue({
        url = url,
        video_name = video_name,
        channel_url = channel_url,
        channel_name = channel_name
    })
    if not YouTubeQueue.get_current_video() then
        play_next_in_queue()
    else
        mp.commandv("loadfile", url, "append-play")
        print_osd_message("Added " .. video_name .. " to queue.", MSG_DURATION)
    end
end

-- play the previous video in the queue
local function play_previous_video()
    local previous_video = YouTubeQueue.prev_in_queue()
    if not previous_video or previous_video == "" then
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

local function open_url_in_browser(url)
    local command = options.browser .. " " .. url
    os.execute(command)
end

local function open_video_in_browser() open_url_in_browser(current_video.url) end

local function open_channel_in_browser()
    open_url_in_browser(current_video.channel_url)
end

-- }}}

-- KEY BINDINGS {{{
mp.add_key_binding(options.add_to_queue, "add_to_queue", add_to_queue)
mp.add_key_binding(options.play_next_in_queue, "play_next_in_queue",
    play_next_in_queue)
mp.add_key_binding(options.play_previous_in_queue, "play_previous_video",
    play_previous_video)
mp.add_key_binding(options.print_queue, "print_queue", YouTubeQueue.print_queue)
mp.add_key_binding(options.move_selection_up, "move_selection_up",
    move_selection_up)
mp.add_key_binding(options.move_selection_down, "move_selection_down",
    move_selection_down)
mp.add_key_binding(options.play_selected_video, "play_selected_video",
    play_selected_video)
mp.add_key_binding(options.open_video_in_browser, "open_video_in_browser",
    open_video_in_browser)
mp.add_key_binding(options.print_current_video, "print_current_video",
    print_current_video)
mp.add_key_binding(options.open_channel_in_browser, "open_channel_in_browser",
    open_channel_in_browser)

-- Listen for the file-loaded event
mp.register_event("end-file", YouTubeQueue.on_end_file)
mp.register_event("track-changed", YouTubeQueue.on_track_changed)
mp.register_event("playback-restart", YouTubeQueue.on_playback_restart)
-- }}}
