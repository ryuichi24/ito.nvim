vim.opt.runtimepath:prepend(vim.fn.getcwd())
local data_dir = vim.fn.tempname()
local stdpath = vim.fn.stdpath
vim.fn.stdpath = function(kind) return kind == "data" and data_dir or stdpath(kind) end
local notices, starts = {}, {}
vim.notify = function(message) notices[#notices + 1] = message end
vim.fn.jobstart = function(command) starts[#starts + 1] = command; return #starts end
vim.fn.jobstop = function() return 1 end
local storage = require("ito.storage")
local ito = require("ito")
local function disk()
  return vim.json.decode(table.concat(vim.fn.readfile(storage.path()), "\n"))
end
local function restart()
  ito.stop()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then vim.api.nvim_win_close(win, true) end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match("^ito[%w%-]*://") then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  package.loaded["ito"] = nil
  ito = require("ito")
end

ito.open("gateway")
local gateway = vim.api.nvim_get_current_buf()
local lines = { "# My database", "", "15432 -> db.internal:5432", "[::1]:8080 -> [::1]:3000" }
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, lines)
vim.cmd("write")
assert(vim.deep_equal(disk().hosts.gateway, lines))
ito.open("staging")
local staging = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(staging, 0, -1, false, { "9000 -> 90" })
vim.cmd("write")
assert(disk().hosts.staging[1] == "9000 -> 90")
-- Confirm restoration in a genuinely separate Neovim process.
local child = vim.system({ vim.v.progpath, "--headless", "-u", "NONE",
  "--cmd", ("lua vim.fn.stdpath = function() return %q end"):format(data_dir),
  "-c", "lua vim.opt.runtimepath:prepend(vim.fn.getcwd()); vim.fn.jobstart = function() error('unexpected SSH startup') end; "
    .. "require('ito').open('gateway'); assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[3] == '15432 -> db.internal:5432')",
  "-c", "qa!" }, { text = true }):wait()
assert(child.code == 0 and not (child.stderr or ""):find("Error", 1, true), child.stderr)
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, { "15432 -> other.internal:5432" })
vim.cmd("write") -- saving staging must not save gateway's unsaved edits
assert(vim.deep_equal(disk().hosts.gateway, lines))

local count = #starts
restart()
ito.dashboard()
assert(#starts == count) -- opening saved hosts does not launch SSH
local overview = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(overview:find("gateway  [0 running]", 1, true))
assert(overview:find("staging  [0 running]", 1, true))
ito.open("gateway")
gateway = vim.api.nvim_get_current_buf()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(gateway, 0, -1, false), lines))
assert(not vim.bo[gateway].modified)
vim.cmd("write")
assert(#starts == count + 2)
ito.stop()
assert(vim.deep_equal(disk().hosts.gateway, lines))

-- Invalid edits and failed disk writes leave saved definitions and jobs intact.
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, { "invalid" })
vim.cmd("write")
assert(vim.deep_equal(disk().hosts.gateway, lines))
assert(vim.bo[gateway].modified)
vim.api.nvim_buf_set_lines(gateway, 0, -1, false, { "15432 -> other.internal:5432" })
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function() return nil, "simulated write failure" end
count = #starts
vim.cmd("write")
vim.uv.fs_rename = rename
assert(#starts == count and vim.bo[gateway].modified)
assert(vim.deep_equal(disk().hosts.gateway, lines))
vim.cmd("write")
assert(disk().hosts.gateway[1] == "15432 -> other.internal:5432")

-- Wiping is not forgetting: reopening restores the last saved definitions.
vim.api.nvim_buf_delete(gateway, { force = true })
ito.open("gateway")
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "15432 -> other.internal:5432")
ito.forget("staging")
assert(disk().hosts.staging == nil)
restart()
ito.dashboard()
assert(not table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("staging", 1, true))
ito.open("gateway")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
vim.cmd("write")
assert(#assert(ito.parse(disk().hosts.gateway)) == 0)
ito.forget("gateway")
assert(vim.tbl_isempty(disk().hosts))

-- A malformed file is reported and never silently replaced.
restart()
vim.fn.writefile({ "not json" }, storage.path())
ito.dashboard()
assert(notices[#notices]:find("Cannot load", 1, true))
ito.open("new-host")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "8080 -> 80" })
count = #starts
vim.cmd("write")
assert(#starts == count and vim.fn.readfile(storage.path())[1] == "not json")
assert(vim.bo.modified)
ito.stop()
vim.fn.delete(data_dir, "rf")
print("ito persistence checks passed")
