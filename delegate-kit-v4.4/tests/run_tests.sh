#!/usr/bin/env bash
# Tests for delegate/delegate-run.sh using a fake codex. No network, no real Codex, no changes outside a temp dir.
# Works on Linux and macOS (bash 3.2).
#
# Usage (from the unzipped kit folder):   bash tests/run_tests.sh
# Takes about 40 seconds. Prints PASS/FAIL per check and a final RESULT line; exit code 0 only if all passed.
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$KIT/delegate/delegate-run.sh"
[ -f "$SCRIPT" ] || { echo "cannot find $SCRIPT"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/delegate-tests.XXXXXX")" || exit 1
trap 'rm -rf "$T"' EXIT
REPO="$T/repo"; mkdir -p "$REPO" "$T/bin"
PASS=0; FAILN=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad()  { FAILN=$((FAILN+1)); echo "  FAIL: $1"; }
expect_rc() { # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1 (rc=$3)"; else bad "$1 (expected rc=$2, got $3)"; fi
}

# ---- fake codex ----
cat > "$T/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "call" >> "$FAKE_COUNT_FILE"
OUT=""; ARGS="$*"
while [ $# -gt 0 ]; do case "$1" in --output-last-message) OUT="$2"; shift 2;; *) shift;; esac; done
cat > /dev/null
if [ "${FAKE_BANNER:-yes}" != "none" ]; then
  echo "approval: ${FAKE_APPROVAL:-never}" >&2
  echo "sandbox: ${FAKE_SANDBOX:-workspace-write} [workdir, /tmp]" >&2
fi
echo "ARGS: $ARGS" >&2
case "${FAKE_MODE:-ok}" in
  ok) [ -n "$OUT" ] && printf 'report from fake codex\n' > "$OUT"; echo "final";;
  fail) echo "boom" >&2; exit 1;;
  noresult) echo "final"; exit 0;;
  sleep) sleep 7331 & wait; [ -n "$OUT" ] && printf 'late\n' > "$OUT";;
  stubborn) trap '' TERM; sleep 7331 & wait; sleep 7331;;
esac
EOF
chmod +x "$T/bin/codex"
export FAKE_COUNT_FILE="$T/calls.txt"; : > "$FAKE_COUNT_FILE"
export CODEX_BIN="$T/bin/codex"
if ! "$CODEX_BIN" </dev/null >/dev/null 2>&1; then
  echo "cannot execute the fake codex in $T (is the temp dir mounted noexec?). Set TMPDIR to another folder."; exit 1
fi
: > "$FAKE_COUNT_FILE"
leftover() { pgrep -f "sleep 7331" > /dev/null 2>&1 || pgrep -f "$T/bin/codex" > /dev/null 2>&1; }

cd "$REPO" || exit 1
git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name tester
echo hi > f.txt; git add -A; git commit -q -m init
RUN=20261007-1600
D=".ai/$RUN"
mkdir -p "$D"; printf '*\n' > .ai/.gitignore
printf '# brief\n' > "$D/task-01-r1.md"
run() { bash "$SCRIPT" "$@"; }

echo "T0 version"
[ "$(run version)" = "delegate-run 4.4" ] && ok "version prints 'delegate-run 4.4'" || bad "version output: $(run version)"

echo "T1 normal run"
FAKE_MODE=ok run codex $RUN 01 1 --model m1 --effort high --max-runs 3 > "$T/o1.txt" 2>&1; rc=$?
expect_rc "normal run" 0 $rc
grep -q "rc=0 result_bytes=" "$T/o1.txt" && grep -q "runs_total=1/3" "$T/o1.txt" && ok "summary line shows runs_total=1/3"
grep -q "settings confirmed approval=never sandbox=workspace-write" "$T/o1.txt" && ok "banner check confirmed settings" || bad "no banner confirmation: $(cat "$T/o1.txt")" || bad "summary line: $(cat "$T/o1.txt")"
grep -q -- '--model m1' "$D/codex-01-r1.log" && grep -q 'model_reasoning_effort="high"' "$D/codex-01-r1.log" && grep -q -- '--sandbox workspace-write' "$D/codex-01-r1.log" && grep -q -- '--cd .' "$D/codex-01-r1.log" && grep -q 'approval_policy="never"' "$D/codex-01-r1.log" && ok "fixed flags passed to codex (incl. approval_policy=never)" || bad "flags: $(cat "$D/codex-01-r1.log")"
[ "$(grep -c '^START ' $D/runs.log)" = 1 ] && [ "$(grep -c '^END ' $D/runs.log)" = 1 ] && ok "ledger has 1 START and 1 END" || bad "ledger: $(cat $D/runs.log)"
[ ! -d "$D/.lock" ] && ok "lock released" || bad "lock left behind"
[ "$(run count $RUN)" = 1 ] && ok "count prints 1" || bad "count"
git status --porcelain | grep -q . && bad "git status not clean after run: $(git status --porcelain)" || ok ".ai/ is invisible to git status"

