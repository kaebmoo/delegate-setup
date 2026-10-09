#!/usr/bin/env bash
# delegate-run.sh : mechanical helper for the /delegate skill.
# It exists so that the things that must not depend on a model remembering them are done by code:
# the Codex run ledger and run cap, the one-run-at-a-time lock, fixed Codex flags (including approval_policy=never,
# so nothing can be escalated or auto-approved outside the sandbox), the Codex time limit, result checks, and a consistency check of status.md against what is really on disk.
#
# Run it from the repository root. Compatible with bash 3.2 (macOS).
#
#   bash ~/.claude/skills/delegate/delegate-run.sh version
#   bash ~/.claude/skills/delegate/delegate-run.sh codex <RUN> <K> <R> [--model M] [--effort E] [--max-runs N] [--timeout-sec S]
#   bash ~/.claude/skills/delegate/delegate-run.sh check-timeout <SECONDS>
#   bash ~/.claude/skills/delegate/delegate-run.sh count <RUN>
#   bash ~/.claude/skills/delegate/delegate-run.sh check-status <RUN>
#
# Exit codes: 0 ok | 2 bad usage or precondition (including a --timeout-sec that does not fit BASH_MAX_TIMEOUT_MS) | 3 run cap reached | 4 another run is active
#             5 codex exited non-zero | 6 codex produced no result message | 7 status.md inconsistent
#             8 codex was stopped because it exceeded --timeout-sec
#             9 codex ran with approval or sandbox settings other than the expected 'never' and 'workspace-write'
# Ledger lines: START <time> slice= round= model= effort= timeout=<seconds, 0 = none> pid=
#               END <time> slice= round= rc=<exit code|timeout|interrupted> result_bytes=
set -u

SCRIPT_VERSION=4.6
CODEX_BIN="${CODEX_BIN:-codex}"
DEFAULT_MAX_RUNS=12

die() {
  echo "delegate-run: $1" >&2
  exit "${2:-2}"
}

now() { date +%Y-%m-%dT%H:%M:%S%z; }

valid_run() { printf '%s' "$1" | grep -Eq '^[0-9]{8}-[0-9]{4}(-[0-9A-Za-z]+)?$'; }

need_repo_root() {
  local top here
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository" 2
  here=$(pwd -P)
  [ "$top" = "$here" ] || die "run from the repo root ($top), not from $here" 2
}

# number of START lines in a ledger file (0 if the file does not exist)
ledger_count() {
  if [ -f "$1" ]; then
    grep -c '^START ' "$1"
  else
    echo 0
  fi
}

# print a pid and all of its descendants, one per line
tree_pids() {
  local p=$1 c
  echo "$p"
  for c in $(pgrep -P "$p" 2>/dev/null); do
    tree_pids "$c"
  done
}

# a process counts as alive unless it is gone or a zombie
pid_alive() {
  local st
  st=$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')
  case "$st" in
    ""|Z*) return 1;;
    *) return 0;;
  esac
}

# ask a process tree to stop (TERM), wait up to 5 seconds, then force it (KILL)
stop_tree() {
  local pids p i alive
  pids=$(tree_pids "$1")
  for p in $pids; do kill -TERM "$p" 2>/dev/null; done
  i=0
  while [ "$i" -lt 5 ]; do
    alive=0
    for p in $pids; do
      if pid_alive "$p"; then alive=1; fi
    done
    [ "$alive" -eq 0 ] && return 0
    sleep 1
    i=$((i + 1))
  done
  for p in $pids; do kill -KILL "$p" 2>/dev/null; done
  return 0
}

# Claude Code cuts off the Bash call that runs this script at BASH_MAX_TIMEOUT_MS (its default is 600000 ms).
# The Codex time limit plus 60 seconds of margin must fit under that ceiling, otherwise the outer cut-off comes first.
check_ceiling() {
  local sec=$1 ceil=${BASH_MAX_TIMEOUT_MS:-600000} need
  printf '%s' "$ceil" | grep -Eq '^[0-9]+$' || die "BASH_MAX_TIMEOUT_MS is not a number: $ceil" 2
  [ "$sec" -eq 0 ] && return 0
  need=$(( (sec + 60) * 1000 ))
  [ "$need" -le "$ceil" ] || die "a ${sec}s Codex time limit needs BASH_MAX_TIMEOUT_MS >= $need (now ${BASH_MAX_TIMEOUT_MS:-unset, Claude Code default 600000}). Merge settings.snippet.json with merge-settings.js and start a new claude session, or use a smaller timeout." 2
}

