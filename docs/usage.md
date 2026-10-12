# Usage

[Back to README](../README.md)

## Multiple SSH machines

Run `:Ito` to open the dashboard:

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
- `r` refreshes the overview. Status also updates when forwards change.
- Unsaved edits are marked; switching hosts preserves them without applying them.

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
- `:ItoStop` stops every forward, leaving rows available to restart with `:w`.

Hosts share the same local address/port space. Normally use different local ports
for forwards to different machines. Overlapping binds (for example, `0.0.0.0:8080`
and `127.0.0.1:8080`) can conflict; SSH reports a bind failure if a port is occupied.

## Port discovery

Press `gp` in a host buffer to list local and remote **listening TCP ports**.
Press Enter on a remote port and enter a free local port to add a row. You can
also select a local port first, then a remote port. Listening local ports are
occupied, so normally choose a different, free local port. Save the host buffer
to apply added pairs. In the discovery split, `r` refreshes and `q` closes it.

Discovery uses local `lsof` or `ss`, with `netstat` as a fallback. On the server it
tries `ss`, `lsof`, then `netstat`. Results are limited by the user's permissions
and represent listeners, not every established connection. Remote discovery
requires a POSIX-compatible shell. A remote port does not need to be listed to
be forwarded: you can always type its number directly.

Discovery scans the SSH machine itself, not arbitrary destination hosts. Pairs
added from discovery explicitly target `127.0.0.1` on that machine, even if you
configured another remote default. Edit that address if the listener requires it.

## Status and lifecycle

Each row owns an SSH process. `running` means the process is alive, not that the
destination service has passed a health check. SSH startup failures are reported
inline and through notifications; save again to retry.

Applying changes is not transactional: a failed replacement does not restore
the old forward. Hiding a buffer keeps its forwards alive. Wiping it or exiting
Neovim stops them. Forward definitions are session-only.
