#!/bin/bash

# Status line - model, context, real Anthropic usage limits (OAuth API)

data=$(cat)

model_raw=$(echo "$data" | jq -r '.model.display_name // .model.id // "unknown"')
max_ctx=$(echo "$data" | jq -r '.context_window.context_window_size // 200000')
used_pct=$(echo "$data" | jq -r '.context_window.used_percentage // empty')
cwd=$(echo "$data" | jq -r '.cwd // empty')

# Strip "Claude " or "claude-" prefix(es) from model name
model=$(echo "$model_raw" | sed -E 's/^[Cc]laude[- ]//;s/^[Cc]laude[- ]//')

# Color by model family
model_lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
case "$model_lower" in
    opus*)   MODEL_COL='\033[1;33m'  ;;  # bold yellow — premium
    sonnet*) MODEL_COL='\033[1;35m'  ;;  # bold magenta — standard
    haiku*)  MODEL_COL='\033[1;36m'  ;;  # bold cyan — fast/light
    *)       MODEL_COL='\033[1;37m'  ;;  # bold white — unknown
esac

# Colors (ANSI)
R='\033[31m'      # red
Y='\033[33m'      # yellow
G='\033[32m'      # green
M='\033[35m'      # magenta
D='\033[2m'       # dim
W='\033[1;37m'    # bold white
N='\033[0m'       # reset

# --- Build 8-segment bar, echo color for caller ---
make_bar() {
    local pct=$1
    local COL
    if [ "$pct" -ge 80 ]; then COL="$R"
    elif [ "$pct" -ge 50 ]; then COL="$Y"
    else COL="$G"; fi

    local filled=$(( pct * 8 / 100 ))
    local bar=""
    for i in 0 1 2 3 4 5 6 7; do
        if [ "$i" -lt "$filled" ]; then bar="${bar}${COL}▓${N}"; else bar="${bar}${D}░${N}"; fi
    done
    printf '%b' "$bar"
}

# --- Context bar ---
if [ -z "$used_pct" ] || [ "$used_pct" = "null" ]; then
    ctx_display="${D}ctx …${N}"
else
    pct=$(printf "%.0f" "$used_pct" 2>/dev/null || echo "$used_pct")
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    used_k=$(( max_ctx * pct / 100 / 1000 ))
    max_k=$(( max_ctx / 1000 ))

    if [ "$pct" -ge 80 ]; then COL="$R"
    elif [ "$pct" -ge 50 ]; then COL="$Y"
    else COL="$G"; fi

    bar=$(make_bar "$pct")
    if [ "$max_k" -ge 1000 ]; then
        max_str="$(( max_k / 1000 ))M"
    else
        max_str="${max_k}k"
    fi
    ctx_display="${D}ctx${N} ${bar} ${COL}${pct}%${N} ${D}${used_k}k/${max_str}${N}"
fi

# --- Anthropic OAuth usage API (cached 60s) ---
CACHE="$HOME/.claude/usage-cache.json"
now=$(date +%s)
need_refresh=1
if [ -f "$CACHE" ]; then
    age=$(( now - $(stat -f %m "$CACHE" 2>/dev/null || echo 0) ))
    [ "$age" -lt 60 ] && need_refresh=0
fi

if [ "$need_refresh" -eq 1 ]; then
    AT=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['claudeAiOauth']['accessToken'])" 2>/dev/null)
    if [ -n "$AT" ]; then
        res=$(curl -s --max-time 3 "https://api.anthropic.com/api/oauth/usage" \
            -H "Authorization: Bearer $AT" \
            -H "Accept: application/json" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: StatusLine" 2>/dev/null)
        echo "$res" | jq -e '.five_hour' >/dev/null 2>&1 && echo "$res" > "$CACHE"
    fi
fi

# --- Parse usage data ---
usage_line=""
if [ -f "$CACHE" ]; then
    usage_line=$(python3 - <<'PYEOF' 2>/dev/null
import json, os
from datetime import datetime, timezone

try:
    with open(os.path.expanduser("~/.claude/usage-cache.json")) as f:
        d = json.load(f)
except Exception:
    exit()

now = datetime.now(timezone.utc)

def fmt_reset(iso_str):
    if not iso_str:
        return ""
    try:
        diff = (datetime.fromisoformat(iso_str) - now).total_seconds()
        if diff <= 0:
            return "now"
        d = int(diff) // 86400
        h = (int(diff) % 86400) // 3600
        m = (int(diff) % 3600) // 60
        if d > 0:
            return f"{d}d:{h:02d}h:{m:02d}m"
        return f"{h}h:{m:02d}m"
    except Exception:
        return ""

parts = []
for key, label in [("five_hour", "5h"), ("seven_day", "7d")]:
    e = d.get(key)
    if e and e.get("utilization") is not None:
        parts.append(f"{label}|{int(e['utilization'])}|{fmt_reset(e.get('resets_at'))}")

print(";".join(parts))
PYEOF
)
fi

# --- Build styled usage entry ---
build_entry() {
    local label=$1
    local pct=$2
    local reset=$3

    local COL
    if [ "$pct" -ge 80 ]; then COL="$R"
    elif [ "$pct" -ge 50 ]; then COL="$Y"
    else COL="$G"; fi

    local bar
    bar=$(make_bar "$pct")

    local rst=""
    [ -n "$reset" ] && rst=" ${D}${reset}${N}"

    printf '%b' "${D}${label}${N} ${bar} ${COL}${pct}%${N}${rst}"
}

# --- Assemble limits line ---
limits=""
if [ -n "$usage_line" ]; then
    IFS=';' read -ra ENTRIES <<< "$usage_line"
    for entry in "${ENTRIES[@]}"; do
        IFS='|' read -r label pct reset <<< "$entry"
        if [ -n "$label" ] && [ -n "$pct" ]; then
            piece=$(build_entry "$label" "$pct" "$reset")
            if [ -n "$limits" ]; then
                limits="${limits}  ${D}·${N}  ${piece}"
            else
                limits="${piece}"
            fi
        fi
    done
fi
[ -z "$limits" ] && limits="${D}limits …${N}"

# --- Output ---
printf '%b\n' "${MODEL_COL}◆${N} ${MODEL_COL}${model}${N}  ${D}│${N}  ${ctx_display}"
printf '%b\n' "${D}Usage${N}  ${limits}"
[ -n "$cwd" ] && printf '%b\n' "${D}${cwd/#$HOME/~}${N}"
