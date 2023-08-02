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
local queue_is_displayed = false
local index = 0

local options = {
    add_to_queue = "ctrl+a",
    play_next_in_queue = "ctrl+n",
    play_previous_in_queue = "ctrl+p",
    print_queue = "ctrl+q",
    move_selection_up = "ctrl+UP",
    move_selection_down = "ctrl+DOWN",
    play_selected_video = "ctrl+ENTER",
    open_video_in_browser = "ctrl+o",
    print_current_video = "ctrl+P",
    browser = "firefox",
    clipboard_command = "xclip -o"
}
mp.options.read_options(options, "mpv-youtube-queue")

-- QUEUE GETTERS AND SETTERS {{{

function YouTubeQueue.size()
    return #video_queue
end

function YouTubeQueue.get_current_index()
    return index
end

function YouTubeQueue.get_video_queue()
    return video_queue
end

function YouTubeQueue.set_current_index(idx)
    index = idx
end

function YouTubeQueue.get_current_video()
    return current_video
end

-- }}}

-- QUEUE FUNCTIONS {{{

function YouTubeQueue.add_to_queue(video)
    table.insert(video_queue, video)
end

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
    mp.commandv("loadfile", current_video.url, "replace")
    return current_video
end

function YouTubeQueue.is_in_queue(url)
    for _, v in ipairs(video_queue) do
        if v.url == url then
            return true
        end
    end
    return false
end

-- }}}

-- MAIN FUNCTIONS {{{
-- Function to get the video name from a YouTube URL
local function get_video_name(url)
    local command = 'yt-dlp --get-title ' .. url
    local handle = io.popen(command)
    if not handle then
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

-- returns the content of the clipboard
local function get_clipboard_content()
    local handle = io.popen(options.clipboard_command)
    if not handle then
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    return result
end


-- print the queue to the OSD
local function print_queue()
    local complete_list = YouTubeQueue.get_video_queue()
    local current_index = YouTubeQueue.get_current_index()
    if #complete_list > 0 then
        local message = ""
        for i, v in ipairs(complete_list) do
            local prefix = (i == current_index) and "=> " or "   "
            message = message .. prefix .. i .. ". " .. v.name .. "\n"
        end
        mp.osd_message(message, 5)
        queue_is_displayed = true
    else
        mp.osd_message("No videos in the queue or history.")
    end
end

local function move_selection_up()
    local current_index = YouTubeQueue.get_current_index()
    if queue_is_displayed and current_index > 1 then
        current_index = current_index - 1
        YouTubeQueue.set_current_index(current_index)
        print_queue()
    end
end

local function move_selection_down()
    local current_index = YouTubeQueue.get_current_index()
    if queue_is_displayed and current_index < YouTubeQueue.size() then
        current_index = current_index + 1
        YouTubeQueue.set_current_index(current_index)
        print_queue()
    end
end

local function play_selected_video()
    local current_index = YouTubeQueue.get_current_index()
    if queue_is_displayed then
        YouTubeQueue.play_video_at(current_index)
        queue_is_displayed = false
    end
end

-- play the next video in the queue
local function play_next_in_queue()
    local next_video = YouTubeQueue.next_in_queue()
    if not next_video then
        return
    end
    local next_video_url = next_video.url
    local name = next_video.name
    mp.commandv("loadfile", next_video_url, "replace")
    mp.osd_message("Playing " .. name)
end

-- add the video to the queue from the clipboard
local function add_to_queue()
    local url = get_clipboard_content()
    -- get video name in background
    local name = get_video_name(url)

    -- check to make sure the video is not already in the queue
    if YouTubeQueue.is_in_queue(url) then
        mp.osd_message("Video already in queue.")
        return
    end
    YouTubeQueue.add_to_queue({ url = url, name = name })
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
    local previous_video_url = previous_video.url
    local name = previous_video.name
    if previous_video_url then
        mp.commandv("loadfile", previous_video_url, "replace")
        mp.osd_message("Playing " .. name)
    else
        mp.osd_message("No previous video available.")
    end
end

local function open_url_in_browser(url)
    local command = options.browser .. " " .. url
    os.execute(command)
end


local function open_video_in_browser()
    local current_url = mp.get_property("path")
    open_url_in_browser(current_url)
end


local function print_current_video()
    local current_url = mp.get_property("path")
    local current_name = get_video_name(current_url)
    mp.osd_message("Currently playing " .. current_name, 3)
end
-- }}}

-- KEY BINDINGS {{{
mp.add_key_binding(options.add_to_queue, "add_to_queue", add_to_queue)
mp.add_key_binding(options.play_next_in_queue, "play_next_in_queue", play_next_in_queue)
mp.add_key_binding(options.play_previous_in_queue, "play_previous_video", play_previous_video)
mp.add_key_binding(options.print_queue, "print_queue", print_queue)
mp.add_key_binding(options.move_selection_up, "move_selection_up", move_selection_up)
mp.add_key_binding(options.move_selection_down, "move_selection_down", move_selection_down)
mp.add_key_binding(options.play_selected_video, "play_selected_video", play_selected_video)
mp.add_key_binding(options.open_video_in_browser, "open_video_in_browser", open_video_in_browser)
mp.add_key_binding(options.print_current_video, "print_current_video", print_current_video)

-- Listen for the file-loaded event
-- mp.register_event("file-loaded", update_current_index)
-- }}}


return YouTubeQueue
