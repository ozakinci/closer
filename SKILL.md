---
name: closer
description: Close out a project session — verify nothing is still running, write the documentation a fresh agent needs, commit and push every repository, and hand over cleanly. Use when the user says "close the project", "closer", "close it out", "hand off" or "wrap up".
---

# Closer

Close the project so that **a different agent, in a different harness, with only the repository**,
can continue the work without asking anyone what happened.

## The three tests

A close is done only when all three pass. Name the one that failed; never round up.

1. **Documented** — everything discussed, decided, asked for and implemented this session lives
   where a fresh agent looks: the project `AGENTS.md`, the global `AGENTS.md` when the rule is
   global, the registers (tickets, bugs, decisions), the session log, the `README`, the testing
   record. **A decision that exists only in this chat is not documented.**
2. **Closed** — no agent is working here and nothing is in flight: no background jobs in this
   session, no dev server, watcher or test run that outlived it, no git lock files, no other chat
   still writing to this project's session store.
3. **Committed and pushed** — every repository the session changed is clean, has an upstream,
   `HEAD` equals `@{u}`, and carries no stash or unpushed local branch.

**The honest limit:** "no other session is running" cannot be proven from disk — the harness keeps
every session file open, and an idle open tab looks exactly like a closed one. What you can prove
is *quiescence*: nothing wrote to this project while the close was running. So run the check, ask
the user to confirm the other tabs are closed, and keep the `Still open:` line in the report. The
last item is always the user's: closing this chat.

## Before you touch anything

Read the project `AGENTS.md` and the record map it points at. If it has a `## Closing` section, that
section wins for the repository list, the gate command and where the records live. Never close from
memory.

If there is no `## Closing` section, write one now from what this close teaches you: repositories and
remotes, the gate command, where the records live, what "nothing flying" means here, and how commits
are tagged. Commit it with the close, so the next close is cheap and nobody has to remember this.

## Step 1 — Freeze

- `job_list`: no running jobs. Wait for, or stop, anything in flight.
- Run the verifier: `pwsh -File <this skill folder>/close-check.ps1 -ProjectRoot <project>`
  (`-SessionId` if `DSH_SESSION_ID` is not set). Fix every FAIL and read every WARN out loud.
- Ask once: "close any other chat, terminal or server working on this project, then tell me to
  continue." Re-run the verifier afterwards — anything that changed in between was still flying.

## Step 2 — Document

Answer these seven questions **in the repository**, each in the record that already owns it. If the
project has no such record yet, create the minimum and say so in the log entry.

| # | Question the next agent will ask | Where it goes |
|---|---|---|
| 1 | What is this, and how do I run and verify it? | `AGENTS.md` / `README` |
| 2 | What changed last session, and why? | session-log entry + `Why:` in commit bodies |
| 3 | What is done, what is open? | tickets / bugs / roadmap registers |
| 4 | What was decided, and what was rejected? | ADR with `## Rejected` (five lines is enough) |
| 5 | What is unverified? | testing record — the words "not run", never "works" |
| 6 | What must I not break? | non-negotiables in the project `AGENTS.md` |
| 7 | Where do I write the next record? | stated in the log entry |

Rules:

- **One record per question.** If the project already indexes its records (a `docs/standards.md`
  records table, a `project/agent-log.md`), use that map — never add a second rulebook, log or
  ticket list.
- **Promote what is global.** A rule for every project goes to the global `AGENTS.md`; a rule for
  this project goes to its own `AGENTS.md`. Both at once is almost always wrong.
- **Date the entry and say where you stopped.** The next session starts by reading it.
- **Fix stale documentation now:** links that no longer resolve, counts that no longer match
  ("23 tickets" after adding the 24th), behaviour the `README` still claims.

## Step 3 — Commit

- Run the project's gate (typecheck / tests / build / lint — whatever its `AGENTS.md` or
  `package.json` names as the gate) **after the last content change**. A gate that passed before
  the docs were written proves nothing.
