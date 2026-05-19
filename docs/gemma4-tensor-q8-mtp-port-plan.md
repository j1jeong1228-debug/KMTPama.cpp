# Gemma4 Tensor/Internal q8 KV + MTP Port Plan

Date: 2026-05-19

Branch: `berje/b9222-gemma4-tensor-q8-mtp`

Base: `llama.cpp b9222 / 9a532ae`

Fork remote: `https://github.com/j1jeong1228-debug/KMTPama.cpp.git`

## Goal

Port the useful local LM Studio / llama.cpp patches onto a fresh upstream base and turn the Gemma4 MTP work into a reviewable branch.

The target outcome is not just "Gemma4 MTP loads". The target is:

- Gemma4 target + official assistant MTP works.
- Tensor/Internal can remain enabled for the target.
- q8_0/q8_0 KV works with Tensor/Internal.
- MTP does not collapse acceptance or burn CPU through an external assistant loop.
- LM Studio Engine Protocol packaging remains possible after standalone validation.

## Fixed Local Context

Target clone:

`C:\Users\berje\.lmstudio\models\lmstudio-community\Gemma-4-31B-MTP-IQ4_XS\Gemma-4-31B-MTP-IQ4_XS.gguf`

Original Heretic target:

`C:\Users\berje\.lmstudio\models\lmstudio-community\gemma-4-31B-it-GGUF\Gemma-4-Garnet-V2-31B-it-ultra-uncensored-heretic.i1-IQ4_XS.gguf`

Assistant:

`C:\Users\berje\.lmstudio\models\Radamanthys11\Gemma-4-31B-it-assistant-GGUF\gemma-4-31B-it-assistant-Q8_0.gguf`

## Prior Local Results To Preserve

Previous working branch:

`C:\Users\berje\src\llama.cpp-b9190-qwen36-mtp-tensor-q8kv-lmstudio-eval\source`

Important prior artifact summaries:

- `artifacts\eval-20260518-gemma4-attached-mtp-runtime\RESULTS-SUMMARY.md`
- `artifacts\eval-20260519-gemma4-mtp-realistic-redesign\RESULTS-SUMMARY.md`

Key measured results from the prior branch:

| Case | Mode | Generation | Acceptance | CPU | Decision |
| --- | --- | ---: | ---: | ---: | --- |
| case05 | layer/q4 target-only | 18.80 tok/s | n/a | 5.36% | baseline |
| case06 | layer/q4 attached MTP | 37.00 tok/s | 0.66514 | 43.39% | speed win, CPU high |
| case26 | layer/q4 dedicated MTP | 42.76 tok/s | 0.66514 | 44.39% | historical best |
| current 16K | layer/q4 h_idx mapfix MTP | 36.91 tok/s | 0.66514 | 45.53% | current reproducible baseline |
| case22 | Tensor/Internal q8 target-only | 22.68 tok/s | n/a | 3.16% | target path OK |
| case21 | Tensor/Internal q8 MTP, tensor-compatible assistant | 9.77 tok/s | 0.14583 | 40.45% | reject |
| case35 | Tensor/Internal q8 target + layer assistant MTP | 27.56 tok/s | 0.66972 | 45.00% | research-only |

Main local conclusion:

Tensor/Internal q8 target-only works, but Gemma4 external assistant MTP is not adoption-grade in the old boundary. The winning path must be an attached target-owned assistant path that shares target KV and avoids treating the assistant as a generic external draft context.

## Upstream Changes To Absorb

The b9222 base already includes post-b9190 upstream changes. Still verify the following during port:

1. `#22673` MTP support
   - Mainline MTP infrastructure.
   - Good for Qwen-style in-GGUF MTP.
   - Not sufficient alone for Gemma4 external assistant checkpoints.

2. `#23198` MTP prompt logits-copy avoidance
   - Avoids copying logits during prompt decode when only pre-norm is needed.
   - Required to separate prompt-eval regression from generation bottleneck.

3. `#23256` pre-norm embedding mask initialization
   - Stabilization fix after `#23198`.
   - Required for b9200+ style MTP prompt handling.

