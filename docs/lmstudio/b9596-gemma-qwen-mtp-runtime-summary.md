# b9596 Gemma4/Qwen MTP Runtime Summary

Date: 2026-06-13

## Verdict

The current b9596 LM Studio runtime is a manual-test candidate for two separate model paths:

- Gemma4 31B QAT attached MTP: keep the QAT Q4 assistant and 9/6 layer split.
- Qwen Tensor/Internal/native MTP: keep `experimentalTensorInternal=true`; do not disable it for Gemma preflight.

The latest live LM Studio config was corrected on 2026-06-13 because it had drifted:

- `hardware-config.json` was missing `gemma4MtpAssistant`.
- `gemma4-mtp-draft-override.json` pointed at the removed Janvitos Q8 assistant.
- The stale override file was moved to `C:\Users\berje\.lmstudio\.internal\codex-backups\b9596-config-fix-20260613-134210`.
- The live config now has `customRatio=[9,6]`, `experimentalTensorInternal=true`, and `gemma4MtpAssistant=qat-q4`.

## Current Gemma4 QAT Evidence

Primary retained baseline:

- Source: `artifacts/lmstudio-b9596-gemma-qat-assistant-selected-q4-summary.json`
- Selected assistant: `qat-q4`
- Q4 short: `40.83 tok/s`, acceptance `0.96923`
- Q4 long fresh: `28.96 tok/s`, acceptance `0.76000`
- Q4 long best observed: `30.50 tok/s`, acceptance `0.83158`
- Q8 short: `47.89 tok/s`, acceptance `0.96923`
- Q8 long fresh: `28.18 tok/s`, acceptance `0.73529`

The retained decision is QAT Q4 assistant for long-context stability. Q8 assistant is not deleted from history, but it is not the selected default.

Current live smoke after the config fix:

- Source: `artifacts/lmstudio-b9596-goal-smoke-20260613-1344/audit-result.json`
- Runtime: `llama.cpp-win-x86_64-nvidia-cuda-avx2-2.20.9596-gemma4-qwen-mtp-b9596-candidate`
- LM Studio key: `google/gemma-4-31b-qat`
- Content: `OK-QAT-MTP`
- Eval speed: `40.38 tok/s`
- Draft acceptance: `0.83333` (`40 accepted / 48 generated`)
- HTTP status: `200`
- Stale override exists: `false`

Current live short/true32K/short-after-long after the config fix:

- Source: `artifacts/lmstudio-b9596-goal-short-long-short-20260613-1354/summary.json`
- Short before long: `47.32 tok/s`, acceptance `0.82258`, content `OK-QAT-MTP`
- True32K prompt: `32236` prompt tokens, `34.48 tok/s`, acceptance `1.00000`, content `OK-QAT-MTP`
- Short after true32K: `38.75 tok/s`, acceptance `0.83333`, content `OK-QAT-MTP`
- Immediate short-after-long collapse: not reproduced in this run.

Current live long generation-length sample after the config fix:

- Source: `artifacts/lmstudio-b9596-goal-long128-20260613-1358/summary.json`
- Prompt tokens: `32244`
- Completion tokens: `160`
- Eval speed: `31.12 tok/s`
- Draft acceptance: `0.77419` (`96 accepted / 124 generated`)
- Prompt eval: `39054.59 ms`, `825.61 tok/s`
- Note: the response stayed in `reasoning_content` and hit `max_tokens`, but this run is valid as a generation-length speed sample.

Important log evidence:

- `assistant_source=hardware-config-qat-q4`
- `target_tensor_split=9,6`
- `target_path=...\gemma-4-31B-it-QAT-Q4_0.gguf`
- `target_kv=q4_0/q4_0`
- `common_speculative_impl_draft_mtp: adding speculative implementation 'draft-mtp'`
- `tensor_internal_policy=not-for-gemma-q4`

## Final Cleanup Verification

Final reversible cleanup was performed on 2026-06-13.

