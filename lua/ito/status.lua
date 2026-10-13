local M = {}

-- A successful TCP connection proves a listener exists, not its SSH destination.
function M.check(pair, callback)
  local address = pair.bind_address:gsub('^%[', ''):gsub('%]$', '')
  if address == "0.0.0.0" then address = "127.0.0.1" end
  if address == "::" then address = "::1" end
  local timer = assert(vim.uv.new_timer())
  local sockets, finished = {}, false
  local function finish(listening)
    if finished then return end
    finished = true
    timer:stop()
    timer:close()
    for _, socket in ipairs(sockets) do socket:close() end
    vim.schedule(function() callback(listening) end)
  end
  timer:start(1000, 0, function() finish(false) end)
  vim.uv.getaddrinfo(address, tostring(pair.local_port), { socktype = "stream" }, function(err, addresses)
    if finished then return end
    if err or not addresses or #addresses == 0 then finish(false); return end
    local pending = #addresses
    for _, resolved in ipairs(addresses) do
      local socket = assert(vim.uv.new_tcp())
      sockets[#sockets + 1] = socket
      socket:connect(resolved.addr, pair.local_port, function(connect_error)
        if finished then return end
        pending = pending - 1
        if not connect_error then finish(true)
        elseif pending == 0 then finish(false) end
      end)
    end
  end)
end

return M
