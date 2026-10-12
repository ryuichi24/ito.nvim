local M = {}

function M.path()
  return vim.fn.stdpath("data") .. "/ito/forwards.json"
end

function M.load(validate)
  local path = M.path()
  if not vim.uv.fs_stat(path) then return {} end
  local ok, data = pcall(function()
    local decoded = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    assert(type(decoded) == "table" and decoded.version == 1 and type(decoded.hosts) == "table",
      "Unsupported forwarding file format")
    for host, lines in pairs(decoded.hosts) do
      assert(type(host) == "string" and host ~= "" and not host:match("^%-") and not host:find("[%s%c]"),
        "Invalid SSH destination")
      assert(type(lines) == "table" and vim.islist(lines), "Invalid host buffer")
      for _, line in ipairs(lines) do assert(type(line) == "string" and not line:find("[\r\n]"), "Invalid buffer line") end
      local mappings, err = validate(lines)
      assert(mappings, err)
    end
    return decoded.hosts
  end)
  if not ok then return nil, "Cannot load " .. path .. ": " .. tostring(data) end
  return data
end

function M.save(hosts)
  local path = M.path()
  local temp = path .. "." .. vim.fn.getpid() .. ".tmp"
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local json = vim.json.encode({ version = 1, hosts = vim.tbl_isempty(hosts) and vim.empty_dict() or hosts })
    assert(vim.fn.writefile({ json }, temp) == 0, "Cannot write temporary file")
    local renamed, reason = vim.uv.fs_rename(temp, path)
    assert(renamed, reason)
  end)
  if not ok then
    vim.fn.delete(temp)
    return nil, "Cannot save " .. path .. ": " .. tostring(err)
  end
  return true
end

return M
