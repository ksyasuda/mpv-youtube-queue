local state = require("state")

local function eq(actual, expected, message)
	assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local function same_table(actual, expected, message)
	eq(#actual, #expected, message .. " length")
	for i, value in ipairs(expected) do
		eq(actual[i], value, message .. " [" .. i .. "]")
	end
end

do
	local start_index, end_index = state.get_display_range(20, 20, 10)
	eq(start_index, 11, "range start should backfill near queue end")
	eq(end_index, 20, "range end should stop at queue end")
end

do
	local result = state.remove_queue_item({
		queue = { "a", "b", "c", "d" },
		current_index = 2,
		selected_index = 4,
		marked_index = 3,
	})
	same_table(result.queue, { "a", "b", "c" }, "remove after current queue")
	eq(result.current_index, 2, "current index should not shift when removing after current")
	eq(result.selected_index, 3, "selected index should move to previous row when deleting last row")
	eq(result.marked_index, 3, "marked index should remain attached to same item when removing after it")
end

do
	local result = state.remove_queue_item({
		queue = { "a", "b", "c", "d" },
		current_index = 4,
		selected_index = 2,
		marked_index = 4,
	})
	same_table(result.queue, { "a", "c", "d" }, "remove before current queue")
	eq(result.current_index, 3, "current index should shift back when removing before current")
	eq(result.marked_index, 3, "marked index should rebase when its item shifts")
end

do
	local result = state.reorder_queue({
		queue = { "a", "b", "c", "d" },
		current_index = 3,
		selected_index = 1,
		from_index = 1,
		to_index = 3,
	})
	same_table(result.queue, { "b", "c", "a", "d" }, "reorder into current slot queue")
	eq(result.current_index, 2, "current index should follow the current item when inserting before it")
	eq(result.selected_index, 3, "selected index should follow moved item")
end

do
	local ok, err = pcall(function()
		state.normalize_reorder_indices("2", "4")
	end)
	assert(ok, "string reorder indices should be accepted: " .. tostring(err))
end
