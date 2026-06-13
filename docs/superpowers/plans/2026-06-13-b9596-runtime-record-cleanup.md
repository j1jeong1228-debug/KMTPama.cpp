# b9596 Runtime Record Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the validated b9596 Gemma4 QAT/Qwen MTP runtime state, fix live LM Studio config drift, document pass/fail evidence, and move superseded experiment files to trash.

**Architecture:** Keep runtime code and model-specific policies separate: Gemma4 uses QAT Q4 attached MTP with 9/6 split, while Qwen keeps Tensor/Internal/native MTP enabled through `experimentalTensorInternal=true`. Treat LM Studio logs and retained artifact JSON as the authoritative verification layer.

**Tech Stack:** Windows PowerShell, LM Studio CLI, GitHub CLI, llama.cpp b9596 runtime, LM Studio internal JSON config.

---

### Task 1: Fix Live LM Studio Gemma4 QAT Assistant Config

**Files:**
- Modify: `C:\Users\berje\.lmstudio\.internal\hardware-config.json`
- Move: `C:\Users\berje\.lmstudio\.internal\gemma4-mtp-draft-override.json`
- Create: `C:\Users\berje\.lmstudio\.internal\codex-backups\b9596-config-fix-20260613-134210\CONFIG-FIX-MANIFEST.json`

- [x] **Step 1: Back up current config**

Run:

```powershell
Copy-Item C:\Users\berje\.lmstudio\.internal\hardware-config.json C:\Users\berje\.lmstudio\.internal\codex-backups\b9596-config-fix-20260613-134210\hardware-config.json.before
```

- [x] **Step 2: Set Gemma4 assistant to QAT Q4 while preserving Qwen Tensor/Internal**

Expected values:

```json
{
  "customRatio": [9, 6],
  "experimentalTensorInternal": true,
  "gemma4MtpAssistant": "qat-q4"
}
```

- [x] **Step 3: Remove stale Q8 override from the live path**

Moved to:

```text
C:\Users\berje\.lmstudio\.internal\codex-backups\b9596-config-fix-20260613-134210\gemma4-mtp-draft-override.json.disabled-stale-q8
```

### Task 2: Smoke Test LM Studio Effective Runtime State

**Files:**
- Create: `artifacts/lmstudio-b9596-goal-smoke-20260613-1344/audit-result.json`

- [x] **Step 1: Load Gemma4 QAT through LM Studio**

Run:

```powershell
lms load google/gemma-4-31b-qat -c 65536 --parallel 1 --gpu max --identifier gemma-b9596-qat-smoke -y
```

- [x] **Step 2: Verify effective server log**

Required log fields:

```text
assistant_source=hardware-config-qat-q4
target_tensor_split=9,6
target_kv=q4_0/q4_0
tensor_internal_policy=not-for-gemma-q4
common_speculative_impl_draft_mtp: adding speculative implementation 'draft-mtp'
```

- [x] **Step 3: Verify API smoke**

Observed:

```text
content=OK-QAT-MTP
eval_tok_s=40.38
acceptance=0.83333
```

### Task 3: Prepare GitHub Fork Remote

**Files:**
- Modify local git remotes only.

- [x] **Step 1: Verify GitHub CLI auth**

Observed account:

```text
j1jeong1228-debug
```

- [x] **Step 2: Add fork remote**

Observed remote:

```text
j1jeong1228-debug https://github.com/j1jeong1228-debug/KMTPama.cpp.git
```

### Task 4: Document Evidence and Cleanup Rules

**Files:**
- Create: `docs/lmstudio/b9596-gemma-qwen-mtp-runtime-summary.md`
- Create: `docs/lmstudio/b9596-defects-and-rejections.md`

- [x] **Step 1: Record retained pass evidence**

Retained artifacts:

```text
artifacts/lmstudio-b9596-gemma-qat-assistant-selected-q4-summary.json
artifacts/lmstudio-b9596-gemma-qat-assistant-completion-audit-smoke-001
artifacts/lmstudio-b9596-goal-smoke-20260613-1344
artifacts/lmstudio-b9596-qwen-native-q8-q4-001
artifacts/lmstudio-b9596-targetonly-qwen2-smoke-001
```

- [x] **Step 2: Record rejected paths**

Rejected or not selected:

```text
Q8 assistant as Gemma4 default
Tensor/Internal as Gemma4 q4/layer production fix
raw process command line as sole verification
stale Q8 override
```

### Task 5: Move Superseded Files to Trash

**Files:**
- Create: `artifacts/_trash/b9596-cleanup-20260613-<time>/TRASH-MANIFEST.json`
- Move: superseded compare directories and the non-curl harness.

- [x] **Step 1: Move only superseded compare artifacts**

Candidates:

```text
artifacts/lmstudio-b9596-gemma-qat-assistant-q4-q8-compare-001
artifacts/lmstudio-b9596-gemma-qat-assistant-q4-q8-compare-002
artifacts/lmstudio-b9596-gemma-qat-assistant-q4-q8-compare-003
```

- [x] **Step 2: Move the non-curl harness**

Candidate:

```text
scripts/compare-lmstudio-gemma-qat-assistants.ps1
```

- [x] **Step 3: Keep the curl harness**

Keep:

```text
scripts/compare-lmstudio-gemma-qat-assistants-curl.ps1
```
