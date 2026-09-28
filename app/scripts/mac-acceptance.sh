#!/bin/bash
# Anti-slop on-Mac acceptance run: everything that needs a real Mac and your own
# provider sign-ins. Uses synthetic text only and writes sanitized receipts to
# app/evidence/mac/<timestamp>/. Send that folder (or the printed summary) back.
#
#   cd app && ./scripts/mac-acceptance.sh                 # default run
#   ./scripts/mac-acceptance.sh --claude-corpus           # also rerun the 54-case Claude corpus on this Mac
#
# Before running:
#   - Quit TextEdit (save your documents first). The probe opens its own temporary files.
#   - Give your terminal app Accessibility access: System Settings › Privacy & Security › Accessibility.
#   - Sign in with your own accounts: `claude auth login` and `codex login` (ChatGPT).
#   - Don't type or click while the live checks run; they send real key presses.
set -uo pipefail
cd "$(dirname "$0")/.."

CLAUDE_CORPUS=0
for arg in "$@"; do
  case "$arg" in
    --claude-corpus) CLAUDE_CORPUS=1 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

OUT="evidence/mac/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
LOG="$OUT/run.log"
say() { echo "$@" | tee -a "$LOG"; }
# Only the probe's own temporary documents are open (checked below), so quitting is safe.
quit_textedit() { pkill -x TextEdit 2>/dev/null; sleep 2; }
step() { say ""; say "== $1"; }

say "Anti-slop on-Mac acceptance run, $(date)"
say "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
say "$(xcodebuild -version 2>/dev/null | head -1) / $(swift --version 2>&1 | head -1)"
for tool in claude codex; do
  if command -v "$tool" >/dev/null 2>&1; then
    say "$tool: $(command -v "$tool") ($("$tool" --version 2>/dev/null | head -1))"
  else
    say "$tool: NOT FOUND on PATH (install it and sign in; the matching checks will fail)"
  fi
done
if pgrep -x TextEdit >/dev/null; then
  echo "TextEdit is running. Save your documents and quit TextEdit, then run this again."
  exit 4
fi

step "Unit and contract tests"
swift test 2>&1 | tee "$OUT/test.log" | grep -E "Executed [0-9]+ tests|error:" | tail -3 | tee -a "$LOG"

step "Build the app bundle"
./scripts/build-app.sh 2>&1 | tail -2 | tee -a "$LOG"
swift build -c release --product antislop-eval >/dev/null 2>&1
swift build -c release --product antislop-axprobe >/dev/null 2>&1
BIN="$(swift build -c release --show-bin-path)"

step "Provider readiness (a harmless live request each)"
"$BIN/antislop-eval" readiness --provider claude-code 2>&1 | tee -a "$LOG" "$OUT/readiness.txt"
"$BIN/antislop-eval" readiness --provider codex 2>&1 | tee -a "$LOG" "$OUT/readiness.txt"

step "TextEdit capture and replacement probe"
"$BIN/antislop-axprobe" textedit --allow-quit-textedit --out "$OUT/probe-textedit.json" 2>&1 | tee -a "$LOG"
quit_textedit

step "Live end to end: Claude Code in the real app"
"$BIN/antislop-axprobe" e2e --app build/Anti-slop.app --live --provider claude-code --force \
  --out "$OUT/e2e-claude-code.json" 2>&1 | tee -a "$LOG"
quit_textedit

step "Live end to end: Codex in the real app"
"$BIN/antislop-axprobe" e2e --app build/Anti-slop.app --live --provider codex --force \
  --out "$OUT/e2e-codex.json" 2>&1 | tee -a "$LOG"
quit_textedit

step "Codex editorial corpus (18 cases x 3 profiles)"
"$BIN/antislop-eval" corpus --provider codex --fixtures ../fixtures/editorial-cases.json \
  --out "$OUT/codex-corpus.json" 2>&1 | tee -a "$LOG"

if [ "$CLAUDE_CORPUS" = 1 ]; then
  step "Claude Code editorial corpus on this Mac"
  "$BIN/antislop-eval" corpus --provider claude-code --fixtures ../fixtures/editorial-cases.json \
    --out "$OUT/claude-code-corpus.json" 2>&1 | tee -a "$LOG"
fi

step "Summary"
python3 - "$OUT" <<'PY' | tee -a "$LOG"
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
for name in ["probe-textedit.json", "e2e-claude-code.json", "e2e-codex.json"]:
    p = out / name
    if not p.exists():
        print(f"{name}: missing"); continue
    checks = json.loads(p.read_text())["checks"]
    failed = [c["id"] for c in checks if not c["passed"]]
    print(f"{name}: {len(checks) - len(failed)}/{len(checks)} passed" + (f"  FAILED: {', '.join(failed)}" if failed else ""))
for name in ["codex-corpus.json", "claude-code-corpus.json"]:
    p = out / name
    if not p.exists():
        continue
    r = json.loads(p.read_text())
    res = r["results"]
    ok = [x for x in res if x["status"] == "ok"]
    review = [f'{x["case_id"]}/{x["profile"]}' for x in ok if x["missing_literals"]]
    print(f"{name}: {len(ok)}/{len(res)} validated proposals; readiness: {r['readiness']}")
    if review:
        print("  literal cues to review (not automatically failures): " + ", ".join(review))
PY
say ""
say "Receipts: app/$OUT (synthetic fixture text only; no credentials)."
