#!/usr/bin/env bats

setup() {
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	PATH=$PATH:.
}

@test "Can run bash commands" {
	run chat.sh <<-EOF
	Run pwd and tell me on which directory are we
	/exit
	EOF
	assert_output --partial "$(pwd)"
	assert_output --partial "</think>"
	assert_output --partial "Exiting..."
}

@test "Can read files" {
	run chat.sh <<-EOF
	Find the file called joke, read it, and tell me what it says exactly
	/exit
	EOF
	assert_output --partial "$(cat benchmark/joke)"
	assert_output --partial "</think>"
	assert_output --partial "Exiting..."
}

