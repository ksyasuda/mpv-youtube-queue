local input = {}

function input.is_file_info(result)
	return type(result) == "table" and result.is_file == true
end

function input.sanitize_source(value)
	if value == nil then
		return nil
	end

	local sanitized = value:match("^%s*(.-)%s*$")
	if sanitized == nil then
		return nil
	end
	if #sanitized >= 2 then
		local first_char = sanitized:sub(1, 1)
		local last_char = sanitized:sub(-1)
		if (first_char == '"' and last_char == '"') or (first_char == "'" and last_char == "'") then
			sanitized = sanitized:sub(2, -2)
		end
	end
	return sanitized
end

function input.split_command(command)
	local parts = {}
	local current = {}
	local quote = nil

	for i = 1, #command do
		local char = command:sub(i, i)
		if quote then
			if char == quote then
				quote = nil
			else
				table.insert(current, char)
			end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char:match("%s") then
			if #current > 0 then
				table.insert(parts, table.concat(current))
				current = {}
			end
		else
			table.insert(current, char)
		end
	end

	if #current > 0 then
		table.insert(parts, table.concat(current))
	end

	return parts
end

return input
