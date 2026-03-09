local state = {}

local function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

local function copy_queue(queue)
	local copied = {}
	for i, item in ipairs(queue) do
		copied[i] = item
	end
	return copied
end

local function move_index(index_value, from_index, to_index)
	if index_value == nil then
		return nil
	end
	if index_value == from_index then
		return to_index
	end
	if from_index < index_value and to_index >= index_value then
		return index_value - 1
	end
	if from_index > index_value and to_index <= index_value then
		return index_value + 1
	end
	return index_value
end

function state.normalize_reorder_indices(from_index, to_index)
	local normalized_from = tonumber(from_index)
	local normalized_to = tonumber(to_index)
	if normalized_from == nil or normalized_to == nil then
		error("invalid reorder indices")
	end
	return normalized_from, normalized_to
end

function state.get_display_range(queue_length, selected_index, limit)
	if queue_length <= 0 or limit <= 0 then
		return 1, 0
	end

	local normalized_selected = clamp(selected_index, 1, queue_length)
	if queue_length <= limit then
		return 1, queue_length
	end

	local half_limit = math.floor(limit / 2)
	local start_index = normalized_selected - half_limit
	start_index = clamp(start_index, 1, queue_length - limit + 1)
	local end_index = math.min(queue_length, start_index + limit - 1)
	return start_index, end_index
end

function state.remove_queue_item(args)
	local queue = copy_queue(args.queue)
	local selected_index = args.selected_index
	if selected_index < 1 or selected_index > #queue then
		error("invalid selected index")
	end

	table.remove(queue, selected_index)

	local current_index = args.current_index or 0
	if current_index > 0 and selected_index < current_index then
		current_index = current_index - 1
	elseif #queue == 0 then
		current_index = 0
	end

	local marked_index = args.marked_index
	if marked_index == selected_index then
		marked_index = nil
	elseif marked_index ~= nil and marked_index > selected_index then
		marked_index = marked_index - 1
	end

	local next_selected = selected_index
	if #queue == 0 then
		next_selected = 1
	else
		next_selected = clamp(next_selected, 1, #queue)
	end

	return {
		queue = queue,
		current_index = current_index,
		selected_index = next_selected,
		marked_index = marked_index,
	}
end

function state.reorder_queue(args)
	local from_index, to_index = state.normalize_reorder_indices(args.from_index, args.to_index)
	local queue = copy_queue(args.queue)
	if from_index < 1 or from_index > #queue or to_index < 1 or to_index > #queue then
		error("invalid reorder indices")
	end
	if from_index == to_index then
		return {
			queue = queue,
			current_index = args.current_index or 0,
			selected_index = args.selected_index or to_index,
			marked_index = args.marked_index,
			mpv_from = from_index - 1,
			mpv_to = to_index - 1,
		}
	end

	local moved_item = queue[from_index]
	table.remove(queue, from_index)
	table.insert(queue, to_index, moved_item)

	local current_index = move_index(args.current_index or 0, from_index, to_index)
	local marked_index = move_index(args.marked_index, from_index, to_index)

	local mpv_to = to_index - 1
	if from_index < to_index then
		mpv_to = to_index
	end

	return {
		queue = queue,
		current_index = current_index,
		selected_index = to_index,
		marked_index = marked_index,
		mpv_from = from_index - 1,
		mpv_to = mpv_to,
	}
end

return state
