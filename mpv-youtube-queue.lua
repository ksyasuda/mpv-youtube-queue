-- mpv-youtube-queue.lua
--
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
local SLEEP_TIME = 1.5

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
    clipboard_command = "xclip -o"
}
mp.options.read_options(options, "mpv-youtube-queue")

-- HELPERS {{{

-- print the name of the current video to the OSD
local function print_video_name(video, duration)
    if not video then return end
    if not duration then duration = 2 end
    mp.osd_message('Currently playing: ' .. video.name, duration)
end

-- Function to get the video name from a YouTube URL
local function get_video_name(url)
    local command = 'yt-dlp --get-title ' .. url
    local handle = io.popen(command)
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

-- get the channel url from a video url
local function get_channel_url(url)
    local command = 'yt-dlp --print channel_url --playlist-items 1 ' .. url
    local handle = io.popen(command)
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
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

function YouTubeQueue.set_current_index(idx) index = idx end

function YouTubeQueue.get_current_video() return current_video end

function YouTubeQueue.get_video_at(idx)
    if idx <= 0 or idx > #video_queue then
        mp.osd_message("Invalid video index")
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
        current_video = video_queue[index]
        return current_video
    end
end

function YouTubeQueue.prev_in_queue()
    if index > 1 then
        index = index - 1
        current_video = video_queue[index]
    else
        current_video = video_queue[1]
    end
    return current_video
end

function YouTubeQueue.play_video_at(idx)
    if idx <= 0 or idx > #video_queue then
        mp.osd_message("Invalid video index")
        return nil
    end
    index = idx
    current_video = video_queue[index]
    mp.set_property_number("playlist-pos", index - 1) -- zero-based index
    return current_video
end

function YouTubeQueue.is_in_queue(url)
    for _, v in ipairs(video_queue) do if v.url == url then return true end end
    return false
end

-- Function to find the index of the currently playing video
function YouTubeQueue.update_current_index()
    local current_url = mp.get_property("path")
    for i, v in ipairs(video_queue) do
        if v.url == current_url then
            index = i
            return
        end
    end
    -- if not found, reset the index
    index = 0
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
    local queue = YouTubeQueue.get_video_queue()
    local current_index = YouTubeQueue.get_current_index()
    if not duration then duration = 5 end
    if #queue > 0 then
        local message = ""
        for i, v in ipairs(queue) do
            local prefix = (i == current_index and i == selected_index) and
                "=>> " or (i == current_index) and "=> " or
                (i == selected_index) and "> " or "   "
            -- prefix = (i == selected_index) and prefix .. "> " or prefix
            message = message .. prefix .. i .. ". " .. v.name .. "\n"
        end
        mp.osd_message(message, duration)
    else
        mp.osd_message("No videos in the queue or history.")
    end
end

-- }}}

-- MAIN FUNCTIONS {{{

-- returns the content of the clipboard
local function get_clipboard_content()
    local handle = io.popen(options.clipboard_command)
    if not handle then
        mp.osd_message("Error getting clipboard content")
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    return result
end

local function move_selection_up()
    -- selected_index = YouTubeQueue.get_current_index()
    if selected_index > 1 then
        selected_index = selected_index - 1
        YouTubeQueue.print_queue()
    end
end

local function move_selection_down()
    -- selected_index = YouTubeQueue.get_current_index()
    if selected_index < YouTubeQueue.size() then
        selected_index = selected_index + 1
        -- YouTubeQueue.set_current_index(current_index)
        YouTubeQueue.print_queue()
    end
end

local function sleep(n) os.execute("sleep " .. tonumber(n)) end

local function play_selected_video()
    -- local current_index = YouTubeQueue.get_current_index()
    local video = YouTubeQueue.play_video_at(selected_index)
    YouTubeQueue.print_queue(SLEEP_TIME - 0.5)
    sleep(SLEEP_TIME)
    print_video_name(video, SLEEP_TIME)
end

-- play the next video in the queue
local function play_next_in_queue()
    local next_video = YouTubeQueue.next_in_queue()
    if not next_video then return end
    local next_video_url = next_video.url
    if YouTubeQueue.size() > 1 then
        mp.set_property_number("playlist-pos",
            YouTubeQueue.get_current_index() - 1)
    else
        mp.commandv("loadfile", next_video_url, "replace")
    end
    print_video_name(next_video, SLEEP_TIME)
    sleep(SLEEP_TIME)
end

-- add the video to the queue from the clipboard
local function add_to_queue()
    local url = get_clipboard_content()
    if not url then
        mp.osd_message("Nothing found in the clipboard.")
        return
    end
    if not string.match(url, "^https://www.youtube.com") then
        mp.osd_message("Not a YouTube URL.")
        return
    end
    if YouTubeQueue.is_in_queue(url) then
        mp.osd_message("Video already in queue.")
        return
    elseif not is_valid_ytdlp_url(url) then
        mp.osd_message("Invalid URL.")
        return
    end
    local name = get_video_name(url)
    local channel_url = get_channel_url(url)
    YouTubeQueue.add_to_queue({
        url = url,
        name = name,
        channel_url = channel_url
    })
    if not YouTubeQueue.get_current_video() then
        play_next_in_queue()
    else
        mp.commandv("loadfile", url, "append-play")
        mp.osd_message("Added " .. name .. " to queue.")
    end
end

-- play the previous video in the queue
local function play_previous_video()
    local previous_video = YouTubeQueue.prev_in_queue()
    if not previous_video then
        mp.osd_message("No previous video available.")
        return
    end
    mp.set_property_number("playlist-pos", YouTubeQueue.get_current_index() - 1)
    print_video_name(previous_video, SLEEP_TIME)
    sleep(SLEEP_TIME)
end

local function open_url_in_browser(url)
    local command = options.browser .. " " .. url
    os.execute(command)
end

local function open_video_in_browser() open_url_in_browser(current_video.url) end

local function open_channel_in_browser()
    open_url_in_browser(current_video.channel_url)
end

local function print_current_video()
    mp.osd_message("Currently playing " .. current_video.name, 3)
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
