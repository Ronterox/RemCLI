#!/usr/bin/env bats

setup() {
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	PATH=$PATH:.
}

@test "Sanity check ping pong" {
	run chat.sh <<-EOF
	/ping
	EOF
	assert_output --partial "pong"
}

@test "Sanity check llama server health" {
	run chat.sh <<-EOF
	/checkhealth
	EOF
	assert_output --partial "ok!"
}
