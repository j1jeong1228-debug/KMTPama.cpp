# Gemma4 Dedicated Attached-MTP Port Slices

The b9294 long-context best was not produced by recent upstream generic `llama_decode(ctx_dft, batch)` draft-MTP. It used a dedicated attached-MTP transaction path. Porting must preserve that path without importing unrelated b9294 experiments.

## Exclude From This Port

Do not port in this Gemma4 pass:

- `DFLASH_DRAFT`
- `EAGLE3_DRAFT`
- DFlash/Eagle hparams, tensor names, model classes, API helpers
- rejected row-ref zero-copy defaults
- rejected source-KV promotion

Those appeared in the old dirty worktree but are not part of the accepted Gemma4 31B q4/layer attached-MTP baseline.

## Slice G1: Assistant Recognition And Loading

Goal: make the AtomicChat/assistant GGUF load as a Gemma4 assistant without changing general models.

Keep:

- `LLM_ARCH_GEMMA4_ASSISTANT`
- arch strings `gemma4_mtp`, `gemma4_assistant`, `gemma4-assistant`
- loader key aliases for assistant metadata
- tensor aliases:
  - `nextn.pre_projection.*`
  - `nextn.post_projection.*`
  - `mtp.pre_projection.*`
  - `mtp.post_projection.*`
  - `mtp_pre_proj.*`
  - `mtp_post_proj.*`
- `llama_model_gemma4_assistant`
- `llama_model_load_mtp_from_file` validation:
  - target arch is Gemma4
  - assistant arch is Gemma4 assistant
  - `n_embd_backbone == target n_embd`
  - vocab text matches

Done so far:

- arch enum/name/alias added
- loader metadata/tensor alias added
- assistant model class and graph added
- model factory case added
- attached assistant storage/API added
- compile passed for `llama-server` and `llama-cli`
- auto attach smoke passed in the prior b9371 port workspace: `artifacts/b9371-gemma4-auto-mtp-smoke-20260528-2`

## Slice G2: MTP Context API Surface

Goal: expose the minimal API used by the b9294 speculative implementation.

Needed:

- `common/mtp.cpp`
- `common/mtp.h`
- `llama_model_has_mtp_assistant`
- `llama_model_mtp_n_embd_backbone`
- `llama_decode_mtp`
- `llama_decode_mtp_async`
- `llama_decode_mtp_wait`
- `llama_decode_mtp_from_output_row_ref_async`

Do not promote row-ref zero-copy by default. The API can exist for parity, but default runtime path must match the accepted b9294 controls unless a new benchmark proves otherwise.

Status: minimal decode/wait API is ported for the dedicated attached-MTP path. Row-ref/source-KV experiments remain excluded from runtime defaults.

## Slice G3: Dedicated MTP Graph Execution

Goal: restore the performance-relevant path that recent upstream generic draft-MTP lacks.

Needed:

- `llama_context::process_ubatch_mtp`
- `llama_context::decode_mtp`
- `llama_context::decode_mtp_async`
- `llama_context::decode_mtp_wait`
- `llama_context::graph_compute_mtp`
- graph inputs for last token and target pre-norm hidden row
- Gemma4 target graph exposes `t_h_pre_norm` when `embeddings_pre_norm` is requested
- target KV read from the attached assistant graph

This is the primary performance gap. Prior b9371 transition retakes showed long29K attach could work while 160-token throughput stayed below b9294, so acceptance-only tuning is not enough.

Status: dedicated `process_ubatch_mtp` / `graph_compute_mtp` path builds and is reachable through the attached assistant smoke. Performance gates are still pending.

## Slice G4: Speculative Integration

Goal: switch Gemma4 attached-MTP from generic draft context decode to dedicated `common_mtp_decode*`.

Needed:

- include `common/mtp.h`
- use target pre-norm hidden from verify rows
- call `common_mtp_decode*` in draft path
- keep `nmax4`, q4/q4 draft KV, split `12,3`, broad projection override conditions available
- keep poll-off and depth-yield in the Gemma4 explicit/auto attached-MTP default bundle only