4. `#23211` Gemma4 attached MTP assistant
   - Closed, not merged, but closest mainline-shaped skeleton.
   - Use as reference for `gemma4_assistant` architecture, attached assistant graph, common/server bridge, and CUDA FA shape support.

5. `#23225` split-mode tensor with quantized KV
   - Open.
   - Use as reference to replace older local q8 Tensor/Internal workarounds.
   - Important idea: preserve split-axis metadata through rotation path instead of flattening tensors in a way that breaks meta-backend tracking.

## Patch Groups To Port

Port in this order. Do not mix all old changes at once.

### Group A: Documentation and test scaffolding

- Keep this plan in-tree.
- Add runbook for serial-only testing.
- Add defect registry template.
- No model execution in this group.

### Group B: Tensor/Internal q8 KV foundation

Source references:

- Old local q8KV branch.
- `#23225`.

Target behavior:

- `-sm tensor`
- `GGML_CUDA_ALLREDUCE=internal`
- `-ctk q8_0 -ctv q8_0`
- fail loud for unsupported q4/mixed/TurboQuant KV in upstream-compatible branch.

Gate:

- Heretic or clone target-only Tensor/Internal q8 16K smoke.
- Qwen3.6 MTP q8 regression smoke, if build supports it.

### Group C: Gemma4 assistant loader and attached path

Source references:

- Old local `src/models/gemma4-mtp.cpp`.
- `#23211`.
- Atomic MTP documentation.
- vLLM Gemma4 MTP implementation notes.

Target behavior:

- `gemma4_assistant` / `gemma4_mtp` architecture is recognized.
- Assistant is target-owned, not a generic draft context.
- Assistant tokenizer, sampler, and KV are not duplicated.
- Assistant reads target KV read-only.
- In-graph argmax remains enabled.

Gate:

- layer/q4 standalone correctness first.
- `OK`, `Paris`, Korean one-sentence smoke.
- 16K 256/512 generation.
- 32K passkey only after 16K passes.

### Group D: CPU overhead reduction

Primary issue:

The old path still repeated assistant graph execution/synchronization per draft block. Full logits copy was no longer the main bottleneck.

Port/implement:

- target-owned MTP service boundary
- persistent scheduler/result graph cache
- accurate `h_idx` contract
- optional async depth-2 pipeline only after sync correctness

Reject:

- block2/block3 graph unroll that reduces sync count but lowers wall tok/s.
- any change that lowers CPU while also lowering tok/s below the current reproducible baseline.

### Group E: LM Studio Engine Protocol packaging

Only after standalone passes:

- package as a separate Engine Protocol runtime
- clone model auto-attach only
- GUI split/KV/batch/mmproj caller-wins
- original Heretic and Qwen runtime unchanged

## Safety Rules

- Never run two models in parallel.
- Every model case must be: unload, preflight, one case, collect, cleanup.
- If system RAM used is 26GB or higher, do not start a new model case.
- If system RAM used is 28GB or higher, kill only the active test PID and its children.
- Keep `--no-mmap` for local model tests unless explicitly testing mmap.
- Do not use LM Studio runtime packaging until standalone passes.

## GitHub Update Plan

This branch should first be pushed to the user's fork:

`j1jeong1228-debug/KMTPama.cpp`

Draft PR scope:

- Base: upstream `ggml-org/llama.cpp` or fork `master`, depending on final intent.
- Initial PR title:
  `WIP: Gemma4 attached MTP + Tensor/Internal q8 KV experiments`
- Initial PR status:
  draft / research branch

Do not open an upstream PR until:

- patches are split into reviewable commits
- standalone tests pass
- Tensor/Internal q8 + MTP has an adoption-grade result
- local-only LM Studio hooks are separated from upstreamable code

## Open Defects

- `D-gemma4-external-loop`: old assistant loop remains CPU-heavy.
- `D-tensor-q8-acceptance-collapse`: pure Tensor/Internal q8 assistant path collapsed acceptance.
- `D-lmstudio-engine-gap`: LM Studio draft-model UI does not support native draft speculative decoding through Engine Protocol.
- `D-template-channel`: raw Gemma4 template output can include thought/channel artifacts; track separately from MTP.
- `D-baseline-drift`: historical 42.76 tok/s is not always reproduced; current corrected baseline is closer to 36-37 tok/s.

