# mpv-youtube-queue

A Lua script for mpv that allows you to add YouTube videos to a queue,
navigate through the queue, and select a video to play.

![mpv-youtube-queue image](.assets/mpv-youtube-queue.png)

## Features

- Add YouTube videos to a queue from the clipboard
- Select a video from the queue to play from an interactive menu,
  or navigate through the queue with keybinds
- Open the URL of the currently playing video in a new browser tab.
- Fetch and display the names of YouTube videos.
- Print the current contents of the queue

## Notes

- This script uses the Linux `xclip` utility to read from the clipboard.
  If you're on macOS or Windows, you'll need to adjust the setting in
  `mpv-youtube-queue.conf` as described in the [install section](#installation).
- When adding videos to the queue, the script fetches the video name using
  `yt-dlp`. Ensure you have `yt-dlp` installed and in your PATH.
- The script maintains its own queue separate from mpv's internal playlist.
  This means that loading files manually or using the next/previous buttons on
  the mpv OSC will not affect the queue.

## Requirements

This script requires the following software to be installed on the system

- [xclip](https://github.com/astrand/xclip)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)

## Installation

- Copy the `mpv-youtube-queue.lua` script to your `~~/scripts` directory
- Optionally copy the `mpv-youtube-queue.conf` to the `~~/script-opts` directory
  to customize the keybindings

## License

This project is licensed under the terms of the GPLv3 license.
