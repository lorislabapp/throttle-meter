#!/usr/bin/env bash
# PreCompact hook: write a deterministic thread-preservation file before
# Claude Code compacts the conversation. Pure extraction — no LLM, no network.
# On any error, exits 0 so compaction is never blocked.

set -u

# Kill switch
if [ "${CLAUDE_DISABLE_TOKOPT_HOOKS:-0}" = "1" ]; then
  exit 0
fi

MEMORY_DIR="$HOME/.claude/projects/$(echo "$HOME" | sed "s|/|-|g")/memory"
mkdir -p "$MEMORY_DIR" 2>/dev/null || exit 0

# Read hook JSON from stdin.
INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)"
TRIGGER="$(printf '%s' "$INPUT" | jq -r '.trigger // "auto"' 2>/dev/null)"
TS="$(date +%Y%m%d_%H%M%S)"
CWD="${PWD:-$(pwd)}"
OUT="$MEMORY_DIR/pre_compact_${TS}.md"

# Resolve session transcript path. Claude Code stores it at
# ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl where <encoded-cwd>
# replaces / with -.
ENCODED_CWD="-$(printf '%s' "$CWD" | sed 's|/|-|g')"
TRANSCRIPT="$HOME/.claude/projects/${ENCODED_CWD}/${SESSION_ID}.jsonl"

{
  echo "---"
  echo "name: Pre-compaction breadcrumb ${TS}"
  echo "description: Session compacted at ${TS} — structured facts for thread preservation"
  echo "type: reference"
  echo "---"
  echo
  echo "# Pre-compaction snapshot"
  echo
  echo "- **Timestamp:** $(date -Iseconds 2>/dev/null || date)"
  echo "- **Trigger:** ${TRIGGER}"
  echo "- **Session ID:** ${SESSION_ID}"
  echo "- **CWD:** ${CWD}"
  echo

  # 1. Open tasks (if a task file for this session exists)
  echo "## Open tasks"
  echo
  TASKS_FILE="$HOME/.claude/tasks/${SESSION_ID}.json"
  if [ -f "$TASKS_FILE" ]; then
    jq -r '
      ( .tasks // [] )
      | map(select(.status != "completed" and .status != "deleted"))
      | if length == 0 then ["_(none)_"] else map("- [\(.status)] \(.subject)") end
      | .[]
    ' "$TASKS_FILE" 2>/dev/null || echo "_(could not read tasks file)_"
  else
    echo "_(no tasks file found)_"
  fi
  echo

  # 2. Recently modified files in CWD
  echo "## Recently modified files (last hour, top 20)"
  echo
  if [ -d "$CWD" ]; then
    find "$CWD" -type f -mmin -60 2>/dev/null \
      | grep -v -E '/\.(git|build|DS_Store)/' \
      | head -20 \
      | sed 's|^|- |' || echo "_(none)_"
  else
    echo "_(CWD not a directory)_"
  fi
  echo

  # 3. Last 5 user messages from transcript
  echo "## Last 5 user prompts"
  echo
  if [ -f "$TRANSCRIPT" ]; then
    jq -r '
      select(.type == "user" and (.message.content | type == "string"))
      | .message.content
    ' "$TRANSCRIPT" 2>/dev/null \
      | tail -5 \
      | awk 'NF { sub(/^[[:space:]]+/,""); print "- " substr($0, 1, 200) }' \
      || echo "_(could not parse transcript)_"
  else
    echo "_(transcript not found at \`${TRANSCRIPT}\`)_"
  fi
  echo

  # 4. Active git branches for repos touched in CWD
  echo "## Active git branches"
  echo
  if [ -d "$CWD" ]; then
    find "$CWD" -type d -name ".git" -maxdepth 3 2>/dev/null \
      | head -10 \
      | while IFS= read -r gitdir; do
        repo="${gitdir%/.git}"
        branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "?")
        echo "- \`$repo\` → \`$branch\`"
      done
  fi
  if ! find "$CWD" -type d -name ".git" -maxdepth 3 2>/dev/null | head -1 | grep -q .; then
    echo "_(no git repos detected within depth 3)_"
  fi
  echo

  echo "---"
  echo
  echo "Prior turns are summarized in the next message. Use the structured sections above to resume the thread."
} > "$OUT" 2>/dev/null

# Emit savings record for Throttle. The free-form auto-summary that this
# hook displaces is empirically ~6000 bytes; our structured extract is
# typically ~1500 bytes. We log the real "actual" size of our output and
# a 6000-byte baseline so the dashboard reflects the average win.
{
  ACTUAL_BYTES=0
  if [ -f "$OUT" ]; then
    ACTUAL_BYTES=$(wc -c < "$OUT" 2>/dev/null | tr -d ' ')
  fi
  TS=$(date +%s)
  LOG_DIR="$HOME/Library/Application Support/Throttle"
  mkdir -p "$LOG_DIR" 2>/dev/null
  LOG="$LOG_DIR/savings.jsonl"
  printf '{"ts":%s,"hook":"pre-compact","baseline_bytes":6000,"actual_bytes":%s}\n' \
    "$TS" "${ACTUAL_BYTES:-0}" >> "$LOG" 2>/dev/null
} 2>/dev/null

exit 0
