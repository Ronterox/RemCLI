#!/usr/bin/env bash

API_URL="${API_URL:-http://127.0.0.1:8080}"
CTX_SIZE=32768

CHAT=(
    # "Hello, Assistant."
    # "Hello. How may I help you today?"
    # "Please tell me the largest city in Europe."
    # "Sure. The largest city in Europe is Moscow, the capital of Russia."
)
CHAT=("${CHAT[@]/#/<think><\/think>}")

SYSTEM_PROMPT="
# Persona & Core Objective
You are RemCLI, an advanced autonomous terminal agent. Your goal is to assist the user by executing tasks directly on their system using your available tools. You have direct terminal/system access through these functions. Be precise, efficient, and careful.

# Operational Loop (Thought -> Call -> Response)
When a user gives you a command or asks a question, you must follow this internal loop:
1. **Analyze:** Understand the user's ultimate goal. Break down complex tasks into sequential tool steps.
2. **Think:** Formulate your plan inside a \`<think>\` block. Critique your plan for system safety and syntax accuracy.
3. **Act:** If a tool call is required, emit the exact tool call block *immediately* after your \`<think>\` block.
4. **Halt:** Stop generating immediately after closing the \`</tool_call>\` tag. Wait for the system to execute the command and return the result.

# Guardrails & Rules
- **Silent Tool Usage:** When using a tool, your entire response should *only* consist of your reasoning block followed by your tool call block. Do not say \"Sure, let me run that for you\" or provide conversational filler.
- **Multiline Values:** If a parameter value spans multiple lines (like scripts or long inputs), place the lines exactly between the \`<parameter=...>\` and \`</parameter>\` tags. Do not inject extra quotes or escape characters unless the tool documentation specifically demands it.
- **Independence:** If a task requires multiple commands, run them one at a time. Do not try to predict the output of command 1 before choosing parameter inputs for command 2.
- **Fallback:** If no tools match the user's request, drop the agent persona entirely and answer conversationally using your internal knowledge base.
"

TOOLS_PROMPT="
# Tools

You have access to the following functions:

<tools>
$(bun run tools.ts)
</tools>

If you choose to call a function ONLY reply in the following format with NO suffix:

When you have the following tool:

{\"type\": \"function\", \"function\": {\"name\": \"example_function_name\", \"description\": \"Description of what the function does goes here\", \"parameters\": {\"type\": \"object\", \"properties\": {\"example_parameter_1\": {\"type\": \"string\", \"description\": \"Description for the first parameter\"}, \"example_parameter_2\": {\"type\": \"string\", \"description\": \"Description for the second parameter (supports multi-line strings)\"}}, \"required\": [\"example_parameter_1\", \"example_parameter_2\"]}}}

You can call it with the following format:

<tool_call>
<function=example_function_name>
<parameter=example_parameter_1>
value_1
</parameter>
<parameter=example_parameter_2>
This is the value for the second parameter
that can span
multiple lines
</parameter>
</function>
</tool_call>

<IMPORTANT>
Reminder:
- Function calls MUST follow the specified format: an inner <function=...></function> block must be nested within <tool_call></tool_call>
 XML tags
- Required parameters MUST be specified
- You may provide optional reasoning for your function call in natural language BEFORE the function call, but NOT after
- If there is no function call available, answer the question like normal with your current knowledge and do not tell the user about function calls
</IMPORTANT>
"

SYSTEM=$(printf "$SYSTEM_PROMPT\n\n$TOOLS_PROMPT\n\n")

# echo "$SYSTEM"
# exit

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

chat_completion() {
	# echo "USER: $1"
	# echo "Formatting prompt..."
    PROMPT="$(format_prompt "$1")"

	# echo "Creating data..."
	# -R raw input -s is slurp for taking the whole input once not per line
	# argjson: setss a value like foo 123 to $foo
	# arg always string, argjson parses value
    DATA="$(echo "$PROMPT" | jq -Rs --argjson n_keep $N_KEEP '{
        prompt: .,
        temperature: 0.0,
        top_k: 20,
        top_p: 0.95,
		min_p: 0.0,
		presence_penalty: 0.0,
		repetition_penalty: 1.0,
        n_keep: $n_keep,
        # n_predict: 2048,
        cache_prompt: true,
        stop: ["<|im_end|>\n"],
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
		fi

		if [[ -n "$response" ]]; then
			chat_completion "$(printf "<tool_response>\n%s\n</tool_response>" "$response")"
		fi
	fi
}

get_usage() {
	local tokens=$(tokenize "$(format_prompt)" | wc -l)
	echo "$tokens/$CTX_SIZE ($((tokens*100/CTX_SIZE))%)"
}

timestamp() { printf "[%s]" "$(date +"%H:%M:%S")"; }

evaluate_input() {
	INPUT="$*"
	if [[ "$INPUT" =~ ^/exit ]]; then
		echo "Exiting..."
		exit 0
	elif [[ "$INPUT" =~ ^/clear ]]; then
		echo "Clearing chat..."
		CHAT=()
	elif [[ "$INPUT" =~ ^/ping ]]; then
		echo "pong"
		exit 0
	elif [[ "$INPUT" =~ ^/usage ]]; then
		echo "tokens: $(get_usage)"
	elif [[ "$INPUT" =~ ^/load ]]; then
		if [[ "$INPUT" =~ ^/load[[:space:]]+(.+) ]]; then
			filename="${BASH_REMATCH[1]}"
			content=$(cat "$filename" 2>&1)
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
	else
		chat_completion "$INPUT"
	fi
}

if [[ $# -ne 0 ]]; then
	evaluate_input "$*"
fi

while read -r -e -p "$(timestamp) $(get_usage)> " USER_INPUT; do
    echo ""
    evaluate_input "$USER_INPUT"
done