- Cleanup manifest: `artifacts/_trash/b9596-final-cleanup-20260613-150433/CLEANUP-MANIFEST.json`
- Verification summary: `artifacts/_trash/b9596-final-cleanup-20260613-150433/VERIFY-SUMMARY.json`
- Moved to trash: `285` items, `50.424 GiB`
- Repo raw artifacts moved: `262` files
- Old custom runtimes moved: `14`
- Old/stub models moved: `9`
- Restore needed: `false`

Recycle Bin correction:

- The cleanup payloads were later sent to the Windows Recycle Bin.
- Confirmed in Recycle Bin: repo raw artifact payload and old custom runtime payload.
- Not confirmed in Recycle Bin: the old/stub model payload. `SendToRecycleBin` returned without exception, but no Recycle Bin metadata was created for the `52.31 GiB` model payload. This likely exceeded the configured Recycle Bin capacity.
- Required active models remained present after this correction: Gemma4 QAT target, Gemma4 QAT assistant, Qwen validation models, and target-only smoke model.
- `CLEANUP-MANIFEST.json` now records Recycle Bin restore commands for recoverable payloads and marks model entries as not restore-available from the Recycle Bin.

Post-cleanup smoke results:

- Gemma4 QAT 9/6: pass, HTTP `200`, content `OK-QAT-MTP`, `36.52 tok/s`, acceptance `0.81429`
- Gemma4 attach evidence: `assistant_source=hardware-config-qat-q4`, `target_tensor_split=9,6`, `target_kv=q4_0/q4_0`, `draft-mtp`, `tensor_internal_policy=not-for-gemma-q4`
- Qwen Tensor/Internal/native MTP: pass, HTTP `200`, content `OK-QWEN-MTP`, `40.20 tok/s`, acceptance `1.00000`
- Target-only Qwen2 control: pass, HTTP `200`, non-empty content, `common_speculative_init: no implementations specified`, no `draft-mtp`

## LM Studio Command Line Caveat

The OS process command line still shows LM Studio's original arguments, for example `--tensor-split 0`, `--threads 12`, and the selected IQ4_XS model path. The b9596 runtime then reads LM Studio internal config and rewrites the effective Gemma4 attached MTP path internally.

Therefore, for this runtime, the authoritative evidence is:

1. The executable path in `Win32_Process`.
2. The `LMSTUDIO_GEMMA4_MTP_AUTO_B9596` server log line.
3. The later `draft-mtp` initialization and timing lines.

Do not judge the Gemma4 attached MTP state from the raw command line alone.

## Qwen Evidence

Retained Qwen Tensor/Internal/native MTP evidence:

- Source: `artifacts/lmstudio-b9596-qwen-native-q8-q4-001/summary.json`
- `qwen-q8_0-short`: pass, acceptance `1.0`
- `qwen-q8_0-long`: pass, `35.19 tok/s`, acceptance `1.0`
- `qwen-q4_0-short`: pass, acceptance `1.0`
- `qwen-q4_0-long`: pass, `36.58 tok/s`, acceptance `1.0`

Retained target-only regression control:

- Source: `artifacts/lmstudio-b9596-targetonly-qwen2-smoke-001/summary.json`
- Verdict: target-only Qwen2 stayed target-only.
- No Gemma auto policy, no Qwen auto policy, no `draft-mtp`, no `--mtp-head`.

## What Is Still Not Proven

- A GUI-driven user run after the 2026-06-13 config repair is still not proven in this pass.
- CLI rejected `google/gemma-4-31b-qat@q4_0`; loading `google/gemma-4-31b-qat` selected the IQ4_XS variant at the LM Studio layer, and the runtime remapped it to the QAT Q4_0 target internally.
- GUI variant selection should still be checked manually when promoting beyond manual-test candidate status.
- The prior long-context cache/reuse instability is not declared solved by this smoke.

## Current Recommendation

Keep b9596 as a manual-test candidate, not a clean promotion. The current live LM Studio settings are now aligned with the intended QAT Q4 assistant path, and the short smoke passed. The next promotion gate should be a user-clean GUI run:

- short QAT 9/6
- long QAT 9/6
- short-after-long QAT 9/6
- Qwen Tensor/Internal q8/q4 smoke
- target-only control
