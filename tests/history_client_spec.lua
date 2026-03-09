local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(
			(message or "values differ")
				.. string.format("\nexpected: %s\nactual: %s", tostring(expected), tostring(actual))
		)
	end
end

local function assert_nil(value, message)
	if value ~= nil then
		error((message or "expected nil") .. string.format("\nactual: %s", tostring(value)))
	end
end

local function assert_truthy(value, message)
	if not value then
		error(message or "expected truthy value")
	end
end

package.loaded["history_client"] = nil
package.loaded["json"] = nil

local calls = {}
local notices = {}
local client = require("history_client").new({
	mp = {
		command_native_async = function(command, callback)
			table.insert(calls, command)
			callback(true, { status = 0 }, nil)
		end,
	},
	options = {
		use_history_db = true,
		backend_host = "http://backend.test",
		backend_port = "42069",
	},
	notify = function(message)
		table.insert(notices, message)
	end,
})

assert_nil(client.save_queue, "queue save backend API should be removed")
assert_nil(client.load_queue, "queue load backend API should be removed")

local ok = client:add_video({
	video_name = "Demo",
	video_url = "https://example.test/watch?v=1",
})

assert_truthy(ok, "add_video should still be enabled for shared backend")
assert_equal(#calls, 1, "add_video should issue one backend request")
assert_equal(calls[1].args[1], "curl", "backend request should use curl subprocess")
assert_equal(
	calls[1].args[4],
	"http://backend.test:42069/add_video",
	"backend request should target add_video endpoint"
)
assert_equal(notices[#notices], "Video added to history db", "successful add_video should notify")
