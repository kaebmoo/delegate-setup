---
name: delegate
description: Planner and reviewer plus coder loop. Claude plans and accepts the work; Codex CLI (codex exec) writes the code. Use only when the user explicitly types /delegate followed by a task, or /delegate resume. Never start it on your own.
compatibility: Needs a shell on the machine where Codex CLI is installed and logged in, inside a git repository (for example Claude Code on the user's Mac).
metadata:
  version: "3"
---

# /delegate : Claude plans and accepts, Codex writes the code

Start only when the user explicitly invoked /delegate, or asked in plain words to have Codex write the code with you as
planner and reviewer. If this skill was loaded for any other reason, stop and do nothing.

The task text is what the user typed after /delegate. Claude Code appends it at the end of this file as a line starting
with `ARGUMENTS:`; in other hosts take it from the user's message. If there is no task text, the task is empty.

Environment: this skill needs a shell on the machine where Codex CLI is installed and logged in. If there is no shell,
or `codex` is not installed on this machine (for example a cloud session), stop at preflight and tell the user in Thai
that /delegate must run in Claude Code on the machine that has Codex.

## Configuration (edit these values here)

```
CODEX_MODEL=                 # blank = use Codex default. Set only to a model that `codex` accepts on this account.
CODEX_EFFORT=high            # passed as --config 'model_reasoning_effort="<value>"'. blank = Codex default.
CODEX_TIMEOUT_MS=600000      # Bash tool timeout for ONE Codex run. 600000 is Claude Code's default ceiling;
                             # raise BASH_MAX_TIMEOUT_MS in settings (see settings.snippet.json) before raising this.
MAX_ROUNDS_PER_SLICE=3       # Codex attempts per slice (round 1 + fixes) before BLOCKED.
MAX_CODEX_RUNS_PER_RUN=12    # hard cap on Codex invocations for the whole /delegate run.
MAX_SLICES_WITHOUT_CONFIRM=4 # more slices than this => show the plan and wait for the user's approval.
CLAUDE_MECHANICAL_FIXES=allow   # allow | deny. See "Mechanical fixes".
```

## Roles and hard rules

- You (Claude) are the planner and the acceptor. Codex is the only author of source and test changes.
  You write only files under `.ai/`. Exception: "Mechanical fixes" below, when allowed.
- Talk to the user in Thai. Write briefs, plans, reviews in English unless the user's task or the repo is in Thai.
- Never push, merge, rebase, deploy, change a real database, or run destructive git commands
  (`reset --hard`, `clean`, `checkout -- .`, `branch -D`). Local commits on the task branch after PASS are allowed.
- Never use `--dangerously-bypass-approvals-and-sandbox`, `--yolo`, or `--sandbox danger-full-access`.
- Never use `codex exec resume`. Every round is a fresh `codex exec` with a new brief file (auditable, no hidden state).
- Never run two Codex processes at the same time, and never start a new run while a previous one may still be alive.
- Never declare PASS from Codex's own report. PASS requires your own diff review and your own run of the acceptance commands.
- Run each Bash command as its own call. Do not chain with `&&`, `||`, `;` (permission rules match each part separately,
  and a chained command prompts the user).
- Keep context small: never print whole logs. Codex's progress goes to a log file; read only `tail -n 40` on failure.
- If anything is unexpected and not covered here, stop with status BLOCKED and ask the user. Do not improvise around safety rules.

## Mode selection

- If the task text is exactly `resume`, or starts with `resume `, go to "Resume mode".
- If the task text is empty, ask the user (Thai) what the task is, and stop.
- Otherwise start a new run at step 0.

## 0. Preflight (any failure: stop, explain in Thai, change nothing except what is stated)

1. `pwd -P` and `git rev-parse --show-toplevel` must be the same directory. If not, tell the user to start `claude` at the repo root.
2. `git branch --show-current` must be non-empty (not detached HEAD). Remember it as ORIGINAL_BRANCH.
3. `codex --version`, then `codex login status`.
   `codex login status` returns exit code 0 even when not logged in, so read its text: continue only if the text contains
   `Logged in`. If it contains `Not logged in` or is unclear, stop and tell the user to run `codex login` themselves.
4. `codex exec --help`: confirm it lists `--cd`, `--sandbox`, `--config`, `--output-last-message`
   (and `--model` if CODEX_MODEL is set). If any is missing, stop: the installed Codex differs from what this skill expects.
5. `mkdir -p .ai`. Make the folder ignore itself without touching `.git`: if `.ai/.gitignore` does not exist,
   create it with the Write tool containing the single line `*`. (A `.gitignore` containing `*` also ignores itself,
   so `.ai/` never appears in `git status`, `git diff`, or `git add -A`. This works in worktrees too.)
6. `git status --porcelain` must be empty. If not, stop and ask the user to commit or stash. Do not do it for them.
7. External-send consent. If the file `.ai/external-ok` does not exist, ask the user (Thai) once:
   Codex reads files in this repo and sends their content to OpenAI. Is this repo allowed to be sent, and does it contain no
   confidential, personal, or organization-restricted data? Only after an explicit yes, create `.ai/external-ok`
   (one line with today's date). If the answer is no or unclear, stop.
8. Find sensitive-looking files: `git ls-files` filtered for names like `.env*`, `*.pem`, `*.key`, `id_rsa*`, `*credential*`, `*secret*`,
   plus any data folder the user mentions. List them for the user and put them in the DO-NOT-READ list of every brief.
   (This is an instruction to Codex, not an enforced barrier. Say so if the list is non-empty.)
9. Learn the project's commands: read `AGENTS.md` and `CLAUDE.md` if present, then README, `package.json` scripts,
   `pyproject.toml`, `Makefile`. Identify the test command(s) and lint/format command(s). If you cannot determine acceptance
   commands for the task and the user gave none, ask once and stop.
   Then run those commands once on the clean tree as a baseline (each as its own Bash call) and record the results in status.md.
   Failing tests are fine for a bug-fix task; it is the starting point. After the baseline run `git status --porcelain` again.
   If the commands left untracked files (for example `__pycache__/`, `.pytest_cache/`, `node_modules/`, `.DS_Store`),
   stop and ask the user to add them to `.gitignore` and commit it. Do not edit `.gitignore` yourself. Otherwise those files
   would be reported as scope violations or committed.
10. Create the run: `date +%Y%m%d-%H%M` gives RUN. `mkdir -p .ai/<RUN>`.
    If ORIGINAL_BRANCH starts with `ai/`, stay on it; otherwise `git switch -c ai/delegate-<RUN>`.
    `git rev-parse HEAD` gives INITIAL_BASE. Create `.ai/<RUN>/status.md` (see "status.md").

## 1. Plan

Write `.ai/<RUN>/plan.md`:

- Goal and assumptions (state each assumption explicitly).
- Slices. Each slice is one reviewable diff, ordered by dependency, and leaves the repo in a passing state.
  Guideline: at most about 8 files and about 300 changed lines. For each slice: title, ALLOWED files (paths or globs),
  FORBIDDEN files, acceptance commands with expected results, and what is out of scope.
- Risks, and anything you could not determine.

Stop after writing the plan, show a short Thai summary, and wait for the user's approval if ANY of these holds:
more slices than MAX_SLICES_WITHOUT_CONFIRM; the work touches authentication, security, payments, data migrations,
production configuration, CI/CD or deploy files; requirements are ambiguous or contradictory; acceptance commands cannot be defined.
Otherwise continue without asking.

## 2. Slice loop

For slice K (two digits, 01, 02, ...) and round R (starting at 1):

**2.1 Precondition (round 1 only).** `git status --porcelain` is empty. `git rev-parse HEAD` gives SLICE_BASE; record it in status.md.

**2.2 Write the brief** `.ai/<RUN>/task-<K>-r<R>.md` from the template below. The brief must be self-contained: Codex does not see this chat.

**2.3 Run Codex.** One foreground Bash call, Bash `timeout` parameter = CODEX_TIMEOUT_MS. Use literal values (each Bash call is a fresh shell).
Omit `--model` when CODEX_MODEL is blank; omit `--config` when CODEX_EFFORT is blank:

```
codex exec --cd . --sandbox workspace-write --model <CODEX_MODEL> --config 'model_reasoning_effort="<CODEX_EFFORT>"' --output-last-message .ai/<RUN>/result-<K>-r<R>.md - < .ai/<RUN>/task-<K>-r<R>.md > .ai/<RUN>/stdout-<K>-r<R>.txt 2> .ai/<RUN>/codex-<K>-r<R>.log
```

Increment the Codex run counter in status.md. If the counter would exceed MAX_CODEX_RUNS_PER_RUN, stop with BLOCKED instead.

**2.4 Check the run.** If the command failed, timed out, or `result-<K>-r<R>.md` is missing or empty: verdict BLOCKED.
Show `tail -n 40` of the log. After a timeout also run `pgrep -fl "codex exec"`; if a process still runs, report it to the user and stop
(do not kill other sessions' processes, do not start another run). A timeout can leave a half-edited working tree: report
`git status --porcelain`, do not clean it.

**2.5 Independent review.** Do all of this yourself; the result file is only a claim to check.

1. `git add -N .` (makes new files visible to diff; `.ai/` ignores itself). Then `git diff --stat <SLICE_BASE>`,
   `git diff --name-only <SLICE_BASE>`, `git status --porcelain`.
2. Scope: every changed or new path must match the slice's ALLOWED list. Anything else is FAIL (scope violation).
3. Test tampering: in any test or acceptance file, look for removed or weakened assertions, new skip/xfail/only markers,
   loosened tolerances, deleted cases, changed commands. FAIL unless the brief explicitly allowed that file to change.
4. Dependencies and config: changes to `package.json`, lockfiles, `pyproject.toml`, `requirements*`, CI, Dockerfiles, env files
   not authorized by the brief are FAIL.
5. Secrets and leftovers: hard-coded keys, tokens, absolute personal paths, debug prints, commented-out code, TODOs added without request.
6. Read the actual diff (`git diff <SLICE_BASE>`) against the brief for correctness, edge cases, error handling, and behavior beyond the brief.
   If the diff is very large (over about 800 changed lines) verdict FAIL: slice too large, re-plan into smaller slices.
7. Run the acceptance commands yourself, each as its own Bash call, and record exit codes and the few lines that matter.
   Never copy results from Codex's report.
8. Compare the result file's claims with what you found. Any discrepancy is a finding.

Write `.ai/<RUN>/review-<K>-r<R>.md`: verdict `PASS`, `FAIL` or `BLOCKED`; findings (file:line, issue, evidence);
commands you ran with exit codes; discrepancies; instructions for the next round.

**2.6 Act on the verdict.**

- PASS: `git add -A`, then `git commit -m "<short imperative title> (delegate <RUN> slice <K>)"`. Update status.md. Next slice.
- FAIL: if R is below MAX_ROUNDS_PER_SLICE and progress is being made, write the next brief (R+1) and loop to 2.3.
  The next brief contains the original goal, scope and acceptance criteria unchanged, plus a "Findings to fix" section
  (file:line, issue, evidence, expected behavior). It says: fix only these findings, no refactoring, no scope change.
  If Codex changed files outside scope, the brief tells Codex to restore each such file to its content at SLICE_BASE
  (it may read it with `git show <SLICE_BASE>:<path>`) and to delete files it created itself. Codex cannot use state-changing git.
  No progress means: the same finding (same file and issue) appears in two consecutive rounds, or the diff stat is identical
  to the previous round. No progress, or R reached the limit: BLOCKED.
- BLOCKED: stop the whole run, summarize in Thai what is done, what blocks, what you need from the user. Never claim completion.

**2.7 Mechanical fixes (only if CLAUDE_MECHANICAL_FIXES=allow).** You may fix a defect yourself only if ALL hold:
at most 5 changed lines in total, purely mechanical (typo, import order, whitespace, running the repo's own formatter),
no behavior change, and you record it in the review file as `claude-mechanical-fix` with the exact change. Then re-run the acceptance commands.
Anything else goes back to Codex. If CLAUDE_MECHANICAL_FIXES=deny, never edit source files.

After every step update `.ai/<RUN>/status.md`.

## 3. Finish

1. Run the full acceptance set (all tests and lint the project uses) once more on the final HEAD, yourself.
2. `git status --porcelain` must be empty. `git diff --stat <INITIAL_BASE>..HEAD`.
3. Write `.ai/<RUN>/summary.md` and set status DONE.
4. Report to the user in Thai: branch name and commits; files changed; actual test results (counts, exit codes);
   rounds used per slice and total Codex runs; mechanical fixes you made; residual risks; what was not verified; and that nothing was pushed.
   Tell the user how to review (`git log --oneline <ORIGINAL_BRANCH>..HEAD`, `git diff <ORIGINAL_BRANCH>...HEAD`)
   and how to discard (switch back to ORIGINAL_BRANCH and delete the task branch). Give these as text; do not run discard commands.

## Resume mode

`/delegate resume` or `/delegate resume <RUN>`:

1. Find `.ai/<RUN>/status.md` (named RUN, or the newest folder whose state is not DONE). If none, tell the user and stop.
2. Read status.md, plan.md and the latest review. Do not trust them over reality: check `git branch --show-current`,
   `git rev-parse HEAD`, `git status --porcelain` against what status.md recorded.
3. If they differ (for example uncommitted changes left by an interrupted Codex run), stop with BLOCKED and ask the user
   how to proceed. Never discard changes on your own.
4. Otherwise run the preflight items that are still relevant (3, 4, 6 as applicable), then continue from the recorded next step.

## status.md

Keep it short and current:

```
run: <RUN>
state: PLANNING | AWAITING_APPROVAL | RUNNING | BLOCKED | DONE
original_branch: <ORIGINAL_BRANCH>
task_branch: <branch>
initial_base: <INITIAL_BASE>
slice: <K>/<N>   round: <R>   codex_runs: <count>
slice_base: <SLICE_BASE>
last_verdict: <PASS|FAIL|BLOCKED|none>
next_step: <one sentence>
config: model=<..> effort=<..> timeout_ms=<..> max_rounds=<..> mechanical_fixes=<..>
task: <the user's task text>
```

## Brief template (copy for each round)

```
# Task <K> round <R>: <title>

You are the implementer. A separate reviewer will inspect your diff and run the acceptance commands independently.
Do not claim anything you have not verified by running it.

## Read first
- AGENTS.md (if present) and .ai/<RUN>/plan.md (slice <K> only)

## Goal
<1-3 sentences: the observable outcome>

## Allowed files (create or modify ONLY these)
<paths or globs>

## Forbidden
- Any file not listed above, including existing tests and acceptance commands unless listed above.
- Do not read or open: <sensitive file list, or "nothing special">
- No state-changing git (no add, commit, checkout, reset, stash, clean, push). Read-only git is fine.
- No new dependencies, no network downloads, unless listed here: <none>

## Requirements and constraints
<language/version, style rules from AGENTS.md, interfaces that must not change>

## Acceptance criteria (the reviewer runs these exactly)
1. `<command>` -> expected <exit 0 / output / behavior>

## Out of scope
<things not to do even if they look useful>

## Findings to fix (rounds 2+ only; fix only these, no refactoring)
- <file:line> <issue> <evidence> <expected>

## Final report (your last message)
- Files changed (path, one line each)
- Commands you ran and their exit codes
- Anything uncertain, skipped or blocked
```
