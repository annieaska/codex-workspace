# Workspace Instructions

## Default execution

- Treat the current user request and repository state as the source of truth.
- Prefer small, reviewable changes that preserve the existing architecture.
- When the goal, boundaries, and acceptance criteria are clear and the action is low risk, execute directly.
- For non-trivial work, state a short plan before editing. Ask only when a missing decision would materially change scope, cost, risk, or direction.
- Do not invent APIs, configuration keys, paths, or repository state. Inspect first.
- A request to explain, diagnose, review, or design does not authorize implementation or publication.

## Safety and quality

- Never expose or commit secrets, credentials, private data, local account details, or machine-specific configuration.
- Preserve unrelated user changes in a dirty worktree.
- Use explicit error handling and type-safe interfaces where the project supports them.
- Validate in proportion to the changed behavior and demonstrated risk. Prefer the smallest relevant check over an automatic full test suite.
- Reuse valid evidence; independent review does not automatically require rerunning tests. Expand validation only when changed behavior or concrete risk warrants it.
- Documentation-only Git pushes require content and remote commit verification, not service smoke tests. Actual deployment checks should follow the affected service and risks.
- Stop when the requested behavior is verified and all in-scope failures introduced or discovered by the change are closed.

## Active context

- Keep one active working set per task: goal and acceptance criteria, explicit exclusions, constraints and authorization, confirmed decisions, current gate, required paths or versions, latest verification, risks, and next action.
- Keep resolved history, complete logs, old outputs, and unused references outside the active context. Retain their paths so they can be reopened if needed.
- Search narrowly before reading broadly. Read relevant sections rather than entire repositories or long documents.
- Filter, summarize, or persist large tool output before returning only the evidence required for the current decision.
- Use summaries as navigation; inspect source passages before edits and consequential decisions. Apply the question-driven reading guidance in `docs/context-and-memory.md` when needed.
- Default to one agent. Delegate only with explicit user authorization or an applicable instruction for a bounded independent task; do not automatically switch models.
- For batch or media-heavy work, fix the current batch, inputs, dependencies, and acceptance criteria before processing it.
- Before compaction or handoff, write an incremental anchor containing only durable state. On resume, read the anchor first and retrieve supporting evidence only as needed.

## Project state

- Use an existing `PROJECT.md` as the single state source for a long-running project. Do not create a parallel context or status file.
- Record the current delivery cycle, confirmed decisions, gate, latest verification, active risks, and next action.
- Do not create a project state file for a short, self-contained task.

## Memory and skills

- Do not preload long-term memory for every task. Query it only when the user asks for recall or a necessary historical fact is missing.
- Treat memory as a historical lead, not as authority. Verify recalled claims against the current workspace and include their source.
- Bound memory results by count and size; reject stale, duplicate, unrelated, or sensitive material.
- Discover specialized skills only when the task needs them. Load the single relevant instruction set and only its required resources.
- Keep personal skills, skill inventories, installation paths, and private plugin settings out of public repositories.

## Handoff

- A handoff must preserve the goal, acceptance criteria, exclusions, authorization, decisions, exact identifiers, active errors, reusable verification, risks, and next action.
- Do not repeat unchanged validation or reload unchanged evidence after a handoff.
