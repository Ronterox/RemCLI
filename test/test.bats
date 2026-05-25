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
