#!/usr/bin/env bash

# while out=$(gum input); do
#     if [[ "$out" == "/exit" ]]; then
# 		exit 0
#     fi
# 	gum style --border="normal" --foreground="white" --align="center" --padding="0 1" --margin="0 0" --width="50" "$out"
# 	curl -s -N http://127.0.0.1:8080/completion \
# 	  -H "Content-Type: application/json" \
# 	  -d "{\"prompt\": \"$out\", \"stream\": true}" \
# 	  | stdbuf -oL sed 's/^data: // ' \
# 	  | jq -j '.content // empty'
# done

out="Say hello to Pipi!"
curl -s -N http://127.0.0.1:8080/completion \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"$out\", \"stream\": true}" \
  # | stdbuf -oL sed 's/^data: // ' \
  # | jq -j '.content // empty'
