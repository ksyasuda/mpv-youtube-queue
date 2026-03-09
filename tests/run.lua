package.path = table.concat({
	"./?.lua",
	"./?/init.lua",
	"./?/?.lua",
	"./mpv-youtube-queue/?.lua",
	"./mpv-youtube-queue/?/?.lua",
	package.path,
}, ";")

local total = 0
local failed = 0

local function run_test(file)
	local chunk, err = loadfile(file)
	if not chunk then
		error(err)
	end
	local ok, test_err = pcall(chunk)
	total = total + 1
	if ok then
		io.write("PASS ", file, "\n")
		return
	end
	failed = failed + 1
	io.write("FAIL ", file, "\n", test_err, "\n")
end

local tests = {
	"tests/app_spec.lua",
	"tests/metadata_resolution_test.lua",
	"tests/state_spec.lua",
	"tests/history_client_spec.lua",
	"tests/input_spec.lua",
}

for _, file in ipairs(tests) do
	run_test(file)
end

if failed > 0 then
	error(string.format("%d/%d tests failed", failed, total))
end

io.write(string.format("PASS %d tests\n", total))
