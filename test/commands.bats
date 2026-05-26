#!/usr/bin/env bats

setup() {
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	PATH=$PATH:.
}

@test "/ping: sanity check" {
	run chat.sh <<-EOF
	/ping
	/exit
	EOF
	assert_output --partial "pong"
	assert_output --partial "Exiting..."
}

@test "/checkhealth: llama server health" {
	run chat.sh <<-EOF
	/checkhealth
	/exit
	EOF
	assert_output --partial "ok"
	assert_output --partial "Exiting..."
}

@test "/usage: tokens" {
	run chat.sh <<-EOF
	/usage
	/exit
	EOF
	assert_output --regexp "tokens: [0-9]+/[0-9]+ \([0-9]+%\)"
	assert_output --partial "Exiting..."
}

@test "/load: load a file as context" {
	run timeout 4 chat.sh <<-EOF
	/load benchmark/joke
	/exit
	EOF
	assert_output --partial "$(cat benchmark/joke)"
	assert_output --partial "</think>"
	assert_output --partial "Exiting..."
}

@test "/ask: run command and exit get response" {
	run timeout 2 chat.sh "/ask hi."
	assert_output --partial "> Full output at:"
	refute_output --partial "</think>"
}
