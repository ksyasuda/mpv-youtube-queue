local json = require("json")

local history_client = {}

function history_client.new(config)
	local client = {
		mp = config.mp,
		options = config.options,
		notify = config.notify,
	}

	function client:add_video(video)
		if not self.options.use_history_db or not video then
			return false
		end

		self.mp.command_native_async({
			name = "subprocess",
			playback_only = false,
			capture_stdout = true,
			args = {
				"curl",
				"-X",
				"POST",
				self.options.backend_host .. ":" .. self.options.backend_port .. "/add_video",
				"-H",
				"Content-Type: application/json",
				"-d",
				json.encode(video),
			},
		}, function(success, result, err)
			if not success or not result or result.status ~= 0 then
				self.notify("Failed to send video data to backend: " .. (err or "request failed"), nil, true)
				return
			end
			self.notify("Video added to history db", nil, false)
		end)
		return true
	end

	return client
end

return history_client
