vim.opt.runtimepath:prepend(vim.fn.getcwd())
-- Keep checks isolated from the user's persisted forwarding definitions.
local data_dir = vim.fn.tempname()
local stdpath = vim.fn.stdpath
vim.fn.stdpath = function(kind) return kind == "data" and data_dir or stdpath(kind) end
local ito = require("ito")
local ports = require("ito.ports")
local mappings = assert(ito.parse({ "# comment", "", "3000 -> 80", " 15432 -> 5432 " }))
assert(#mappings == 2 and mappings[2].remote_port == 5432)
assert(not ito.parse({ "0 -> 80" }))
assert(not ito.parse({ "3000 -> 65536" }))
assert(not ito.parse({ "3000 -> 80", "3000 -> 81" }))
assert(not ito.parse({ "execute something" }))
local addressed = assert(ito.parse({ "0.0.0.0:8080 -> web.internal:80", "[::1]:8080 -> [2001:db8::1]:443" }))
assert(addressed[1].bind_address == "0.0.0.0" and addressed[1].remote_address == "web.internal")
assert(addressed[2].bind_address == "[::1]" and addressed[2].remote_port == 443)
assert(not ito.parse({ "8080 -> :80" }))
assert(not ito.parse({ "8080 -> ::1:80" }))
assert(not ito.parse({ "8080 -> host/path:80" }))
assert(not ito.parse({ "8080 -> 80", "127.0.0.1:8080 -> 81" }))
ito.setup({ default_bind_address = "localhost", default_remote_address = "db.internal" })
local defaults = assert(ito.parse({ "8080 -> 80", "0.0.0.0:8081 -> web.internal:81" }))
assert(defaults[1].bind_address == "localhost" and defaults[1].remote_address == "db.internal")
assert(defaults[2].bind_address == "0.0.0.0" and defaults[2].remote_address == "web.internal")
ito.setup({ default_bind_address = "127.0.0.1", default_remote_address = "127.0.0.1" })
assert(vim.deep_equal(ports.parse("LISTEN 0 128 127.0.0.1:3000 0.0.0.0:*\nLISTEN 0 128 [::]:80 [::]:*"), { 80, 3000 }))
assert(vim.deep_equal(ports.parse("node 123 user 1u IPv4 0x0 0t0 TCP *:8080 (LISTEN)"), { 8080 }))
assert(vim.deep_equal(ports.parse("tcp4 0 0 127.0.0.1.5432 *.* LISTEN"), { 5432 }))

-- Exercise reconciliation with a mock SSH process, without a remote server.
local starts, stops, callbacks = {}, {}, {}
local notices = {}
vim.notify = function(message) notices[#notices + 1] = message end
vim.fn.jobstart = function(command, opts)
  starts[#starts + 1] = command
  callbacks[#starts] = opts
  return #starts
end
vim.fn.jobstop = function(id) stops[#stops + 1] = id; return 1 end
ito.open("test-host")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "3000 -> 80" })
vim.cmd("write")
assert(#starts == 1 and starts[1][#starts[1]] == "test-host")
vim.cmd("write")
assert(#starts == 1)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "3000 -> 81" })
vim.cmd("write")
assert(#starts == 2 and #stops == 1)
callbacks[1].on_exit(1, 0) -- stale exit must not affect its replacement
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "bad input" })
vim.cmd("write")
assert(#starts == 2 and #stops == 1 and vim.bo[buf].modified)
assert(notices[#notices]:find("expected LOCAL", 1, true))
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
vim.cmd("write")
assert(#stops == 2)
vim.api.nvim_buf_delete(buf, { force = true })

local origin_win = vim.api.nvim_get_current_win()
local origin_buf = vim.api.nvim_get_current_buf()
ito.open()
local dashboard = vim.api.nvim_get_current_buf()
local float = vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_config(float).relative == "editor")
assert(vim.api.nvim_win_get_buf(origin_win) == origin_buf)
ito.dashboard()
assert(vim.api.nvim_get_current_win() == float)
local columns = vim.o.columns
vim.o.columns = 50
vim.api.nvim_exec_autocmds("VimResized", {})
assert(vim.api.nvim_win_get_config(float).width < 50)
vim.o.columns = columns
vim.api.nvim_exec_autocmds("VimResized", {})
local function dashboard_text()
  return table.concat(vim.api.nvim_buf_get_lines(dashboard, 0, -1, false), "\n")
end
assert(dashboard_text():find("No hosts yet", 1, true))
ito.open("alpha")
local alpha = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(alpha, 0, -1, false, { "4000 -> 80" })
vim.cmd("write")
ito.open("beta")
local beta = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(beta, 0, -1, false, { "5000 -> 90" })
vim.cmd("write")
ito.dashboard()
assert(vim.api.nvim_get_current_buf() == dashboard)
assert(dashboard_text():find("alpha  [1 running]", 1, true))
assert(dashboard_text():find("5000 -> 90  [running]", 1, true))
local function press(key)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(dashboard, "n")) do
    if mapping.lhs == key then mapping.callback(); return end
  end
  error("Missing dashboard mapping: " .. key)
end
vim.api.nvim_win_set_cursor(0, { 5, 0 }) -- alpha's pair also navigates to alpha
press("<CR>")
assert(vim.api.nvim_get_current_buf() == alpha)
assert(vim.api.nvim_get_current_win() == origin_win)
assert(not vim.api.nvim_win_is_valid(float))
vim.api.nvim_buf_set_lines(alpha, 0, -1, false, { "4000 -> 81" })
ito.dashboard() -- preserve a modified acwrite buffer even with 'hidden' off
assert(vim.bo[alpha].modified)
assert(dashboard_text():find("[unsaved edits]", 1, true))
assert(dashboard_text():find("4000 -> 81  [not applied]", 1, true))
press("q")
assert(vim.api.nvim_get_current_win() == origin_win)
assert(vim.api.nvim_get_current_buf() == alpha and vim.bo[alpha].modified)
ito.dashboard()
press("<Esc>")
assert(vim.api.nvim_get_current_buf() == alpha)
ito.dashboard()
local before_stop = #stops
vim.api.nvim_win_set_cursor(0, { 4, 0 })
press("s")
assert(#stops == before_stop + 1)
assert(dashboard_text():find("alpha  [0 running]", 1, true))
assert(dashboard_text():find("beta  [1 running]", 1, true))
callbacks[4].on_exit(4, 255)
assert(dashboard_text():find("5000 -> 90  [exited (255)]", 1, true))
press("q")
vim.api.nvim_buf_delete(alpha, { force = true })
assert(not dashboard_text():find("alpha", 1, true), dashboard_text())
vim.api.nvim_buf_delete(beta, { force = true })
assert(dashboard_text():find("No hosts yet", 1, true))
vim.api.nvim_buf_delete(dashboard, { force = true })
ito.dashboard()
assert(vim.api.nvim_buf_is_valid(vim.api.nvim_get_current_buf()))

ito.open("gateway")
local gateway = vim.api.nvim_get_current_buf()
local function forward_arg(command)
  for i, arg in ipairs(command) do if arg == "-L" then return command[i + 1] end end
end
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, { "127.0.0.1:8080 -> web.internal:80" })
vim.cmd("write")
assert(forward_arg(starts[#starts]) == "127.0.0.1:8080:web.internal:80")
local start_count, stop_count = #starts, #stops
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, { "127.0.0.1:8080 -> other.internal:80" })
ito.dashboard()
local overview = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(overview:find("127.0.0.1:8080 -> other.internal:80  [not applied]", 1, true))
ito.open("gateway")
vim.cmd("write")
assert(#starts == start_count + 1 and #stops == stop_count + 1)
assert(forward_arg(starts[#starts]) == "127.0.0.1:8080:other.internal:80")
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, { "[::1]:8080 -> [::1]:80", "127.0.0.1:8080 -> 80" })
vim.cmd("write")
assert(#starts == start_count + 3 and #stops == stop_count + 2)
assert(forward_arg(starts[#starts - 1]) == "[::1]:8080:[::1]:80")
vim.cmd("write")
assert(#starts == start_count + 3)
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, { "8080 -> 80" })
vim.cmd("write")
ito.setup({ default_remote_address = "db.internal" })
vim.cmd("write")
assert(forward_arg(starts[#starts]) == "127.0.0.1:8080:db.internal:80")
local original_scan, original_input = ports.scan, vim.ui.input
ports.scan = function(host, _, callback) callback(host and { 5432 } or {}) end
vim.ui.input = function(_, callback) callback("15432") end
local function buffer_key(buffer, key)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do
    if mapping.lhs == key then mapping.callback(); return end
  end
  error("Missing mapping: " .. key)
end
buffer_key(gateway, "gp")
local port_buf = vim.api.nvim_get_current_buf()
for row, line in ipairs(vim.api.nvim_buf_get_lines(port_buf, 0, -1, false)) do
  if line == "5432" then vim.api.nvim_win_set_cursor(0, { row, 0 }); break end
end
buffer_key(port_buf, "<CR>")
local discovered = assert(ito.parse(vim.api.nvim_buf_get_lines(gateway, 0, -1, false)))
assert(discovered[2].local_port == 15432 and discovered[2].remote_address == "127.0.0.1")
vim.cmd("close")
ports.scan, vim.ui.input = original_scan, original_input
vim.api.nvim_buf_delete(gateway, { force = true })
ito.setup({ default_remote_address = "127.0.0.1" })
ito.open("forgotten")
local forgotten = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(forgotten, 0, -1, false, { "7000 -> 70" })
vim.cmd("write")
ito.dashboard()
vim.api.nvim_win_set_cursor(0, { 4, 0 })
local dashboard_window = vim.api.nvim_get_current_win()
buffer_key(vim.api.nvim_get_current_buf(), "d")
assert(not vim.api.nvim_buf_is_valid(forgotten))
assert(vim.api.nvim_get_current_win() == dashboard_window)
assert(not table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("forgotten", 1, true))
print("ito checks passed")
vim.fn.delete(data_dir, "rf")
