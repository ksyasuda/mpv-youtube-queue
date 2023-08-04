# mpv-youtube-queue

A Lua script for mpv that allows you to add YouTube videos to a queue,
navigate through the queue, and select a video to play.

![mpv-youtube-queue image](.assets/mpv-youtube-queue.png)

## Features

- Add YouTube videos to a queue from the clipboard
- Fetch and display the video and channel names of the videos in the queue
- Select a video to play from the queue with an interactive menu,
  or navigate through the queue with keyboard shortcuts
- Open the URL of the currently playing video in a new browser tab
- Open the channel page of the currently playing video
- Download the currently playing video

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
- Optionally copy the `mpv-youtube-queue.conf` to the `~~/script-opts` directory
  to customize the script configuration

## License

This project is licensed under the terms of the GPLv3 license.
