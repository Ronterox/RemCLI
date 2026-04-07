# RemCLI

A terminal-based AI chat frontend built on top of [opencode](https://opencode.ai) and [gum](https://github.com/charmbracelet/gum).

The project uses **git worktrees** to compare two AI coding agents side-by-side: each agent was given the same prompt and asked to implement a CLI chat interface. The resulting implementations live on separate branches and can be run independently.

## Branch layout

| Branch | Agent | Description |
|--------|-------|-------------|
| `master` | — | Base template / starting point |
| `claude` | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Claude's implementation |
| `opencode` | [opencode](https://opencode.ai) | opencode's implementation |

Each branch contains a single entry point: `rem.sh`.

## Features

Both implementations provide:

- Interactive REPL powered by `gum input`
- Multi-turn conversation (session tracking)
- Streaming tool-use indicators (read, bash, write, edit, glob, grep)
- Reasoning/thinking display
- Token and cost stats
- Model switching (`/model`)
- Session clearing (`/clear`)
- Markdown rendering via `glow`

## Dependencies

- [opencode](https://opencode.ai) — the AI backend (`opencode run`)
- [gum](https://github.com/charmbracelet/gum) — terminal UI primitives
- [jq](https://jqlang.github.io/jq/) — JSON parsing
- [glow](https://github.com/charmbracelet/glow) — Markdown rendering (optional, falls back to plain text)

## Usage

### Running an implementation

```bash
# From the project root (bare repo), cd into a worktree:
cd claude    && bash rem.sh
cd opencode  && bash rem.sh
```

### Commands (inside the REPL)

```
/clear    Reset the conversation
/model    Switch the model (e.g. anthropic/claude-sonnet-4-20250514)
/quit     Exit
```

## Repository structure

This is a **bare git repository** with linked worktrees:

```
RemCLI/               ← bare repo (.git)
├── master/           ← worktree for master branch
│   └── rem.sh
├── claude/           ← worktree for claude branch
│   └── rem.sh
└── opencode/         ← worktree for opencode branch
    └── rem.sh
```

## Why

RemCLI is a practical benchmark: the same task given to two different AI coding agents, with results checked into separate branches. The goal is to compare implementation quality, style, and approach — not just the final output, but the commit history, structure, and trade-offs each agent makes.
