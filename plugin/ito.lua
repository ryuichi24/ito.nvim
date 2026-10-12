if vim.g.loaded_ito then
  return
end
vim.g.loaded_ito = true

vim.api.nvim_create_user_command("Ito", function(opts)
  require("ito").open(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Open SSH dashboard or edit a host's forwards" })

vim.api.nvim_create_user_command("ItoStop", function()
  require("ito").stop()
end, { desc = "Stop all Ito SSH forwards" })
