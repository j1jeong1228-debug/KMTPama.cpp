# Gemma4 Head-Aware Tensor/Internal Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Gemma4 attached MTP Tensor/Internal splits diagnose and then respect GQA Q/KV head ownership so uneven splits such as `9,6` and `8,7` can be evaluated safely.

**Architecture:** Start with diagnostics that prove device-local Q/KV head ownership, then implement the smallest head-aware routing fix. Do not relax `FLASH_ATTN_EXT` assertions silently. If head-aware split proves too broad, fall back to an assistant layer-mode hybrid while keeping target Tensor/Internal as caller-selected.

**Tech Stack:** llama.cpp b9222 fork, ggml meta backend, CUDA Flash Attention, Gemma4 attached MTP, PowerShell serial runners, LM Studio models.

---

## Files

- Modify: `ggml/src/ggml-backend-meta.cpp`
  - Add head-ratio diagnostic for `FLASH_ATTN_EXT`.
  - Keep strict split-state assertions.
- Modify: `src/llama-graph.cpp`
  - Add MTP attention diagnostics in `build_attn_mtp(...)`.
  - Later hold head-aware routing changes if needed.
- Modify: `src/llama-model.cpp`
  - Add optional diagnostic logging for split metadata of `mtp.blk.*.attn_q.weight`, `mtp.blk.*.attn_output.weight`, `cache_k_l*`, `cache_v_l*`.
  - Later hold head-aware split planning if diagnostics prove the fix belongs at model split-state level.
- Create: `scripts/run-gemma4-tensor-mtp-diagnostic.ps1`
  - Serial runner for `ts=1,1`, `9,6`, `8,7`, f16/q8 KV.
- Modify: `docs/development/gemma4-gqa-tensor-internal-root-cause.md`
  - Append measured diagnostic results after each stage.

## Safety Rules

- Never run models in parallel.
- Each case must run:
  - `lms unload -a`
  - `lms ps --json == []`
  - verify no `llama-server.exe`, `llama-cli.exe`, `llama-bench.exe`
  - run exactly one server/case
  - collect logs
  - terminate only that PID
  - cleanup and verify no residue
- Always use `--no-mmap`.
- If system RAM used is `26GB+`, do not start a case.
- If system RAM used reaches `28GB+`, kill the active test PID and children.

## Task 1: Add FLASH_ATTN_EXT Head-Ratio Diagnostics

**Files:**
- Modify: `ggml/src/ggml-backend-meta.cpp`

- [ ] **Step 1: Add diagnostic helper near `handle_flash_attn_ext`**

Add a helper that logs:

```text
META_FA_HEAD_RATIO: tensor=<name> q_axis=<axis> k_axis=<axis> v_axis=<axis> q_ne=<...> k_ne=<...> v_ne=<...> q_part=<...> k_part=<...> v_part=<...> expected_q_per_kv=<...>
```

Use existing `buf_ctx->debug > 0` gating.

- [ ] **Step 2: Add ratio warning before existing ratio assert**

When Q and K are both split on the head axis, compute per-device:

```text
q_heads_on_device = split_state.ne[j]
kv_heads_on_device = src_ss[1].ne[...]
```

Warn if:

```text
q_heads_on_device * total_kv_heads != kv_heads_on_device * total_q_heads
```

- [ ] **Step 3: Verify static diff**

Run:

```powershell
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 4: Build**

Run:

```powershell
cmake --build C:\Users\berje\src\llama.cpp-b9222-gemma4-tensor-q8-mtp-eval\source\build-vs-cuda128 --config Release --target llama-server -- /m:6
```

Expected: `llama-server.exe` builds successfully.

- [ ] **Step 5: Commit**

```powershell
git add ggml/src/ggml-backend-meta.cpp
git commit -m "debug(gemma4): log tensor MTP FA head ratios"
```

## Task 2: Add MTP Attention Source Diagnostics

**Files:**
- Modify: `src/llama-graph.cpp`
- Modify: `src/llama-model.cpp`

- [ ] **Step 1: Log MTP attention mapping**

In `build_attn_mtp(...)`, log one line per assistant attention call under a debug env gate:

```text
GEMMA4_MTP_ATTENTION_MAP: il_mtp=<n> il_kv=<n> read_swa=<0|1> q_ne=<...> k_ne=<...> v_ne=<...> q_type=<...> k_type=<...> v_type=<...>
```

- [ ] **Step 2: Log split state for selected tensors**

In `llama_meta_device_get_split_state(...)`, only when debug is enabled and tensor name matches:

- `mtp.blk.*.attn_q.weight`
- `mtp.blk.*.attn_output.weight`
- `cache_k_l*`
- `cache_v_l*`

Log:

```text
META_SPLIT_TENSOR: name=<name> axis=<axis> ne={<per-device>} n_segments=<n> rotation=<n>
```

- [ ] **Step 3: Verify static diff**

Run:

```powershell
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 4: Build**

Run:

```powershell
cmake --build C:\Users\berje\src\llama.cpp-b9222-gemma4-tensor-q8-mtp-eval\source\build-vs-cuda128 --config Release --target llama-server -- /m:6
```

Expected: `llama-server.exe` builds successfully.

- [ ] **Step 5: Commit**

```powershell
git add src/llama-graph.cpp src/llama-model.cpp
git commit -m "debug(gemma4): trace attached MTP tensor split mapping"
```

## Task 3: Create Serial Diagnostic Runner

**Files:**
- Create: `scripts/run-gemma4-tensor-mtp-diagnostic.ps1`

- [ ] **Step 1: Implement preflight**

