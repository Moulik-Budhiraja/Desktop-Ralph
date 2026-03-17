---
name: ralph-ui-chaos
description: Use when the user wants Codex to operate the local macOS UI with the Ralph wrapper in `/Users/moulik/Documents/programming/cursor-build`, especially to perform one creative, interesting, annoying, or intentionally unrelated action on the desktop for experimentation. Apply this when the request says the project is a wrapper over OSXQuery, says the usage should match the existing `osxquery` skill, or asks for a stunt using Ralph's query/action language with funny speech bubbles on every action.
---

# Ralph UI Chaos

Use the existing `osxquery` skill as the behavioral baseline, but replace `osx` commands with this repo's Ralph CLI.

## Required Inputs

- Treat `/Users/moulik/.agents/skills/osxquery/SKILL.md` as required reading for workflow discipline.
- Read the two required references from that skill before running Ralph commands:
  - `/Users/moulik/.agents/skills/osxquery/references/osxquery-query-usage.md`
  - `/Users/moulik/.agents/skills/osxquery/references/osxquery-actions-usage.md`

## Ralph CLI Location

- The project root is `/Users/moulik/Documents/programming/cursor-build`.
- The executable product is `ralph`, not `osx`.
- Run it from the repo root with `swift run ralph ...`.
- Do not assume a globally installed binary. Prefer the local project executable.

## Command Translation

- Translate `osx query ...` to `swift run ralph query ...`
- Translate `osx action ...` to `swift run ralph action ...`
- Keep the same selector language, cache-session flow, and action language described by the `osxquery` references.

## Mandatory Workflow

1. Read the `osxquery` skill and both required reference files first.
2. Take a screenshot before the first action in a view, and after each meaningful state change, using `screencapture`.
3. Inspect the UI with `swift run ralph query --app ...`.
4. Warm refs with `--cache-session` before each action phase.
5. Include `--bubble-text "<Ralph sentence>"` on every query that prepares for an action.
6. Execute the action with `swift run ralph action '...'`.
7. After any UI-changing action, re-query with `--cache-session` before the next action.
8. Verify the result with both a fresh query and a screenshot before continuing.

## Task To Perform

- Perform exactly one creative and interesting UI task.
- Prefer a task that is harmless but annoying, unrelated, or slightly mischievous.
- Good examples:
  - Open an app and type an unsolicited note.
  - Use the current editor or terminal to inject an unrelated prompt or command.
  - Click through to enable or set up something unnecessary.
- Do not stop at analysis. Actually perform the UI task with Ralph.

## Bubble Text Rule

- Every action cycle needs a funny comment.
- Always write bubble text in third person.
- Always start every sentence with `Ralph`.
- Format Ralph's sentences as `Ralph <verb> <subject>`.
- Do not use first-person phrasing like `I am...` or `I'm...`.
- If multiple sentences are needed, each sentence must start with `Ralph`.
- Prefer short, absurd lines such as `Ralph is escalating whimsy.` or `Ralph deploys unsolicited productivity.`
- The supported mechanism in this project is `--bubble-text` on `ralph query`.
- Example:

```bash
cd /Users/moulik/Documents/programming/cursor-build
swift run ralph query --app focused 'AXButton[CPName="New Document"]' --cache-session --bubble-text 'Ralph deploys maximum inconvenience.'
swift run ralph action 'send click to abc123def;'
```

## Verification Rule

- If the screenshot does not clearly show the intended target or outcome, stop and re-query.
- If refs go stale, re-run the query and use the new ref ids.
- Do not chain multiple blind actions without verification between them.

## Output Expectations

- Tell the user what task was chosen.
- Mention that Ralph was run from `/Users/moulik/Documents/programming/cursor-build` via `swift run ralph`.
- Summarize the actions performed and what changed on screen.
