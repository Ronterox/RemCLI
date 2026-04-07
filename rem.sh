#!/usr/bin/env bash

SESSION_ID=""
MODEL=""
TMPDIR_WORK=$(mktemp -d /tmp/rem.XXXXXX)

cleanup() {
    jobs -p 2>/dev/null | xargs kill 2>/dev/null || true
    rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT INT TERM

gum style \
    --border rounded \
    --margin "0 1" \
    --padding "0 3" \
    --border-foreground 99 \
    --foreground 99 \
    "rem · OpenCode CLI"

echo ""
gum style --foreground 240 "  /exit quit · /clear reset · /model switch model"
echo ""

while true; do
    USER_INPUT=""
    USER_INPUT=$(gum input --prompt "❯ " --placeholder "Message... (/exit to quit)" --width "$(tput cols)") || continue

    [[ -z "$USER_INPUT" ]] && continue

    case "$USER_INPUT" in
        /exit|/q)
            echo ""
            gum style --foreground 99 "Goodbye!"
            exit 0
            ;;
        /clear)
            SESSION_ID=""
            echo ""
            gum style --foreground 99 "Session cleared."
            echo ""
            continue
            ;;
        /model)
            echo ""
            MODEL=$(gum input --prompt "model ❯ " --placeholder "provider/model (e.g. anthropic/claude-sonnet-4-20250514)") || continue
            echo ""
            gum style --foreground 240 "Model: $MODEL"
            echo ""
            continue
            ;;
    esac

    echo ""

    OUTFILE="$TMPDIR_WORK/response.jsonl"

    ARGS=(--format json)
    [[ -n "$MODEL" ]] && ARGS+=(-m "$MODEL")
    [[ -n "$SESSION_ID" ]] && ARGS+=(-c -s "$SESSION_ID")
    ARGS+=("$USER_INPUT")

    gum spin --spinner dot --spinner.foreground 99 --title " thinking..." -- \
        sh -c 'opencode run "$@" > "$0" 2>/dev/null' "$OUTFILE" "${ARGS[@]}"

    FULL_TEXT=""
    TOTAL_TOKENS=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        EVENT_TYPE=$(jq -r '.type // ""' <<< "$line" 2>/dev/null) || continue

        case "$EVENT_TYPE" in
            step_start)
                if [[ -z "$SESSION_ID" ]]; then
                    SESSION_ID=$(jq -r '.sessionID // ""' <<< "$line" 2>/dev/null)
                fi
                ;;
            text)
                T=$(jq -r '.part.text // ""' <<< "$line" 2>/dev/null)
                [[ -n "$T" ]] && FULL_TEXT+="$T"
                ;;
            tool_use)
                TOOL=$(jq -r '.part.tool // "unknown"' <<< "$line" 2>/dev/null)
                DETAIL=""
                case "$TOOL" in
                    read)   DETAIL=$(jq -r '.part.state.input.filePath // ""' <<< "$line" 2>/dev/null) ;;
                    bash)   DETAIL=$(jq -r '.part.state.input.command // ""' <<< "$line" 2>/dev/null | cut -c1-60) ;;
                    write)  DETAIL=$(jq -r '.part.state.input.filePath // ""' <<< "$line" 2>/dev/null) ;;
                    edit)   DETAIL=$(jq -r '.part.state.input.filePath // ""' <<< "$line" 2>/dev/null) ;;
                    glob)   DETAIL=$(jq -r '.part.state.input.pattern // ""' <<< "$line" 2>/dev/null) ;;
                    grep)   DETAIL=$(jq -r '.part.state.input.pattern // ""' <<< "$line" 2>/dev/null) ;;
                    *)      DETAIL="" ;;
                esac
                if [[ -n "$DETAIL" ]]; then
                    gum style --foreground 240 "  ⟡ $TOOL → $DETAIL"
                else
                    gum style --foreground 240 "  ⟡ $TOOL"
                fi
                ;;
            step_finish)
                TOK=$(jq -r '.part.tokens.total // 0' <<< "$line" 2>/dev/null)
                TOTAL_TOKENS=$((TOTAL_TOKENS + TOK))
                ;;
        esac
    done < "$OUTFILE"

    if [[ -n "$FULL_TEXT" ]]; then
        FULL_TEXT="${FULL_TEXT#"${FULL_TEXT%%[![:space:]]*}"}"
        printf '%s\n' "$FULL_TEXT" | gum format -t markdown 2>/dev/null || printf '%s\n' "$FULL_TEXT"
    else
        gum style --foreground 196 "No response."
    fi

    echo ""
    gum style --foreground 240 "session: ${SESSION_ID:0:16}… │ tokens: $TOTAL_TOKENS"
    echo ""
done
