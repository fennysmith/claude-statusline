#!/bin/sh
# Claude Code statusline.
#
# Reads the statusline JSON payload from stdin and prints a single
# colored line: user@host:dir [model] (ctx/tokens) [5h] [week] {month}
#
# Optional environment variables:
#   ANTHROPIC_API_KEY              enable {month:Ntok $cost} segment
#   CLAUDE_STATUSLINE_NO_MONTHLY=1 disable monthly segment even if key set
#   CLAUDE_STATUSLINE_NO_RATE=1    disable 5h / weekly segments
#   CLAUDE_STATUSLINE_DEBUG=path   dump raw input JSON to this path

input=$(cat)

if [ -n "$CLAUDE_STATUSLINE_DEBUG" ]; then
    printf "%s" "$input" > "$CLAUDE_STATUSLINE_DEBUG" 2>/dev/null || true
fi

user=$(whoami)
host=$(hostname -s 2>/dev/null || hostname)

# Minimal fallback if jq is missing.
if ! command -v jq >/dev/null 2>&1; then
    printf "\033[32m%s@%s\033[0m \033[31m(install jq for full statusline)\033[0m\n" "$user" "$host"
    exit 0
fi

# Detect date flavor once.
if date -d "@0" >/dev/null 2>&1; then
    DATE_FLAVOR=gnu
else
    DATE_FLAVOR=bsd
fi

fmt_epoch() {  # $1=epoch seconds, $2=strftime format
    if [ "$DATE_FLAVOR" = gnu ]; then
        date -d "@$1" "+$2" 2>/dev/null
    else
        date -r "$1" "+$2" 2>/dev/null
    fi
}

month_bounds_start() {
    date -u +"%Y-%m-01T00:00:00Z"
}

month_bounds_end() {
    if [ "$DATE_FLAVOR" = gnu ]; then
        date -u -d "$(date +%Y-%m-01) +1 month -1 day" +"%Y-%m-%dT23:59:59Z" 2>/dev/null
    else
        date -u -v1d -v+1m -v-1d +"%Y-%m-%dT23:59:59Z" 2>/dev/null
    fi
}

dir=$(printf "%s" "$input" | jq -r '.workspace.current_dir // .cwd // empty')
short_dir=$(basename "${dir:-?}")

model=$(printf "%s" "$input" | jq -r '.model.display_name // empty')

used_pct=$(printf "%s" "$input" | jq -r '.context_window.used_percentage // empty')
total_in=$(printf "%s" "$input" | jq -r '.context_window.total_input_tokens // empty')
total_out=$(printf "%s" "$input" | jq -r '.context_window.total_output_tokens // empty')

