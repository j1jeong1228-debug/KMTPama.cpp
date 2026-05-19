# Gemma4 Tensor/Internal q8 KV + MTP Port Inventory

Date: 2026-05-19

Branch: `berje/b9222-gemma4-tensor-q8-mtp`

This document records the read-only subagent review used to decide how to port the older local b9190 patches onto b9222.

No model process was run for this inventory.

## Current Branch State

Worktree:

`C:\Users\berje\src\llama.cpp-b9222-gemma4-tensor-q8-mtp-eval\source`

Base:

`b9222 / 9a532ae`

Initial planning commit:

`0614d3b docs: plan Gemma4 tensor q8 MTP port`

Fork remote:

`https://github.com/j1jeong1228-debug/KMTPama.cpp.git`

## What b9222 Already Has

### Generic / Qwen-style MTP

`#22673` is present.

Important files and symbols:

- `include/llama.h`
  - `LLAMA_CONTEXT_TYPE_MTP`
  - `llama_context_params::ctx_type`
- `common/common.h`
  - `COMMON_SPECULATIVE_TYPE_DRAFT_MTP`
- `common/arg.cpp`
  - HF sidecar MTP discovery
  - `spec_type_draft_mtp`
- `common/speculative.cpp`
  - `common_speculative_state_draft_mtp`
- `src/llama-context.cpp`
  - MTP context maps to `LLM_GRAPH_TYPE_DECODER_MTP`
- `src/models/qwen35.cpp`
- `src/models/qwen35moe.cpp`
  - `nextn_predict_layers`
  - `graph_mtp`
  - `nextn.*` tensors
- `conversion/qwen.py`
  - Qwen MTP conversion mixin

Implication:

Do not blindly port old Qwen MTP changes. Treat b9222 as the owner of the generic Qwen/pre-norm MTP path and add only local compatibility glue if needed.

### MTP Prompt Pre-Norm Fixes

`#23198` is present.

Important files and symbols:

- `common/speculative.cpp`
  - `need_embd_pre_norm()`
- `common/speculative.h`
  - `common_speculative_need_embd_pre_norm`
- `src/llama-context.cpp`
  - pre-norm extraction path
- `src/llama-graph.cpp`
  - `llm_graph_result::set_outputs()` includes `t_h_pre_norm`
- `tools/server/server-context.cpp`
  - server-side `need_embd_pre_norm()`

`#23256` is present.

Important file and symbol:

- `src/llama-context.cpp`
  - `cparams.embeddings_pre_norm_masked = false`

Implication:

The b9190-era prompt-eval regression fix should not be reimplemented wholesale. Port only Gemma4-specific hidden-row mapping if still needed after attached MTP is added.

## What b9222 Does Not Have

### Gemma4 Attached Assistant MTP

`#23211`-style Gemma4 assistant support is not present.

Missing or needing local port:

- `common/mtp.cpp`
- `common/mtp.h`
- `src/models/gemma4-assistant.cpp`
- `src/llama-arch.h`
  - add `LLM_ARCH_GEMMA4_ASSISTANT`
  - add assistant tensor IDs
- `src/llama-model.h`
  - add attached assistant model storage and assistant tensors
- `src/llama.cpp`
  - add assistant loading / attached MTP helper bridge
- `common/speculative.cpp`
  - add attached MTP state and dispatch
- `src/llama-context.cpp`
  - add Gemma4 assistant decode path
- `src/llama-graph.h`
  - add MTP graph input / assistant attention builders
- `src/llama-kv-cache-iswa.cpp`
  - add MTP view into target iSWA KV
- `src/llama-kv-cache.cpp`
  - add MTP slot info access
- `gguf-py/gguf/constants.py`
  - add `GEMMA4_ASSISTANT` architecture and tensor mapping if converter support is in scope

Implication:

Gemma4 must not be treated as the old generic external draft model. The local target should become target-owned attached assistant MTP.

### Tensor/Internal Quantized KV

`#23225`-style split-mode tensor quantized KV support is not present.

Still visible blockers in b9222:

- `src/llama-context.cpp`
  - still rejects `SPLIT_MODE_TENSOR` with quantized KV
- `ggml/src/ggml-backend-meta.cpp`
  - missing split-state propagation for mirrored rotation matrices on axis 2/3
- `src/llama-graph.cpp`
  - `ggml_mul_mat_aux` still goes through a 2D reshape/cont path
- `src/llama-kv-cache.cpp`
  - KV rotation helper still uses a similar 2D reshape path

Implication:

