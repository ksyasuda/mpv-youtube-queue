# mpv-youtube-queue

<div align="center">

A Lua script that implements the YouTube 'Add to Queue' functionality for mpv

</div>

![mpv-youtube-queue image](.assets/mpv-youtube-queue.png)

## Features

- Add YouTube videos to a queue from the clipboard
- Fetch and display the video and channel names of the videos in the queue
- Select a video to play from the queue with an interactive menu,
  or navigate through the queue with keyboard shortcuts
- Edit the order of videos in the queue
- Open the URL or channel page of the currently playing video in a new browser tab
- Download the currently playing video
- Download a video in the queue

## Notes

- This script uses the Linux `xclip` utility to read from the clipboard.
  If you're on macOS or Windows, you'll need to adjust the `clipboard_command`
  config variable in [mpv-youtube-queue.conf](./mpv-youtube-queue.conf)
- When adding videos to the queue, the script fetches the video name using
  `yt-dlp`. Ensure you have `yt-dlp` installed and in your PATH.

## Requirements

This script requires the following software to be installed on the system

- [xclip](https://github.com/astrand/xclip)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)

## Installation

- Copy the `mpv-youtube-queue.lua` script to your `~~/scripts` directory
  (`~/.config/mpv` on Linux)
- Optionally copy the `mpv-youtube-queue.conf` to the `~~/script-opts` directory
  to customize the script configuration as described in the next section

## Configuration

### Default Keybindings

- `add_to_queue - ctrl+a`: Add a video in the clipboard to the queue
- `download_current_video - ctrl+d`: Download the currently playing video
- `download_selected_video - ctrl+D`: Download the currently selected video
  in the queue
- `move_cursor_down - ctrl+j`: Move the cursor down one row in the queue
- `move_cursor_up - ctrl+k`- Move the cursor up one row in the queue
- `move_video - ctrl+m`: Mark/move the selected video in the queue
- `play_next_in_queue - ctrl+n`: Play the next video in the queue
- `open_video_in_browser - ctrl+o`: Open the currently playing video in the browser
- `open_channel_in_browser - ctrl+O`: Open the channel page for the currently
  playing video in the browser
- `play_previous_in_queue - ctrl+p`: Play the previous video in the queue
- `print_current_video - ctrl+P`: Print the name and channel of the currently
  playing video to the OSD
- `print_queue - ctrl+q`: Print the contents of the queue to the OSD
- `remove_from_queue - ctrl+x`: Remove the currently selected video from the
  queue
- `play_selected_video - ctrl+ENTER`: Play the currently selected video in
  the queue

### Default Option

- `browser - firefox`: The browser to use when opening a video or channel page
- `clipboard_command - xclip -o`: The command to use to get the contents of the clipboard
- `cursor_icon - ➤`: The icon to use for the cursor
- `display_limit - 6`: The maximum amount of videos to show on the OSD at once
- `download_directory - ~/videos/YouTube`: The directory to use when
  downloading a video
- `download_quality 720p`: The maximum download quality
- `downloader - curl`: The name of the program to use to download the video
- `font_name - JetBrains Mono`: The name of the font to use
- `font_size - 12`: Size of the font
- `marked_icon - ⇅`: The icon to use to mark a video as ready to be moved
  in the queue
- `show_errors - yes`: Show error messages on the OSD
- `ytdlp_output_template - %(uploader)s/%(title)s.%(ext)s`: The [yt-dlp output
  template string](https://github.com/yt-dlp/yt-dlp#output-template)
  - Full path with the default `download_directory`
  is: `~/videos/YouTube/<uploader>/<title>.<ext>`

## License

This project is licensed under the terms of the GPLv3 license.
