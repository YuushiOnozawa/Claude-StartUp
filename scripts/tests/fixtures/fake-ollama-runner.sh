#!/usr/bin/env bash
set -u

system_path="${2:?system path required}"
prompt="$(cat)"

if [ -n "${FAKE_OLLAMA_PROMPT_LOG:-}" ]; then
  {
    printf '%s\n' "$prompt"
    printf '%s\n' '---PROMPT_END---'
  } >> "$FAKE_OLLAMA_PROMPT_LOG"
fi

if [ -n "${FAKE_OLLAMA_SYSTEM_LOG:-}" ]; then
  cp "$system_path" "$FAKE_OLLAMA_SYSTEM_LOG"
fi

if [ -n "${FAKE_OLLAMA_STDERR:-}" ]; then
  printf '%s' "$FAKE_OLLAMA_STDERR" >&2
fi

printf '%s' "${FAKE_OLLAMA_OUTPUT:-}"
exit "${FAKE_OLLAMA_EXIT:-0}"
