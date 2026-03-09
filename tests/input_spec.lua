local input = require("input")

local function eq(actual, expected, message)
	assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

do
	local sanitized = input.sanitize_source([[  "Mary's Video.mp4"
]])
	eq(sanitized, "Mary's Video.mp4", "sanitize should trim wrapper quotes and whitespace without dropping apostrophes")
end

do
	eq(input.is_file_info({ is_file = true }), true, "file info should accept files")
	eq(input.is_file_info({ is_file = false }), false, "file info should reject directories")
	eq(input.is_file_info(nil), false, "file info should reject missing paths")
end
