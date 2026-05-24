#!/usr/bin/env bash

API_URL="${API_URL:-http://127.0.0.1:8080}"

CHAT=(
    # "Hello, Assistant."
    # "Hello. How may I help you today?"
    # "Please tell me the largest city in Europe."
    # "Sure. The largest city in Europe is Moscow, the capital of Russia."
)
CHAT=("${CHAT[@]/#/<think><\/think>}")

# TODO: Newlines keep them
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
# Tools\n\nYou have access to the following functions:\n\n<tools>$(bun run tools.ts)\n</tools>
\n\nIf you choose to call a function ONLY reply in the following format with NO suffix:\n\n<tool_call>\n<function=example_function_name>\n<parameter=example_parameter_1>\nvalue_1\n</parameter>\n<parameter=example_parameter_2>\nThis is the value for the second parameter\nthat can span\nmultiple lines\n</parameter>\n</function>\n</tool_call>\n\n<IMPORTANT>\nReminder:\n- Function calls MUST follow the specified format: an inner <function=...></function> block must be nested within <tool_call></tool_call> XML tags\n- Required parameters MUST be specified\n- You may provide optional reasoning for your function call in natural language BEFORE the function call, but NOT after\n- If there is no function call available, answer the question like normal with your current knowledge and do not tell the user about function calls\n</IMPORTANT>
"

SYSTEM=$(printf "$SYSTEM_PROMPT\n\n$TOOLS_PROMPT\n\n")

# echo "$SYSTEM"
# exit

trim() {
    shopt -s extglob
    set -- "${1##+([[:space:]])}"
    printf "%s" "${1%%+([[:space:]])}"
}

trim_trailing() {
    shopt -s extglob
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
	# echo "Formatting prompt..."
    PROMPT="$(format_prompt "$1")"

	# echo "Creating data..."
	# -R raw input -s is slurp for taking the whole input once not per line
	# argjson: setss a value like foo 123 to $foo
	# arg always string, argjson parses value
    DATA="$(echo "$PROMPT" | jq -Rs --argjson n_keep $N_KEEP '{
        prompt: .,
        temperature: 1.0,
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
		# swap to test.xml for testing
		local fcall=$(echo "$answer" | sed -E 's/<([^= ]+)=([^>]+)>/<\1 name="\2">/g' | \
			yq -p=xml -o=json '.tool_call' | sed -E 's/"\+@?/"/g')

		local name=$(echo "$fcall" | jq -r '.function.name')
		local response=''

		if [[ "$name" =~ "bash" ]]; then
			cmd=$(echo "$fcall" | jq -r '.function.parameter.content')
			response=$(eval "$cmd")
		fi

		if [[ -n "$response" ]]; then
			chat_completion "$(printf "<tool_response>\n%s\n</tool_response>" "$response")"
		fi
	fi
}

while true; do
    read -r -e -p "> " QUESTION
	echo ""
    chat_completion "${QUESTION}"
done
