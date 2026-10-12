local M = {}
local config = { ssh = "ssh", ssh_options = {}, default_bind_address = "127.0.0.1", default_remote_address = "127.0.0.1" }
local sessions = {}
local ns = vim.api.nvim_create_namespace("ito")
local dashboard_buf
local dashboard_win
local dashboard_origin
local dashboard_rows = {}
local refresh_dashboard
local create_session
local saved_hosts = {}
local loaded = false
local load_error
local storage = require("ito.storage")

local function dashboard_geometry()
  local available_height = math.max(1, vim.o.lines - vim.o.cmdheight - 3)
  local width = math.max(1, math.min(96, math.floor((vim.o.columns - 2) * 0.85)))
  local height = math.max(1, math.min(24, math.floor(available_height * 0.75)))
  return { relative = "editor", width = width, height = height,
    row = math.max(0, math.floor((available_height - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1) }
end

local function close_dashboard()
  if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win) then
    local focused = vim.api.nvim_get_current_win() == dashboard_win
    vim.api.nvim_win_close(dashboard_win, true)
    if focused and dashboard_origin and vim.api.nvim_win_is_valid(dashboard_origin) then
      vim.api.nvim_set_current_win(dashboard_origin)
    end
  end
  dashboard_win = nil
end

local function show_view(buf, title)
  if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win) then
    vim.api.nvim_set_current_win(dashboard_win)
    vim.cmd("hide buffer " .. buf)
    vim.api.nvim_win_set_config(dashboard_win, { title = " Ito — " .. title .. " ", title_pos = "center" })
  else
    dashboard_origin = vim.api.nvim_get_current_win()
    local options = dashboard_geometry()
    options.style, options.border = "minimal", "rounded"
    options.title, options.title_pos = " Ito — " .. title .. " ", "center"
    dashboard_win = vim.api.nvim_open_win(buf, true, options)
  end
  vim.wo[dashboard_win].wrap = false
  vim.wo[dashboard_win].cursorline = true
end

-- Small editable input pages keep host/port prompts inside the same window too.
local function input_view(prompt, default, submit, cancel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "itoinput"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# " .. prompt, "# Edit below; Enter submit, Esc cancel", default or "" })
  local function accept()
    local value = vim.trim(vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1] or "")
    if value ~= "" then submit(value) end
  end
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    vim.cmd("stopinsert")
    accept()
  end, { buffer = buf, desc = "Submit input" })
  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    vim.cmd("stopinsert")
    cancel()
  end, { buffer = buf, desc = "Cancel input" })
  show_view(buf, prompt)
  vim.api.nvim_win_set_cursor(dashboard_win, { 3, #(default or "") })
  vim.cmd("startinsert!")
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "ito.nvim" })
end

local function address_valid(address)
  return type(address) == "string" and (address:match("^[%w_.%-]+$") or address:match("^%[[%x:%.]+%]$"))
end

function M.setup(opts)
  local updated = vim.tbl_deep_extend("force", config, opts or {})
  assert(address_valid(updated.default_bind_address), "Invalid default_bind_address (bracket IPv6 addresses)")
  assert(address_valid(updated.default_remote_address), "Invalid default_remote_address (bracket IPv6 addresses)")
  config = updated
end

local function endpoint(text, default_address)
  if not text then return end
  local address, port
  if text:match("^%d+$") then
    address, port = default_address, text
  else
    address, port = text:match("^(%[[^%]]+%]):(%d+)$")
    if not address then address, port = text:match("^([^:]+):(%d+)$") end
  end
  port = tonumber(port)
  if not address or not address_valid(address) or not port or port < 1 or port > 65535 then return end
  return address, port
end

local function matches(job, pair)
  return job and job.remote_address == pair.remote_address and job.remote_port == pair.remote_port
end

function M.parse(lines)
  local pairs, seen = {}, {}
  for row, line in ipairs(lines) do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local left, right = line:match("^%s*(%S+)%s*%-%>%s*(%S+)%s*$")
      local bind_address, local_port = endpoint(left, config.default_bind_address)
      local remote_address, remote_port = endpoint(right, config.default_remote_address)
      if not local_port or not remote_port then
        return nil, ("Line %d: expected LOCAL -> REMOTE (PORT or ADDRESS:PORT; ports 1–65535; IPv6 in brackets)"):format(row)
      end
      local key = bind_address:lower() .. ":" .. local_port
      if seen[key] then return nil, ("Line %d: duplicate local endpoint %s"):format(row, key) end
      seen[key] = true
      pairs[#pairs + 1] = { local_port = local_port, remote_port = remote_port, row = row,
        bind_address = bind_address, remote_address = remote_address, key = key,
        text = left .. " -> " .. right }
    end
  end
  return pairs
