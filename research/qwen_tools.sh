#!/usr/bin/env bash

API_URL="${API_URL:-http://127.0.0.1:8080}"

# Highly aggressive system prompt with a few-shot example for the 0.8B model
INSTRUCTION="You are a pro-active Agent. When a user provides a URL, you MUST ALWAYS use the fetch_webpage tool.
Do not explain your tools. Just use them.

# Example:
User: Summarize http://example.com
Assistant: <think>
The user wants a summary of example.com. I will fetch the content first.
</think>
<tool_call>
<function=fetch_webpage>
<parameter=url>
http://example.com
</parameter>
</function>
</tool_call>"

# Tool definition
TOOLS_DEFINITION='[
  {
    "name": "fetch_webpage",
    "description": "Fetches the content of a webpage using curl",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL of the webpage to fetch"
        }
      },
      "required": ["url"]
    }
  }
]'

CHAT=()

fetch_webpage() {
    local URL="$1"
    echo "  [Executing: curl -sL $URL]" >&2
    curl -sL "$URL" | head -c 2000 | sed 's/[<>&]/ /g'
}

format_prompt() {
    printf "<|im_start|>system\n%s\n\n# Tools available:\n%s<|im_end|>" "$INSTRUCTION" "$TOOLS_DEFINITION"

    for (( i=0; i<${#CHAT[@]}; i+=2 )); do
        printf "\n<|im_start|>user\n%s<|im_end|>" "${CHAT[i]}"
        printf "\n<|im_start|>assistant\n%s<|im_end|>" "${CHAT[i+1]}"
    done

    printf "\n<|im_start|>user\n%s<|im_end|>" "$1"

    # We stop pre-filling <think> to let the model decide if it needs to think or call tool directly
    # as 0.8B can get confused by the forced state.
    printf "\n<|im_start|>assistant\n"
}

chat_completion() {
    local QUESTION="$1"
    local PROMPT="$(format_prompt "$QUESTION")"

    # Request completion
    DATA="$(echo -n "$PROMPT" | jq -Rs '{
        prompt: .,
        temperature: 0.0,
        stop: ["<|im_end|>", "<|im_start|>user", "</tool_call>"],
        stream: false
    }')"

    RESPONSE=$(curl -s -X POST "${API_URL}/completion" -H "Content-Type: application/json" -d "$DATA")
    ANSWER=$(echo "$RESPONSE" | jq -r '.content')

    # Check for Tool Call
    if [[ "$ANSWER" == *"<tool_call>"* ]]; then
        echo "Assistant: (Using Tool...)"

        # Robust extraction for the URL
        # Look for the URL inside the XML-like tags
        ARG_URL=$(echo "$ANSWER" | sed -n 's/.*<parameter=url>\(.*\)<\/parameter>.*/\1/p' | head -n 1 | tr -d '[:space:]')

        # Fallback if sed fails (happens with multi-line output)
        if [ -z "$ARG_URL" ]; then
            ARG_URL=$(echo "$ANSWER" | grep -A 1 "<parameter=url>" | tail -n 1 | tr -d '[:space:]')
        fi

        if [ -n "$ARG_URL" ]; then
            TOOL_RESULT=$(fetch_webpage "$ARG_URL")

            # Construct the continuation prompt
            # We append </tool_call> because it was a stop token
            NEW_PROMPT="${PROMPT}${ANSWER}</tool_call>\n<tool_response>\n${TOOL_RESULT}\n</tool_response>\n<|im_start|>assistant\n"

            DATA_CONT="$(echo -n "$NEW_PROMPT" | jq -Rs '{prompt: ., temperature: 0.7, stop: ["<|im_end|>"], stream: true}')"

            echo -n "Assistant: "
            FINAL_ANSWER=""
            while IFS= read -r LINE; do
                if [[ $LINE = data:* ]]; then
                    CONTENT="$(echo "${LINE:5}" | jq -r '.content')"
                    printf "%s" "${CONTENT}"
                    FINAL_ANSWER+="${CONTENT}"
                fi
            done < <(curl --silent --no-buffer -X POST "${API_URL}/completion" -H "Content-Type: application/json" -d "$DATA_CONT")
            printf "\n"
            CHAT+=("$QUESTION" "${ANSWER}</tool_call>\n[Tool Output]\n${FINAL_ANSWER}")
        else
            echo "Assistant: (Failed to parse tool call) $ANSWER"
            CHAT+=("$QUESTION" "$ANSWER")
        fi
    else
        printf "Assistant: %s\n" "$ANSWER"
        CHAT+=("$QUESTION" "$ANSWER")
    fi
}

echo "--- Qwen Tool Use Script (Refined) ---"
while true; do
    read -r -e -p "> " USER_INPUT
    if [ -z "$USER_INPUT" ]; then continue; fi
    chat_completion "$USER_INPUT"
done
