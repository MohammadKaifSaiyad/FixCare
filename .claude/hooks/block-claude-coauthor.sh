#!/bin/sh
# Claude Code PreToolUse hook (Bash matcher).
# Blocks a `git commit` whose command embeds a "Co-Authored-By: Claude" trailer,
# as an early layer on top of the committed .githooks/commit-msg hook.
#
# Receives the tool-call as JSON on stdin. Exit 2 = block the tool call.

input=$(cat)

# Extract the Bash command. Prefer jq; if jq is missing OR fails to parse
# (malformed JSON), fall back to scanning the raw input so we never silently
# pass a commit we should have inspected.
cmd=""
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
fi
[ -z "$cmd" ] && cmd="$input"

# Only care about git commits.
case "$cmd" in
  *"git commit"*|*"git "*"commit"*) ;;
  *) exit 0 ;;
esac

# Block if a Claude co-author trailer is present in the command text.
if printf '%s' "$cmd" | grep -qiE 'Co-Authored-By:[[:space:]]*Claude'; then
  echo "Blocked: this git commit contains a 'Co-Authored-By: Claude' trailer." >&2
  echo "FixCare commits are authored solely by MohammadKaifSaiyad — drop the trailer." >&2
  exit 2
fi

exit 0