end

local function load_hosts()
  if loaded then return end
  loaded = true
  saved_hosts, load_error = storage.load(M.parse)
  if not saved_hosts then
    saved_hosts = {}
    notify(load_error, vim.log.levels.ERROR)
    return
  end
  for host, lines in pairs(saved_hosts) do create_session(host, lines) end
end

local function persist(host, lines)
  if load_error then notify(load_error, vim.log.levels.ERROR); return false end
  local updated = vim.deepcopy(saved_hosts)
  updated[host] = lines
  local ok, err = storage.save(updated)
  if not ok then notify(err, vim.log.levels.ERROR); return false end
  saved_hosts = updated
  return true
end

local function render(session)
  if not vim.api.nvim_buf_is_valid(session.buf) then return end
  vim.api.nvim_buf_clear_namespace(session.buf, ns, 0, -1)
  local pairs = M.parse(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))
  for _, pair in ipairs(pairs or {}) do
    local job = session.jobs[pair.key]
    local status = "not applied"
    if matches(job, pair) then status = job.status end
    vim.api.nvim_buf_set_extmark(session.buf, ns, pair.row - 1, 0, {
      virt_text = { { "  " .. status, status == "running" and "DiagnosticOk" or "DiagnosticWarn" } },
    })
  end
  if refresh_dashboard then refresh_dashboard() end
end

local function stop_job(job)
  if job.id then vim.fn.jobstop(job.id) end
end

