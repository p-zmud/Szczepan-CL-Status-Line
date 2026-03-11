#!/bin/bash

# Status line - model, context, real Anthropic usage limits (OAuth API)

data=$(cat)

model=$(echo "$data" | jq -r '.model.display_name // .model.id // "unknown"')
max_ctx=$(echo "$data" | jq -r '.context_window.context_window_size // 200000')
used_pct=$(echo "$data" | jq -r '.context_window.used_percentage // empty')

# Colors
B='\033[34m'    # blue
R='\033[31m'    # red
Y='\033[33m'    # yellow
G='\033[32m'    # green
C='\033[36m'    # cyan
D='\033[2m'     # dim
W='\033[1;37m'  # bold white
N='\033[0m'     # reset

# --- Context bar (10 segments) ---
if [ -z "$used_pct" ] || [ "$used_pct" = "null" ]; then
    ctx_display="${D}ctx loading...${N}"
else
    pct=$(printf "%.0f" "$used_pct" 2>/dev/null || echo "$used_pct")
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    used_k=$(( max_ctx * pct / 100 / 1000 ))
    max_k=$(( max_ctx / 1000 ))

    filled=$(( pct / 10 ))
    if [ "$pct" -ge 80 ]; then COL="$R"
    elif [ "$pct" -ge 50 ]; then COL="$Y"
    else COL="$G"; fi

    bar=""
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if [ "$i" -lt "$filled" ]; then bar="${bar}${COL}▰${N}"; else bar="${bar}${D}▱${N}"; fi
    done

    pct_str=""
    if [ "$pct" -lt 10 ]; then pct_str=" ${pct}%"
    elif [ "$pct" -lt 100 ]; then pct_str="${pct}%"
    else pct_str="MAX"; fi

    ctx_display="${W}ctx${N} ${bar} ${COL}${pct_str}${N} ${D}${used_k}k/${max_k}k${N}"
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
    AT=$(python3 -c "import json; print(json.load(open('$HOME/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])" 2>/dev/null)
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

# --- Build usage bar (10 segments) ---
build_bar() {
    local pct=$1
    local label=$2
    local reset=$3

    # Color by severity
    local COL
    if [ "$pct" -ge 80 ]; then COL="$R"
    elif [ "$pct" -ge 50 ]; then COL="$Y"
    else COL="$G"; fi

    # 10-segment bar
    local filled=$(( pct / 10 ))
    local bar=""
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if [ "$i" -lt "$filled" ]; then bar="${bar}${COL}▰${N}"; else bar="${bar}${D}▱${N}"; fi
    done

    # Padded percentage
    local pct_str
    if [ "$pct" -lt 10 ]; then pct_str=" ${pct}%"
    elif [ "$pct" -lt 100 ]; then pct_str="${pct}%"
    else pct_str="MAX"; fi

    # Reset countdown
    local rst=""
    if [ -n "$reset" ]; then
        rst=" ${D}${reset}${N}"
    fi

    printf '%b' "${W}${label}${N} ${bar} ${COL}${pct_str}${N}${rst}"
}

# --- Assemble limits ---
limits=""
if [ -n "$usage_line" ]; then
    IFS=';' read -ra ENTRIES <<< "$usage_line"
    for entry in "${ENTRIES[@]}"; do
        IFS='|' read -r label pct reset <<< "$entry"
        if [ -n "$label" ] && [ -n "$pct" ]; then
            piece=$(build_bar "$pct" "$label" "$reset")
            if [ -n "$limits" ]; then
                limits="${limits}  ${piece}"
            else
                limits="${C}Usage${N}  ${piece}"
            fi
        fi
    done
fi
[ -z "$limits" ] && limits="${D}limits: loading...${N}"

# --- Output ---
printf '%b\n' "${model}  ${ctx_display}"
printf '%b\n' "${limits}"