echo "T2 refuses to overwrite an existing result"
FAKE_MODE=ok run codex $RUN 01 1 > /dev/null 2>&1; rc=$?; expect_rc "same slice/round again" 2 $rc

echo "T3 missing brief"
run codex $RUN 01 2 > /dev/null 2>&1; rc=$?; expect_rc "missing brief" 2 $rc

echo "T4 run cap"
for r in 2 3; do printf '# b\n' > "$D/task-01-r$r.md"; done
FAKE_MODE=ok run codex $RUN 01 2 --max-runs 3 > /dev/null 2>&1; rc=$?; expect_rc "2nd run within cap" 0 $rc
FAKE_MODE=ok run codex $RUN 01 3 --max-runs 3 > /dev/null 2>&1; rc=$?; expect_rc "3rd run within cap" 0 $rc
printf '# b\n' > "$D/task-01-r4.md"; BEFORE=$(wc -l < "$FAKE_COUNT_FILE" | tr -d ' ')
FAKE_MODE=ok run codex $RUN 01 4 --max-runs 3 > /dev/null 2>&1; rc=$?
expect_rc "4th run blocked by cap" 3 $rc
[ "$(wc -l < "$FAKE_COUNT_FILE" | tr -d ' ')" = "$BEFORE" ] && ok "codex was NOT called when cap reached" || bad "codex called despite cap"

echo "T5 live lock blocks, stale lock is taken over"
printf '# b\n' > "$D/task-02-r1.md"
mkdir "$D/.lock"; sleep 7332 & LIVE=$!; echo $LIVE > "$D/.lock/pid"
FAKE_MODE=ok run codex $RUN 02 1 --max-runs 20 > /dev/null 2>&1; rc=$?; expect_rc "live lock refused" 4 $rc
kill $LIVE 2>/dev/null; wait $LIVE 2>/dev/null
FAKE_MODE=ok run codex $RUN 02 1 --max-runs 20 > "$T/o5.txt" 2>&1; rc=$?; expect_rc "stale lock taken over" 0 $rc
grep -q "stale lock" "$T/o5.txt" && ok "stale lock reported" || bad "no stale lock message"

echo "T6 codex failure and empty result"
printf '# b\n' > "$D/task-03-r1.md"; printf '# b\n' > "$D/task-03-r2.md"
FAKE_MODE=fail run codex $RUN 03 1 --max-runs 20 > "$T/o6.txt" 2>&1; rc=$?; expect_rc "codex non-zero" 5 $rc
grep -q "boom" "$T/o6.txt" && ok "log tail shown on failure" || bad "no log tail"
grep -q "rc=1 " "$D/runs.log" && ok "ledger records rc=1" || bad "ledger rc"
FAKE_MODE=noresult run codex $RUN 03 2 --max-runs 20 > /dev/null 2>&1; rc=$?; expect_rc "no result message" 6 $rc

echo "T7 argument validation and repo root"
run codex "bad run;id" 01 1 > /dev/null 2>&1; rc=$?; expect_rc "bad RUN rejected" 2 $rc
run codex $RUN 1 1 > /dev/null 2>&1; rc=$?; expect_rc "bad slice rejected" 2 $rc
run codex $RUN 01 1 --model 'a;rm -rf /' > /dev/null 2>&1; rc=$?; expect_rc "bad model rejected" 2 $rc
run codex $RUN 01 9 --bogus > /dev/null 2>&1; rc=$?; expect_rc "unknown option rejected" 2 $rc
run codex $RUN 01 9 --timeout-sec abc > /dev/null 2>&1; rc=$?; expect_rc "bad --timeout-sec rejected" 2 $rc
mkdir -p sub; (cd sub && bash "$SCRIPT" count $RUN > /dev/null 2>&1); rc=$?; expect_rc "not at repo root" 2 $rc
run nonsense > /dev/null 2>&1; rc=$?; expect_rc "unknown subcommand" 2 $rc

