#!/usr/bin/env bash

API_URL="${API_URL:-http://127.0.0.1:8080/v1/chat/completions}"

# Modern OpenAI-style messages history
MESSAGES_JSON='[{"role": "system", "content": "You are a helpful assistant with tool access."}]'

# Tool definition (OpenAI standard)
TOOLS='[
  {
    "type": "function",
    "function": {
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
  }
]'

# Tool Implementation
fetch_webpage() {
    local URL="$1"
    echo "  [Executing: curl -sL $URL]" >&2
    curl -sL "$URL" | head -c 2000 | sed 's/[<>&]/ /g'
}

chat_completion() {
    USER_QUERY="$1"
    MESSAGES_JSON=$(echo "$MESSAGES_JSON" | jq --arg content "$USER_QUERY" '. += [{"role": "user", "content": $content}]')

    # 1. Ask the model (we disable streaming for the tool-check turn for simplicity)
    DATA=$(jq -n --argjson messages "$MESSAGES_JSON" --argjson tools "$TOOLS" '{
        messages: $messages,
        tools: $tools,
        tool_choice: "auto",
        temperature: 0.1
    }')

    RESPONSE=$(curl -s -X POST "${API_URL}" -H "Content-Type: application/json" -d "$DATA")
    
    # Check if the model wants to call a tool
    TOOL_CALLS=$(echo "$RESPONSE" | jq -c '.choices[0].message.tool_calls // empty')

    if [ -n "$TOOL_CALLS" ]; then
        echo "Assistant wants to use tools..."
        
        # Save the assistant's tool-call message to history
        ASSISTANT_MSG=$(echo "$RESPONSE" | jq -c '.choices[0].message')
        MESSAGES_JSON=$(echo "$MESSAGES_JSON" | jq --argjson msg "$ASSISTANT_MSG" '. += [$msg]')

        # Process each tool call
        echo "$TOOL_CALLS" | jq -c '.[]' | while read -r CALL; do
            CALL_ID=$(echo "$CALL" | jq -r '.id')
            FUNC_NAME=$(echo "$CALL" | jq -r '.function.name')
            ARGS=$(echo "$CALL" | jq -r '.function.arguments')
            
            if [ "$FUNC_NAME" == "fetch_webpage" ]; then
                URL=$(echo "$ARGS" | jq -r '.url')
                RESULT=$(fetch_webpage "$URL")
                
                # Add tool response to history
                # IMPORTANT: 'tool_call_id' is required in OpenAI format
                MESSAGES_JSON=$(echo "$MESSAGES_JSON" | jq --arg id "$CALL_ID" --arg name "$FUNC_NAME" --arg content "$RESULT" \
                    '. += [{"role": "tool", "tool_call_id": $id, "name": $name, "content": $content}]')
                
                # After adding tool results, we need to call the API again to get the final answer
                FINAL_DATA=$(jq -n --argjson messages "$MESSAGES_JSON" '{messages: $messages, temperature: 0.7, stream: true}')
                
                echo -n "Assistant: "
                FINAL_ANSWER=""
                while IFS= read -r LINE; do
                    if [[ $LINE = data:* && $LINE != "data: [DONE]" ]]; then
                        CONTENT=$(echo "${LINE:5}" | jq -r '.choices[0].delta.content // empty')
                        printf "%s" "$CONTENT"
                        FINAL_ANSWER+="$CONTENT"
                    fi
                done < <(curl --silent --no-buffer -X POST "${API_URL}" -H "Content-Type: application/json" -d "$FINAL_DATA")
                printf "\n"
                
                # Save final answer to global variable (hacky because of the while pipe, but works for demo)
                # In a real script, we'd avoid the pipe or use a file/variable update logic.
                echo "MESSAGES_JSON_UPDATE|$(echo "$MESSAGES_JSON" | jq -c --arg content "$FINAL_ANSWER" '. += [{"role": "assistant", "content": $content}]')" > /tmp/msg_sync
            fi
        done
        # Sync back the JSON from the subshell
        if [ -f /tmp/msg_sync ]; then
            MESSAGES_JSON=$(cat /tmp/msg_sync | cut -d'|' -f2)
            rm /tmp/msg_sync
        fi
    else
        # Normal response
        CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
        printf "Assistant: %s\n" "$CONTENT"
        MESSAGES_JSON=$(echo "$MESSAGES_JSON" | jq --arg content "$CONTENT" '. += [{"role": "assistant", "content": $content}]')
    fi
}

echo "--- Generic OpenAI-API Tool Use (/v1/chat/completions) ---"

while true; do
    read -r -e -p "User: " QUESTION
    if [ -z "$QUESTION" ]; then continue; fi
    chat_completion "$QUESTION"
done
