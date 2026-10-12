local M = {}

-- Both commands report TCP listeners, not established outbound connections.
M.remote_command = "if command -v ss >/dev/null 2>&1; then ss -H -ltn; "
  .. "elif command -v lsof >/dev/null 2>&1; then lsof -nP -iTCP -sTCP:LISTEN; "
  .. "else netstat -an; fi"

function M.parse(text)
  local found = {}
  for line in text:gmatch("[^\r\n]+") do
    if line:match("^LISTEN%s") then
      local address = line:match("^LISTEN%s+%S+%s+%S+%s+(%S+)")
      local port = address and address:match(":(%d+)$")
      if port then found[tonumber(port)] = true end
    elseif line:find("(LISTEN)", 1, true) then
      local port = line:match(":(%d+)%s+%(LISTEN%)")
      if port then found[tonumber(port)] = true end
    elseif line:match("^tcp") and line:find("LISTEN", 1, true) then
      local address = line:match("^%S+%s+%S+%s+%S+%s+(%S+)")
      local port = address and (address:match(":(%d+)$") or address:match("%.(%d+)$"))
      if port then found[tonumber(port)] = true end
    end
  end
  local ports = {}
  for port in pairs(found) do
    if port > 0 and port <= 65535 then ports[#ports + 1] = port end
  end
  table.sort(ports)
  return ports
end

function M.scan(host, config, callback)
  local command
  if host then
    command = { config.ssh, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10" }
    vim.list_extend(command, config.ssh_options)
    vim.list_extend(command, { host, M.remote_command })
  elseif vim.fn.executable("lsof") == 1 then
    command = { "lsof", "-nP", "-iTCP", "-sTCP:LISTEN" }
  elseif vim.fn.executable("ss") == 1 then
    command = { "ss", "-H", "-ltn" }
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

return M
