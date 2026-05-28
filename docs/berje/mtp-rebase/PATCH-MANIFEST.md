# b9374 Gemma4/Qwen MTP Rebase Patch Manifest

Base: upstream `ggml-org/llama.cpp` tag `b9374` (`491c4d7`).

This rebase intentionally does not copy the old b9294/b9222 trees as a blob. Each patch must be classified as one of:

- `keep`: required for the current objective.
- `upstream`: already present in b9374 and must not be duplicated.
- `research`: useful for isolated experiments, not a runtime default.
- `reject`: measured and not kept.

## Accepted Baselines To Preserve

These are the b9294 attached-MTP controls that the new fork must reproduce or beat before LM Studio packaging:

| Scope | Artifact | Prompt tokens | Generation | Acceptance | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| long29K best | `long65k-batiai-atomic-q4-broadoverride-nmax4-noargmax-margin010-160-20260526` | 28936 | 31.57 tok/s | 107/205 = 0.52195 | split `12,3`, nmax4, AtomicChat Q4 assistant, q4/q4 draft KV |
| long29K runtime-safe | `long65k-batiai-atomic-q4-broadoverride-polloff-nmax4-noargmax-margin010-160-20260526` | 28936 | 31.20 tok/s | 107/205 = 0.52195 | same as above, poll off |
| true32K fitted | `true32k-q4kv-ctx36864-b32-control64-20260526` | 33936 | 29.87 tok/s | 42/71 = 0.59155 | ctx 36864, batch/ubatch 32 |
| true32K confirm | `long65k-batiai-atomic-q4-true32k-depthyield-confirm-nmax4-margin010-160-20260526` | 36436 | 28.71 tok/s | 96/151 = 0.63576 | 160-token confirmation |

Correction: the 31.57/31.20 tok/s records are long29K-ish, not true32K+. The true32K+ hard evidence is 29.87/28.71 tok/s.

The preserved runtime bundle is not just "MTP attaches". It includes the conditions that produced the accepted b9294 records:

- target: `batiai/gemma-4-31B-it-IQ4_XS`
- assistant: `AtomicChat/gemma-4-31B-it-assistant.Q4_K_M`
- split: layer `12,3` after confirming llama.cpp device ordering
- target KV and draft KV: `q4_0/q4_0`
- draft request: `n_max=4`, `p_min=0`
- CPU sanity: target and draft `poll=0`
- draft tensor override: `(mtp_pre_proj|mtp.pre_projection|nextn.pre_projection).weight=CUDA1,token_embd.weight=CUDA1`
- long-context env: `LLAMA_GEMMA4_MTP_LONGCTX_THRESHOLD=32768`
- long-context graph margin: `LLAMA_GEMMA4_MTP_LONGCTX_GRAPH_MARGIN_MIN=0.10`
- b9374 prompt-length draft caps:
  - short `< 16384`: effective `n_max=2`
  - mid `[16384, 32768)`: effective `n_max=3`
  - long `>= 32768`: effective `n_max=4` plus depth-yield controller
- true32K+ accepted improvement: `LLAMA_GEMMA4_MTP_DEPTH_YIELD_CONTROLLER=1` with min samples 16

If any of the above is missing from standalone or LM Studio logs, the run is not equivalent to the b9294 best/control artifacts even if `draft-mtp` attaches.

Harness contract:

- `scripts/berje/run-b9374-gemma4-mtp-benchmark.ps1 -Case long29k` must reproduce the long29K profile: ctx `65536`, batch/ubatch `160`, max `160`, expected prompt around `28936`.
- `-Case true32k-fitted` must reproduce the fitted true32K control: ctx `36864`, batch/ubatch `32`, max `64`, expected prompt around `33936`.
- `-Case true32k-confirm` and the `true32k` alias must reproduce the 160-token true32K+ confirmation: ctx `65536`, batch/ubatch `160`, max `160`, expected prompt around `36436`.

