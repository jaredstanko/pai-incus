# PAI Linux — Sandboxed AI Workspace for Linux

Run Claude Code + PAI in an isolated Incus container on native Linux. Same experience as [pai-lima](https://github.com/jaredstanko/pai-lima) (macOS), but using Incus system containers instead of Lima VMs.

## Why Incus?

| Feature | Incus | Docker | systemd-nspawn |
|---------|-------|--------|----------------|
| Isolation defaults | Strong (unprivileged + AppArmor + seccomp) | Weak ($1 escape) | Weak without hardening |
| systemd as PID 1 | Native | Fights it | Native |
| Snapshots/rollback | Built-in | None | Manual (btrfs only) |
| Audio passthrough | Declarative proxy | Manual mounts | Manual mounts |
| Dependencies | One package | One package | Built-in |

## Quick Start

```bash
git clone https://github.com/jaredstanko/pai-linux.git
cd pai-linux
./install.sh
```

That's it. The installer:
1. Installs Incus from Zabbly stable repo
2. Creates an unprivileged Ubuntu 24.04 container
3. Provisions it with Claude Code, PAI, Bun, Playwright
4. Installs CLI commands to `~/.local/bin/`
5. Sets up shared directories at `~/pai-workspace/`

## CLI Commands

| Command | Description |
|---------|-------------|
| `pai-start` | Start the sandbox container |
| `pai-stop` | Stop the sandbox container |
| `pai-status` | Show health, versions, and resource usage |
| `pai-talk` | Launch an interactive PAI session (Claude Code) |
| `pai-talk --resume` | Resume a previous session |
| `pai-talk --claude` | Run plain Claude Code (no PAI) |
| `pai-shell` | Open a shell inside the sandbox |

## Shared Directories

Files in `~/pai-workspace/` are accessible from both host and container:

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `~/pai-workspace/claude-home` | `/home/claude/.claude` | PAI config and state |
| `~/pai-workspace/data` | `/home/claude/data` | Persistent data |
| `~/pai-workspace/exchange` | `/home/claude/exchange` | File exchange with host |
| `~/pai-workspace/portal` | `/home/claude/portal` | Web portal files |
| `~/pai-workspace/work` | `/home/claude/work` | Working directory |
| `~/pai-workspace/upstream` | `/home/claude/upstream` | Upstream repos |

## Audio

Audio passthrough uses your host's PipeWire or PulseAudio socket, mounted into the container. ElevenLabs voice output works without VirtIO or virtual sound devices.

## Security Model

The container runs **unprivileged** with:
- **User namespaces** — container root is not host root
- **AppArmor** — auto-generated per-container profile
- **Seccomp** — allowlist of ~300 safe syscalls
- **Controlled mounts** — only 6 specific directories shared
- **Resource limits** — 4 CPU, 4GB RAM, 50GB disk

This is a real security boundary, not just process isolation.

## Requirements

- Linux (Ubuntu 22.04+, Debian 12+, or Fedora 38+)
- x86_64 or aarch64
- systemd
- Internet connection
- sudo access (for initial Incus install only)

## Version Pinning

All dependencies are pinned in `versions.env`. Edit versions there, not in scripts. Run `./scripts/verify.sh` to check the full system state against the manifest.

## Comparison with pai-lima (macOS)

| | pai-lima (macOS) | pai-linux |
|---|---|---|
| Isolation | Lima VM (Apple Virtualization.framework) | Incus container (namespaces + seccomp + AppArmor) |
| Audio | VirtIO sound device | PipeWire socket passthrough |
| Terminal | kitty (bundled) | Any terminal |
| Status UI | Swift menu bar app | CLI (`pai-status`) |
| Install | `brew install lima kitty` + VM provision | `apt install incus` + container provision |
| Architecture | macOS + Apple Silicon only | Linux x86_64 + aarch64 |
