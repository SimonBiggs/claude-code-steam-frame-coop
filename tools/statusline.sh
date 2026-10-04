#!/bin/bash
# Claude Code status line: shows claude.ai usage limits and saves them to
# ~/.claude/usage.json so Claude can check them (see ~/.local/bin/claude-usage).
input=$(cat)
dir=$HOME/.claude
printf '%s' "$input" > "$dir/statusline-last.json"

rl=$(jq -c '.rate_limits // empty' <<<"$input" 2>/dev/null)
if [ -n "$rl" ] && [ "$rl" != "null" ]; then
  # Each session saves its own reading; usage.json merges them. An idle session keeps showing the
  # reading from its last API reply, which can be stale (e.g. from before a usage reset), so per
  # window the newest window wins, then the reading of the most recently active session
  # (the one whose transcript changed last).
  sid=$(jq -r '.session_id // "unknown"' <<<"$input")
  mkdir -p "$dir/usage.d"
  tp=$(jq -r '.transcript_path // empty' <<<"$input")
  # Activity = the time of the session's last assistant reply (the background service can touch an
  # old transcript without talking to the API, which made a stale reading look fresh).
  last=$(tail -n 400 "$tp" 2>/dev/null | grep '"type":"assistant"' | tail -n 1 | jq -r '.timestamp // empty' 2>/dev/null)
  act=$( [ -n "$last" ] && date -d "$last" +%s 2>/dev/null || echo 0)
  jq -n --argjson rl "$rl" --argjson ep "$(date +%s)" --argjson act "$act" '{updated_epoch: $ep, active_epoch: $act, rate_limits: $rl}' \
    > "$dir/usage.d/$sid.json.tmp" && mv "$dir/usage.d/$sid.json.tmp" "$dir/usage.d/$sid.json"
  jq -s --argjson now "$(date +%s)" --arg at "$(date -Is)" '
    [.[] | select(.updated_epoch > $now - 21600)]
    | {updated: $at, updated_epoch: (map(.updated_epoch) | max),
       rate_limits: ([.[] | .active_epoch as $a | .rate_limits | to_entries[] | select(.value | type == "object") | .value.active = $a]
         | group_by(.key)
         | map({key: .[0].key, value: (map(.value) | max_by([.resets_at // 0, .active // 0]) | del(.active))})
         | from_entries)}' "$dir"/usage.d/*.json > "$dir/usage.json.tmp" && mv "$dir/usage.json.tmp" "$dir/usage.json"
  rl=$(jq -c '.rate_limits' "$dir/usage.json")
  # Usage history for claude-pace (one line a minute at most): epoch 5h% 5h_reset 7d% 7d_reset
  hist=$dir/usage-history.log
  last=$(tail -n1 "$hist" 2>/dev/null | cut -d' ' -f1)
  if [ $(( $(date +%s) - ${last:-0} )) -ge 55 ]; then
    echo "$(date +%s) $(jq -r '[.five_hour.used_percentage, .five_hour.resets_at, .seven_day.used_percentage, .seven_day.resets_at] | map(. // 0 | tostring) | join(" ")' <<<"$rl")" >> "$hist"
  fi
fi

when() {  # resets_at (epoch s/ms or ISO string) -> local time
  local v=$1
  [ -z "$v" ] || [ "$v" = null ] && return
  if [[ $v =~ ^[0-9]+$ ]]; then
    [ ${#v} -gt 11 ] && v=$((v / 1000))
    v="@$v"
  fi
  local t; t=$(date -d "$v" +%s 2>/dev/null) || return
  if [ "$(date -d "@$t" +%F)" = "$(date +%F)" ]; then date -d "@$t" +%H:%M; else date -d "@$t" '+%a %H:%M'; fi
}

parts=()
if [ -n "$rl" ] && [ "$rl" != "null" ]; then
  while IFS=$'\t' read -r name pct reset; do
    case $name in five_hour) label=5h ;; seven_day) label=week ;; *) label=${name//_/ } ;; esac
    r=$(when "$reset")
    parts+=("$label ${pct%.*}%${r:+ (resets $r)}")
  done < <(jq -r 'to_entries[] | select(.value | type == "object" and has("used_percentage"))
                  | [.key, (.value.used_percentage | tostring), (.value.resets_at // "" | tostring)] | @tsv' <<<"$rl")
fi
model=$(jq -r '.model.display_name // empty' <<<"$input" 2>/dev/null)
line="${model}"
for p in "${parts[@]}"; do line+="${line:+ · }$p"; done
printf '%s' "${line:-usage: waiting for first reply}"