Do not compare b9374 to the b9294 true32K controls using the wrong ctx/batch/max-token profile. That was the easiest way to misclassify a harness mismatch as an MTP algorithm failure.

Gate correction: preserving the b9294 controls means more than passing the tok/s threshold. The benchmark result must keep separate `tok_s_gate_pass` / `tok_s_preferred_pass` fields, and final `gate_pass` must also require:

- acceptance no worse than baseline by more than `0.03`
- draft generated count not inflated by more than `10%` against the matching baseline
- passkey present at the response prefix
- attached `draft-mtp` evidence in the server log
- CPU all-core sanity under the configured ceiling
- for traced true32K confirmation runs, a visible depth-yield decision line

This prevents a newer run from being accepted only because tok/s improved while MTP acceptance/depth-yield behavior regressed.

Current true32K preservation status is tracked in `DEFECTS.md`. The old b9294 acceptance floor remains useful as a warning signal, but it is no longer sufficient as a standalone failure proof after target-only comparison showed a deterministic target trajectory change: b9294 target-only starts with `ZX-TS87-QWEN`, while b9374 target-only and b9374 attached MTP start with `PASSKEY: ZX-TS87-QWEN` for the same 36,436-token request. The b9374 true32K gate therefore needs current-target-path calibration before final acceptance.

Harness policy after the target-path finding: true32K confirm keeps `historical_acceptance_gate_pass` and `historical_draft_generated_gate_pass` for b9294 comparison, but uses `current_path_acceptance_floor = 0.50` for the current b9374 target trajectory. This preserves the old evidence without misclassifying a target-only trajectory change as an attached-MTP correctness failure.

Current Qwen status is also tracked in `DEFECTS.md`. The LM Studio API/proxy reasoning-only failure was fixed by making Qwen Tensor/Internal q8 native MTP auto default to reasoning off unless `LMSTUDIO_QWEN_MTP_KEEP_REASONING` is set. A later current-state retake showed that `lms load qwen3.6-27b-mtp` could pass q8/q8 KV while argv still contained `--tensor-split 0`, which bypassed Qwen auto. The runtime now treats Qwen3.6 q8/q8 + `kv-unified` as the Tensor/Internal request and repairs missing tensor split to `9,6` before enabling native MTP. Current accepted LM Studio evidence is `artifacts/lmstudio-b9374-qwen36-q8-mtp-currentverify-20260529-4`.

## Keep: Gemma4 Attached-MTP

Primary missing patch family:

- b9294 dedicated attached-MTP execution engine:
  - `common/mtp.cpp`
  - `common/mtp.h`
  - `common/speculative.cpp` path calling `common_mtp_decode*`
  - `src/llama-context.cpp/.h` `process_ubatch_mtp`, `decode_mtp*`, `graph_compute_mtp`
  - `src/llama-ext.h` staging MTP APIs
  - build-system registration
  - Gemma4 target graph `t_h_pre_norm` exposure gated by `embeddings_pre_norm`
- Gemma4 assistant architecture/loader support:
  - `gemma4_assistant` / `gemma4-assistant` arch alias
  - assistant metadata fallback for `nextn_predict_layers` and backbone embedding size
  - tensor aliases for `nextn.pre_projection`, `mtp.pre_projection`, `mtp_pre_proj`, and matching post-projection names
- b9294 default bundle preservation:
  - Gemma4-only explicit/auto attached-MTP defaults in `common/arg.cpp`
  - broad pre-projection override including `nextn.pre_projection`
  - target/draft `poll=0`
  - short cap `2`, mid cap `3`, long cap `4`, and true32K depth-yield controller
  - stale rejected row0/adaptive fallbacks cleared from auto path
- server long-context draft controller:
  - record per-depth draft acceptance
  - apply `LLAMA_GEMMA4_MTP_DEPTH_YIELD_CONTROLLER` only above `LLAMA_GEMMA4_MTP_LONGCTX_THRESHOLD`
  - keep default `LLAMA_GEMMA4_MTP_DEPTH_YIELD_MIN_SAMPLES=16`