cmd_check_timeout() {
  [ $# -eq 1 ] || die "usage: check-timeout <SECONDS>" 2
  printf '%s' "$1" | grep -Eq '^[0-9]+$' || die "bad seconds: $1" 2
  check_ceiling "$1"
  echo "timeout ${1}s fits BASH_MAX_TIMEOUT_MS=${BASH_MAX_TIMEOUT_MS:-600000 (default)}"
}

cmd_version() {
  echo "delegate-run $SCRIPT_VERSION"
}

cmd_count() {
  [ $# -eq 1 ] || die "usage: count <RUN>" 2
  valid_run "$1" || die "bad RUN id: $1" 2
  need_repo_root
  ledger_count ".ai/$1/runs.log"
}

cmd_check_status() {
  [ $# -eq 1 ] || die "usage: check-status <RUN>" 2
  local RUN=$1 S ledger state verdict next runs problems=0 review rv expected review_bad
  valid_run "$RUN" || die "bad RUN id: $RUN" 2
  need_repo_root
  S=".ai/$RUN/status.md"
  [ -f "$S" ] || die "status.md not found: $S" 2
  ledger=$(ledger_count ".ai/$RUN/runs.log")
  state=$(sed -n 's/^state: *//p' "$S" | head -n 1)
  verdict=$(sed -n 's/^last_verdict: *//p' "$S" | head -n 1 | tr 'a-z' 'A-Z')
  next=$(sed -n 's/^next_step: *//p' "$S" | head -n 1)
  runs=$(sed -n 's/.*codex_runs: *\([0-9][0-9]*\).*/\1/p' "$S" | head -n 1)

  case "$state" in
    PLANNING|AWAITING_APPROVAL|RUNNING|BLOCKED|DONE) ;;
    *) echo "MISMATCH state: '${state:-missing}' is not one of PLANNING, AWAITING_APPROVAL, RUNNING, BLOCKED, DONE"
       problems=$((problems + 1));;
  esac

  if [ "$runs" != "$ledger" ]; then
    echo "MISMATCH codex_runs: status.md says '${runs:-missing}', the ledger (runs.log) says $ledger"
    problems=$((problems + 1))
  fi

  # last_verdict must equal the verdict on the first 'verdict:' line of the newest review file
  review=$(ls -t ".ai/$RUN"/review-*.md 2>/dev/null | head -n 1)
  expected="NONE"
  review_bad=0
  if [ -n "$review" ]; then
    rv=$(sed -n 's/^verdict: *\([A-Za-z][A-Za-z]*\).*/\1/p' "$review" | head -n 1 | tr 'a-z' 'A-Z')
    if [ -z "$rv" ]; then
      echo "MISMATCH review file $review has no line starting with 'verdict: PASS|FAIL|BLOCKED'"
      problems=$((problems + 1))
      review_bad=1
    else
      expected=$rv
    fi
  fi
  if [ "$review_bad" -eq 0 ] && [ "$verdict" != "$expected" ]; then
    echo "MISMATCH last_verdict: status.md says '${verdict:-missing}', the newest review ($(basename "${review:-none}")) says $expected"
    problems=$((problems + 1))
  fi

  if [ "$state" = "DONE" ]; then
    if [ "$expected" != "PASS" ]; then
      echo "MISMATCH state DONE needs the newest review to be PASS (found: $expected)"
      problems=$((problems + 1))
    fi
    case "$next" in
      none*) ;;
      *) echo "MISMATCH next_step: '${next:-missing}' (must start with 'none' when state is DONE)"
         problems=$((problems + 1));;
    esac
    if [ ! -s ".ai/$RUN/summary.md" ]; then
      echo "MISMATCH state DONE needs a non-empty .ai/$RUN/summary.md"
      problems=$((problems + 1))
    fi
  fi

  if [ "$problems" -eq 0 ]; then
    echo "status.md consistent (state=$state, codex_runs=$runs, ledger=$ledger, newest review=$expected)"
    exit 0
  fi
  echo "delegate-run: fix status.md (or the review/summary file) so it matches reality, then run check-status again" >&2
  exit 7
}