Status: b9294 best bundle preservation is restored in `common/arg.cpp` for Gemma4 target detection:

- auto assistant: AtomicChat Q4 first, Radamanthys Q8 fallback only if AtomicChat is absent
- draft `n_max=4`, `p_min=0`
- target/draft KV `q4_0/q4_0`
- split mode layer, tensor split `12,3`
- `poll=0` for target and draft CPU params
- broad override `(mtp_pre_proj|mtp.pre_projection|nextn.pre_projection).weight=CUDA1,token_embd.weight=CUDA1`
- `LLAMA_GEMMA4_MTP_DEPTH_YIELD_CONTROLLER=1`, short threshold `16384`, long threshold `32768`, prompt-length caps short `2`, mid `3`, long `4`
- rejected row0/adaptive fallbacks cleared in the auto path

## Slice G5: Verification

Minimum before LM Studio runtime:

- clean Release CUDA build
- standalone attach smoke:
  - assistant GGUF loaded
  - `draft-mtp` implementation added
  - no target-only fallback
- auto attach smoke:
  - target-only command triggered `LMSTUDIO_GEMMA4_MTP_AUTO_B9294`
  - `ctx_dft=no`
  - no separate draft model load
  - external assistant fit pre-reservation skipped instead of crashing
- short16K gate: >= 34 tok/s, preferred >= 36
- long29K gate: >= 30 tok/s, preferred >= 32, using the b9294 `28936`-prompt / `160`-token profile
- true32K fitted gate: >= 28 tok/s, preferred >= 30, using the b9294 `33936`-prompt / ctx `36864` / batch `32` / `64`-token profile
- true32K confirm gate: >= 28 tok/s, preferred >= 30, using the b9294 `36436`-prompt / ctx `65536` / batch `160` / `160`-token profile
- passkey/prefix quality, acceptance, CPU, GPU pmon, poll state recorded
- Qwen Tensor/Internal q8/native MTP still independently selectable
- general target-only still clean

Current verified evidence:

- `git diff --check`: passed, CRLF warnings only
- `scripts/berje/check-b9374-mtp-rebase-contract.ps1 -RequirePortedGemmaEngine`: passed after the core patch was applied
- `cmake --build build-vs-cuda128 --config Release --target llama-server -- /m`: passed after the prompt-length cap change
- `cmake --build build-vs-cuda128 --config Release --target llama-cli -- /m`: passed before the prompt-length cap change; rerun if CLI packaging becomes required
- attached MTP smoke: `artifacts/b9374-gemma4-attached-mtp-smoke-20260528-1`
- benchmark harness now separates `long29k`, `true32k-fitted`, and `true32k-confirm` so the b9294 best matrix is not collapsed into one misleading "long" case
- short16K policy default: `artifacts/b9374-gemma4-short16k-policy-default-256-20260529-1`, 34.63 tok/s, acceptance `87/156 = 0.55769`
- long29K policy default: `artifacts/b9374-gemma4-long29k-policy-default-160-20260529-1`, 32.25 tok/s, acceptance `96/183 = 0.52459`
- true32K confirm policy default: `artifacts/b9374-gemma4-true32k-confirm-policy-default-160-20260529-1`, 29.70 tok/s, acceptance `98/184 = 0.53261`
- true32K fitted policy default: `artifacts/b9374-gemma4-true32k-fitted-policy-default-64-20260529-1`, 32.00 tok/s, acceptance `41/72 = 0.56944`
- Qwen Tensor/Internal q8/native MTP smoke: `artifacts/b9374-qwen36-27b-native-mtp-tensor-q8-smoke-20260529-1`
- general target-only smoke: `artifacts/b9374-target-only-qwen2-1_5b-smoke-20260529-1`

Still pending before LM Studio runtime:

- Repeat/confirmation run if runtime packaging needs Reps > 1
- Qwen Tensor/Internal q8/native MTP performance check and LM Studio GUI selection mapping
- Investigate or document Qwen tensor-split warnings: fit params unavailable for `SPLIT_MODE_TENSOR`, backend sampler CPU fallback
