#!/usr/bin/env bash

# This version uses the OpenAI-compatible /v1/chat/completions API.
# This is the modern standard for agent CLIs as it allows the server
# to handle model-specific prompt templates (like ChatML, Llama-3, etc.)

API_URL="${API_URL:-http://127.0.0.1:8080/v1/chat/completions}"

# We store messages as a JSON array string to easily pass to jq
MESSAGES_JSON='[{"role": "system", "content": "You are a helpful assistant."}]'

chat_completion() {
    USER_QUERY="$1"

    # Append the user message to our JSON array
    MESSAGES_JSON=$(echo "$MESSAGES_JSON" | jq --arg content "$USER_QUERY" '. += [{"role": "user", "content": $content}]')

    # Prepare the payload
    # Note: We can add "include_reasoning": true if the server supports it,
    # or just let it come through the 'content' if the model outputs tags.
    DATA=$(jq -n --argjson messages "$MESSAGES_JSON" '{
        messages: $messages,
        temperature: 0.8,
        stream: true
    }')

    ANSWER=''

    echo -n "Assistant: "

    # Stream the response
    # OpenAI format: data: {"choices": [{"delta": {"content": "..."}}]}
    while IFS= read -r LINE; do
        if [[ $LINE = data:* && $LINE != "data: [DONE]" ]]; then
            JSON_CHUNK="${LINE:5}"

            # Extract content
            CONTENT=$(echo "$JSON_CHUNK" | jq -r '.choices[0].delta.content // empty')
            if [ -n "$CONTENT" ]; then
                printf "%s" "$CONTENT"
                ANSWER+="$CONTENT"
            fi

            # Extract reasoning (thinking) if provided separately
            REASONING=$(echo "$JSON_CHUNK" | jq -r '.choices[0].delta.reasoning_content // empty')
            if [ -n "$REASONING" ]; then
                # Print reasoning in gray
                printf "\e[90m%s\e[0m" "$REASONING"
                # We don't necessarily want to save reasoning in the final answer
                # unless we want the model to see its own past thoughts.
                ANSWER+="$REASONING"
            fi
        fi
    done < <(curl \
        --silent \
        --no-buffer \
        --request POST \
        --url "${API_URL}" \
        --header "Content-Type: application/json" \
        --data-raw "$DATA")

    printf "\n"

    # Save the assistant response to history
    MESSAGES_JSON=$(echo "$MESSAGES_JSON" | jq --arg content "$ANSWER" '. += [{"role": "assistant", "content": $content}]')
}

echo "--- Modern API Mode (/v1/chat/completions) ---"

while true; do
    read -r -e -p "User: " QUESTION
    if [ -z "$QUESTION" ]; then continue; fi
    chat_completion "$QUESTION"
done