Why this is first priority: recent upstream generic `draft-mtp` can attach and can even show higher long acceptance than b9294, but the b9371 transition retakes remained slower in long generation. The lost performance is therefore not explained by acceptance alone; the missing structural execution path is the primary gap.

## Upstream: Do Not Duplicate

b9374 already contains Qwen native/internal MTP graph work:

- `src/models/qwen35.cpp`
- `src/models/qwen35moe.cpp`
- `LLM_GRAPH_TYPE_DECODER_MTP`
- `blk.%d.nextn.*` tensor mapping and MTP draft-head graph code

These should be preserved and verified, not reimplemented.

## Keep: Qwen Tensor/Internal q8

b9374 still rejects tensor split plus quantized KV globally. The Qwen path needs a guarded allowlist:

- Allow only `QWEN35` / `QWEN35MOE` with `q8_0/q8_0` KV, or an explicit experimental env override.
- Keep Gemma4 q4/layer baseline on `tensor_request=false`; do not globally disable Tensor/Internal because Qwen needs it.
- Preserve backend-meta split-state fixes required for tensor-parallel q8 KV routing.

Current standalone smoke evidence:

- Artifact: `b9374-qwen36-native-mtp-q8-currentverify-20260529-2`
- Model: `Qwen3.6-27B-uncensored-heretic-v2-Native-MTP-Preserved-Q4_K_S.gguf`
- Command path: `-sm tensor -ts 9,6 -ctk q8_0 -ctv q8_0 --spec-type draft-mtp`, no separate draft model.
- Logs confirmed `creating MTP draft context against the target model`, `adding speculative implementation 'draft-mtp'`, `ctx_tgt=yes`, `ctx_dft=yes`, and MTP context `cache_k=q8_0`, `cache_v=q8_0`.
- Logs confirmed Gemma auto path did not run.
- Result: `41.17 tok/s`, acceptance `19/23 = 0.82609`, content non-empty, `gate_pass=true`.
- Warning to track before LM Studio packaging: `llama_params_fit is not implemented for SPLIT_MODE_TENSOR` and backend sampling falls back to CPU under `SPLIT_MODE_TENSOR`. This does not block the smoke, but it is not a final performance acceptance.

Current LM Studio Qwen evidence:

- Artifact: `lmstudio-b9374-qwen36-q8-mtp-currentverify-20260529-4`
- Load path: `lms load qwen3.6-27b-mtp -c 4096 --gpu max`.
- Command line still showed `--tensor-split 0`, but runtime log confirmed Qwen Tensor/Internal repair: `LMSTUDIO_QWEN_MTP_AUTO ... tensor_split=9,6 ... reasoning=off-by-default`.
- Logs confirmed `creating MTP draft context against the target model` and `adding speculative implementation 'draft-mtp'`.
- Result: q8/q8 KV, `kv-unified`, native MTP, proxy content non-empty, proxy `reasoning_tokens=0`, backend direct content non-empty, `gate_pass=true`.

## Keep: General Target-Only Clean Path

Current standalone smoke evidence:

- Artifact: `b9374-target-only-qwen2-currentverify-20260529-2`
- Model: `spec-drafts/qwen2-1_5b-instruct-q4_0.gguf`
- Command path did not request speculative decoding or Tensor/Internal.
- Logs/result confirmed no Gemma auto attach, no `draft-mtp`, no MTP context, no Qwen Tensor/Internal allowlist path, and normal generation completed.
- Result: `209.91 tok/s`, content non-empty, `gate_pass=true`.

Current LM Studio target-only evidence:

- Artifact: `lmstudio-b9374-targetonly-gemma26-currentverify-20260529-3`
- Model: `google/gemma-4-26b-a4b`
- Request path: raw `/v1/completions` smoke to avoid chat-template reasoning noise.
- Logs/result confirmed `no implementations specified for speculative decoding`, no attached MTP assistant, no Gemma auto, no Qwen auto, content non-empty, CPU all-core `0.74%`, `gate_pass=true`.

