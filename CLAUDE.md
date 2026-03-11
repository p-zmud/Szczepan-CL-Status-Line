# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A two-line Claude Code status line script that shows real usage limits from the Anthropic OAuth API.

```
Line 1: model name + context window bar with % and token count
Line 2: 5h and 7d usage limits with progress bars and reset countdown
```

## Prerequisites

- `jq`, `curl`, `python3` — used at runtime
- OAuth credentials at `~/.claude/.credentials.json` (from `claude login`) with `claudeAiOauth.accessToken`
- macOS (`stat -f %m` for file mtime) — Linux needs `stat -c %Y`

## Install

```bash
./install.sh
```

Copies `status-line.sh` to `~/.claude/scripts/` and adds `statusLine` config to `~/.claude/settings.json`.

## How it works

1. Reads JSON from stdin (Claude Code pipes session data automatically)
2. Builds context window bar from `context_window.used_percentage`
3. Calls `https://api.anthropic.com/api/oauth/usage` with OAuth bearer token (cached 60s in `~/.claude/usage-cache.json`)
4. API returns `utilization` (0-100%) and `resets_at` (ISO timestamp) for `five_hour` and `seven_day` windows
5. Outputs two lines with ANSI-colored progress bars

## Color thresholds (consistent across all bars)

- Green: < 50%
- Yellow: 50–79%
- Red: >= 80%

## Key constraints

- Script must complete fast — Claude Code calls it frequently. API call has `--max-time 3` and 60s cache.
- `local` keyword is used inside functions but NOT at top-level scope (bash quirk — line 40 has a stale `local` that works by accident outside function).
- Embedded Python blocks handle JSON parsing and datetime math that bash can't do cleanly.
- `stat -f %m` is macOS-specific for checking cache file age.
