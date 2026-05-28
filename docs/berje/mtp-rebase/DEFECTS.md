# b9374 Gemma4/Qwen MTP Rebase Defects

This file records defects that affect the current clean-clone rebase goal. A run is not accepted just because it boots, attaches MTP, or passes a tok/s threshold.

## GEMMA4-HARNESS-001: tok/s-only Gate Misclassified true32K

Status: fixed in harness, verification ongoing.

Evidence:

- `artifacts/b9374-gemma4-true32k-confirm-depthtrace-gated-20260529-1/run.result.json`
- tok/s hard gate passed: `29.52 tok/s >= 28 tok/s`
- acceptance failed: `0.53261 < 0.60576` floor from b9294 `0.63576 - 0.03`
- draft generated failed: `184 > 167` ceiling from b9294 `151 * 1.10`
- final `gate_pass=false`

Root cause:

The first b9374 benchmark harness used `gate_pass` as a tok/s-only field. That allowed true32K runs to look accepted even when b9294 acceptance/depth-yield behavior was not preserved.

Fix:

- `scripts/berje/run-b9374-gemma4-mtp-benchmark.ps1` now separates `tok_s_gate_pass` from final `gate_pass`.
- `scripts/berje/run-b9374-lmstudio-gemma4-benchmark.ps1` now uses the same combined gate pattern.
- Final `gate_pass` requires tok/s, acceptance, draft-generated ceiling, passkey prefix, attached-MTP evidence, and CPU sanity.
- Traced true32K confirmation runs also require a depth-yield trace line.

## GEMMA4-TRUE32K-001: b9374 true32K Target Trajectory Differs from b9294

Status: current-path hard gate passes in standalone and LM Studio; historical b9294 acceptance/draft-efficiency warning remains open.

Old baseline:

- `C:\Users\berje\src\llama.cpp-b9294-gemma4-attached-mtp-port\source\artifacts\goal-gemma4-runtime-internalization\long65k-batiai-atomic-q4-true32k-depthyield-confirm-nmax4-margin010-160-20260526`
- prompt tokens: `36436`
- eval: `28.71 tok/s`
- acceptance: `96/151 = 0.63576`
- response prefix: `ZX-TS87-QWEN`

Current b9374 evidence:

- `artifacts/b9374-gemma4-true32k-confirm-depthtrace-gated-20260529-1`
- prompt tokens: `36436`
- eval: `29.52 tok/s`
- acceptance: `98/184 = 0.53261`
- depth-yield trace: present
- old-acceptance gate: failed by b9294 acceptance and draft-generated ceiling
- `artifacts/b9374-gemma4-true32k-confirm-currentpath-gated-20260529-1`
  - eval: `29.46 tok/s`
  - acceptance: `98/184 = 0.53261`
  - current-path acceptance floor: `0.50`
  - current-path `gate_pass=true`
  - historical b9294 acceptance/draft-generated gates remain false
- `artifacts/lmstudio-b9374-gemma-true32k-confirm-currentverify-20260529-1`
  - eval: `29.83 tok/s`
  - acceptance: `98/184 = 0.53261`
  - current-path `gate_pass=true`
  - historical b9294 acceptance/draft-generated gates remain false

Rejected hypothesis:

- Static long-context draft cap was not the root cause. `artifacts/b9374-gemma4-true32k-confirm-depthtrace-longcapoff-20260529-1` disabled `LLAMA_GEMMA4_MTP_LONGCTX_DRAFT_N_MAX` with `-1`, but still produced `98/184 = 0.53261`.

Confirmed boundary:

The b9374 target decode trajectory differs from b9294 before MTP acceptance is considered. This is not an attached-MTP correctness failure by itself: b9374 attached MTP follows the b9374 target-only prefix.

Evidence:

- `artifacts/b9374-gemma4-true32k-target-drift-analysis-20260529-1/analysis.json`
- b9294 target-only, same b9374 true32K request, no attached MTP:
  - `artifacts/b9294-gemma4-true32k-targetonly-prefix-compare-20260529-1`
  - prompt tokens: `36436`
  - eval: `17.28 tok/s`
  - response prefix: `ZX-TS87-QWEN`
- `artifacts/b9374-gemma4-true32k-targetonly-prefix-20260529-1/run.result.json`
- target-only, no attached MTP, prompt tokens `36436`
- response prefix: `PASSKEY: ZX-TS87-QWEN`
- `artifacts/b9374-gemma4-true32k-confirm-depthtrace-gated-20260529-1`
  - attached MTP response prefix: `PASSKEY: ZX-TS87-QWEN`
  - attached MTP starts with the b9374 target-only prefix

Next action:

1. Stop treating the old b9294 first-line prefix or old acceptance floor as standalone proof of b9374 MTP failure.
2. Keep the old b9294 true32K numbers as historical controls, but calibrate the b9374 true32K gate against current target-path parity: b9374 target-only prefix, attached-MTP prefix, speed, CPU, and repeated acceptance distribution.
3. Keep the historical b9294 efficiency miss visible: current true32K confirm is usable by the realistic speed/quality gate, but it has not preserved the old `96/151 = 0.63576` draft efficiency.

## QWEN-TENSOR-001: Tensor/Internal q8 Native MTP Attaches, but Thinking Disable Did Not Produce Content

Status: fixed in runtime, keep under regression guard.

Evidence:

- `artifacts/lmstudio-b9374-qwen36-mtp-no-thinking-20260529-1`
- LM Studio command line used Tensor/Internal-style q8 path: `--tensor-split 9,6`, `--cache-type-k q8_0`, `--cache-type-v q8_0`, `--kv-unified`
- runtime auto log: `LMSTUDIO_QWEN_MTP_AUTO`
- native `draft-mtp` attached
- acceptance: `62/66 = 0.93939`
- eval speed from server log: `54.66 tok/s`
- request explicitly set `chat_template_kwargs.enable_thinking=false`, `reasoning_format=none`, and `thinking_budget_tokens=0`
- response `message.content` was empty
- all 96 completion tokens were reported as `reasoning_content`

