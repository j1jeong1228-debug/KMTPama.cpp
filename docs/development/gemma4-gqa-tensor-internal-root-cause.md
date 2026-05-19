# Gemma4 Tensor/Internal GQA Split Root Cause

Date: 2026-05-19
Branch: `berje/b9222-gemma4-tensor-q8-mtp`

## Goal

Explain why Gemma4 attached MTP works with Tensor/Internal `1,1` but fails with uneven splits such as `9,6` and `8,7`, and identify the most realistic fix candidates.

## Confirmed Local Symptom

Representative failure:

```text
META_RATIO_MISMATCH: tensor=node_21 op=FLASH_ATTN_EXT axis=1 ne=32 src=1 src_name=cache_k_l58 (view) (permuted) src_axis=2 src_ne=16 dst_part=16 src_part_sum=10 device=0
GGML_ASSERT(split_state.ne[j] * tensor->src[i]->ne[src_ss[i].axis] == sum * tensor->ne[split_state.axis]) failed
```

Interpretation:

- `FLASH_ATTN_EXT` output/Q side has 32 Q heads.
- Target KV cache side has 16 KV heads.
- With `ts=9,6`, device 0 gets 16 Q-side output heads but 10 KV heads.
- The required GQA ratio is therefore not preserved on the device-local shard.

`1,1` works because equal split accidentally preserves the local Q:KV ratio:

- Q heads: `16 + 16`
- KV heads: `8 + 8`
- ratio: `2:1` on both devices

`9,6` and `8,7` fail because independent proportional rounding creates invalid local ratios:

- example: Q `16` vs KV `10`, not `20` vs `10`.

## Why This Happens

Gemma4 attached MTP does not have its own K/V projections. The assistant builds Q and cross-attends into the target model's K/V cache.

Local code path:

- Assistant Q is built in `src/models/gemma4-assistant.cpp`.
- MTP attention calls `build_attn_mtp(...)`.
- `build_attn_mtp(...)` reads target K/V with `mctx_cur->get_k(...)` and `mctx_cur->get_v(...)`.
- `ggml-backend-meta.cpp` requires Q/K/V to have compatible split states in `FLASH_ATTN_EXT`.

The currently fixed split metadata patch correctly handles `mtp.blk.*` assistant tensors, which restores acceptance for `ts=1,1`. But it does not make uneven GQA head partitions valid.

The remaining problem is not "q8 KV parsing" and not "assistant tensor is mirrored". It is that the split metadata currently represents tensor proportional partitions, while Gemma4 GQA requires head-group partitions:

```text
device-local Q heads == gqa_ratio * device-local KV heads
```

For Gemma4 MTP that invariant must hold for the target KV layer selected by the assistant layer.

## External References Checked

### llama.cpp multi-GPU docs

The upstream multi-GPU docs mark Tensor Parallelism as experimental and state that `--flash-attn` is required for tensor mode. They also document that quantized KV cache with tensor mode is not implemented in upstream mainline yet.

Source: https://github.com/ggml-org/llama.cpp/blob/master/docs/multi-gpu.md

Relevance:

- Confirms that our q8 Tensor/Internal work is beyond upstream's stable documented path.
- Confirms `-fa off` is not a valid workaround for tensor mode.

### llama.cpp PR #23225

Source: https://github.com/ggml-org/llama.cpp/pull/23225

Local diff inspection shows this PR mainly:

- Removes the hard guard against quantized KV with tensor split.
- Adds a meta-backend case for `MIRRORED x AXIS_2/AXIS_3`.
- Adjusts reshape behavior for auxiliary matmul paths.

Relevance:

- Useful foundation for Tensor/Internal q8 KV.
- Does not solve Gemma4 attached MTP uneven GQA head partitioning.

### llama.cpp PR #23211

Source: https://github.com/ggml-org/llama.cpp/pull/23211

The PR adds Gemma4 attached assistant MTP and notes CUDA flash-attention coverage for a D512/GQA=2 Gemma4 assistant shape.

Relevance:

- Strong reference for attached MTP boundaries and assistant graph design.
- The D512/GQA=2 FA support is shape/kernel coverage, not a multi-GPU uneven tensor split solution.

