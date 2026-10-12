# ito.nvim

Manage SSH local port forwarding by editing Neovim buffers, with a dashboard
for multiple remote machines and local/remote port discovery.

Requires **Neovim 0.10+** and **OpenSSH**. Make sure `ssh your-host` works with
key-based authentication and its host key is accepted; Ito uses SSH batch mode.

## Install

### vim.pack (Neovim 0.12+)

Add to `init.lua`, replacing `YOUR_USERNAME` with the repository owner:

```lua
vim.pack.add({
  { src = "https://github.com/YOUR_USERNAME/ito.nvim" },
})
```

### lazy.nvim

Add to your plugin specs, replacing the path with your checkout:

```lua
{ dir = "~/dev/personal/projects/ito.nvim" }
```

No setup call is required. See [configuration](docs/configuration.md) for options.

## Quick start

1. Run `:Ito` to open the dashboard.
2. Press `a` and enter an SSH hostname, `user@host`, or SSH config alias.
3. Edit port pairs in that host's buffer:

   ```text
   8080 -> 3000
   15432 -> db.internal:5432
   ```

4. Save with `:w` to apply. Edit a row to replace a forward, or delete it and save
   to stop it.
5. Press `gd` to return to the dashboard. Press Enter on a host to edit its pairs.

Saving also persists your hosts and port pairs in `stdpath("data")/ito/forwards.json`.
They return next time you open Ito; save a host's buffer to start its forwards.

`8080 -> 3000` forwards your `localhost:8080` to `localhost:3000` on the SSH
machine. You can also open a host directly with `:Ito user@host`.

| Where | Key / command | Action |
| --- | --- | --- |
| Dashboard | `a` / Enter | Add / edit a host |
| Dashboard | `s` / `r` | Stop selected host / refresh |
| Dashboard | `d` | Forget selected host and stop its forwards |
| Host buffer | `:w` | Apply edited port pairs |
| Host buffer | `gp` / `gd` | Port discovery / dashboard |
| Host buffer | `gr` | Refresh status |
| Port discovery | Enter | Select a remote port and choose a local port |
| Port discovery | `r` / `q` | Refresh / close |
| Anywhere | `:ItoStop` | Stop all forwards |

## Documentation

- [Configuration](docs/configuration.md): SSH options and default addresses.
- [Usage](docs/usage.md): address syntax, IPv6, discovery, and forwarding lifecycle.

## Verification

```sh
nvim --headless -u NONE -l tests/check.lua
nvim --headless -u NONE -l tests/persistence.lua
```
