local state = require("state")

local ui = {}

local colors = {
	error = "9687ED",
	selected = "F5BDE6",
	hover_selected = "C6C6F0",
	cursor = "9FD4EE",
	header = "CAD58B",
	hover = "F8BDB7",
	text = "E0C0B8",
	marked = "F6A0C6",
}

local function truncate_string(value, max_length)
	if not value or max_length <= 0 then
		return value or ""
	end
	if #value <= max_length then
		return value
	end
	if max_length <= 3 then
		return value:sub(1, max_length)
	end
	return value:sub(1, max_length - 3) .. "..."
end

local function format_tag(font_name, font_size, color, alpha, extra)
	return string.format("{\\fn%s\\fs%d\\c&H%s&\\alpha&H%s&%s}", font_name, font_size, color, alpha, extra or "")
end

function ui.create(options)
	local assdraw = require("mp.assdraw")
	local styles = {
		error = format_tag(options.font_name, options.font_size, colors.error, "00"),
		text = format_tag(options.font_name, options.font_size, colors.text, "59"),
		selected = format_tag(options.font_name, options.font_size, colors.selected, "40"),
		hover_selected = format_tag(options.font_name, options.font_size, colors.hover_selected, "33"),
		hover = format_tag(options.font_name, options.font_size, colors.hover, "40"),
		cursor = format_tag(options.font_name, options.font_size, colors.cursor, "00"),
		marked = format_tag(options.font_name, options.font_size, colors.marked, "00"),
		header = format_tag(options.font_name, math.floor(options.font_size * 1.5), colors.header, "00", "\\u1\\b1"),
		reset = "{\\r}",
	}

	local renderer = { styles = styles }

	function renderer:message_style(is_error)
		if is_error then
			return self.styles.error
		end
		return self.styles.text
	end

	function renderer:render_queue(queue, current_index, selected_index, marked_index)
		local ass = assdraw.ass_new()
		local position_indicator = current_index > 0 and string.format(" [%d/%d]", current_index, #queue)
			or string.format(" [%d videos]", #queue)

		ass:append(
			self.styles.header .. "MPV-YOUTUBE-QUEUE" .. position_indicator .. "{\\u0\\b0}" .. self.styles.reset .. "\n"
		)

		local start_index, end_index = state.get_display_range(#queue, selected_index, options.display_limit)
		for i = start_index, end_index do
			local item = queue[i]
			local prefix = "\\h\\h\\h"
			if i == selected_index then
				prefix = self.styles.cursor .. options.cursor_icon .. "\\h" .. self.styles.reset
			end

			local item_style = self.styles.text
			if i == current_index and i == selected_index then
				item_style = self.styles.hover_selected
			elseif i == current_index then
				item_style = self.styles.selected
			elseif i == selected_index then
				item_style = self.styles.hover
			end

			local title = truncate_string(item.video_name or "", options.max_title_length)
			local channel = item.channel_name or ""
			local line = string.format("%s%s%d. %s - (%s)%s", prefix, item_style, i, title, channel, self.styles.reset)
			if i == marked_index then
				line = line .. " " .. self.styles.marked .. options.marked_icon .. self.styles.reset
			end
			ass:append(line .. "\n")
		end

		return ass.text
	end

	return renderer
end

return ui
