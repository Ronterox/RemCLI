#!/usr/bin/env bash

API_URL="${API_URL:-http://127.0.0.1:8080}"

CHAT=(
    # "Hello, Assistant."
    # "Hello. How may I help you today?"
    # "Please tell me the largest city in Europe."
    # "Sure. The largest city in Europe is Moscow, the capital of Russia."
)
CHAT=("${CHAT[@]/#/<think><\/think>}")

INSTRUCTION="A chat between a curious human and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the human's questions."

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
	printf "<|im_start|>system\n%s<|im_end|>\n" "$INSTRUCTION"
	#<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n<think>\nreasoning\n</think>\n\ncontent
	printf "<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n%s<|im_end|>\n" "${CHAT[@]}"
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

N_KEEP=$(tokenize "${INSTRUCTION}" | wc -l)

chat_completion() {
    PROMPT="$(trim_trailing "$(format_prompt "$1")")"
	# -R raw input -s is slurp for taking the whole input once not per line
	# argjson: setss a value like foo 123 to $foo
	# arg always string, argjson parses value
    DATA="$(echo -n "$PROMPT" | jq -Rs --argjson n_keep $N_KEEP '{
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
        stop: ["\n### Human:"],
        stream: true
    }')"

    ANSWER=''
	while IFS= read -r OUT; do
		ANSWER+="${OUT}"
		printf "%s" "${OUT}"
	done < <(curl \
			-X POST -Ns --url "${API_URL}/completion" \
			-H "Content-Type: application/json" --data-raw "${DATA}" \
			| jq -R -r --unbuffered 'sub("^data:";"") | fromjson? | .content')
    printf "\n"

    CHAT+=("$1" "$(trim "$ANSWER")")
}

while true; do
    read -r -e -p "> " QUESTION
    chat_completion "${QUESTION}"
done
