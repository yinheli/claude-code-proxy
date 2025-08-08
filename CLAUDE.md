# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Project overview
- Purpose: FastAPI proxy translating Anthropic Messages API to OpenAI/Gemini via LiteLLM
- Language/tooling: Python 3.10+, uv for env/runtime, FastAPI + Uvicorn, Pydantic v2, LiteLLM
- Entrypoint: server.py defines app and all endpoints

Common commands
- Run proxy (dev, auto-deps):
  uv run uvicorn server:app --host 0.0.0.0 --port 8082 --reload
- Run proxy (quiet logs, same defaults as __main__):
  uv run python server.py
- Use with Claude Code CLI:
  ANTHROPIC_BASE_URL=http://localhost:8082 claude
- Run tests (hits local proxy and Anthropic API; ensure server is running and ANTHROPIC_API_KEY is set):
  uv run python tests.py
  uv run python tests.py --no-streaming
  uv run python tests.py --streaming-only
  uv run python tests.py --simple
  uv run python tests.py --tools-only
- Lint/typecheck/format: not configured in pyproject.toml

Environment configuration
- Keys (read from process env): OPENAI_API_KEY, GEMINI_API_KEY, ANTHROPIC_API_KEY
- Provider preference: PREFERRED_PROVIDER=openai|google (default: openai)
- Model mapping defaults: BIG_MODEL=gpt-4.1, SMALL_MODEL=gpt-4.1-mini
- Known model lists: OPENAI_MODELS, GEMINI_MODELS used to auto-prefix openai/ or gemini/
- Minimal setup to proxy to OpenAI defaults:
  export OPENAI_API_KEY=...
  uv run uvicorn server:app --host 0.0.0.0 --port 8082 --reload

High-level architecture and flow
- Request handling
  - POST /v1/messages server.py:1087
    - Validates and maps model via Pydantic validator
      - MessagesRequest.model validator server.py:189–248
    - Builds LiteLLM request from Anthropic-format input
      - convert_anthropic_to_litellm server.py:401–625
        - Adds system/user messages, caps max tokens for OpenAI/Gemini, converts tools/tool_choice
        - For OpenAI targets, flattens content blocks to text and uses max_completion_tokens
    - Selects API key by model prefix (openai/gemini/anthropic)
    - Executes via LiteLLM (streaming or non-streaming)
      - Streaming: litellm.acompletion → SSE bridge handle_streaming server.py:825–1085
      - Non-streaming: litellm.completion → convert_litellm_to_anthropic server.py:627–823
        - Builds Anthropic-style content blocks; maps finish_reason to stop_reason; copies usage
  - POST /v1/messages/count_tokens server.py:1353–1426
    - Reuses convert_anthropic_to_litellm to normalize input
    - Uses litellm.token_counter to return input token count
  - GET / server.py:1428–1431 health/info

- Model mapping strategy
  - PREFERRED_PROVIDER guides mapping for requests containing haiku/sonnet names
  - Defaults map haiku→SMALL_MODEL, sonnet→BIG_MODEL
  - Auto-prefix if clean model matches OPENAI_MODELS or GEMINI_MODELS
  - Validators: MessagesRequest.model server.py:189–248; TokenCountRequest.model server.py:259–320

- Tools and schema handling
  - Anthropic tools converted into OpenAI function tools server.py:567–601
  - Gemini-specific schema cleaning removes unsupported fields (additionalProperties, default, many formats)
    - clean_gemini_schema server.py:114–135

- Streaming bridge (SSE)
  - Emits Anthropic-compatible sequence: message_start → content_block_start/delta/stop → message_delta → message_stop → [DONE]
  - Handles interleaving text deltas and tool_calls; closes text block before tool_use blocks server.py:868–1070

- Logging
  - Quiet uvicorn, custom filter to drop noisy LiteLLM internals server.py:27–53
  - Colorized model mapping/log lines; compact request summary via log_request_beautifully server.py:1444–1475

Testing notes
- tests.py exercises both real Anthropic API and the local proxy for structural similarity; it requires ANTHROPIC_API_KEY and a running proxy on localhost:8082
- Scenarios are predefined; selection is via flags (no per-scenario name filter). See Common commands for examples

Gotchas and conventions
- For OpenAI/Gemini targets, max tokens are capped at 16384 in convert_anthropic_to_litellm
- OpenAI targets expect flattened string content; complex content blocks are stringified with best-effort extraction
- API key selection is based on model prefix at request time; ensure env keys match chosen provider(s)