- Subject: the project's own convention — typically `<ID>: <imperative>` when it uses ids. Detect it
  from `commit-msg` hooks or `AGENTS.md`; never invent ids.
- Body:

  ```
  Why: <the problem or constraint this solves — not a restatement of the diff>

  What: <what changed>
  Checked: <gate, tests, real runs — with the result>
  Not run: <paths that could not be exercised, or "none">
  ```

- One logical change per commit. The documentation for a change belongs in that change's commit.

## Step 4 — Push

- `git fetch`, then if behind `git pull --rebase`, re-run the gate, push.
- Push **every** repository the session touched, including siblings the project declares (a
  separate tester repo, a submodule). A clean repo that was never pushed is not closed.
- Verify, do not assume: `git status -sb` shows no ahead/behind, `git rev-parse HEAD` equals
  `git rev-parse @{u}`, and the tree is clean.
- Never force-push as part of a close. If the push is rejected: fetch, reconcile, re-run the gate,
  push again — or stop and report.

## Step 5 — Global documentation

If this session changed anything harness-global — the global `AGENTS.md`, a skill, the plugin list —
and this machine keeps those in a git repository, commit and push it. Then confirm the copies match:
a config repository that snapshots them must hold an `AGENTS.md` byte-identical to the live one.
Drift there silently loses the lesson you just learned.

## Step 6 — Hand over

1. Re-run the verifier until it prints `VERDICT: READY`.
2. Record the pushed SHA in the session-log entry — the substantive commit only. The entry's own commit
   cannot contain its own hash, so write "+ the commit that carries this line" and stop there; never
   re-run the close to capture the follow-up hash.
3. Print this report — the only thing the user needs to read:

```
CLOSED <project> — <date>
Repos     : <name> <branch> @ <sha> -> <remote> (clean, up to date)
Docs      : <files created or updated>
Global    : <config repo pushed, or "unchanged">
Unverified: <what was not run, or "none">
Next      : <the first action for the next session>
Still open: <open tickets/bugs> + this chat
```

## Hard rules

- Never print `CLOSED` while a verifier check fails, a repository is unpushed, or a question from
  Step 2 has no record.
- Never write "works" for something that was not run.
- Never leave the only copy of a decision in the chat, a stash or an uncommitted file.
- If something cannot be closed — no remote, protected branch, no repository, a gate you cannot fix —
  say exactly that under `Still open:`. A declared gap is closed; a silent one is not.

## Using this file in another harness

This protocol needs nothing from DSH. It is published as an Agent Skill, so most harnesses can install
it in one command:

```bash
npx skills add ozakinci/closer
```

Or without tooling:

- **A harness with skills:** copy this folder to `~/.claude/skills/closer/`, `~/.agents/skills/closer/`
  or that harness's skills directory. Same frontmatter, same body, same script.
- **A harness with only an instruction file:** paste this body into its global instructions
  (`~/.claude/CLAUDE.md`, the Codex `AGENTS.md`, the Cursor rules file) under the heading
  `## Closing a project`, and keep the trigger sentence in the description.
- **No skills, no global file:** give the agent this file's path — it is self-contained; only the
  session and process checks degrade gracefully.

## Failure modes

| Situation | What to do |
|---|---|
| Project is not a git repository | Say so; offer `git init` and a remote. Until then "committed" and "pushed" are declared gaps, not done. |
| Repository has no remote | WARN: local-only. Record it in `## Closing` and in the report; do not call it pushed. |
| Push rejected / non-fast-forward | `git fetch` → `git pull --rebase` → gate → push. Never force. Conflict → stop, leave it, report. |
| Interrupted rebase or merge, or a `.lock` file | Do not delete locks to "unstick" it. Report the state; let the user decide. |
| Gate fails | Fix it, or record it as unverified with the exact failing command — never commit red silently. |
| Another session is writing | Stop. Name the session and the timestamp. Wait for the user. |
| Dirty submodule or LFS pointers | Report; do not commit the parent repository around it. |
| Nothing was implemented this session | Still write a short entry: what was discussed, what was decided, what is next. The next session pays for that knowledge either way. |