cmd_codex() {
  [ $# -ge 3 ] || die "usage: codex <RUN> <K> <R> [--model M] [--effort E] [--max-runs N] [--timeout-sec S]" 2
  RUN=$1; K=$2; R=$3
  shift 3
  MODEL=""; EFFORT=""; MAXRUNS=$DEFAULT_MAX_RUNS; TIMEOUT_SEC=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --model)       [ $# -ge 2 ] || die "--model needs a value" 2; MODEL=$2; shift 2;;
      --effort)      [ $# -ge 2 ] || die "--effort needs a value" 2; EFFORT=$2; shift 2;;
      --max-runs)    [ $# -ge 2 ] || die "--max-runs needs a value" 2; MAXRUNS=$2; shift 2;;
      --timeout-sec) [ $# -ge 2 ] || die "--timeout-sec needs a value" 2; TIMEOUT_SEC=$2; shift 2;;
      *) die "unknown option: $1" 2;;
    esac
  done

  valid_run "$RUN" || die "bad RUN id: $RUN" 2
  printf '%s' "$K" | grep -Eq '^[0-9]{2}$' || die "bad slice number (need two digits): $K" 2
  printf '%s' "$R" | grep -Eq '^[0-9]+$' || die "bad round number: $R" 2
  printf '%s' "$MAXRUNS" | grep -Eq '^[0-9]+$' || die "bad --max-runs: $MAXRUNS" 2
  printf '%s' "$TIMEOUT_SEC" | grep -Eq '^[0-9]+$' || die "bad --timeout-sec: $TIMEOUT_SEC" 2
  check_ceiling "$TIMEOUT_SEC"
  if [ -n "$MODEL" ]; then
    printf '%s' "$MODEL" | grep -Eq '^[A-Za-z0-9._:/-]+$' || die "bad model name: $MODEL" 2
  fi
  if [ -n "$EFFORT" ]; then
    printf '%s' "$EFFORT" | grep -Eq '^[a-z]+$' || die "bad effort value: $EFFORT" 2
  fi

  need_repo_root
  D=".ai/$RUN"
  [ -d "$D" ] || die "no such run folder: $D" 2
  TASK="$D/task-$K-r$R.md"
  RESULT="$D/result-$K-r$R.md"
  STDOUT_F="$D/stdout-$K-r$R.txt"
  LOG="$D/codex-$K-r$R.log"
  LEDGER="$D/runs.log"
  LOCK="$D/.lock"
  TFLAG="$D/.timed-out"

  [ -s "$TASK" ] || die "brief missing or empty: $TASK" 2
  [ ! -e "$RESULT" ] || die "result already exists for this slice and round: $RESULT (use a new round number)" 2
  command -v "$CODEX_BIN" >/dev/null 2>&1 || die "codex not found: $CODEX_BIN" 2

  N=$(ledger_count "$LEDGER")
  [ "$N" -lt "$MAXRUNS" ] || die "Codex run cap reached ($N of $MAXRUNS). Stop and ask the user." 3

  if ! mkdir "$LOCK" 2>/dev/null; then
    OLDPID=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [ -n "$OLDPID" ] && pid_alive "$OLDPID"; then
      die "another delegate-run is active (pid $OLDPID)" 4
    fi
    echo "delegate-run: removing stale lock (pid ${OLDPID:-unknown} is not running)" >&2
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || die "cannot take the lock" 4
  fi
  echo $$ > "$LOCK/pid"
  rm -f "$TFLAG"

  FINISHED=0
  CHILD=""
  WD=""
  cleanup() {
    if [ "$FINISHED" -eq 0 ]; then
      if [ -n "$WD" ]; then
        stop_tree "$WD"
        wait "$WD" 2>/dev/null
      fi
      if [ -n "$CHILD" ]; then
        stop_tree "$CHILD"
        wait "$CHILD" 2>/dev/null
      fi
      printf 'END %s slice=%s round=%s rc=interrupted result_bytes=0\n' "$(now)" "$K" "$R" >> "$LEDGER"
    fi
    rm -f "$TFLAG"
    rm -rf "$LOCK"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  printf 'START %s slice=%s round=%s model=%s effort=%s timeout=%s pid=%s\n' \
    "$(now)" "$K" "$R" "${MODEL:-default}" "${EFFORT:-default}" "$TIMEOUT_SEC" "$$" >> "$LEDGER"

  set -- exec --cd . --sandbox workspace-write --config 'approval_policy="never"'
  if [ -n "$MODEL" ]; then set -- "$@" --model "$MODEL"; fi
  if [ -n "$EFFORT" ]; then set -- "$@" --config "model_reasoning_effort=\"$EFFORT\""; fi
  set -- "$@" --output-last-message "$RESULT" -

  "$CODEX_BIN" "$@" < "$TASK" > "$STDOUT_F" 2> "$LOG" &
  CHILD=$!

  if [ "$TIMEOUT_SEC" -gt 0 ]; then
    ( sleep "$TIMEOUT_SEC"; : > "$TFLAG"; stop_tree "$CHILD" ) &
    WD=$!
  fi

  wait "$CHILD"
  RC=$?

  if [ -n "$WD" ]; then
    stop_tree "$WD"
    wait "$WD" 2>/dev/null
    WD=""
  fi

  TIMED_OUT=0
  if [ -e "$TFLAG" ]; then TIMED_OUT=1; fi

  RB=0
  if [ -s "$RESULT" ]; then RB=$(wc -c < "$RESULT" | tr -d ' '); fi
  N=$(( $(ledger_count "$LEDGER") ))
  if [ "$TIMED_OUT" -eq 1 ]; then
    printf 'END %s slice=%s round=%s rc=timeout result_bytes=%s\n' "$(now)" "$K" "$R" "$RB" >> "$LEDGER"
  else
    printf 'END %s slice=%s round=%s rc=%s result_bytes=%s\n' "$(now)" "$K" "$R" "$RC" "$RB" >> "$LEDGER"
  fi
  FINISHED=1

  if [ "$TIMED_OUT" -eq 1 ]; then
    echo "delegate-run: slice=$K round=$R rc=timeout after ${TIMEOUT_SEC}s result_bytes=$RB runs_total=$N/$MAXRUNS"
    echo "delegate-run: log=$LOG"
    echo "delegate-run: codex was stopped because it ran longer than ${TIMEOUT_SEC} seconds. The working tree may be half edited."
    tail -n 20 "$LOG" 2>/dev/null
    exit 8
  fi

  echo "delegate-run: slice=$K round=$R rc=$RC result_bytes=$RB runs_total=$N/$MAXRUNS"
  echo "delegate-run: log=$LOG result=$RESULT"
  if [ "$RC" -ne 0 ]; then
    echo "delegate-run: codex exited with status $RC. Last log lines:"
    tail -n 20 "$LOG" 2>/dev/null
    exit 5
  fi
  # Codex prints its effective settings at the top of its log. The containment assumption is: approval never, sandbox workspace-write.
  BAN_APPROVAL=$(sed -n 's/^approval: *//p' "$LOG" | head -n 1 | tr -d ' ')
  BAN_SANDBOX=$(sed -n 's/^sandbox: *\([A-Za-z-]*\).*/\1/p' "$LOG" | head -n 1)
  if [ -z "$BAN_APPROVAL" ] || [ -z "$BAN_SANDBOX" ]; then
    echo "delegate-run: note: settings banner not found in $LOG (approval='${BAN_APPROVAL:-?}' sandbox='${BAN_SANDBOX:-?}'), could not confirm containment"
  elif [ "$BAN_APPROVAL" != "never" ] || [ "$BAN_SANDBOX" != "workspace-write" ]; then
    echo "delegate-run: codex ran with approval='$BAN_APPROVAL' sandbox='$BAN_SANDBOX' (expected approval=never sandbox=workspace-write). Do not trust this result."
    exit 9
  else
    echo "delegate-run: settings confirmed approval=never sandbox=workspace-write"
  fi
  if [ "$RB" -eq 0 ]; then
    echo "delegate-run: codex exited 0 but wrote no result message"
    exit 6
  fi
  exit 0
}

[ $# -ge 1 ] || die "usage: delegate-run.sh version|codex|check-timeout|count|check-status ..." 2
SUB=$1
shift
case "$SUB" in
  version)      cmd_version;;
  codex)        cmd_codex "$@";;
  check-timeout) cmd_check_timeout "$@";;
  count)        cmd_count "$@";;
  check-status) cmd_check_status "$@";;
  *) die "unknown subcommand: $SUB" 2;;
esac
