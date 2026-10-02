#!/usr/bin/env bash

: '
CTX_SIZE=32768 \
API_URL=http://127.0.0.1:8080 \
SYSTEM_PROMPT="$(cat AGENTS.md)" \
USE_TOOLS=true \
./chat.sh /ask do something AI
'

API_URL="${API_URL:-http://127.0.0.1:8080}"
CTX_SIZE="${CTX_SIZE:-32768}"

# TODO: Need edits and grep tool
# TODO: memory wiki system with agent
# TODO: Limit repetition infinite loop hashing

# NOTE: Need smart trash context cleanup
# NOTE: need orchestrating cause is smarter less context
# NOTE: Separated agents with different tools per analysis or wiki saving task
# NOTE: Even with web search tool decision need different agent for keeping out context

SYSTEM_PROMPT=${SYSTEM_PROMPT:-$(cat AGENTS.md)}
TOOLS_PROMPT=$(TOOLS=$(bun run tools/tools.ts) envsubst < tools/AGENTS.md)

[[ "$USE_TOOLS" == "false" ]] && TOOLS_PROMPT="" || TOOLS_PROMPT=$(printf "$TOOLS_PROMPT\n\n")
SYSTEM=$(printf "$SYSTEM_PROMPT\n\n$TOOLS_PROMPT")

CHAT=(
    # "Hello, Assistant."
    # "Hello. How may I help you today?"
    # "Please tell me the largest city in Europe."
    # "Sure. The largest city in Europe is Moscow, the capital of Russia."
)
CHAT=("${CHAT[@]/#/<think><\/think>}")

trim() {
    shopt -s extglob
    set -- "${1##+([[:space:]])}"
    printf "%s" "${1%%+([[:space:]])}"
}

format_prompt() {
	printf "<|im_start|>system\n%s<|im_end|>\n" "$SYSTEM"
	#<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n<think>\nreasoning\n</think>\n\ncontent
	if [[ "${#CHAT[@]}" -gt 0 ]]; then
		printf "<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n%s<|im_end|>\n" "${CHAT[@]}"
	fi
	printf "<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n" "$1"
}

tokenize() {
	# -n means do not read input. Good for constructing json
    curl \
        -s -X POST --url "${API_URL}/tokenize" \
        -H "Content-Type: application/json" \
        --data-raw "$(jq -ns --arg content "$1" '{content:$content}')" \
    | jq '.tokens[]'
}

count_visual_lines() {
    local text="$1"
    local cols=$(tput cols)
    local count=0
    while IFS= read -r line; do
        local len=${#line}
        if [ "$len" -eq 0 ]; then
            count=$((count + 1))
        else
            count=$((count + (len + cols - 1) / cols))
        fi
    done <<< "$text"
    echo "$count"
}

N_KEEP=$(tokenize "${SYSTEM}" | wc -l)
N_PREDICT=$(((CTX_SIZE / 2) - N_KEEP))

chat_completion() {
	# echo "USER: $1"
	# echo "Formatting prompt..."
    PROMPT="$(format_prompt "$1")"

	# echo "Creating data..."
	# -R raw input -s is slurp for taking the whole input once not per line
	# argjson: setss a value like foo 123 to $foo
	# arg always string, argjson parses value
    DATA="$(echo "$PROMPT" | jq -Rs --argjson n_keep $N_KEEP --argjson n_predict $N_PREDICT '{
        prompt: .,
        temperature: 0.0,
        top_k: 40,
        top_p: 0.95,
		min_p: 0.05,
		presence_penalty: 0.1,
		repetition_penalty: 1.0,
		repeat_last_n: 64,
        n_keep: $n_keep,
        n_predict: $n_predict,
        cache_prompt: true,
        stop: ["<|im_end|>"],
        stream: true
    }')"

	# echo "Waiting for AI..."
    local answer=''
	while IFS= read -r OUT; do
		TOKEN="${OUT//$'\\n'/$'\n'}" # WTF is this?
		answer+="${TOKEN}"
		printf "%s" "${TOKEN}"
	done < <(curl \
			-X POST -Ns --url "${API_URL}/completion" \
			-H "Content-Type: application/json" --data-raw "${DATA}" \
			| jq -R -r --unbuffered 'sub("^data:";"") | fromjson? | .content | gsub("\n";"\\n")')

	PREV=$(count_visual_lines "$answer")

	tput cuu "$((PREV - 1))"
	tput hpa 0 # horizontal position absolute
	tput ed

	echo "$answer" | mq-view | sed 's/^/\t/'

    CHAT+=("$1" "$(trim "$answer")")

	if [[ "$answer" =~ "<tool_call>" ]]; then
		local name=$(echo "$answer" | grep -oP '(?<=<function=)[^>]+')
		local response=""

		if [[ "$name" == "bash" ]]; then
			local param=$(echo "$answer" | sed -n '/<parameter=command>/,/<\/parameter>/p' | sed '1d;$d')
			response=$(eval "$param" 2>&1 | tee /dev/stderr)
			[ -z "$response" ] && response="exit code ${PIPESTATUS[0]}"
		elif [[ "$name" == "read" ]]; then
			local param=$(echo "$answer" | sed -n '/<parameter=name>/,/<\/parameter>/p' | sed '1d;$d')
			response=$(cat "$param" 2>&1 | tee /dev/stderr)
			[ -z "$response" ] && response="exit code ${PIPESTATUS[0]}"
		elif [[ "$name" == "subagent" ]]; then
			local param=$(echo "$answer" | sed -n '/<parameter=prompt>/,/<\/parameter>/p' | sed '1d;$d')
			response=$(${BASH_SOURCE[0]} "/ask $param" 2>&1 | tee /dev/stderr)
			[ -z "$response" ] && response="exit code ${PIPESTATUS[0]}"
		elif [[ "$name" == "websearch" ]]; then
			local param=$(echo "$answer" | sed -n '/<parameter=query>/,/<\/parameter>/p' | sed '1d;$d')
			response=$(ddgr --noua --unsafe --json --np "$param" | jq -r .[] | tee /dev/stderr)
			[ -z "$response" ] && response="exit code ${PIPESTATUS[0]}"
		elif [[ "$name" == "fetch" ]]; then
			USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
			local param=$(echo "$answer" | sed -n '/<parameter=url>/,/<\/parameter>/p' | sed '1d;$d')
			response=$(xh -b -I -F "$param" User-Agent:"$USER_AGENT" 2>&1)
			if [[ "$response" == *"<title>Just a moment...</title>"* ]]; then
				response=$(xh -b -I -F --json POST "$param" Content-Length:0 User-Agent:"$USER_AGENT" 2>&1)
			fi
			response=$(printf '%s' "$response" | mq-conv --format html | tee /dev/stderr)
			[ -z "$response" ] && response="exit code ${PIPESTATUS[0]}"
		fi

		if [[ -n "$response" ]]; then
			chat_completion "$(printf "<tool_response>\n%s\n</tool_response>" "$response")"
		fi
	fi
}

