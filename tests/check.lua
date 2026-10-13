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
assert(vim.deep_equal(ports.parse("LISTEN 0 128 127.0.0.1:3000 0.0.0.0:*\nLISTEN 0 128 [::]:80 [::]:*"),
  { { port = 80, processes = {} }, { port = 3000, processes = {} } }))
assert(vim.deep_equal(ports.parse("node 123 user 1u IPv4 0x0 0t0 TCP *:8080 (LISTEN)"),
  { { port = 8080, processes = { { name = "node", pid = 123 } } } }))
assert(vim.deep_equal(ports.parse("tcp4 0 0 127.0.0.1.5432 *.* LISTEN"), { { port = 5432, processes = {} } }))
local ss_listeners = ports.parse('LISTEN 0 128 [::]:80 [::]:* users:(("nginx",pid=20,fd=7),("nginx",pid=10,fd=7))\n'
  .. 'LISTEN 0 128 0.0.0.0:80 0.0.0.0:* users:(("nginx",pid=10,fd=8))')
assert(vim.deep_equal(ss_listeners, { { port = 80, processes = {
  { name = "nginx", pid = 10 }, { name = "nginx", pid = 20 },
} } }))
local lsof_listeners = ports.parse("p123\ncnode\nn127.0.0.1:8080\nn[::1]:8080\np456\ncPython Helper\nn*:8080\nn*:9000\n")
assert(#lsof_listeners == 2 and #lsof_listeners[1].processes == 2)
assert(lsof_listeners[2].processes[1].name == "Python Helper" and lsof_listeners[2].processes[1].pid == 456)
assert(ports.describe(lsof_listeners[1]):find("node (pid 123)", 1, true))
assert(ports.describe({ port = 5432, processes = {} }):find("process unavailable", 1, true))

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
vim.cmd("close")
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
assert(vim.api.nvim_get_current_win() == float)
assert(vim.api.nvim_win_get_buf(origin_win) == origin_buf)
vim.api.nvim_buf_set_lines(alpha, 0, -1, false, { "4000 -> 81" })
ito.dashboard() -- preserve a modified acwrite buffer even with 'hidden' off
assert(vim.bo[alpha].modified)
assert(dashboard_text():find("[unsaved edits]", 1, true))
assert(dashboard_text():find("4000 -> 81  [not applied]", 1, true))
press("q")
assert(vim.api.nvim_get_current_win() == origin_win)
assert(vim.api.nvim_get_current_buf() == origin_buf and vim.bo[alpha].modified)
ito.dashboard()
press("<Esc>")
assert(vim.api.nvim_get_current_buf() == origin_buf)
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
local original_scan = ports.scan
local original_terminate = ports.terminate
local stopped_processes = {}
ports.terminate = function(host, listener, process, _, callback)
  stopped_processes[#stopped_processes + 1] = { host = host, port = listener.port, pid = process.pid }
  callback(true)
end
ports.scan = function(host, _, callback)
  callback(host and { { port = 5432, processes = { { name = "postgres", pid = 456 } } } } or {})
end
local function buffer_key(buffer, key)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do
    if mapping.lhs == key then mapping.callback(); return end
  end
  error("Missing mapping: " .. key)
end
local unified_window = vim.api.nvim_get_current_win()
local window_count = #vim.api.nvim_list_wins()
buffer_key(gateway, "gp")
assert(vim.api.nvim_get_current_win() == unified_window)
assert(#vim.api.nvim_list_wins() == window_count)
local port_buf = vim.api.nvim_get_current_buf()
assert(table.concat(vim.api.nvim_buf_get_lines(port_buf, 0, -1, false), "\n"):find("postgres (pid 456)", 1, true))
for row, line in ipairs(vim.api.nvim_buf_get_lines(port_buf, 0, -1, false)) do
  if line:match("^5432%s") then vim.api.nvim_win_set_cursor(0, { row, 0 }); break end
end
buffer_key(port_buf, "k")
assert(stopped_processes[1].host == "gateway" and stopped_processes[1].pid == 456)
assert(vim.wait(1000, function() return not vim.api.nvim_buf_is_valid(port_buf) end, 10))
port_buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_get_current_win() == unified_window)
for row, line in ipairs(vim.api.nvim_buf_get_lines(port_buf, 0, -1, false)) do
  if line:match("^5432%s") then vim.api.nvim_win_set_cursor(0, { row, 0 }); break end
end
buffer_key(port_buf, "<CR>")
local input_buf = vim.api.nvim_get_current_buf()
assert(vim.bo[input_buf].filetype == "itoinput")
assert(vim.api.nvim_get_current_win() == unified_window)
vim.api.nvim_buf_set_lines(input_buf, 2, 3, false, { "0" })
buffer_key(input_buf, "<CR>")
assert(vim.api.nvim_get_current_buf() == input_buf)
assert(#assert(ito.parse(vim.api.nvim_buf_get_lines(gateway, 0, -1, false))) == 1)
vim.api.nvim_buf_set_lines(input_buf, 2, 3, false, { "15432" })
buffer_key(input_buf, "<CR>")
assert(vim.api.nvim_get_current_buf() == gateway)
assert(vim.api.nvim_get_current_win() == unified_window)
local discovered = assert(ito.parse(vim.api.nvim_buf_get_lines(gateway, 0, -1, false)))
assert(discovered[2].local_port == 15432 and discovered[2].remote_address == "127.0.0.1")
assert(vim.bo[gateway].modified)
buffer_key(gateway, "gp")
buffer_key(vim.api.nvim_get_current_buf(), "q")
assert(vim.api.nvim_get_current_buf() == gateway and vim.api.nvim_get_current_win() == unified_window)
buffer_key(gateway, "gp")
port_buf = vim.api.nvim_get_current_buf()
for row, line in ipairs(vim.api.nvim_buf_get_lines(port_buf, 0, -1, false)) do
  if line:match("^5432%s") then vim.api.nvim_win_set_cursor(0, { row, 0 }); break end
end
buffer_key(port_buf, "<CR>")
buffer_key(vim.api.nvim_get_current_buf(), "<Esc>")
assert(vim.bo.filetype == "itoports" and vim.api.nvim_get_current_win() == unified_window)
buffer_key(vim.api.nvim_get_current_buf(), "gd")
assert(vim.bo.filetype == "itodashboard" and vim.bo[gateway].modified)
ito.open("gateway")
assert(#vim.api.nvim_list_wins() == window_count)
ports.scan = function(host, _, callback)
  callback(host and { { port = 5432, processes = { { name = "postgres", pid = 456 },
    { name = "postgres", pid = 457 } } } } or {})
end
buffer_key(gateway, "gp")
port_buf = vim.api.nvim_get_current_buf()
for row, line in ipairs(vim.api.nvim_buf_get_lines(port_buf, 0, -1, false)) do
  if line:match("^5432%s") then vim.api.nvim_win_set_cursor(0, { row, 0 }); break end
end
buffer_key(port_buf, "k")
local picker = vim.api.nvim_get_current_buf()
assert(vim.bo[picker].filetype == "itoprocesses" and vim.api.nvim_get_current_win() == unified_window)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
buffer_key(picker, "<CR>")
assert(stopped_processes[2].pid == 457 and stopped_processes[2].port == 5432)
assert(vim.wait(1000, function() return not vim.api.nvim_buf_is_valid(picker) end, 10))
buffer_key(vim.api.nvim_get_current_buf(), "q")
vim.cmd("close")
ports.scan = original_scan
ports.terminate = original_terminate
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
-- Host creation and cancellation also use the existing window.
local current_dashboard = vim.api.nvim_get_current_buf()
buffer_key(current_dashboard, "a")
local host_input = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_get_current_win() == dashboard_window)
buffer_key(host_input, "<Esc>")
assert(vim.api.nvim_get_current_buf() == current_dashboard)
buffer_key(current_dashboard, "a")
host_input = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(host_input, 2, 3, false, { "new-host" })
buffer_key(host_input, "<CR>")
assert(vim.api.nvim_get_current_win() == dashboard_window)
assert(vim.api.nvim_buf_get_name(0) == "ito://new-host")
ito.dashboard()
assert(vim.api.nvim_get_current_win() == dashboard_window)
buffer_key(current_dashboard, "q")
assert(vim.api.nvim_get_current_win() == origin_win)
assert(vim.api.nvim_get_current_buf() == origin_buf)
-- Verify ownership against a real TCP listener in this Neovim process.
if vim.fn.executable("lsof") == 1 or vim.fn.executable("ss") == 1 then
  local server = assert(vim.uv.new_tcp())
  assert(server:bind("127.0.0.1", 0))
  assert(server:listen(1, function() end))
  local port = server:getsockname().port
  local completed, owned, scan_error = false, false, nil
  ports.scan(nil, {}, function(listeners, err)
    scan_error = err
    for _, listener in ipairs(listeners or {}) do
      if listener.port == port then
        for _, process in ipairs(listener.processes) do
          if process.pid == vim.fn.getpid() then owned = true end
        end
      end
    end
    completed = true
  end)
  local finished = vim.wait(10000, function() return completed end, 10)
  server:close()
  assert(finished and not scan_error and owned, scan_error or "Local listener ownership was not discovered")
end
-- Existing listeners are detected without starting or adopting an SSH job.
local live = assert(vim.uv.new_tcp())
assert(live:bind("127.0.0.1", 0))
assert(live:listen(16, function()
  local client = assert(vim.uv.new_tcp())
  live:accept(client)
  client:close()
end))
local live_port = live:getsockname().port
ito.open("existing-forward")
local existing = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(existing, 0, -1, false, { live_port .. " -> 80" })
local jobs_before = #starts
ito.dashboard()
local live_dashboard = vim.api.nvim_get_current_buf()
local function live_text()
  return table.concat(vim.api.nvim_buf_get_lines(live_dashboard, 0, -1, false), "\n")
end
assert(vim.wait(3000, function()
  return live_text():find(live_port .. " -> 80  [listening (external)]", 1, true)
end, 10), live_text())
assert(#starts == jobs_before)
live:close()
buffer_key(live_dashboard, "r")
assert(vim.wait(3000, function()
  return live_text():find(live_port .. " -> 80  [not applied]", 1, true)
end, 10), live_text())
vim.api.nvim_buf_delete(existing, { force = true })
print("ito checks passed")
vim.fn.delete(data_dir, "rf")