echo "T8 interrupt: TERM kills codex and its child, writes END, frees the lock"
printf '# b\n' > "$D/task-04-r1.md"
FAKE_MODE=sleep bash "$SCRIPT" codex $RUN 04 1 --max-runs 20 > /dev/null 2>&1 &
SP=$!; sleep 2
pgrep -f "sleep 7331" > /dev/null && ok "fake codex child is running before TERM" || bad "child not running"
kill -TERM $SP; wait $SP 2>/dev/null; sleep 1
leftover && bad "fake codex or its sleep is still alive" || ok "fake codex and its child are gone"
grep -q "slice=04 round=1 rc=interrupted" "$D/runs.log" && ok "END interrupted recorded" || bad "no END interrupted: $(tail -2 $D/runs.log)"
[ ! -d "$D/.lock" ] && ok "lock freed after interrupt" || bad "lock left after interrupt"

echo "T9 check-status"
RUNS=$(run count $RUN)
printf 'verdict: PASS\n\nfindings: none\n' > "$D/review-01-r1.md"
printf '# summary\nall good\n' > "$D/summary.md"
cat > "$D/status.md" <<EOF
run: $RUN
state: DONE
slice: 01/1   round: 1   codex_runs: 0
last_verdict: none
next_step: run Codex for slice 01 round 1
EOF
run check-status $RUN > "$T/o9.txt" 2>&1; rc=$?; expect_rc "stale status (the real v3 failure) is flagged" 7 $rc
[ "$(grep -c MISMATCH "$T/o9.txt")" = 3 ] && ok "3 mismatches reported (codex_runs, last_verdict, next_step)" || bad "mismatches: $(cat "$T/o9.txt")"
cat > "$D/status.md" <<EOF
run: $RUN
state: DONE
slice: 01/01
round: 1
codex_runs: $RUNS
last_verdict: PASS
next_step: none, run complete
EOF
run check-status $RUN > /dev/null 2>&1; rc=$?; expect_rc "corrected status accepted" 0 $rc
rm "$D/summary.md"
run check-status $RUN > /dev/null 2>&1; rc=$?; expect_rc "DONE without summary.md flagged" 7 $rc
printf '# summary\n' > "$D/summary.md"
printf 'verdict: FAIL\n' > "$D/review-01-r2.md"
run check-status $RUN > /dev/null 2>&1; rc=$?; expect_rc "newest review FAIL but status says PASS and DONE" 7 $rc
printf 'run: x\nstate: RUNNING\ncodex_runs: %s\nlast_verdict: FAIL\nnext_step: write round 2 brief\n' "$RUNS" > "$D/status.md"
run check-status $RUN > /dev/null 2>&1; rc=$?; expect_rc "RUNNING status matching ledger and newest review accepted" 0 $rc
printf 'no verdict line here\n' > "$D/review-01-r3.md"
run check-status $RUN > /dev/null 2>&1; rc=$?; expect_rc "review file without verdict line flagged" 7 $rc
rm "$D/review-01-r3.md"

echo "T10 timeout: the script stops codex itself"
printf '# b\n' > "$D/task-05-r1.md"
S=$(date +%s)
FAKE_MODE=sleep run codex $RUN 05 1 --max-runs 30 --timeout-sec 2 > "$T/o10.txt" 2>&1; rc=$?
E=$(date +%s)
expect_rc "timeout exit code" 8 $rc
[ $((E - S)) -le 10 ] && ok "returned within 10 seconds ($((E - S))s)" || bad "took $((E - S))s"
grep -q "slice=05 round=1 rc=timeout" "$D/runs.log" && ok "ledger records rc=timeout" || bad "ledger: $(tail -2 $D/runs.log)"
[ "$(grep -c 'slice=05 round=1' "$D/runs.log")" = 2 ] && ok "exactly one START and one END for the run" || bad "ledger lines: $(grep 'slice=05' "$D/runs.log")"
leftover && bad "codex or its sleep still alive after timeout" || ok "nothing left running after timeout"
[ ! -d "$D/.lock" ] && [ ! -e "$D/.timed-out" ] && ok "lock and timeout flag cleaned" || bad "lock or flag left"