## b9374 Gemma4 Gate Evidence

The first b9374 port preserved attach but failed the b9294 long29K gate at `27.99 tok/s`, with acceptance dropping to `93/260 = 0.35769`. A transaction-probe run showed that the first 64 generated tokens were healthy (`35.52 tok/s`, `42/74 = 0.56757`), while the 160-token tail collapsed (`after20 windows = 0.27778`, tail20 = 0.2375). The root cause was not MTP attach failure; it was over-deep `n_max=4` drafting for the b9374 mid-context output path.

The accepted b9374 correction is a Gemma4-only prompt-length draft cap:

| Artifact | Prompt tokens | Requested n_max | Effective cap | Generation | Acceptance | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `b9374-gemma4-short16k-currentpath-gated-20260529-1` | 14336 | 4 | short -> 2 | 34.55 tok/s | 87/156 = 0.55769 | hard pass |
| `b9374-gemma4-long29k-currentpath-gated-20260529-1` | 28936 | 4 | mid -> 3 | 32.27 tok/s | 96/183 = 0.52459 | preferred pass |
| `b9374-gemma4-true32k-fitted-currentpath-gated-20260529-1` | 33936 | 4 | long -> 4 | 32.47 tok/s | 41/72 = 0.56944 | preferred pass |
| `b9374-gemma4-true32k-confirm-currentpath-gated-20260529-1` | 36436 | 4 | long -> 4 | 29.46 tok/s | 98/184 = 0.53261 | current-path hard pass; historical acceptance warning |

This is not a thread rightsize workaround. It keeps the same target/draft models, split, q4/q4 KV, poll-off state, and attached-MTP path, but avoids wasting target verify rows after mid-context acceptance begins to decay.

Target-path caveat: `artifacts/b9374-gemma4-true32k-target-drift-analysis-20260529-1/analysis.json` confirms that b9374 target-only differs from b9294 target-only on the same true32K request, while b9374 attached MTP follows the b9374 target-only prefix. This makes the old b9294 true32K acceptance profile a historical control rather than a direct correctness oracle for the latest fork.

## Research / Reject

Do not promote these as runtime defaults without new evidence:

- #23398/source-KV Gemma4 path: booted, but measured true32K results did not beat b9294 controls.
- Source-KV plus depth-yield: improved some acceptance metrics, but did not recover throughput.
- Row-ref zero-copy / device row copy / host pre-norm copy skip: rejected or no material speedup in b9294 defect records.
- Verify-draft transaction, no-lookahead verify, static depth-yield row-cost retune: rejected or exhausted as small boundary patches.

## Gates Before LM Studio Runtime

- Release CUDA build succeeds.
- Standalone Gemma4 attached MTP logs show `loaded attached MTP assistant` and `draft-mtp`.
- Standalone Gemma4 passes:
  - short16K: hard 34 tok/s, preferred 36 tok/s
  - long29K profile: hard 30 tok/s, preferred 32 tok/s, compared against the `31.20 tok/s` runtime-safe b9294 control
  - true32K fitted profile: hard 28 tok/s, preferred 30 tok/s, compared against `29.87 tok/s` at ctx `36864` and batch/ubatch `32`
  - true32K confirm profile: hard 28 tok/s, preferred 30 tok/s, compared against `28.71 tok/s` at ctx `65536` and batch/ubatch `160`
  - true32K current-path parity: target-only and attached-MTP prefixes agree under the b9374 target trajectory
  - passkey/prefix quality, acceptance distribution, CPU, GPU pmon, poll state recorded
- Qwen Tensor/Internal q8/native MTP remains selectable independently.
- General target-only load/generation is not contaminated by Gemma4/Qwen settings.
- Only after the standalone gates pass, package LM Studio runtime and verify GUI/CLI/API load paths reproduce the same model-specific args.
