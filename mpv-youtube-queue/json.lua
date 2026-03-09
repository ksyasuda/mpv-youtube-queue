local json = {}

local function escape_string(value)
	local escaped = value
	escaped = escaped:gsub("\\", "\\\\")
	escaped = escaped:gsub('"', '\\"')
	escaped = escaped:gsub("\b", "\\b")
	escaped = escaped:gsub("\f", "\\f")
	escaped = escaped:gsub("\n", "\\n")
	escaped = escaped:gsub("\r", "\\r")
	escaped = escaped:gsub("\t", "\\t")
	return escaped
end

local function is_array(value)
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count = count + 1
	end
	return count == #value
end

local function encode_value(value)
	local value_type = type(value)
	if value_type == "string" then
		return '"' .. escape_string(value) .. '"'
	end
	if value_type == "number" or value_type == "boolean" then
		return tostring(value)
	end
	if value == nil then
		return "null"
	end
	if value_type ~= "table" then
		error("unsupported json type: " .. value_type)
	end

	if is_array(value) then
		local encoded = {}
		for _, item in ipairs(value) do
			table.insert(encoded, encode_value(item))
		end
		return "[" .. table.concat(encoded, ",") .. "]"
	end

	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys)

	local encoded = {}
	for _, key in ipairs(keys) do
		table.insert(encoded, '"' .. escape_string(key) .. '":' .. encode_value(value[key]))
	end
	return "{" .. table.concat(encoded, ",") .. "}"
end

function json.encode(value)
	return encode_value(value)
end

local function new_parser(input)
	local parser = {
		input = input,
		index = 1,
		length = #input,
	}

	function parser:peek()
		return self.input:sub(self.index, self.index)
	end

	function parser:consume()
		local char = self:peek()
		self.index = self.index + 1
		return char
	end

	function parser:skip_whitespace()
		while self.index <= self.length do
			local char = self:peek()
			if not char:match("%s") then
				return
			end
			self.index = self.index + 1
		end
	end

	function parser:error(message)
		error(string.format("json parse error at %d: %s", self.index, message))
	end

	return parser
end

local parse_value

local function parse_string(parser)
	if parser:consume() ~= '"' then
		parser:error("expected '\"'")
	end

	local result = {}
	while parser.index <= parser.length do
		local char = parser:consume()
		if char == '"' then
			return table.concat(result)
		end
		if char ~= "\\" then
			table.insert(result, char)
			goto continue
		end

		local escape = parser:consume()
		local replacements = {
			['"'] = '"',
			["\\"] = "\\",
			["/"] = "/",
			["b"] = "\b",
			["f"] = "\f",
			["n"] = "\n",
			["r"] = "\r",
			["t"] = "\t",
		}
		if escape == "u" then
			local codepoint = parser.input:sub(parser.index, parser.index + 3)
			if #codepoint < 4 or not codepoint:match("^[0-9a-fA-F]+$") then
				parser:error("invalid unicode escape")
			end
			parser.index = parser.index + 4
			table.insert(result, utf8.char(tonumber(codepoint, 16)))
		elseif replacements[escape] then
			table.insert(result, replacements[escape])
		else
			parser:error("invalid escape sequence")
		end

		::continue::
	end

	parser:error("unterminated string")
end

local function parse_number(parser)
	local start_index = parser.index
	while parser.index <= parser.length do
		local char = parser:peek()
		if not char:match("[%d%+%-%.eE]") then
			break
		end
		parser.index = parser.index + 1
	end
	local value = tonumber(parser.input:sub(start_index, parser.index - 1))
	if value == nil then
		parser:error("invalid number")
	end
	return value
end

local function parse_literal(parser, literal, value)
	if parser.input:sub(parser.index, parser.index + #literal - 1) ~= literal then
		parser:error("expected " .. literal)
	end
	parser.index = parser.index + #literal
	return value
end

local function parse_array(parser)
	parser:consume()
	parser:skip_whitespace()
	local result = {}
	if parser:peek() == "]" then
		parser:consume()
		return result
	end

	while true do
		table.insert(result, parse_value(parser))
		parser:skip_whitespace()
		local char = parser:consume()
		if char == "]" then
			return result
		end
		if char ~= "," then
			parser:error("expected ',' or ']'")
		end
		parser:skip_whitespace()
	end
end

local function parse_object(parser)
	parser:consume()
	parser:skip_whitespace()
	local result = {}
	if parser:peek() == "}" then
		parser:consume()
		return result
	end

	while true do
		if parser:peek() ~= '"' then
			parser:error("expected string key")
		end
		local key = parse_string(parser)
		parser:skip_whitespace()
		if parser:consume() ~= ":" then
			parser:error("expected ':'")
		end
		parser:skip_whitespace()
		result[key] = parse_value(parser)
		parser:skip_whitespace()
		local char = parser:consume()
		if char == "}" then
			return result
		end
		if char ~= "," then
			parser:error("expected ',' or '}'")
		end
		parser:skip_whitespace()
	end
end

parse_value = function(parser)
	parser:skip_whitespace()
	local char = parser:peek()
	if char == '"' then
		return parse_string(parser)
	end
	if char == "[" then
		return parse_array(parser)
	end
	if char == "{" then
		return parse_object(parser)
	end
	if char == "t" then
		return parse_literal(parser, "true", true)
	end
	if char == "f" then
		return parse_literal(parser, "false", false)
	end
	if char == "n" then
		return parse_literal(parser, "null", nil)
	end
	if char:match("[%d%-]") then
		return parse_number(parser)
	end
	parser:error("unexpected token")
end

function json.decode(input)
	local parser = new_parser(input)
	local value = parse_value(parser)
	parser:skip_whitespace()
	if parser.index <= parser.length then
		parser:error("trailing characters")
	end
	return value
end

return json
