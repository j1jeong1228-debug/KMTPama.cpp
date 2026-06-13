# b9596 GitHub Publish Scope

Date: 2026-06-13

## Remote State

- Upstream remote: `origin -> https://github.com/ggml-org/llama.cpp.git`
- Personal fork remote: `j1jeong1228-debug -> https://github.com/j1jeong1228-debug/KMTPama.cpp.git`
- Current branch: `berje/b9596-gemma4-qwen-mtp-runtime`

The fork exists and is a fork of `ggml-org/llama.cpp`, but its repository name is `KMTPama.cpp`, not `llama.cpp`.

## Intended Commit Scope

Runtime code changes:

- `common/arg.cpp`
- `common/speculative.cpp`
- `common/speculative.h`
- `src/llama-arch.cpp`
- `src/llama-arch.h`
- `src/llama-context.cpp`
- `src/llama-hparams.h`
- `src/llama-kv-cache.cpp`
- `src/llama-model-loader.cpp`
- `src/models/gemma4-assistant.cpp`
- `tools/server/server-context.cpp`

Documentation:

- `docs/lmstudio/b9596-gemma-qwen-mtp-runtime-summary.md`
- `docs/lmstudio/b9596-defects-and-rejections.md`
- `docs/lmstudio/b9596-github-publish-scope.md`
- `docs/superpowers/plans/2026-06-13-b9596-runtime-record-cleanup.md`

Utility script:

- `scripts/compare-lmstudio-gemma-qat-assistants-curl.ps1`

Small evidence summaries only:

- `artifacts/lmstudio-b9596-gemma-qat-assistant-selected-q4-summary.json`
- `artifacts/lmstudio-b9596-goal-smoke-20260613-1344/audit-result.json`
- `artifacts/lmstudio-b9596-goal-short-long-short-20260613-1354/summary.json`
- `artifacts/lmstudio-b9596-goal-long128-20260613-1358/summary.json`
- `artifacts/lmstudio-b9596-qwen-native-q8-q4-001/summary.json`
- `artifacts/lmstudio-b9596-targetonly-qwen2-smoke-001/summary.json`
- `artifacts/_trash/b9596-cleanup-20260613-134909/TRASH-MANIFEST.json`

## Do Not Commit

Do not commit raw response files, raw LM Studio logs, full command-line captures, PID files, or backup copies under `artifacts/`.

Reason:

- They contain local absolute paths.
- Some command-line captures previously contained LM Studio temporary API keys, now redacted locally.
- The summary files already preserve the decision-grade evidence.

## Validation Before Push

Required checks before pushing:

```powershell
rg -n --hidden --glob '!build/**' --glob '!*.bin' --glob '!*.gguf' -e '--api-key\s+[^<\s][^\s]*' -e 'gho_[A-Za-z0-9_]+' artifacts docs scripts common src tools -S
lms ps --json
git status --short --branch
```

Expected:

- Secret scan only reports the upstream documentation placeholder in `tools/server/README.md`.
- `lms ps --json` returns `[]`.
- No stale `C:\Users\berje\.lmstudio\.internal\gemma4-mtp-draft-override.json`.
