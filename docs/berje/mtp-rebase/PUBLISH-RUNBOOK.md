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

## Publish Status

- Local commit created: `74bc26795e33eb17f3b849a9f34ad3027346cfc6`
- Fork remote: `https://github.com/j1jeong1228-debug/KMTPama.cpp.git`
- Pushed branch: `berje/b9374-gemma4-qwen-mtp-rebase`
- Branch URL: `https://github.com/j1jeong1228-debug/KMTPama.cpp/tree/berje/b9374-gemma4-qwen-mtp-rebase`
- PR creation URL: `https://github.com/j1jeong1228-debug/KMTPama.cpp/pull/new/berje/b9374-gemma4-qwen-mtp-rebase`

## Local Publish Notes

The machine still does not have GitHub CLI `gh`, so PR creation was not automated from the terminal. The commit was created with one-shot identity flags instead of changing global git config:

```powershell
git -c user.name="berje" -c user.email="berje@users.noreply.github.com" commit -m "Port Gemma4 and Qwen MTP runtime on b9374"
```

If the author identity needs to be changed later:

```powershell
git commit --amend --reset-author
git push --force-with-lease
```

Install and authenticate GitHub CLI only if PR creation from this machine is desired:

```powershell
gh auth login
```

## Republish Commands

The intended tracked scope is code, docs, and scripts only. `artifacts/` should remain untracked.

```powershell
git status --short --branch
git push fork berje/b9374-gemma4-qwen-mtp-rebase
```

Open the PR against `ggml-org/llama.cpp` only if this experimental runtime branch is meant to be reviewed upstream. Otherwise keep it as a fork branch backup.
