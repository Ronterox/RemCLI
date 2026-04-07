#!/usr/bin/env bash

while true; do
    out=$(gum input)
    if [[ "$out" == "exit" ]]; then
	exit 0
    fi
done
