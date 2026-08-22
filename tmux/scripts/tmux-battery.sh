#!/usr/bin/env bash
# tmux-battery.sh — battery pill for the tmux status line (portable: macOS + Linux).
#
# Emits a FULLY-STYLED tmux segment (hardcoded tokyonight-storm hex + rounded
# caps, exactly like tmux-netinfo.sh). Prints NOTHING when no battery exists
# (desktops, iMacs, VMs), so the segment simply vanishes there.
#
# WHY THIS IS A SCRIPT AND NOT INLINE #(...) IN tmux.conf:
#   tmux runs strftime %-expansion over the whole status-right string, and the
#   '%' in an inline pattern like  grep -Eo '[0-9]+%'  gets corrupted before the
#   command runs — the pattern degrades to [0-9]+ and then matches the "0" in
#   macOS's "InternalBattery-0", so the bar shows "0". Doing the work inside a
#   script keeps every '%', '$' and regex away from tmux's parser. We extract the
#   number with awk ($3 + 0), which turns "87%;" into the integer 87 with no
#   pattern for tmux to mangle.

set -u

# tokyonight-storm palette — keep in sync with tmux.conf @tn_* / tmux-netinfo.sh
BGDA="#1f2335"
GREEN="#9ece6a"
YELLOW="#e0af68"
RED="#f7768e"
CAP_L="" # @cap_l rounded left cap
CAP_R="" # @cap_r rounded right cap

pct=""
state=""

if command -v pmset >/dev/null 2>&1; then
  # macOS. Sample line:
  #   -InternalBattery-0 (id=4325475)\t87%; discharging; 4:32 remaining present: true
  # Find the field containing '%' wherever it sits (robust to spacing), and
  # classify state checking 'discharging' BEFORE 'charging' (substring trap).
  read -r pct state < <(pmset -g batt | awk '
        /InternalBattery/ {
            for (i = 1; i <= NF; i++) if ($i ~ /%/) p = $i + 0
            st = /discharging/ ? "dis" : (/charging|charged/ ? "chg" : "unk")
            print p, st; exit
        }')
elif ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  # Linux. First battery wins.
  for d in /sys/class/power_supply/BAT*; do
    [ -r "$d/capacity" ] || continue
    pct=$(cat "$d/capacity")
    state=$(cat "$d/status" 2>/dev/null || echo Unknown)
    break
  done
fi

# No battery detected -> emit nothing (segment disappears).
[ -n "${pct:-}" ] || exit 0

# Charging? macOS: "charging;"/"charged;" (but NOT "discharging;").
# Linux: "Charging"/"Full".
charging=0
case "$state" in
chg | Charging* | Full*) charging=1 ;;
esac

# Color + Nerd Font glyph by level.
if [ "$pct" -ge 60 ]; then
  color="$GREEN"
  glyph="󰂁"
elif [ "$pct" -ge 20 ]; then
  color="$YELLOW"
  glyph="󰁾"
else
  color="$RED"
  glyph="󰁻"
fi
[ "$charging" -eq 1 ] && glyph="󰂄"

# Styled pill. printf '%%' emits one literal '%'; it lands at the end of a token
# (followed by a space), which tmux passes through verbatim.
printf '#[fg=%s,bg=default]%s#[fg=%s,bg=%s,bold]%s %d%%#[fg=%s,bg=default]%s' \
  "$BGDA" "$CAP_L" "$color" "$BGDA" "$glyph" "$pct" "$BGDA" "$CAP_R"