The script must:

- unload LM Studio models
- assert `lms ps --json` is empty
- fail if any `llama-server.exe`, `llama-cli.exe`, or `llama-bench.exe` exists
- check RAM used before starting

- [ ] **Step 2: Implement one-case runner**

The script must accept:

```powershell
-TensorSplit "1,1"
-KvType "f16" # or q8_0
-OutDir "<artifact-dir>"
```

It must start one hidden `llama-server.exe` with:

```powershell
--no-mmap --jinja -fa on -np 1 -c 16384 -b 160 -ub 160 -ngl 999 -sm tensor -ts <TensorSplit> -ctk <KvType> -ctv <KvType>
```

and MTP auto attach for the Gemma4 clone.

- [ ] **Step 3: Add RAM kill guard**

While the server is alive:

- if system RAM used reaches `28GB+`, kill server PID and children
- write `D-memory-redline` into the case log

- [ ] **Step 4: Add request smoke**

Send one request:

```text
Return exactly: OK
```

Expected:

- `1,1` should complete
- `9,6` and `8,7` may fail, but must produce diagnostic lines before failure

- [ ] **Step 5: Commit**

```powershell
git add scripts/run-gemma4-tensor-mtp-diagnostic.ps1
git commit -m "test(gemma4): add serial tensor MTP diagnostic runner"
```

## Task 4: Run Diagnostic Matrix

**Files:**
- Output only under `C:\Users\berje\src\llama.cpp-b9222-gemma4-tensor-q8-mtp-eval\artifacts\eval-20260519-gemma4-head-aware-tensor-split\`

- [ ] **Step 1: Run f16 matrix**

Run, strictly one after another:

```powershell
.\scripts\run-gemma4-tensor-mtp-diagnostic.ps1 -TensorSplit "1,1" -KvType "f16"  -OutDir "<artifact>\f16-ts11"
.\scripts\run-gemma4-tensor-mtp-diagnostic.ps1 -TensorSplit "9,6" -KvType "f16"  -OutDir "<artifact>\f16-ts96"
.\scripts\run-gemma4-tensor-mtp-diagnostic.ps1 -TensorSplit "8,7" -KvType "f16"  -OutDir "<artifact>\f16-ts87"
```

Expected:

- If f16 fails for `9,6`/`8,7`, the root cause is head partitioning, not q8.

- [ ] **Step 2: Run q8 matrix only if f16 diagnostics are understood**

Run, strictly one after another:

```powershell
.\scripts\run-gemma4-tensor-mtp-diagnostic.ps1 -TensorSplit "1,1" -KvType "q8_0" -OutDir "<artifact>\q8-ts11"
.\scripts\run-gemma4-tensor-mtp-diagnostic.ps1 -TensorSplit "9,6" -KvType "q8_0" -OutDir "<artifact>\q8-ts96"
.\scripts\run-gemma4-tensor-mtp-diagnostic.ps1 -TensorSplit "8,7" -KvType "q8_0" -OutDir "<artifact>\q8-ts87"
```

Expected:

- q8 should show the same class of head-ratio failure if the issue is split planning.

- [ ] **Step 3: Summarize**

Append a table to `docs/development/gemma4-gqa-tensor-internal-root-cause.md`:

```text
split | kv | q_heads/device | kv_heads/device | ratio valid | result
```

## Task 5: Implement Head-Aware Split Or Choose Fallback

**Files:**
- Modify: `src/llama-model.cpp`
- Modify: `ggml/src/ggml-backend-meta.cpp`
- Modify: `src/llama-graph.cpp`

- [ ] **Step 1: Decide from diagnostics**

If diagnostics show invalid Q/KV local head ratios, implement head-aware split.

If diagnostics show assistant tensor placement or q8-only reshape as root cause, stop and write a new defect-specific plan.

- [ ] **Step 2: Prototype head-aware split**

For Gemma4 attached MTP `FLASH_ATTN_EXT` only:

- derive KV head range per backend from target KV split state
- derive Q head range as `kv_range * gqa_ratio`
- reject impossible splits loudly

- [ ] **Step 3: Verify `1,1`, `9,6`, `8,7`**

Run f16 first, then q8 only if f16 passes.

Expected:

- no `META_RATIO_MISMATCH`
- accepted draft tokens > 0
- no output collapse

- [ ] **Step 4: If head-aware split is too invasive, implement assistant layer-mode hybrid**

Fallback rule:

- target may stay Tensor/Internal caller-wins
- assistant MTP FA must use layer/single-device-safe placement
- log `gemma4_mtp_tensor_fallback=assistant-layer`

- [ ] **Step 5: Commit**

Commit either:

```powershell
git commit -m "fix(gemma4): align tensor MTP GQA head splits"
```

or:

```powershell
git commit -m "fix(gemma4): route tensor target to layer-mode MTP assistant"
```

## Acceptance Criteria

- `ts=9,6` and `ts=8,7` no longer crash with `META_RATIO_MISMATCH`.
- f16/f16 Tensor/Internal + Gemma4 MTP accepts draft tokens.
- q8/q8 Tensor/Internal + Gemma4 MTP accepts draft tokens.
- q8/q8 Tensor/Internal + Gemma4 MTP beats q8 target-only by `10%+`, or is explicitly marked research-only with evidence.
- No model process residue after every case.
- System RAM never exceeds the redline without immediate kill.

## Non-Goals

- Do not tune `n-max` / `p-min` before head-ratio correctness is solved.
- Do not package LM Studio runtime before standalone passes.
- Do not silently relax meta-backend assertions.
- Do not run models in parallel.