local function apply(session)
  local mappings, err = M.parse(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))
  if not mappings then notify(err, vim.log.levels.ERROR); return end
  if not persist(session.host, vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)) then return end
  local wanted = {}
  for _, pair in ipairs(mappings) do wanted[pair.key] = pair end
  for key, job in pairs(session.jobs) do
    if not wanted[key] or not matches(job, wanted[key]) or job.status ~= "running" then
      session.jobs[key] = nil
      stop_job(job)
    end
  end
  for _, pair in ipairs(mappings) do
    if not session.jobs[pair.key] then
      local job = { remote_port = pair.remote_port, remote_address = pair.remote_address, status = "running", errors = {} }
      session.jobs[pair.key] = job
      local command = { config.ssh, "-N", "-T", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
        "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3" }
      vim.list_extend(command, config.ssh_options)
      vim.list_extend(command, { "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "ForkAfterAuthentication=no",
        "-L", ("%s:%d:%s:%d"):format(pair.bind_address, pair.local_port,
         pair.remote_address, pair.remote_port), session.host })
      job.id = vim.fn.jobstart(command, {
        on_stderr = function(_, data)
          for _, line in ipairs(data) do if line ~= "" then job.errors[#job.errors + 1] = line end end
        end,
        on_exit = function(_, code)
          if session.jobs[pair.key] ~= job then return end
          job.id = nil
          job.status = "exited (" .. code .. ")"
          render(session)
          notify(("%s: %s"):format(pair.text,
            table.concat(job.errors, "\n") ~= "" and table.concat(job.errors, "\n") or job.status), vim.log.levels.WARN)
        end,
      })
      if job.id <= 0 then job.id = nil; job.status = "failed to start" end
    end
  end
  vim.bo[session.buf].modified = false
  render(session)
end

local function show_ports(session)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "itoports"
  vim.bo[buf].bufhidden = "wipe"
  local results, errors, rows = {}, {}, {}
  local selected
  local generation = 0
  local function draw()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local lines = { "# Listening TCP ports — r refresh, q back, gd dashboard", "# Enter on local, then remote, to add a pair",
      "# Used local ports cannot be bound again; type a free port in the forwarding buffer.",
      "# Selected local: " .. (selected or "none"), "" }
    rows = {}
    for _, side in ipairs({ "local", "remote" }) do
      lines[#lines + 1] = "# " .. side .. (side == "remote" and " (" .. session.host .. ")" or "")
      if errors[side] then lines[#lines + 1] = "# " .. errors[side]
      elseif not results[side] then lines[#lines + 1] = "# Scanning…"
      elseif #results[side] == 0 then lines[#lines + 1] = "# No visible listeners" end
      for _, port in ipairs(results[side] or {}) do
        lines[#lines + 1] = tostring(port)
        rows[#lines] = { side = side, port = port }
      end
      lines[#lines + 1] = ""
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end
  local function refresh()
    generation = generation + 1
    local current_generation = generation
    results, errors = {}, {}
    draw()
    for _, side in ipairs({ "local", "remote" }) do
      require("ito.ports").scan(side == "remote" and session.host or nil, config, function(ports, err)
        if generation ~= current_generation or not vim.api.nvim_buf_is_valid(buf) then return end
        results[side], errors[side] = ports, err
        draw()
      end)
    end
  end
  vim.keymap.set("n", "r", refresh, { buffer = buf })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function() M.open(session.host) end, { buffer = buf, desc = "Back to host" })
  end
  vim.keymap.set("n", "gd", M.dashboard, { buffer = buf, desc = "Open SSH dashboard" })
  vim.keymap.set("n", "<CR>", function()
    local entry = rows[vim.api.nvim_win_get_cursor(0)[1]]
    if not entry then return end
    if entry.side == "local" then selected = entry.port; draw(); return end
    local function insert(port)
      port = tonumber(port)
      if not port or port % 1 ~= 0 or port < 1 or port > 65535 then
        notify("Enter a local port between 1 and 65535", vim.log.levels.ERROR); return
      end
      if not vim.api.nvim_buf_is_valid(session.buf) then return end
      -- Discovery scans the SSH machine itself, independently of destination defaults.
      vim.api.nvim_buf_set_lines(session.buf, -1, -1, false, { ("%d -> 127.0.0.1:%d"):format(port, entry.port) })
      render(session)
      M.open(session.host)
      vim.api.nvim_win_set_cursor(dashboard_win, { vim.api.nvim_buf_line_count(session.buf), 0 })
    end
    if selected then insert(selected)
    else input_view("Free local port", tostring(entry.port), insert, function() show_ports(session) end) end
  end, { buffer = buf })
  refresh()
  show_view(buf, session.host .. " — ports")
end

refresh_dashboard = function()
  if not dashboard_buf or not vim.api.nvim_buf_is_valid(dashboard_buf) then return end
  local lines = { "# Ito — SSH forwarding dashboard",
    "# <Enter> edit   a add   s stop   d forget   r refresh   q close", "" }
  dashboard_rows = {}
  local hosts = vim.tbl_keys(sessions)
  table.sort(hosts)
  if #hosts == 0 then lines[#lines + 1] = "No hosts yet. Press a to add an SSH destination." end
  for _, host in ipairs(hosts) do
    local session = sessions[host]
    local running = 0
    for _, job in pairs(session.jobs) do if job.status == "running" then running = running + 1 end end
    lines[#lines + 1] = ("%s  [%d running]%s"):format(host, running,
      vim.bo[session.buf].modified and "  [unsaved edits]" or "")
    dashboard_rows[#lines] = host
    local mappings, err = M.parse(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))
    if not mappings then
      lines[#lines + 1] = "  " .. err
      dashboard_rows[#lines] = host
    elseif #mappings == 0 then
      lines[#lines + 1] = "  No port pairs. Press Enter to edit."
      dashboard_rows[#lines] = host
    else
      for _, pair in ipairs(mappings) do
        local job = session.jobs[pair.key]
        local status = matches(job, pair) and job.status or "not applied"
        lines[#lines + 1] = ("  %s  [%s]"):format(pair.text, status)
        dashboard_rows[#lines] = host
      end
    end
    lines[#lines + 1] = ""
  end
  vim.bo[dashboard_buf].modifiable = true
  vim.api.nvim_buf_set_lines(dashboard_buf, 0, -1, false, lines)
  vim.bo[dashboard_buf].modifiable = false
end

function M.dashboard()
  load_hosts()
  if not dashboard_buf or not vim.api.nvim_buf_is_valid(dashboard_buf) then
    dashboard_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(dashboard_buf, "ito-dashboard://overview")
    vim.bo[dashboard_buf].bufhidden = "hide"
    vim.bo[dashboard_buf].filetype = "itodashboard"
    local function host_at_cursor() return dashboard_rows[vim.api.nvim_win_get_cursor(0)[1]] end
    vim.keymap.set("n", "<CR>", function()
      local host = host_at_cursor()
      if host then M.open(host) end
    end, { buffer = dashboard_buf, desc = "Edit host port pairs" })
    vim.keymap.set("n", "a", function()
      input_view("SSH host (or config alias)", "", M.open, M.dashboard)
    end, { buffer = dashboard_buf, desc = "Add SSH host" })
    vim.keymap.set("n", "s", function()
      local host = host_at_cursor()
      if host then M.stop(host) end
    end, { buffer = dashboard_buf, desc = "Stop host forwards" })
    vim.keymap.set("n", "d", function()
      local host = host_at_cursor()
      if host then M.forget(host) end
    end, { buffer = dashboard_buf, desc = "Forget host and stop forwards" })
    vim.keymap.set("n", "r", refresh_dashboard, { buffer = dashboard_buf, desc = "Refresh dashboard" })
    for _, key in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", key, close_dashboard, { buffer = dashboard_buf, desc = "Close dashboard" })
    end
    vim.api.nvim_create_autocmd("BufEnter", { buffer = dashboard_buf, callback = refresh_dashboard })
  end
  refresh_dashboard()
  show_view(dashboard_buf, "SSH forwards")
end

create_session = function(host, lines)
  local session = { host = host, jobs = {}, buf = vim.api.nvim_create_buf(true, false) }
  sessions[host] = session
  vim.api.nvim_buf_set_name(session.buf, "ito://" .. host)
  vim.bo[session.buf].buftype = "acwrite"
  vim.bo[session.buf].bufhidden = "hide"
  vim.bo[session.buf].swapfile = false
  vim.bo[session.buf].filetype = "ito"
  vim.api.nvim_buf_set_lines(session.buf, 0, -1, false, lines or {
    "# SSH local forwarding: " .. host,
    "# LOCAL -> REMOTE   |   :w apply   |   gp ports   |   gr status   |   gd dashboard   |   q close",
    "# Each side: PORT or ADDRESS:PORT (IPv6: [::1]:PORT). Delete a row and save to stop it.", "",
  })
  vim.bo[session.buf].modified = false
  vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = session.buf, callback = function() apply(session) end })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = session.buf, callback = function() render(session) end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = session.buf, callback = function()
    sessions[host] = nil
    for _, job in pairs(session.jobs) do stop_job(job) end
    session.jobs = {}
    refresh_dashboard()
  end })
  vim.keymap.set("n", "gp", function() show_ports(session) end, { buffer = session.buf, desc = "Show listening ports" })
  vim.keymap.set("n", "gr", function() render(session) end, { buffer = session.buf, desc = "Refresh forwarding status" })
  vim.keymap.set("n", "gd", M.dashboard, { buffer = session.buf, desc = "Open SSH dashboard" })
  vim.keymap.set("n", "q", close_dashboard, { buffer = session.buf, desc = "Close Ito window" })
  return session
end

function M.open(host)
  if not host then M.dashboard(); return end
  if host == "" or host:match("^%-") or host:find("[%s%c]") then
    notify("Use an SSH hostname, user@host, or config alias", vim.log.levels.ERROR); return
  end
  load_hosts()
  local session = sessions[host]
  if not session or not vim.api.nvim_buf_is_valid(session.buf) then
    session = create_session(host, saved_hosts[host])
  end
  show_view(session.buf, session.host .. " — forwards")
  render(session)
end

function M.forget(host)
  load_hosts()
  if not persist(host, nil) then return end
  local session = sessions[host]
  if session then
    if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win)
      and vim.api.nvim_win_get_buf(dashboard_win) == session.buf then M.dashboard() end
    local current = vim.api.nvim_get_current_win()
    -- Delete a displayed host buffer from its normal window, rather than the float.
    if dashboard_origin and vim.api.nvim_win_is_valid(dashboard_origin)
      and vim.api.nvim_win_get_buf(dashboard_origin) == session.buf then
      vim.api.nvim_set_current_win(dashboard_origin)
    end
    vim.api.nvim_buf_delete(session.buf, { force = true })
    if vim.api.nvim_win_is_valid(current) then vim.api.nvim_set_current_win(current) end
  end
  refresh_dashboard()
end

function M.stop(host)
  for name, session in pairs(sessions) do
    if not host or name == host then
      local jobs = session.jobs
      session.jobs = {}
      for _, job in pairs(jobs) do stop_job(job) end
      render(session)
    end
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", { callback = function() M.stop() end })
vim.api.nvim_create_autocmd("VimResized", { callback = function()
  if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win) then
    vim.api.nvim_win_set_config(dashboard_win, dashboard_geometry())
  end
end })

return M