STATE_RAM="/dev/shm/chat_index.$$"
trap 'rm -f "$STATE_RAM"' EXIT
echo 0 > $STATE_RAM
prompt_count() {
	chat_index=$(cat $STATE_RAM)
	chat_index=$((chat_index+1))
	echo $chat_index > $STATE_RAM
	echo "[$chat_index]"
}

get_usage() {
	local tokens=$(tokenize "$(format_prompt)" | wc -l)
	echo "$tokens/$CTX_SIZE ($((tokens*100/CTX_SIZE))%)"
}

timestamp() { printf "[%s]" "$(date +"%H:%M:%S")"; }

evaluate_input() {
	INPUT="$*"
	COMMANDS=(help exit clear ping checkhealth usage load breakdown ask)

	if [[ "$INPUT" =~ ^/exit ]]; then
		echo "Exiting..."
		exit 0
	elif [[ "$INPUT" =~ ^/clear ]]; then
		echo "Clearing chat..."
		CHAT=()
	elif [[ "$INPUT" =~ ^/ping ]]; then
		echo "pong"
	elif [[ "$INPUT" =~ ^/checkhealth ]]; then
		curl -Ls http://localhost:8080/health | jq -r .status
	elif [[ "$INPUT" =~ ^/usage ]]; then
		echo "tokens: $(get_usage)"
	elif [[ "$INPUT" =~ ^/load ]]; then
		if [[ "$INPUT" =~ ^/load[[:space:]]+(.+) ]]; then
			filename="${BASH_REMATCH[1]}"
			content=$(cat "$filename" 2>&1)
			printf "<file=$filename>\n$(head $filename)\n...\n</file>\n" | mq-view
			chat_completion "$(printf "<file=%s>\n%s\n</file>" "$filename" "$content")"
		else
			echo "Please provide the file path to load."
		fi
	elif [[ "$INPUT" =~ ^/ask ]]; then
		if [[ "$INPUT" =~ ^/ask[[:space:]]+(.+) ]]; then
			tmp=$(mktemp)
			chat_completion "${BASH_REMATCH[1]}" > "$tmp"
			echo "> Full output at: $tmp"
			echo "${CHAT[-1]}" | sed '/<think>/,/<\/think>/d'
		else
			echo "Please provide the question/petition to ask."
		fi
		exit 0
	elif [[ "$INPUT" =~ ^/breakdown ]]; then
		if [[ "$INPUT" =~ ^/breakdown[[:space:]]+(.+) ]]; then
			REQUEST="/ask breakdown what the user is asking for <prompt>${BASH_REMATCH[1]}</prompt>"
			breakdown=$(USE_TOOLS=false SYSTEM_PROMPT="$(cat agents/ANALYST.md)" ${BASH_SOURCE[0]} "$REQUEST" | tail +2)
			echo "$breakdown" | mq-view | sed 's/^/\t/'
			chat_completion "$breakdown"
		else
			echo "Please provide the question/petition to breakdown."
		fi
	elif [[ "$INPUT" =~ ^/help ]]; then
		echo "Available commands:"
		printf "%s\n" "${COMMANDS[@]}"
	else
		chat_completion "$INPUT"
	fi
}

if [[ $# -ne 0 ]]; then
	evaluate_input "$*"
fi

while read -r -p "$(prompt_count) $(timestamp) $(get_usage)> " USER_INPUT; do
    echo ""
    evaluate_input "$USER_INPUT"
done
