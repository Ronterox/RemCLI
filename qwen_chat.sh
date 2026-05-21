#!/usr/bin/env bash

API_URL="${API_URL:-http://127.0.0.1:8080}"

# Configuration for Qwen/ChatML
INSTRUCTION="You are a helpful assistant. If the task is complex, use reasoning."
THINKING_MODE=true # Set to true to encourage the model to think

CHAT=(
    "Hello, Assistant."
    "Hello! I am your AI assistant, powered by Qwen. How can I help you today?"
)

trim() {
    shopt -s extglob
    set -- "${1##+([[:space:]])}"
    printf "%s" "${1%%+([[:space:]])}"
}

trim_trailing() {
    shopt -s extglob
    printf "%s" "${1%%+([[:space:]])}"
}

# ChatML Formatting
format_prompt() {
    # System message
    printf "<|im_start|>system\n%s<|im_end|>" "${INSTRUCTION}"

    # History
    # Note: CHAT array contains [User1, Assistant1, User2, Assistant2, ...]
    for (( i=0; i<${#CHAT[@]}; i+=2 )); do
        printf "\n<|im_start|>user\n%s<|im_end|>" "${CHAT[i]}"
        printf "\n<|im_start|>assistant\n%s<|im_end|>" "${CHAT[i+1]}"
    done

    # Current User Question
    printf "\n<|im_start|>user\n%s<|im_end|>" "$1"

    # Assistant Start
    printf "\n<|im_start|>assistant\n"

    # Encourage thinking if enabled
    if [ "$THINKING_MODE" = true ]; then
        printf "<think>\n"
    fi
}

tokenize() {
    curl \
        --silent \
        --request POST \
        --url "${API_URL}/tokenize" \
        --header "Content-Type: application/json" \
        --data-raw "$(jq -ns --arg content "$1" '{content:$content}')" \
    | jq '.tokens[]'
}

# Calculate N_KEEP for the system prompt
N_KEEP=$(tokenize "<|im_start|>system\n${INSTRUCTION}<|im_end|>" | wc -l)

chat_completion() {
    PROMPT="$(trim_trailing "$(format_prompt "$1")")"

    # Qwen uses <|im_end|> and <|im_start|> as stop sequences
    DATA="$(echo -n "$PROMPT" | jq -Rs --argjson n_keep $N_KEEP '{
        prompt: .,
        temperature: 0.8,
        top_k: 40,
        top_p: 0.95,
        min_p: 0.05,
        presence_penalty: 0.0,
        repetition_penalty: 1.0,
        n_keep: $n_keep,
        n_predict: 1024,
        cache_prompt: true,
        stop: ["<|im_end|>", "<|im_start|>user"],
        stream: true
    }')"

    ANSWER=''
    if [ "$THINKING_MODE" = true ]; then
        ANSWER='<think>\n' # We already printed this in the prompt start
    fi

    while IFS= read -r LINE; do
        if [[ $LINE = data:* ]]; then
            CONTENT="$(echo "${LINE:5}" | jq -r '.content')"
            printf "%s" "${CONTENT}"
            ANSWER+="${CONTENT}"
        fi
    done < <(curl \
        --silent \
        --no-buffer \
        --request POST \
        --url "${API_URL}/completion" \
        --header "Content-Type: application/json" \
        --data-raw "${DATA}")

    printf "\n"

    # Save to history (trimming the thinking block if you prefer, or keeping it)
    CHAT+=("$1" "$(trim "$ANSWER")")
}

echo "--- ChatML Mode for Qwen ---"
echo "Thinking Mode: ${THINKING_MODE}"
echo "----------------------------"

while true; do
    read -r -e -p "> " QUESTION
    if [ -z "$QUESTION" ]; then continue; fi
    chat_completion "${QUESTION}"
done

