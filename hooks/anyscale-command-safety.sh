#!/usr/bin/env bash
#
# Kiro PreToolUse adapter for the Anyscale agent-skills command-safety hook.
#
# Anyscale's `anyscale skills install` ships a shell-command screening script
# (hooks/main.sh) plus a PreToolUse hook registration, but only for Claude Code,
# Cursor, Codex and Copilot. This adapter reuses that upstream script unmodified
# so its denylist stays current with `anyscale skills update`, and translates
# between the two conventions:
#
#   upstream (Claude/Copilot) : always exit 0; emit JSON with
#                               permissionDecision == "deny" to block
#   Kiro                      : exit 2 + reason on stderr to block
#                               exit 0 to allow
#
# Fails OPEN in every ambiguous case (no upstream script, no JSON parser,
# unparseable payload, upstream crash). A safety net that bricks the shell tool
# is worse than one that occasionally misses; this mirrors upstream's own
# fail-open behaviour.
#
# Override the upstream script path with ANYSCALE_SAFETY_HOOK if needed.

set -uo pipefail

INPUT="$(cat)"

# --- locate the Anyscale-managed screening script ----------------------------

UPSTREAM="${ANYSCALE_SAFETY_HOOK:-}"
if [ -z "$UPSTREAM" ]; then
  for candidate in \
    "$HOME/.codex/hooks/main.sh" \
    "$HOME/.claude/hooks/main.sh" \
    "${CLAUDE_CONFIG_DIR:-}/hooks/main.sh"
  do
    if [ -n "$candidate" ] && [ -r "$candidate" ]; then
      UPSTREAM="$candidate"
      break
    fi
  done
fi
[ -n "$UPSTREAM" ] || exit 0

# --- pick a JSON parser ------------------------------------------------------

JSON_TOOL="${JSON_TOOL:-}"
if [ -z "$JSON_TOOL" ]; then
  if command -v jq >/dev/null 2>&1; then
    JSON_TOOL="jq"
  elif command -v python3 >/dev/null 2>&1; then
    JSON_TOOL="python3"
  else
    exit 0
  fi
fi

# --- normalise the Kiro event into the payload upstream expects --------------
#
# Kiro sends: {"hook_event_name":"preToolUse","tool_name":"execute_bash",
#              "tool_input":{"command":"..."},"cwd":...,"session_id":...}
# Upstream reads .tool_input.command, so the shapes already line up. Rebuilding
# a minimal payload keeps the contract explicit and tolerates the command
# arriving under a different key.

build_payload() {
  if [ "$JSON_TOOL" = "jq" ]; then
    jq -c '
      (.tool_input // {}) as $ti
      | [$ti.command, $ti.cmd, $ti.script]
      | map(select(type == "string"))
      | (.[0] // "")
      | {tool_input: {command: .}}
    ' 2>/dev/null || true
  else
    python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = data.get("tool_input")
cmd = ""
if isinstance(ti, dict):
    for key in ("command", "cmd", "script"):
        val = ti.get(key)
        if isinstance(val, str) and val:
            cmd = val
            break
print(json.dumps({"tool_input": {"command": cmd}}))
' 2>/dev/null || true
  fi
}

PAYLOAD="$(printf '%s' "$INPUT" | build_payload)"
[ -n "$PAYLOAD" ] || exit 0

# --- run the upstream screen --------------------------------------------------

if ! OUT="$(printf '%s' "$PAYLOAD" | bash "$UPSTREAM" pre-tool 2>/dev/null)"; then
  exit 0
fi
[ -n "$OUT" ] || exit 0

# --- translate a deny decision into Kiro's blocking convention ---------------

read_decision() {  # $1 = jq path expression suffix
  if [ "$JSON_TOOL" = "jq" ]; then
    jq -r "(.hookSpecificOutput.$1 // .$1 // \"\")" 2>/dev/null || true
  else
    HOOK_FIELD="$1" python3 -c '
import sys, json, os
field = os.environ["HOOK_FIELD"]
try:
    data = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
scoped = data.get("hookSpecificOutput")
if isinstance(scoped, dict) and scoped.get(field) is not None:
    print(scoped.get(field) or "")
else:
    print(data.get(field) or "")
' 2>/dev/null || true
  fi
}

DECISION="$(printf '%s' "$OUT" | read_decision permissionDecision)"

if [ "$DECISION" = "deny" ]; then
  REASON="$(printf '%s' "$OUT" | read_decision permissionDecisionReason)"
  [ -n "$REASON" ] || REASON="Command blocked by the Anyscale command-safety hook."
  printf '%s\n' "$REASON" >&2
  exit 2
fi

exit 0