The old local q8 KV patch should be compared against `#23225` and likely replaced with the cleaner split-axis metadata preservation strategy.

## Old b9190 Patch Inventory

Old working tree:

`C:\Users\berje\src\llama.cpp-b9190-qwen36-mtp-tensor-q8kv-lmstudio-eval\source`

Local tracked delta vs b9190:

- 31 tracked files
- about 3012 insertions
- about 89 deletions

Untracked but important:

- `common/mtp.cpp`
- `common/mtp.h`
- `src/models/gemma4-mtp.cpp`
- `scripts/run-gemma4-mtp-target-loop-case.ps1`
- `docs/superpowers/plans/...`

### Patch Group 1: Tensor/Internal q8 KV

Files:

- `common/arg.cpp`
- `ggml/src/CMakeLists.txt`
- `ggml/src/ggml-backend-meta.cpp`
- `src/llama-kv-cache.cpp`
- `src/llama-kv-cache.h`
- `src/llama-kv-cache-iswa.cpp`
- `src/llama-kv-cache-iswa.h`
- `src/llama-graph.cpp`
- `src/llama-graph.h`
- `src/llama-context.cpp`
- `src/llama-context.h`
- `src/llama-cparams.h`
- `src/llama-model.h`

Risk:

Very high. `ggml/src/ggml-backend-meta.cpp` and KV helpers are scheduler/meta correctness code, not cosmetic option plumbing.

### Patch Group 2: Qwen MTP compatibility

Files:

- `common/arg.cpp`
- `common/speculative.cpp`
- `common/speculative.h`
- `src/models/qwen35.cpp`
- `src/models/qwen35moe.cpp`
- `src/llama-context.cpp`
- `src/llama-cparams.h`
- `src/llama-ext.h`

Risk:

High conflict with b9222 because upstream already moved the MTP/pre-norm path forward.

### Patch Group 3: Gemma4 assistant / attached MTP

Files:

- `common/CMakeLists.txt`
- `common/common.cpp`
- `common/common.h`
- `common/mtp.cpp`
- `common/mtp.h`
- `common/speculative.cpp`
- `common/speculative.h`
- `include/llama.h`
- `src/llama.cpp`
- `src/llama-arch.cpp`
- `src/llama-arch.h`
- `src/llama-context.cpp`
- `src/llama-context.h`
- `src/llama-graph.cpp`
- `src/llama-graph.h`
- `src/llama-hparams.h`
- `src/llama-model.cpp`
- `src/llama-model.h`
- `src/models/gemma4.cpp`
- `src/models/gemma4-mtp.cpp`
- `src/models/models.h`
- `tools/server/server-context.cpp`

Risk:

Highest. This is one behavioral unit and should be ported as a deliberately staged feature, not cherry-picked file by file.

### Patch Group 4: LM Studio integration

Files:

- `common/arg.cpp`
- `common/common.cpp`
- `tools/server/server-context.cpp`
- `ggml/src/CMakeLists.txt`
- `scripts/run-gemma4-mtp-target-loop-case.ps1`

Risk:

Medium-high. Useful locally, not upstream-clean as-is due to hard-coded local Windows paths and LM Studio-specific config reading.

### Patch Group 5: Template / Jinja

File:

- `models/templates/google-gemma-4-31B-it.jinja`

Risk:

Medium. Isolated but prompt-sensitive. Use explicit template artifacts and parser tests before changing runtime behavior.

## Recommended Port Order

1. Keep b9222 generic MTP and pre-norm code intact.
2. Add docs, local runbooks, and defect registry.
3. Add Gemma4 assistant architecture and loader metadata.
4. Add standalone Gemma4 assistant graph and attached target-owned decode path.
5. Add common/server bridge for attached MTP.
6. Validate standalone layer/q4 correctness before touching Tensor/Internal.
7. Port Tensor/Internal q8 KV using `#23225` as the main shape, not the older ad hoc patch shape.
8. Re-enter LM Studio Engine Protocol packaging only after standalone Tensor/Internal q8 + MTP is viable.

## Draft PR Summary

Title:

`WIP: Gemma4 attached MTP + Tensor/Internal q8 KV experiments`

Scope:

- Documentation and research branch first.
- Port Gemma4 attached assistant MTP onto b9222.
- Rework Tensor/Internal q8 KV support against the new split-axis metadata strategy.
- Preserve Qwen MTP behavior from upstream b9222.

Non-goals:

- No upstream PR until local-only LM Studio hooks are isolated.
- No model-card/profile mutation.
- No parallel model execution.
- No q4/mixed/TurboQuant KV in the first upstream-shaped branch.

