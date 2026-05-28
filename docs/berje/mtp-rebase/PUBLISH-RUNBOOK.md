# b9374 Gemma4/Qwen MTP Publish Runbook

This branch contains a local clean-clone rebase on upstream `b9374` (`491c4d7`).

## Current Verification

- Release CUDA build: passed with `cmake --build build-vs-cuda128 --config Release --target llama-server llama-cli -- /m`
- Contract: passed with `scripts/berje/check-b9374-mtp-rebase-contract.ps1 -RequirePortedGemmaEngine`
- Whitespace: passed with `git diff --cached --check`
- LM Studio runtime selected: `llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.16.9374`
- Runtime idle after tests: `lms ps --json == []`

## Key Evidence Artifacts

- Gemma4 LM Studio short16K: `artifacts/lmstudio-b9374-gemma-short16k-currentverify-20260529-1`
- Gemma4 LM Studio long29K: `artifacts/lmstudio-b9374-gemma-long29k-currentverify-20260529-1`
- Gemma4 LM Studio true32K fitted: `artifacts/lmstudio-b9374-gemma-true32k-fitted-currentverify-20260529-1`
- Gemma4 LM Studio true32K confirm: `artifacts/lmstudio-b9374-gemma-true32k-confirm-currentverify-20260529-1`
- Qwen LM Studio Tensor/Internal q8 native MTP: `artifacts/lmstudio-b9374-qwen36-q8-mtp-currentverify-20260529-4`
- LM Studio general target-only: `artifacts/lmstudio-b9374-targetonly-gemma26-currentverify-20260529-3`

Do not publish `artifacts/` to GitHub. They include local command lines and transient API keys in captured LM Studio logs.

## Remaining Local Publish Blockers

The local commit failed because this checkout has no git identity:

```powershell
git config user.name
git config user.email
```

The machine also does not have GitHub CLI `gh`, and `origin` points to `https://github.com/ggml-org/llama.cpp.git`.

## User Setup Needed

Set repository-local or global git identity:

```powershell
git config --global user.name "YOUR_NAME"
git config --global user.email "YOUR_EMAIL"
```

Add a fork remote before pushing:

```powershell
git remote add berje https://github.com/YOUR_GITHUB_ID/llama.cpp.git
```

Install and authenticate GitHub CLI if PR creation from this machine is desired:

```powershell
gh auth login
```

## Commit/Push Commands After Setup

The intended tracked scope is code, docs, and scripts only. `artifacts/` should remain untracked.

```powershell
git status --short --branch
git diff --cached --check
git commit -m "Port Gemma4 and Qwen MTP runtime on b9374"
git push -u berje berje/b9374-gemma4-qwen-mtp-rebase
```

Open the PR against `ggml-org/llama.cpp` only if this experimental runtime branch is meant to be reviewed upstream. Otherwise keep it as a fork branch backup.
