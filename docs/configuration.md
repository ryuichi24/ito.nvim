# Configuration

[Back to README](../README.md)

No setup call is required. To customize the defaults, add this after loading the
plugin:

```lua
require("ito").setup({
  ssh = "ssh",
  ssh_options = {}, -- e.g. { "-p", "2222", "-i", "/path/to/key" }
  default_bind_address = "127.0.0.1", -- used when the local address is omitted
  default_remote_address = "127.0.0.1", -- used when the remote address is omitted
})
```

SSH config aliases, jump hosts, and identities in `~/.ssh/config` work. Configure
key-based authentication and accept the host key first using `ssh your-host`;
the plugin runs SSH in batch mode.

## Default addresses

Defaults apply independently to omitted addresses on each row. An explicit
address in the buffer overrides the corresponding default:

| Row | Effective forwarding with built-in defaults |
| --- | --- |
| `8080 -> 3000` | `127.0.0.1:8080 -> 127.0.0.1:3000` |
| `0.0.0.0:8080 -> 3000` | `0.0.0.0:8080 -> 127.0.0.1:3000` |
| `15432 -> db.internal:5432` | `127.0.0.1:15432 -> db.internal:5432` |

The bind address belongs to your computer. The remote address is resolved/reached
from the SSH server, not your computer. A remote `127.0.0.1` refers to the SSH
machine selected for that buffer, independently for each connection.

Changing defaults affects omitted addresses the next time you save a host's
buffer. Explicit addresses remain unchanged. IPv6 defaults must be bracketed,
for example `"[::1]"`.

The former setup keys `bind_address` and `remote_address` have been renamed to
`default_bind_address` and `default_remote_address`.

See [usage](usage.md) for per-row address syntax and examples.
