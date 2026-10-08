# AGENTS.md

Instructions for coding agents (Codex, Claude Code) working in this repository.
Keep this file short and factual. Codex stops reading project instructions after 32 KiB combined.

## Project

<one or two sentences: what this repo is and who uses it>

## Setup and commands

- Install: `<command>`
- Run tests: `<command>`
- Lint / format check: `<command>`
- Run a single test: `<command>`

All of these must pass before work is considered done.

## Conventions

- Language and version: <e.g. Python 3.12>
- Style: <formatter and linter, line length, naming>
- Layout: <where source, tests, and scripts live>
- Prefer small, focused changes. Do not refactor code that is not part of the task.

## Boundaries

- Do not modify: <generated files, vendored code, migrations already applied, CI config unless asked>
- Do not read or print: `.env*`, credentials, key files, and any data folders listed here: <paths>
- Do not add dependencies unless the task says so.
- Do not touch production systems or real data. Use fixtures or sample data.

## Rules for delegated work

- A delegated task arrives as a brief file under `.ai/`. Follow its allowed-files list exactly.
- Do not change existing tests or acceptance commands unless the brief lists them as allowed.
- Do not run state-changing git commands (add, commit, checkout, reset, stash, clean, push). Read-only git is fine.
- Finish with a short report: files changed, commands run with exit codes, anything uncertain or skipped.
