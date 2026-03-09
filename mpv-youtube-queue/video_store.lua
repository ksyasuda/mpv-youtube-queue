local input = require("input")

local VIDEO_INFO_CACHE_MAX_SIZE = 100

local video_store = {}

local function copy_table(value)
	local copied = {}
	for key, item in pairs(value) do
		copied[key] = item
	end
	return copied
end

local function build_local_video(path)
	local directory, filename = path:match("^(.*[/\\])(.-)$")
	if not directory or not filename then
		return nil
	end
	return {
		video_url = path,
		video_name = filename,
		channel_url = directory,
		channel_name = "Local file",
		thumbnail_url = "",
		view_count = "",
		upload_date = "",
		category = "",
		subscribers = 0,
	}
end

local function build_remote_placeholder(url, title)
	return {
		video_url = url,
		video_name = title or url,
		channel_url = "",
		channel_name = "Remote URL",
		thumbnail_url = "",
		view_count = "",
		upload_date = "",
		category = "Unknown",
		subscribers = 0,
	}
end

function video_store.new(config)
	local store = {
		mp = config.mp,
		utils = config.utils,
		options = config.options,
		notify = config.notify,
		cache = {},
		cache_order = {},
	}

	function store:is_file(path)
		return input.is_file_info(self.utils.file_info(path))
	end

	function store.normalize_source(_, source)
		if source and source:match("^file://") then
			return source:gsub("^file://", "")
		end
		return source
	end

	function store:cache_video_info(url, info)
		if self.cache[url] then
			for i, cached_url in ipairs(self.cache_order) do
				if cached_url == url then
					table.remove(self.cache_order, i)
					break
				end
			end
		end
		while #self.cache_order >= VIDEO_INFO_CACHE_MAX_SIZE do
			local oldest_url = table.remove(self.cache_order, 1)
			self.cache[oldest_url] = nil
		end
		self.cache[url] = copy_table(info)
		table.insert(self.cache_order, url)
	end

	function store:get_cached_video_info(url)
		local cached = self.cache[url]
		if not cached then
			return nil
		end
		for i, cached_url in ipairs(self.cache_order) do
			if cached_url == url then
				table.remove(self.cache_order, i)
				table.insert(self.cache_order, url)
				break
			end
		end
		return copy_table(cached)
	end

	function store:get_clipboard_content()
		local result = self.mp.command_native({
			name = "subprocess",
			playback_only = false,
			capture_stdout = true,
			args = input.split_command(self.options.clipboard_command),
		})
		if result.status ~= 0 then
			self.notify("Failed to get clipboard content", nil, true)
			return nil
		end

		local content = input.sanitize_source(result.stdout)
		if not content then
			return nil
		end
		if content:match("^https?://") or content:match("^file://") or self:is_file(content) then
			return content
		end
		self.notify("Clipboard content is not a valid URL or file path", nil, true)
		return nil
	end

	function store:get_video_info(url)
		local cached = self:get_cached_video_info(url)
		if cached then
			return cached
		end

		self.notify("Getting video info...", 3, false)
		local result = self.mp.command_native({
			name = "subprocess",
			playback_only = false,
			capture_stdout = true,
			args = {
				"yt-dlp",
				"--dump-single-json",
				"--ignore-config",
				"--no-warnings",
				"--skip-download",
				"--playlist-items",
				"1",
				url,
			},
		})
		if result.status ~= 0 or not result.stdout or result.stdout:match("^%s*$") then
			self.notify("Failed to get video info (yt-dlp error)", nil, true)
			return nil
		end

		local data = self.utils.parse_json(result.stdout)
		if type(data) ~= "table" then
			self.notify("Failed to parse JSON from yt-dlp", nil, true)
			return nil
		end

		local info = {
			channel_url = data.channel_url or "",
			channel_name = data.uploader or "",
			video_name = data.title or "",
			view_count = data.view_count or "",
			upload_date = data.upload_date or "",
			category = data.categories and data.categories[1] or "Unknown",
			thumbnail_url = data.thumbnail or "",
			subscribers = data.channel_follower_count or 0,
		}
		if info.channel_url == "" or info.channel_name == "" or info.video_name == "" then
			self.notify("Missing metadata in yt-dlp JSON", nil, true)
			return nil
		end

		self:cache_video_info(url, info)
		return copy_table(info)
	end

	function store:resolve_video(source)
		local normalized = self:normalize_source(source)
		if self:is_file(normalized) then
			return build_local_video(normalized)
		end

		local info = self:get_video_info(normalized)
		if not info then
			return nil
		end
		info.video_url = normalized
		return info
	end

	function store:sync_playlist()
		local count = self.mp.get_property_number("playlist-count", 0)
		if count == 0 then
			return {}
		end

		local current_path = self.mp.get_property("path")
		local queue = {}
		for i = 0, count - 1 do
			local url = self.mp.get_property(string.format("playlist/%d/filename", i))
			if url then
				local entry
				if self:is_file(url) then
					entry = build_local_video(url)
				else
					local cached = self:get_cached_video_info(url)
					if cached then
						cached.video_url = url
						entry = cached
					else
						local title = self.mp.get_property(string.format("playlist/%d/title", i))
						if url == current_path then
							local info = self:get_video_info(url)
							if info then
								info.video_url = url
								entry = info
							else
								entry = build_remote_placeholder(url, self.mp.get_property("media-title") or title)
								self:cache_video_info(url, entry)
							end
						else
							entry = build_remote_placeholder(url, title)
						end
					end
				end
				table.insert(queue, entry)
			end
		end

		return queue
	end

	return store
end

return video_store
