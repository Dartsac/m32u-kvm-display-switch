#!/bin/bash
# Switch between extended displays and mirroring optimized for the MacBook's built-in screen.
#   toggle-mirror.sh          -> toggle
#   toggle-mirror.sh mirror   -> mirror (does nothing if already mirrored)
#   toggle-mirror.sh extend   -> extended (does nothing if already extended)
#
# Displays are detected at run time: the MacBook's built-in screen plus exactly one external screen.
# The extended layout is saved by exact mode number before mirroring and restored afterwards,
# so a fixed refresh rate (for example 144 Hz) is not replaced by a "Variable" mode with the
# same resolution and refresh rate.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
STATE="$HOME/.config/display-toggle/extended-layout"

if ! command -v displayplacer >/dev/null; then
  echo "displayplacer not found. Install it with: brew install displayplacer" >&2
  exit 1
fi

# With the lid closed (clamshell mode) there is no MacBook screen to mirror to
if ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'; then
  echo "MacBook lid is closed; nothing to do"
  exit 0
fi

list=$(displayplacer list)

# One line per enabled screen: <id> <builtin 1|0> <mode> <width> <origin> <degree>
screens=$(awk '
  /^Persistent screen id:/ {id=$4; builtin=0; enabled=1}
  /^Type:/ {builtin=($0 ~ /built in/)}
  /^Origin:/ {origin=$2}
  /^Rotation:/ {deg=$2}
  /^Enabled:/ {enabled=($2 == "true")}
  /<-- current mode/ && enabled {m=$2; sub(":","",m); split($3,r,"[:x]"); print id, builtin, m, r[2], origin, deg}
' <<<"$list")

builtin=$(awk '$2==1 {print $1}' <<<"$screens")
external=$(awk '$2==0 {print $1}' <<<"$screens")

if [[ -z "$external" ]]; then
  echo "No external display connected; nothing to do"
  exit 0
fi
if [[ -z "$builtin" ]]; then
  echo "MacBook screen is off; nothing to do"
  exit 0
fi
if [[ $(wc -l <<<"$external") -gt 1 ]]; then
  echo "More than one external display connected; nothing to do"
  exit 0
fi

field() { awk -v id="$1" -v n="$2" '$1==id {print $n}' <<<"$screens"; }

if [[ "$(tail -1 <<<"$list")" == *"+"* ]]; then current=mirror; else current=extend; fi

want="$1"
if [[ -z "$want" ]]; then
  [[ $current == mirror ]] && want=extend || want=mirror
fi

case "$want" in
  "$current")
    echo "Already in $current mode; nothing to do"
    ;;
  extend)
    # Use the saved layout only if it describes exactly the screens connected now
    layout=()
    if [[ -f "$STATE" ]]; then
      while IFS= read -r line; do [[ -n "$line" ]] && layout+=("$line"); done < "$STATE"
    fi
    saved_ids=$(printf '%s\n' "${layout[@]}" | sed -n 's/^id:\([^ ]*\) .*/\1/p' | sort)
    if [[ ${#layout[@]} -eq 0 || "$saved_ids" != "$(printf '%s\n' "$builtin" "$external" | sort)" ]]; then
      # Fallback: keep current modes, external screen on the left, MacBook screen on its right
      layout=("id:$external mode:$(field "$external" 3) origin:(0,0) degree:0"
              "id:$builtin mode:$(field "$builtin" 3) origin:($(field "$external" 4),0) degree:0")
      echo "No usable saved layout; using a basic extended layout"
    fi
    displayplacer "${layout[@]}"
    echo "Switched to extended"
    ;;
  mirror)
    # Save the exact current layout, one screen per line, then mirror the MacBook screen
    mkdir -p "$(dirname "$STATE")"
    awk '{printf "id:%s mode:%s origin:%s degree:%s\n", $1, $3, $5, $6}' <<<"$screens" > "$STATE"
    displayplacer "id:$builtin+$external mode:$(field "$builtin" 3) origin:(0,0) degree:0"
    echo "Switched to mirror"
    ;;
  *)
    echo "Usage: $0 [mirror|extend]" >&2
    exit 2
    ;;
esac
