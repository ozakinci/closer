# closer

A close-out protocol for coding agents. One command turns "I'm done for today" into a project that a
different agent, in a different harness, can pick up tomorrow without asking what happened.

The problem every session has: context dies when the session ends, and the reasoning, the state of the
work and the "what is next" live in a chat nobody will read again. `closer` makes the agent write that
down where it belongs, and verifies the mechanical half so it cannot be skipped.

## The three tests

A close is done only when all three pass:

1. **Documented** — everything discussed, decided, asked for and implemented is where a fresh agent
   looks: the project `AGENTS.md`, the global `AGENTS.md` when the rule is global, the registers
   (tickets, bugs, decisions), the session log, the `README`, the testing record. A decision that
   exists only in the chat is not documented.
2. **Closed** — no agent is working here and nothing is in flight: no background jobs, no dev server or
   watcher left running, no git lock files, no other session still writing to the project.
3. **Committed and pushed** — every repository the session touched is clean, has an upstream, `HEAD`
   equals `@{u}`, and carries no stash or unpushed local branch.

## What is in the box

| File | What it is |
|---|---|
| `SKILL.md` | The protocol: freeze, document, commit, push, hand over — plus a failure table and a "use this elsewhere" section. |
| `close-check.ps1` | A read-only verifier: dirty/behind/ahead repos, stashes, git locks, other sessions writing to the project, processes still touching it. It changes nothing and exits with the number of failures. |

## Install

Most harnesses, one command — the same layout is understood by Claude Code, Codex, Cursor, OpenCode,
Gemini CLI, GitHub Copilot and others:

```bash
npx skills add ozakinci/closer
```

By hand:

| Harness | Copy this folder to |
|---|---|
| Claude Code | `~/.claude/skills/closer/` |
| OpenCode | `~/.config/opencode/skills/closer/` |
| Codex, Cursor, Zed, Cline, … (`.agents` convention) | `~/.agents/skills/closer/` |
| DeepSeek Harness | `~/.dsh/skills/closer/` |
| any harness, project-scoped | `.agents/skills/closer/` inside the project |

A harness with no skills at all: paste `SKILL.md` into its global instruction file under
`## Closing a project`.

## Use

- DeepSeek Harness, Claude Code: `/closer`
- anywhere else: "close the project", "closer", "close it out", "hand off"

The agent runs the verifier, fixes every failure, writes the records, commits, pushes, and prints a
close report. It will not say `CLOSED` while a check fails.

## Requirements

- `git`
- PowerShell 7 (`pwsh`) for the verifier — Windows, macOS or Linux
- Optional: a `## Closing` block in the project's `AGENTS.md`. If it is missing, the first close writes
  one from what the session learned.

## Honest limits

- *"No other session is running"* cannot be proven from disk — an idle open tab looks exactly like a
  closed one. The verifier proves quiescence and asks the user to confirm; the report keeps a
  `Still open:` line instead of pretending.
- The process scan uses WMI/CIM and reports an INFO line where the platform denies it.
- *"Documented"* is semantic. The seven questions are the contract; a script cannot judge prose.

## Tested with

DeepSeek Harness end to end, and a cold read by `opencode` running a free GLM model from the repository
alone — it correctly named the project, its gate, the last session and the next step.

## License

MIT.
