#!/usr/bin/env bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────
MODEL="${REM_MODEL:-}"
SESSION_ID=""
CONTINUE=false
TMPDIR_REM=$(mktemp -d /tmp/remcli.XXXXXX)
trap 'rm -rf "$TMPDIR_REM"' EXIT

# ── Helpers ─────────────────────────────────────────────────────────
log_info()  { gum style --foreground 36 "$1"; }
log_warn()  { gum style --foreground 33 "$1"; }
log_error() { gum style --foreground 196 --bold "$1"; }

# ── Build opencode args ─────────────────────────────────────────────
build_args() {
	local msg="$1"
	local args=(run --format json)

	[[ -n "$MODEL" ]] && args+=(--model "$MODEL")
	$CONTINUE && [[ -n "$SESSION_ID" ]] && args+=(--continue --session "$SESSION_ID")

	args+=("--" "$msg")
	echo "${args[@]}"
}

# ── Parse JSONL → structured JSON ───────────────────────────────────
parse_jsonl() {
	local infile="$1" outfile="$2"

	jq -Rs '
		split("\n")
		| map(select(length > 0) | try fromjson catch null | select(. != null))
		| {
			session_id: (map(select(.type=="step_start"))[0].sessionID // ""),
			reasoning:  ([.[].part.text // empty] | select(length > 0) | join("")),
			text:       ([.[] | select(.type=="text") | .part.text // empty] | join("")),
			tokens_in:  (map(select(.type=="step_finish"))[0].part.tokens.input // 0),
			tokens_out: (map(select(.type=="step_finish"))[0].part.tokens.output // 0),
			cost:       (map(select(.type=="step_finish"))[0].part.cost // 0)
		}
	' "$infile" > "$outfile"
}

# ── Display response ────────────────────────────────────────────────
show_response() {
	local parsed="$1"

	local text reasoning sid tokens_in tokens_out cost
	text=$(jq -r '.text' "$parsed")
	reasoning=$(jq -r '.reasoning' "$parsed")
	sid=$(jq -r '.session_id' "$parsed")
	tokens_in=$(jq -r '.tokens_in' "$parsed")
	tokens_out=$(jq -r '.tokens_out' "$parsed")
	cost=$(jq -r '.cost' "$parsed")

	# Update session for multi-turn
	if [[ -n "$sid" && "$sid" != "null" && "$sid" != "" ]]; then
		SESSION_ID="$sid"
		CONTINUE=true
	fi

	# Reasoning
	if [[ -n "$reasoning" && "$reasoning" != "null" ]]; then
		echo -e "\033[2m━━ Reasoning ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
		echo "$reasoning" | gum style --foreground 240
		echo ""
	fi

	# Response
	if [[ -n "$text" && "$text" != "null" ]]; then
		echo -e "\033[1;36m━━ Rem ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
		echo "$text" | glow - 2>/dev/null || echo "$text"
	fi

	# Stats
	echo ""
	echo -e "\033[2mtokens: ${tokens_in}↑ ${tokens_out}↓  cost: \$${cost}\033[0m"
	echo ""
}

# ── Banner ──────────────────────────────────────────────────────────
show_banner() {
	gum style \
		--border rounded \
		--border-foreground 36 \
		--padding "1 2" \
		--foreground 36 \
		"RemCLI — AI Assistant

  /clear   clear conversation
  /model   change model
  /quit    exit"
	echo ""
}

# ── Main loop ───────────────────────────────────────────────────────
main() {
	show_banner

	while true; do
		local p="You"
		$CONTINUE && p+=" [${SESSION_ID: -8}]"
		p+=" > "

		local input
		input=$(gum input --prompt "$p" --placeholder "Ask anything..." 2>/dev/null) || {
			echo ""
			log_warn "Goodbye!"
			exit 0
		}

		case "${input,,}" in
			"") continue ;;
			"/quit"|"/exit"|"exit")
				log_warn "Goodbye!"
				exit 0
				;;
			"/clear")
				SESSION_ID=""
				CONTINUE=false
				log_info "Conversation cleared."
				echo ""
				continue
				;;
			"/model")
				MODEL=$(gum input --prompt "Model (provider/model): " --value "$MODEL" 2>/dev/null) || true
				log_info "Model set to: ${MODEL:-default}"
				echo ""
				continue
				;;
		esac

		local raw_file="$TMPDIR_REM/raw.jsonl"
		local parsed_file="$TMPDIR_REM/parsed.json"

		# Run opencode inside gum spin — pass everything via env so the
		# sub-bash only needs to call opencode directly (no sourcing).
		gum spin --spinner dot --title "Thinking..." -- \
			env \
				SESSION_ID="$SESSION_ID" \
				CONTINUE="$CONTINUE" \
				REM_MODEL="$MODEL" \
				bash -c '
					args=(run --format json)
					[[ -n "$REM_MODEL" ]] && args+=(--model "$REM_MODEL")
					[[ "$CONTINUE" == "true" && -n "$SESSION_ID" ]] && args+=(--continue --session "$SESSION_ID")
					opencode "${args[@]}" -- "$1" > "$2" 2>/dev/null
				' _ "$input" "$raw_file"

		# Parse
		parse_jsonl "$raw_file" "$parsed_file"

		# Display
		if [[ -f "$parsed_file" && -s "$parsed_file" ]]; then
			show_response "$parsed_file"
		else
			log_error "No response received."
			echo ""
		fi
	done
}

main "$@"
