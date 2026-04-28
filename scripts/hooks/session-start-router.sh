#!/usr/bin/env bash
# SessionStart hook: emit project-relevant memory files based on CWD.
# Source of truth for the routing table: ~/.claude/memory-routing.json.
# Output goes to stdout as a single Markdown prelude. On any error, exit 0
# silently — never block session start.

set -u

# Kill switch
if [ "${CLAUDE_DISABLE_TOKOPT_HOOKS:-0}" = "1" ]; then
  exit 0
fi

# Required tools
command -v jq >/dev/null 2>&1 || exit 0

ROUTING="$HOME/.claude/memory-routing.json"
MEM_DIR="$HOME/.claude/projects/$(echo "$HOME" | sed "s|/|-|g")/memory"
[ -f "$ROUTING" ] || exit 0
[ -d "$MEM_DIR" ] || exit 0

# Read hook input. Claude Code SessionStart payload contains `cwd` and `session_id`.
INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

# Build the file list. Bash glob matching (case statement) is used for the
# rule patterns — that matches the user's mental model of `*` as a shell glob,
# handles `.`/`+`/`?` literally, and avoids regex-escape bugs.
always_files=$(jq -r '.always[]?' "$ROUTING" 2>/dev/null)
rule_count=$(jq -r '.rules | length' "$ROUTING" 2>/dev/null || echo 0)

rule_files=""
for i in $(seq 0 $((rule_count - 1))); do
  pattern=$(jq -r ".rules[$i].match // empty" "$ROUTING" 2>/dev/null)
  [ -z "$pattern" ] && continue
  case "$CWD" in
    $pattern)
      files=$(jq -r ".rules[$i].files[]?" "$ROUTING" 2>/dev/null)
      rule_files="${rule_files}${files}"$'\n'
      ;;
  esac
done

# Combine, dedupe (preserving order), drop empty lines.
matched_files=$(printf '%s\n%s' "$always_files" "$rule_files" \
  | awk 'NF && !seen[$0]++')

[ -z "$matched_files" ] && exit 0

# Emit a single prelude. Each file appears with its name as a sub-header.
# We tee the prelude through wc -c so we can record exactly how many bytes
# were actually emitted (the "actual" half of the savings calculation).
PRELUDE=$(
{
  echo "# Project-routed memory prelude (auto-emitted)"
  echo
  echo "_CWD: \`$CWD\` — matched files: $(echo "$matched_files" | wc -l | tr -d ' ')_"
  echo
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    full="$MEM_DIR/$f"
    if [ -f "$full" ]; then
      echo "---"
      echo
      echo "## \`$f\`"
      echo
      cat "$full"
      echo
    fi
  done <<< "$matched_files"
} 2>/dev/null
)
printf '%s' "$PRELUDE"

# Emit savings record for Throttle. Baseline = bytes of ALL memory files
# (what would have been loaded without routing). Actual = bytes we just
# emitted. Both metrics are best-effort; failures are silent so they
# never block session start.
{
  ACTUAL_BYTES=$(printf '%s' "$PRELUDE" | wc -c | tr -d ' ')
  BASELINE_BYTES=$(find "$MEM_DIR" -type f -name '*.md' -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
  TS=$(date +%s)
  LOG_DIR="$HOME/Library/Application Support/Throttle"
  mkdir -p "$LOG_DIR" 2>/dev/null
  LOG="$LOG_DIR/savings.jsonl"
  printf '{"ts":%s,"hook":"session-start-router","baseline_bytes":%s,"actual_bytes":%s}\n' \
    "$TS" "${BASELINE_BYTES:-0}" "${ACTUAL_BYTES:-0}" >> "$LOG" 2>/dev/null
} 2>/dev/null

exit 0