Root cause hypothesis:

The Qwen Tensor/Internal q8/native MTP route is healthy for load/attach/speed, and standalone direct `llama-server.exe` can return normal content for the same request. The remaining failure is in the LM Studio API/proxy integration path: the log shows the request contained `enable_thinking: false`, but the LM Studio-facing response still returned only `reasoning_content`.

Standalone control:

- `artifacts/standalone-b9374-qwen36-mtp-no-thinking-20260529-1`
- same Qwen model with q8/q8 KV, tensor split `9,6`, `kv-unified`, and native `draft-mtp`
- request set `chat_template_kwargs.enable_thinking=false`, `reasoning_format=none`, and `thinking_budget_tokens=0`
- response `message.content` was non-empty: `<think></think>` followed by the short final answer
- `reasoning_content` was empty
- content gate passed

Fix:

Runtime Qwen Tensor/Internal q8 native MTP auto now disables reasoning by default and sets `enable_thinking=false` in default template kwargs unless `LMSTUDIO_QWEN_MTP_KEEP_REASONING` is set. This is scoped to the Qwen q8 Tensor/Internal native MTP auto path.

Verification:

- `artifacts/lmstudio-b9374-qwen36-proxy-vs-backend-reasoningoff-20260529-1`
- LM Studio command line still used Tensor/Internal-style q8 path: `--tensor-split 9,6`, `--cache-type-k q8_0`, `--cache-type-v q8_0`, `--kv-unified`
- runtime auto log: `LMSTUDIO_QWEN_MTP_AUTO ... reasoning=off-by-default`
- native `draft-mtp` attached
- LM Studio `1234` proxy response content was non-empty
- proxy `reasoning_tokens=0`
- backend direct response content was also non-empty
- defect boundary result: `fixed`

Regression guard:

Qwen Tensor/Internal q8/native MTP is not accepted if LM Studio proxy content is empty, if `draft-mtp` is not attached, or if the q8/tensor/kv-unified command line disappears.

## QWEN-TENSOR-002: LM Studio CLI q8 Path Bypassed Native MTP When argv Had tensor-split 0

Status: fixed in runtime and verified.

Evidence:

- `artifacts/lmstudio-b9374-qwen36-q8-mtp-currentverify-20260529-2`
- `lms load qwen3.6-27b-mtp -c 4096 --gpu max` produced command line with `--cache-type-k q8_0`, `--cache-type-v q8_0`, and `--kv-unified`, but `--tensor-split 0`.
- Because `common_qwen35_tensor_internal_q8_requested()` required both `tensor_split[0] > 0` and `tensor_split[1] > 0`, Qwen auto did not run.
- Server log showed `common_speculative_init: no implementations specified for speculative decoding`.
- Proxy response regressed to content empty / all `reasoning_content`.

Root cause:

The Qwen Tensor/Internal q8 request signal from LM Studio CLI/API is q8/q8 KV plus `kv-unified`; the hardware split ratio may not survive into argv. Requiring a pre-populated tensor split made the runtime miss a valid Tensor/Internal request.

Fix:

- Qwen3.6 q8/q8 KV plus `kv-unified` is now enough to enter the guarded Qwen Tensor/Internal path.
- If LM Studio passes `--tensor-split 0`, the runtime repairs the Qwen Tensor/Internal split to `9,6`.
- Reasoning-off default is applied to the whole Qwen Tensor/Internal q8 path, including non-MTP Qwen models, unless `LMSTUDIO_QWEN_MTP_KEEP_REASONING` is set.

Verification:

- `artifacts/lmstudio-b9374-qwen36-q8-mtp-currentverify-20260529-4`
- Same `lms load qwen3.6-27b-mtp` path still had `--tensor-split 0` in command line, but runtime log showed `LMSTUDIO_QWEN_MTP_AUTO ... tensor_split=9,6 ... reasoning=off-by-default`.
- Logs confirmed native MTP: `creating MTP draft context against the target model` and `adding speculative implementation 'draft-mtp'`.
- q8/q8 KV, `kv-unified`, proxy content non-empty, proxy `reasoning_tokens=0`, backend direct content non-empty, `gate_pass=true`.

Regression guard:

Qwen LM Studio is rejected if q8/q8 + `kv-unified` loads without Qwen auto, if native MTP does not attach for MTP-preserved models, or if the proxy falls back to empty content/reasoning-only output.

## TARGETONLY-001: LM Studio General Target-Only Path Must Stay Uncontaminated

Status: verified.

Evidence:

- `artifacts/lmstudio-b9374-targetonly-gemma26-currentverify-20260529-3`
- Model: `google/gemma-4-26b-a4b`
- Request path: raw `/v1/completions` smoke to avoid chat-template reasoning noise.
- Server log showed `common_speculative_init: no implementations specified for speculative decoding`.
- Result confirmed no `draft-mtp`, no attached MTP assistant, no Gemma auto, no Qwen auto, content non-empty, CPU all-core `0.74%`, `gate_pass=true`.

Rejected/weak evidence:

- `artifacts/lmstudio-b9374-targetonly-gemma26-currentverify-20260529-1` and `...-2` used chat completions and returned empty content because the selected model spent the small generation budget in reasoning output. Those artifacts prove no MTP contamination but are not quality gates.
- `artifacts/lmstudio-b9374-targetonly-qwen36-currentverify-20260529-4` proves Qwen non-MTP stays no-spec, but it is a Qwen Tensor/Internal path and therefore not the clean general-model isolation proof.
