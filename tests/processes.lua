vim.opt.runtimepath:prepend(vim.fn.getcwd())
local ports = require("ito.ports")
local listener = { port = 8080, processes = { { name = "node", pid = 12345 } } }
local config = { ssh = "ssh", ssh_options = { "-p", "2222" } }
local original_scan, original_kill, original_system = ports.scan, vim.uv.kill, vim.system
local scanned, signals, commands = {}, {}, {}
ports.scan = function(host, _, callback)
  scanned[#scanned + 1] = host or "local"
  callback({ listener })
end
vim.uv.kill = function(pid, signal)
  signals[#signals + 1] = { pid = pid, signal = signal }
  return 0
end
local function stop(host, process)
  local result, failure, finished
  ports.terminate(host, listener, process or listener.processes[1], config, function(ok, err)
    result, failure, finished = ok, err, true
  end)
  assert(vim.wait(1000, function() return finished end, 10))
  return result, failure
end
assert(stop(nil))
assert(scanned[1] == "local" and signals[1].pid == 12345 and signals[1].signal == "sigterm")
vim.uv.kill = function() return nil, "permission denied" end
local ok, err = stop(nil)
assert(not ok and err == "permission denied")
local count = #scanned
assert(not stop(nil, { name = "nvim", pid = vim.fn.getpid() }))
assert(not stop(nil, { name = "invalid", pid = -1 }))
assert(not stop(nil, { name = "invalid", pid = 0 }))
assert(not stop(nil, { name = "invalid", pid = 12.5 }))
assert(#scanned == count)
local exit_code = 0
vim.system = function(command, _, callback)
  commands[#commands + 1] = command
  callback({ code = exit_code, stderr = exit_code == 0 and "" or "kill: Operation not permitted" })
end
assert(stop("gateway"))
assert(vim.deep_equal(commands[1], { "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
  "-p", "2222", "gateway", "kill -TERM 12345" }))
assert(#signals == 1 and scanned[#scanned] == "gateway")
exit_code = 1
ok, err = stop("gateway")
assert(not ok and err:find("Operation not permitted", 1, true))
ports.scan = function(_, _, callback) callback({ { port = 8080, processes = { { name = "other", pid = 12345 } } } }) end
count = #commands
ok, err = stop("gateway")
assert(not ok and err:find("no longer owns", 1, true) and #commands == count)
ports.scan = function(_, _, callback) callback(nil, "discovery failed") end
ok, err = stop("gateway")
assert(not ok and err == "discovery failed" and #commands == count)
ports.scan, vim.uv.kill, vim.system = original_scan, original_kill, original_system
print("ito process termination checks passed")