five_h_pct=$(printf "%s" "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_h_reset=$(printf "%s" "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

week_pct=$(printf "%s" "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(printf "%s" "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Context / token segment
token_info=""
if [ -n "$used_pct" ]; then
    used_pct_fmt=$(printf "%.0f" "$used_pct")
    token_info="ctx:${used_pct_fmt}%"
fi
if [ -n "$total_in" ] && [ -n "$total_out" ]; then
    total=$(( total_in + total_out ))
    if [ "$total" -ge 1000 ]; then
        total_fmt=$(echo "$total" | awk '{printf "%.1fk", $1/1000}')
    else
        total_fmt="${total}"
    fi
    if [ -n "$token_info" ]; then
        token_info="${token_info} tokens:${total_fmt}"
    else
        token_info="tokens:${total_fmt}"
    fi
fi

printf "\033[32m%s@%s\033[0m:\033[34m%s\033[0m" "$user" "$host" "$short_dir"

[ -n "$model" ] && printf " \033[33m[%s]\033[0m" "$model"
[ -n "$token_info" ] && printf " \033[36m(%s)\033[0m" "$token_info"

# Rate limit segments
if [ "${CLAUDE_STATUSLINE_NO_RATE:-0}" != "1" ]; then
    if [ -n "$five_h_pct" ]; then
        five_h_fmt=$(printf "%.0f" "$five_h_pct")
        rate_info="5h:${five_h_fmt}%"
        if [ -n "$five_h_reset" ]; then
            reset_time=$(fmt_epoch "$five_h_reset" "%H:%M")
            [ -n "$reset_time" ] && rate_info="${rate_info} ↻ ${reset_time}"
        fi
        printf " \033[35m[%s]\033[0m" "$rate_info"
    fi

    if [ -n "$week_pct" ]; then
        week_fmt=$(printf "%.0f" "$week_pct")
        week_info="week:${week_fmt}%"
        if [ -n "$week_reset" ]; then
            week_reset_time=$(fmt_epoch "$week_reset" "%m/%d %H:%M")
            [ -n "$week_reset_time" ] && week_info="${week_info} ↻ ${week_reset_time}"
        fi
        printf " \033[91m[%s]\033[0m" "$week_info"
    fi
fi

# Monthly Anthropic API usage (cached 5 min)
if [ -n "$ANTHROPIC_API_KEY" ] && [ "${CLAUDE_STATUSLINE_NO_MONTHLY:-0}" != "1" ] && command -v curl >/dev/null 2>&1; then
    CACHE_FILE="${TMPDIR:-/tmp}/.claude_monthly_usage_cache"
    CACHE_TTL=300
    monthly_info=""

    use_cache=0
    if [ -f "$CACHE_FILE" ]; then
        if [ "$DATE_FLAVOR" = gnu ]; then
            mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        else
            mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
        fi
        cache_age=$(( $(date +%s) - mtime ))
        [ "$cache_age" -lt "$CACHE_TTL" ] && use_cache=1
    fi

    if [ "$use_cache" = "1" ]; then
        monthly_info=$(cat "$CACHE_FILE" 2>/dev/null)
    else
        month_start=$(month_bounds_start)
        month_end=$(month_bounds_end)
        [ -z "$month_end" ] && month_end=$(date -u +"%Y-%m-%dT23:59:59Z")

        api_resp=$(curl -sf --max-time 5 \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            "https://api.anthropic.com/v1/usage?start_time=${month_start}&end_time=${month_end}&granularity=month" \
            2>/dev/null)

        if [ -n "$api_resp" ]; then
            total_tokens=$(printf "%s" "$api_resp" | jq -r '
                if .data then
                  [.data[] | (.input_tokens // 0) + (.output_tokens // 0) + (.cache_creation_input_tokens // 0)] | add // 0
                else 0 end' 2>/dev/null)
            total_cost=$(printf "%s" "$api_resp" | jq -r '
                if .data then
                  [.data[] | (.input_cost // 0) + (.output_cost // 0) + (.cache_creation_cost // 0)] | add // 0
                else 0 end' 2>/dev/null)

            if [ -n "$total_tokens" ] && [ "$total_tokens" != "0" ] && [ "$total_tokens" != "null" ]; then
                if [ "$total_tokens" -ge 1000000 ]; then
                    tok_fmt=$(echo "$total_tokens" | awk '{printf "%.1fM", $1/1000000}')
                elif [ "$total_tokens" -ge 1000 ]; then
                    tok_fmt=$(echo "$total_tokens" | awk '{printf "%.1fk", $1/1000}')
                else
                    tok_fmt="${total_tokens}"
                fi
                monthly_info="month:${tok_fmt}tok"
                if [ -n "$total_cost" ] && [ "$total_cost" != "0" ] && [ "$total_cost" != "null" ]; then
                    cost_fmt=$(printf "%.2f" "$total_cost" 2>/dev/null)
                    monthly_info="${monthly_info} \$${cost_fmt}"
                fi
                printf "%s" "$monthly_info" > "$CACHE_FILE"
            fi
        fi
    fi

    [ -n "$monthly_info" ] && printf " \033[33m{%s}\033[0m" "$monthly_info"
fi

printf "\n"