### AtomicBot MTP

Source: https://github.com/AtomicBot-ai/atomic-llama-cpp-turboquant/blob/feature/turboquant-kv-cache/MTP.md

Atomic's design emphasizes:

- Single context.
- Assistant attached to the target model.
- No draft-side KV cache.
- Assistant cross-attends into target KV.
- Dedicated MTP scheduler, async pipeline, in-graph argmax.

Relevance:

- Confirms the architecture we want for Gemma4 MTP.
- Does not document arbitrary Tensor/Internal `9,6` or `8,7` GQA split support.

### ik_llama.cpp Gemma4 MTP PR #1744

Source: https://github.com/ikawrakow/ik_llama.cpp/pull/1744

Reported working Gemma4 MTP implementations exist, but the relevant public signal is that graph split support can be achieved while keeping MTP in a safer layer-mode path.

Relevance:

- Good fallback direction: main model may use graph/tensor style split while assistant path avoids invalid Tensor/Internal attention partitioning.

### vLLM Gemma4 MTP

Sources:

- https://docs.vllm.ai/en/latest/features/speculative_decoding/mtp/
- https://docs.vllm.ai/en/v0.21.0/api/vllm/v1/spec_decode/gemma4/

vLLM treats Gemma4 MTP as a special path with target KV sharing and attention-group/block-table management.

Relevance:

- Strongest conceptual reference for the real fix.
- The lesson is to model KV ownership explicitly by attention group, not infer it from generic tensor proportional split.

## Candidate Fixes

### Candidate A: Head-Aware Tensor/Internal Split

Goal:

- Make the meta backend understand that Gemma4 MTP FA must split Q by KV-head ownership.
- Ensure each device gets `Q_heads = gqa_ratio * KV_heads`.

Pros:

- Directly solves `9,6` and `8,7`.
- Preserves Tensor/Internal intent.
- Best long-term fit for GUI split control.

Cons:

- Requires careful split-state metadata changes and tests.
- Must not silently break target-only tensor mode or Qwen internal MTP.

First diagnostic before implementation:

- Log Q/K/V per-device head counts in `handle_flash_attn_ext`.
- Log assistant layer, selected target KV layer, and `read_swa` in `build_attn_mtp`.
- Add a hard diagnostic assertion:

```text
q_heads_on_device == gqa_ratio * kv_heads_on_device
```

### Candidate B: Assistant Layer-Mode Hybrid

Goal:

- Keep target Tensor/Internal active where useful.
- Route Gemma4 MTP assistant attention through a layer/single-device-safe path.

Pros:

- Most likely short-term stable path.
- Matches public evidence that some forks avoid making MTP itself tensor-parallel.

Cons:

- May not fully exploit two GPUs.
- May keep some CPU/scheduler overhead.
- Needs careful target KV access boundary.

### Candidate C: Force Tensor/Internal `1,1`

Goal:

- Keep only the split that is known to preserve ratio.

Pros:

- Safe control path.
- Already works after the `mtp.blk.*` split metadata fix.

Cons:

- Does not solve user's desired `9,6` / `8,7` GUI split use case.
- Current q8 MTP is only parity with target-only.

### Candidate D: Gather/Mirror KV Before FA

Goal:

- Give each Q shard all KV heads needed for local FA.

Pros:

- Semantically safe if implemented explicitly.

Cons:

- Likely erases q8/tensor memory-bandwidth gains.
- Adds communication and complexity.

### Candidate E: Distributed Flash Attention Softmax

Goal:

- Let devices compute attention over split KV shards and combine softmax correctly.

Pros:

- Theoretically general.

Cons:

- Large kernel/runtime project.
- Overkill for a head partition mismatch.
- Not the right first patch.

## Recommended Order

1. Add head-ratio diagnostics and prove the exact Q/KV local head mismatch.
2. Implement head-aware split planning for Gemma4 attached MTP FA.
3. If head-aware split becomes too broad, implement assistant layer-mode hybrid as a practical fallback.
4. Keep `1,1` as a control path.
5. Do not attempt KV gather or distributed FA until A/B fail.

## Decision

The next implementation task should be diagnostic-first head-aware split work, not further `n-max`, `p-min`, or q8 tuning.
