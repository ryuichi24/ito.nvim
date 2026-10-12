# Usage

[Back to README](../README.md)

## Multiple SSH machines

Run `:Ito` to open the centered floating dashboard:

```text
devbox  [2 running]
  3000 -> 3000  [running]
  15432 -> 5432  [running]

staging  [1 running]
  8080 -> 80  [running]
```

- `a` prompts for an SSH destination and opens its forwarding buffer.
- Enter on a host or one of its pairs opens that host's editable buffer.
- `s` stops only the selected host's forwards, retaining its definitions.
- `d` forgets the selected host's saved definitions and stops its forwards.
- `r` refreshes the overview. Status also updates when forwards change.
- Unsaved edits are marked; switching hosts preserves them without applying them.
- `q` or Esc closes the dashboard and returns to your previous window.

All views share the same floating window. Selecting or adding a host switches
its contents to the host's editable buffer; `gd` switches back to the dashboard.
Port discovery and host/local-port input pages use that window too. Input pages
start in insert mode: edit the value and press Enter to submit or Esc to cancel.
Your underlying editing window and its buffer stay untouched.

The float resizes with Neovim. Running `:Ito` again switches the existing float
to the dashboard rather than creating another window.

Open a host directly with `:Ito my-server`, where `my-server` is an SSH config
alias, hostname, or `user@host`.

## Editing forwards

Rows accept `LOCAL -> REMOTE`, blank lines, and `#` comments. Each side can be
either `PORT` or `ADDRESS:PORT`:

```text
# Services on the SSH machine
8080 -> 3000

# Expose a web tunnel on your local network
0.0.0.0:8081 -> web.internal:80

# Reach an internal database through the SSH machine
15432 -> db.internal:5432

# IPv6 localhost on both sides
[::1]:8082 -> [::1]:3000
```

With the built-in defaults, `8080 -> 3000` means
`127.0.0.1:8080 -> 127.0.0.1:3000`. The remote `127.0.0.1` refers to the SSH
machine selected for that buffer. `0.0.0.0` listens on all local IPv4 interfaces;
an internal destination such as `db.internal` is reached through the SSH machine.
IPv6 addresses must be bracketed to separate the address from its port. `::1`
is IPv6 localhost, equivalent to IPv4 `127.0.0.1`.

Ports must be 1–65535. A local address/port pair can appear only once per host
buffer; the same port on different bind addresses is allowed. Invalid input is
rejected before any running forwards are changed.

- `:w` starts new forwards, replaces edited forwards, and stops deleted rows.
  Editing either address or port replaces the affected forward when you save.
- `gp` opens local and remote port discovery.
- `gr` refreshes inline forwarding status.
- `gd` returns to the dashboard.
- `q` in normal mode closes the floating window, retaining unsaved edits in memory.
- `:ItoStop` stops every forward, leaving rows available to restart with `:w`.

Hosts share the same local address/port space. Normally use different local ports
for forwards to different machines. Overlapping binds (for example, `0.0.0.0:8080`
and `127.0.0.1:8080`) can conflict; SSH reports a bind failure if a port is occupied.

## Port discovery

Press `gp` in a host buffer to list local and remote **listening TCP ports**.
Each row shows the process name and PID when available, for example:

```text
# local
3000   node (pid 12345)
8080   ssh (pid 12346)

# remote (devbox)
5432   postgres (pid 456)
80     nginx (pid 789), nginx (pid 790)
```

Multiple processes sharing a port are listed on the same row. PIDs in the remote
section belong to the remote machine. If ownership is hidden by permissions or
the discovery tool cannot report it, the row says `process unavailable`.

Press Enter on a remote port and enter a free local port on the input page to add
a row. You can also select a local port first, then a remote port. Listening local ports are
occupied, so normally choose a different, free local port. Save the host buffer
to apply added pairs. Adding a pair returns to the host's buffer in the same
float, with the new row selected. In discovery, `r` refreshes, `q` or Esc returns
to the host, and `gd` returns to the dashboard.

Discovery uses local `lsof` or `ss`, with `netstat` as a fallback. On the server it
tries `ss`, `lsof`, then `netstat`. `ss` requests process information and `lsof`
uses field output to preserve full command names. The plain `netstat` fallback
reports ports without ownership. Results are limited by the user's permissions
and represent listeners, not every established connection. Remote discovery
requires a POSIX-compatible shell. A remote port does not need to be listed to
be forwarded: you can always type its number directly.

Discovery scans the SSH machine itself, not arbitrary destination hosts. Pairs
added from discovery explicitly target `127.0.0.1` on that machine, even if you
configured another remote default. Edit that address if the listener requires it.

### Stopping a listener

Press `k` on a port row to send **SIGTERM** to its listening process. For a local
row, Ito signals the local PID; for a remote row, it runs `kill -TERM PID` through
that host's SSH connection. If multiple processes share a port, a process picker
opens in the same float: Enter stops the selected PID, and `q` or Esc returns.

Ito rechecks that the process still owns the port before sending the signal and
refreshes discovery afterward. This stops the whole process, including any other
ports it owns. It requires normal user permissions and does not use sudo or force
termination. Neovim itself cannot be stopped through Ito's local port list.

SIGTERM requests shutdown; a process can ignore it, or a service manager can
restart it. Check the refreshed list before reusing the port. To stop an Ito
forward, you can also delete its row and save, or stop the host from the dashboard.

## Status and lifecycle

Each row owns an SSH process. `running` means the process is alive, not that the
destination service has passed a health check. SSH startup failures are reported
inline and through notifications; save again to retry.

Applying changes is not transactional: a failed replacement does not restore
the old forward. Hiding a buffer keeps its forwards alive. Wiping it or exiting
Neovim stops them. Saved forward definitions persist across sessions.

## Persistence

`:w` validates and saves the host's entire buffer (including comments and blank
lines), then applies its forwards. Definitions are stored as versioned JSON in
`stdpath("data")/ito/forwards.json`, typically
`~/.local/share/nvim/ito/forwards.json`. To see your actual path:

```vim
:lua print(vim.fn.stdpath("data") .. "/ito/forwards.json")
```

The saved hosts are restored when you first open Ito. SSH processes and connection
status are not persisted: restored forwards stay stopped until you save their
host buffer. Unsaved edits are not persisted, and saving one host does not save
another host's pending edits. Address omissions remain omissions, so the current
configured defaults still apply after restoring.

Stopping forwards or wiping a buffer does not delete its saved definitions.
Reopening a wiped host restores its last saved buffer. Use `d` on the dashboard
to forget a host permanently, including any unsaved edits. Deleting a pair and
saving removes it from the saved definitions.

Writes use a temporary file and rename to avoid leaving a partial JSON file.
If a file cannot be loaded or a write fails, Ito reports the error; it does not
apply the pending forwards or mark the buffer as saved. A malformed file is left
intact: fix or move it and restart Neovim before saving again. Multiple Neovim
instances share this file; concurrent saves use the last writer's snapshot.
