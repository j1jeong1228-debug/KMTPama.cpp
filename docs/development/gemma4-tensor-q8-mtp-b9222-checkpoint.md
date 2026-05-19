# Gemma4 Tensor/Internal q8 KV + MTP b9222 Checkpoint

Date: 2026-05-19
Branch: `berje/b9222-gemma4-tensor-q8-mtp`

## Summary

This checkpoint fixes a correctness issue in Gemma4 attached MTP under Tensor/Internal split mode, but it does not yet meet the performance adoption gate.

The important finding is that `mtp.blk.*` assistant tensors need the same split metadata handling as target `blk.*` tensors. Without that, assistant weights are treated as mirrored in places where they need tensor-compatible split state. That can make the graph run but causes draft acceptance to collapse.

## Patch

- `src/llama-model.cpp`
  - Add optional `mtp.` prefix support to split metadata regexes.
  - Parse `mtp.blk.<layer>.` tensor prefixes before suffix lookup.
- `ggml/src/ggml-backend-meta.cpp`
  - Keep strict split compatibility checks.
  - Add diagnostics for split mismatch and ratio mismatch cases.
  - Fix split-state debug logging so each source tensor is inspected correctly.

## Measured State

| Case | Split / KV | MTP | tok/s | CPU all-core | Accepted / Draft | Result |
| --- | --- | --- | ---: | ---: | ---: | --- |
| pre-fix f16 MTP | tensor `1,1`, f16/f16 | on | 9.894 | 47.59% | 0 / 507 | broken |
| post-fix f16 MTP | tensor `1,1`, f16/f16 | on | 18.623 | 46.18% | 61 / 132 | fixed acceptance |
| post-fix q8 MTP | tensor `1,1`, q8/q8 | on | 16.130 | 45.75% | 60 / 134 | fixed acceptance |
| q8 target-only | tensor `1,1`, q8/q8 | off | 16.984 | 3.89% | n/a | baseline |
| q8 MTP | tensor `1,1`, q8/q8 | on | 16.949 | 46.99% | 124 / 259 | parity only |

The best q8 Tensor/Internal MTP case is effectively parity with target-only (`-0.21%`). It is not an adoption candidate.

## Open Defects

### D-tensor-mtp-uneven-gqa-split

`tensor 9,6` and `tensor 8,7` still fail with Flash Attention ratio mismatch. Representative diagnostic:

```text
META_RATIO_MISMATCH: tensor=node_21 op=FLASH_ATTN_EXT axis=1 ne=32 src=1 src_name=cache_k_l58 (view) (permuted) src_axis=2 src_ne=16 dst_part=16 src_part_sum=10 device=0
```

This points to a Gemma4 GQA head partitioning problem: uneven tensor splits do not preserve the required Q-head to KV-head ratio.

### D-tensor-q8-mtp-overhead

`tensor 1,1 + q8 + MTP` now accepts draft tokens, but assistant graph overhead cancels the gain. CPU remains around `46-47%` all-core in MTP runs.

## Recommendation

Do not package an LM Studio runtime from this checkpoint.

Next engineering work should be one of:

1. Implement head-aware Tensor/Internal splitting for Gemma4 GQA so `9,6` and `8,7` become legal.
2. Reduce Gemma4 assistant graph overhead so `tensor 1,1 + q8 + MTP` beats q8 target-only.

Until then, keep this patch as a correctness foundation and treat Tensor/Internal q8 Gemma4 MTP as research-only.
