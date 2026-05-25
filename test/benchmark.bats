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
	assert_output --partial "<function=bash>"
	assert_output --partial "Exiting..."
}

@test "Can read files" {
	run chat.sh <<-EOF
	Find the file called joke, read it, and tell me what it says exactly
	/exit
	EOF
	assert_output --partial "$(cat benchmark/joke)"
	assert_output --partial "<function=read>"
	assert_output --partial "Exiting..."
}

@test "Can run subagents" {
	run chat.sh <<-EOF
	List your tools
	Call a subagent and tell it to run pwd
	/exit
	EOF
	assert_output --partial "$(pwd)"
	assert_output --partial "<function=subagent>"
	assert_output --partial "Exiting..."
}
