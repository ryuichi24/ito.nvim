local M = {}

-- Both commands report TCP listeners, not established outbound connections.
M.remote_command = "if command -v ss >/dev/null 2>&1; then ss -H -ltnp; "
  .. "elif command -v lsof >/dev/null 2>&1; then lsof -nP -iTCP -sTCP:LISTEN -Fpcn; "
  .. "else netstat -an; fi"

function M.parse(text)
  local found = {}
  local function add(port, name, pid)
    port, pid = tonumber(port), tonumber(pid)
    if not port or port < 1 or port > 65535 then return end
    found[port] = found[port] or { port = port, processes = {} }
    if not name or not pid then return end
    for _, process in ipairs(found[port].processes) do
      if process.name == name and process.pid == pid then return end
    end
    found[port].processes[#found[port].processes + 1] = { name = name, pid = pid }
  end
  local pid, name
  for line in text:gmatch("[^\r\n]+") do
    line = vim.trim(line)
    -- lsof field output preserves full command names, unlike its table output.
    if line:match("^p%d+$") then
      pid, name = tonumber(line:sub(2)), nil
    elseif pid and line:match("^c.") then
      name = line:sub(2)
    elseif pid and line:match("^n.") then
      add(line:match(":(%d+)$"), name, pid)
    elseif line:match("^LISTEN%s") then
      local address = line:match("^LISTEN%s+%S+%s+%S+%s+(%S+)")
      local port = address and address:match(":(%d+)$")
      add(port)
      for process_name, process_pid in line:gmatch('"([^"]+)",pid=(%d+)') do
        add(port, process_name, process_pid)
      end
    elseif line:find("(LISTEN)", 1, true) then
      local port = line:match(":(%d+)%s+%(LISTEN%)")
      local process_name, process_pid = line:match("^(%S+)%s+(%d+)%s")
      add(port, process_name, process_pid)
    elseif line:match("^tcp") and line:find("LISTEN", 1, true) then
      local address = line:match("^%S+%s+%S+%s+%S+%s+(%S+)")
      local port = address and (address:match(":(%d+)$") or address:match("%.(%d+)$"))
      -- Plain netstat output does not expose process ownership portably.
      add(port)
    end
  end
  local listeners = {}
  for _, listener in pairs(found) do
    table.sort(listener.processes, function(a, b)
      return a.name == b.name and a.pid < b.pid or a.name < b.name
    end)
    listeners[#listeners + 1] = listener
  end
  table.sort(listeners, function(a, b) return a.port < b.port end)
  return listeners
end

function M.describe(listener)
  local owners = {}
  for _, process in ipairs(listener.processes) do
    owners[#owners + 1] = ("%s (pid %d)"):format(process.name, process.pid)
  end
  return ("%-5d  %s"):format(listener.port,
    #owners > 0 and table.concat(owners, ", ") or "process unavailable")
end

function M.scan(host, config, callback)
  local command
  if host then
    command = { config.ssh, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10" }
    vim.list_extend(command, config.ssh_options)
    vim.list_extend(command, { host, M.remote_command })
  elseif vim.fn.executable("lsof") == 1 then
    command = { "lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn" }
  elseif vim.fn.executable("ss") == 1 then
    command = { "ss", "-H", "-ltnp" }
  else
    command = { "netstat", "-an" }
  end
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      -- lsof returns 1 when there are no matching listeners.
      if result.code ~= 0 and not (not host and command[1] == "lsof" and result.code == 1) then
        callback(nil, vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "Port discovery failed")
      else
        callback(M.parse(result.stdout or ""))
      end
    end)
  end)
end

function M.terminate(host, listener, process, config, callback)
  local pid = process and process.pid
  if type(pid) ~= "number" or pid % 1 ~= 0 or pid <= 1 then
    callback(nil, "Invalid process PID")
    return
  end
  if not host and pid == vim.fn.getpid() then
    callback(nil, "Cannot terminate the Neovim process running Ito")
    return
  end
  -- Recheck ownership so an old discovery row cannot target an unrelated process.
  M.scan(host, config, function(listeners, err)
    if err then callback(nil, err); return end
    local owned = false
    for _, current in ipairs(listeners or {}) do
      if current.port == listener.port then
        for _, owner in ipairs(current.processes) do
          if owner.pid == pid and owner.name == process.name then owned = true end
        end
      end
    end
    if not owned then callback(nil, "Process no longer owns this port; refresh the list"); return end
    if not host then
      local ok, reason = vim.uv.kill(pid, "sigterm")
      if not ok then callback(nil, reason or "Could not send SIGTERM")
      else callback(true) end
      return
    end
    local command = { config.ssh, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10" }
    vim.list_extend(command, config.ssh_options)
    vim.list_extend(command, { host, "kill -TERM " .. string.format("%d", pid) })
    vim.system(command, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then callback(true)
        else callback(nil, vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "Could not send SIGTERM") end
      end)
    end)
  end)
end

return M
