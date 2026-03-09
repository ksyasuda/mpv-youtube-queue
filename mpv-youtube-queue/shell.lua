local input = require("input")

local shell = {}

local function expanduser(path)
	if path:sub(-1) == "/" then
		path = path:sub(1, -2)
	end
	if path:sub(1, 1) == "~" then
		local home = os.getenv("HOME")
		if home then
			return home .. path:sub(2)
		end
	end
	return path
end

function shell.new(config)
	local runner = {
		mp = config.mp,
		options = config.options,
		notify = config.notify,
		is_file = config.is_file,
	}

	function runner:open_in_browser(target)
		if not target or target == "" then
			return
		end
		local browser_args = input.split_command(self.options.browser)
		if #browser_args == 0 then
			self.notify("Invalid browser command", nil, true)
			return
		end
		table.insert(browser_args, target)
		self.mp.command_native({
			name = "subprocess",
			playback_only = false,
			detach = true,
			args = browser_args,
		})
	end

	function runner:download_video(video)
		if self:is_file(video.video_url) then
			self.notify("Current video is a local file... doing nothing.", nil, true)
			return false
		end

		local quality = self.options.download_quality:sub(1, -2)
		self.notify("Downloading " .. video.video_name .. "...", nil, false)
		self.mp.command_native_async({
			name = "subprocess",
			capture_stderr = true,
			detach = true,
			args = {
				"yt-dlp",
				"-f",
				"bestvideo[height<="
					.. quality
					.. "][ext="
					.. self.options.ytdlp_file_format
					.. "]+bestaudio/best[height<="
					.. quality
					.. "]/bestvideo[height<="
					.. quality
					.. "]+bestaudio/best[height<="
					.. quality
					.. "]",
				"-o",
				expanduser(self.options.download_directory) .. "/" .. self.options.ytdlp_output_template,
				"--downloader",
				self.options.downloader,
				"--",
				video.video_url,
			},
		}, function(success, _, err)
			if success then
				self.notify("Finished downloading " .. video.video_name .. ".", nil, false)
				return
			end
			self.notify("Error downloading " .. video.video_name .. ": " .. (err or "request failed"), nil, true)
		end)
		return true
	end

	return runner
end

return shell
