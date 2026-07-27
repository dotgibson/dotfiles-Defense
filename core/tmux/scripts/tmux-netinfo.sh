#!/usr/bin/env bash
# core/tmux/scripts/tmux-netinfo.sh — the "operator" segment of the status line.
# ──────────────────────────────────────────────────────────────────────────────
# Shows your VPN / tunnel IP (the callback address a reverse shell must reach)
# when a tunnel interface is up — in standout ORANGE — otherwise your primary LAN
# IP in GREEN, otherwise NOTHING. The empty case is what keeps this PORTABLE CORE:
# on a box with no tunnel and no routable LAN (and on anything where you just
# don't care) the segment silently disappears, exactly like tmux-menu.sh's ◆
# section. Tunnel-up vs LAN-only is the single most useful at-a-glance fact when
# you're juggling engagement VPNs.
#
# Output is a fully-styled tmux "pill" (it emits its own #[...] colour codes,
# which tmux re-interprets in status-right). Cheap enough to run at the 5s
# status-interval set in tmux.conf.
#
# Deliberately NO `set -e`: a status helper must never hard-fail and blank itself.
# ──────────────────────────────────────────────────────────────────────────────

# tokyonight-storm palette (kept in sync with starship.toml + tmux.conf @tn_*)
ORANGE="#ff9e64"
GREEN="#9ece6a"
BGDA="#1f2335"

# left/right rounded caps make a floating pill on the transparent bar
CAP_L=""
CAP_R=""

pill() { # pill <accent-hex> <text>
  local accent="$1" text="$2"
  printf '#[fg=%s,bg=default]%s#[fg=%s,bg=%s,bold]%s#[fg=%s,bg=default]%s' \
    "$BGDA" "$CAP_L" "$accent" "$BGDA" "$text" "$BGDA" "$CAP_R"
}

# Tunnel interfaces in priority order (OpenVPN / WireGuard / Tailscale / macOS utun)
TUN_IFACES=(tun0 tun1 tun2 wg0 wg1 proton0 nordlynx tailscale0 utun3 utun4 utun5)

tun_ip() {
  local i addr
  if command -v ip >/dev/null 2>&1; then # Linux / WSL
    for i in "${TUN_IFACES[@]}"; do
      addr=$(ip -4 -o addr show "$i" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
      [[ -n "$addr" ]] && {
        printf '%s\t%s' "$i" "$addr"
        return 0
      }
    done
  elif command -v ipconfig >/dev/null 2>&1; then # macOS / BSD
    for i in "${TUN_IFACES[@]}"; do
      addr=$(ipconfig getifaddr "$i" 2>/dev/null)
      [[ -n "$addr" ]] && {
        printf '%s\t%s' "$i" "$addr"
        return 0
      }
    done
  fi
  return 1
}

lan_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip route get 1.1.1.1 2>/dev/null |
      awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
  elif command -v route >/dev/null 2>&1; then
    local dev
    dev=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    [[ -n "$dev" ]] && ipconfig getifaddr "$dev" 2>/dev/null
  fi
}

if t=$(tun_ip); then
  iface=${t%%$'\t'*}
  addr=${t##*$'\t'}
  pill "$ORANGE" "󰦝 ${iface} ${addr}" # shield glyph: you're tunneled
elif l=$(lan_ip) && [[ -n "$l" ]]; then
  pill "$GREEN" "󰈀 ${l}" # ethernet glyph: LAN only
fi