echo "T11 timeout: a codex that ignores TERM is force killed"
printf '# b\n' > "$D/task-06-r1.md"
S=$(date +%s)
FAKE_MODE=stubborn run codex $RUN 06 1 --max-runs 30 --timeout-sec 1 > /dev/null 2>&1; rc=$?
E=$(date +%s)
expect_rc "timeout exit code (stubborn)" 8 $rc
[ $((E - S)) -le 15 ] && ok "returned within 15 seconds ($((E - S))s)" || bad "took $((E - S))s"
leftover && bad "stubborn codex still alive" || ok "stubborn codex and its child are gone"

echo "T12 a fast run leaves no watchdog behind"
printf '# b\n' > "$D/task-07-r1.md"
FAKE_MODE=ok run codex $RUN 07 1 --max-runs 30 --timeout-sec 7333 > /dev/null 2>&1; rc=$?
expect_rc "fast run with a timeout set" 0 $rc
pgrep -f "sleep 7333" > /dev/null && bad "watchdog sleep left running" || ok "no watchdog left running"

echo "T13 banner check: approval and sandbox must be never and workspace-write"
printf '# b\n' > "$D/task-08-r1.md"; printf '# b\n' > "$D/task-08-r2.md"; printf '# b\n' > "$D/task-08-r3.md"; printf '# b\n' > "$D/task-08-r4.md"
FAKE_APPROVAL=on-request run codex $RUN 08 1 --max-runs 40 > "$T/o13.txt" 2>&1; rc=$?
expect_rc "approval on-request is refused" 9 $rc
grep -q "Do not trust this result" "$T/o13.txt" && ok "warning printed" || bad "no warning: $(cat "$T/o13.txt")"
FAKE_SANDBOX=danger-full-access run codex $RUN 08 2 --max-runs 40 > /dev/null 2>&1; rc=$?
expect_rc "sandbox danger-full-access is refused" 9 $rc
FAKE_BANNER=none run codex $RUN 08 3 --max-runs 40 > "$T/o13c.txt" 2>&1; rc=$?
expect_rc "missing banner does not fail the run" 0 $rc
grep -q "settings banner not found" "$T/o13c.txt" && ok "missing banner is reported" || bad "no note about missing banner"
FAKE_MODE=fail FAKE_APPROVAL=on-request run codex $RUN 08 4 --max-runs 40 > /dev/null 2>&1; rc=$?
expect_rc "codex failure takes precedence over banner check" 5 $rc

echo "T14 leftover-process pattern in SKILL.md matches our Codex run but not other Codex processes"
NPAT=$(grep -o 'pgrep -fl "[^"]*"' "$KIT/delegate/SKILL.md" | sort -u | wc -l | tr -d ' ')
[ "$NPAT" = 1 ] && ok "SKILL.md uses exactly one pgrep pattern" || bad "SKILL.md has $NPAT different pgrep patterns"
PAT=$(grep -o 'pgrep -fl "[^"]*"' "$KIT/delegate/SKILL.md" | head -n 1 | sed 's/^pgrep -fl "//; s/"$//')
printf '#!/usr/bin/env bash\nsleep 7336\ntrue\n' > "$T/bin/ours.sh"
printf '#!/usr/bin/env bash\nsleep 7337\ntrue\n' > "$T/bin/appsrv.sh"
bash "$T/bin/ours.sh" exec --cd . --sandbox workspace-write --config 'approval_policy="never"' --output-last-message r.md - > /dev/null 2>&1 &
OURS_PID=$!
bash "$T/bin/appsrv.sh" /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex exec-server --remote https://example.invalid > /dev/null 2>&1 &
APP_PID=$!
sleep 1
MATCHED=$(pgrep -f "$PAT" | tr '\n' ' ')
case " $MATCHED" in *" $OURS_PID "*) ok "pattern finds our Codex run";; *) bad "pattern did not find our run (matched: $MATCHED)";; esac
case " $MATCHED" in *" $APP_PID "*) bad "pattern wrongly matches the app's exec-server";; *) ok "pattern ignores the app's exec-server";; esac
OLD=$(pgrep -f "codex exec" | tr '\n' ' ')
case " $OLD" in *" $APP_PID "*) ok "the old pattern 'codex exec' would have matched the app's exec-server (why it was replaced)";; *) bad "old pattern did not match the app's exec-server on this system";; esac
pkill -P "$OURS_PID" > /dev/null 2>&1; pkill -P "$APP_PID" > /dev/null 2>&1
kill $OURS_PID $APP_PID 2>/dev/null; wait $OURS_PID $APP_PID 2>/dev/null
sleep 1

echo; echo "RESULT: $PASS passed, $FAILN failed"
[ "$FAILN" -eq 0 ]
