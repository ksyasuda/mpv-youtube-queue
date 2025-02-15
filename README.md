# mpv-youtube-queue

<div align="center">

A Lua script that replicates and extends the YouTube "Add to Queue" feature for mpv

</div>

![mpv-youtube-queue image](.assets/mpv-youtube-queue.png)

## Features

- **Interactive Queue Management:** A menu-driven interface for adding, removing, and rearranging videos in your queue
- **yt-dlp Integration:** Gathers video info and allows downloading with any link supported by [yt-dlp](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md "yd-dlp supported sites page")
- **Internal Playlist Integration:** Seamlessly integrates with mpv's internal playlist for a unified playback experience
- **Customizable Keybindings:** Assign your preferred hotkeys to interact with the currently playing video and queue

## Requirements

This script requires the following software to be installed on the system

- One of [xclip](https://github.com/astrand/xclip), [wl-clipboard](https://github.com/bugaevc/wl-clipboard), or any command-line utility that can paste from the system clipboard
  - Windows users can utilize `Get-Clipboard` from powershell by setting the `clipboard_command` in `mpv-youtube-queue.conf` file to the following: `clipboard_command=powershell -command Get-Clipboard`
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)

## Installation

- Copy `mpv-youtube-queue.lua` script to your `~~/scripts` directory
  - `~/.config/mpv/scripts` on Linux
  - `%APPDATA%\mpv\scripts` on Windows
- Optionally copy `mpv-youtube-queue.conf` to the `~~/script-opts` directory
  - `~/.config/mpv/script-opts` on Linux
  - `%APPDATA%\mpv\script-opts` on Windows
    to customize the script configuration as described in the next section

## Configuration

### Default Keybindings

- `add_to_queue - ctrl+a`: Add a video in the clipboard to the queue
- `download_current_video - ctrl+d`: Download the currently playing video
- `download_selected_video - ctrl+D`: Download the currently selected video
  in the queue
- `move_cursor_down - ctrl+j`: Move the cursor down one row in the queue
- `move_cursor_up - ctrl+k`- Move the cursor up one row in the queue
- `load_queue - ctrl+l` - Appends the videos from the most recent save point to the
  queue
- `move_video - ctrl+m`: Mark/move the selected video in the queue
- `play_next_in_queue - ctrl+n`: Play the next video in the queue
- `open_video_in_browser - ctrl+o`: Open the currently playing video in the browser
- `open_channel_in_browser - ctrl+O`: Open the channel page for the currently
  playing video in the browser
- `play_previous_in_queue - ctrl+p`: Play the previous video in the queue
- `print_current_video - ctrl+P`: Print the name and channel of the currently
  playing video to the OSD
- `print_queue - ctrl+q`: Print the contents of the queue to the OSD
- `save_queue - ctrl+s`: Saves the queue using the chosen method in
  `default_save_method`
- `save_queue_alt - ctrl+S`: Saves the queue using the method not chosen in
  `default_save_method`
- `remove_from_queue - ctrl+x`: Remove the currently selected video from the
  queue
- `play_selected_video - ctrl+ENTER`: Play the currently selected video in
  the queue

### Default Options

- `default_save_method - unwatched`: The default method to use when saving the
  queue. Valid options are `unwatched` or `all`. Defaults to `unwatched`
  - Whichever option is chosen is the default method for the `save_queue`
    binding, and the other method will be bound to `save_queue_alt`
- `browser - firefox`: The browser to use when opening a video or channel page
- `clipboard_command - xclip -o`: The command to use to get the contents of the clipboard
- `cursor_icon - ➤`: The icon to use for the cursor
- `display_limit - 10`: The maximum amount of videos to show on the OSD at once
- `download_directory - ~/videos/YouTube`: The directory to use when downloading a video
- `download_quality 720p`: The maximum download quality
- `downloader - curl`: The name of the program to use to download the video
- `font_name - JetBrains Mono`: The name of the font to use
- `font_size - 12`: Size of the font
- `marked_icon - ⇅`: The icon to use to mark a video as ready to be moved in the queue
- `menu_timeout - 5`: The number of seconds until the menu times out
- `show_errors - yes`: Show error messages on the OSD
- `ytdlp_file_format - mp4`: The preferred file format for downloaded videos
- `ytdlp_output_template - %(uploader)s/%(title)s.%(ext)s`: The [yt-dlp output template string](https://github.com/yt-dlp/yt-dlp#output-template)
  - Full path with the default `download_directory` is: `~/videos/YouTube/<uploader>/<title>.<ext>`
- `use_history_db - no`: Enable watch history tracking and remote video queuing through integration with [mpv-youtube-queue-server](https://gitea.suda.codes/sudacode/mpv-youtube-queue-server)
- `backend_host`: ip or hostname of the backend server
- `backend_port`: port to connect to for the backend server

## License

This project is licensed under the terms of the GPLv3 license.
