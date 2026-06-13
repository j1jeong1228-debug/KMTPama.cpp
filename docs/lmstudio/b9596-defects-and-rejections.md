# b9596 Defects, Rejections, and Cleanup Notes

Date: 2026-06-13

## Fixed in the Live LM Studio Config

### Stale Gemma4 Q8 Assistant Override

Status: fixed

Evidence:

- Before: `C:\Users\berje\.lmstudio\.internal\gemma4-mtp-draft-override.json` pointed to `Janvitos\gemma-4-31B-it-qat-assistant-MTP-Q8_0-GGUF\...`.
- That Q8 assistant path no longer existed.
- The override file was moved to `C:\Users\berje\.lmstudio\.internal\codex-backups\b9596-config-fix-20260613-134210`.
- Current smoke reports `staleOverrideExists=false`.

Root cause:

The live LM Studio config drifted after the Q4/Q8 comparison. The selected result was Q4, but an older manual Q8 override file remained.

### Missing Gemma4 Assistant Choice in Hardware Config

Status: fixed

Evidence:

- Before: `hardware-config.json` had `customRatio=[9,6]` and `experimentalTensorInternal=true`, but no `gemma4MtpAssistant`.
- After: `gemma4MtpAssistant=qat-q4`.
- Current log reports `assistant_source=hardware-config-qat-q4`.

Root cause:

The previous final artifact recorded `gemma4MtpAssistant=qat-q4`, but the current live config no longer matched the artifact.

## Rejected or Not Selected

### Q8 Assistant as Default for Gemma4 QAT

Status: rejected as default

Evidence:

- Q8 short was faster: `47.89 tok/s`.
- Q4 long fresh was better: `28.96 tok/s` versus Q8 `28.18 tok/s`.
- Q4 long acceptance was better: `0.76000` versus Q8 `0.73529`.

Decision:

Use Q4 assistant as the default for Gemma4 QAT long-context stability.

### Tensor/Internal as Gemma4 Q4 Long-Context Production Fix

Status: not selected

Reason:

Tensor/Internal remains reserved for Qwen Tensor/Internal/native MTP paths. The b9596 Gemma4 QAT q4/layer path explicitly logs `tensor_internal_policy=not-for-gemma-q4`.

Decision:

Do not disable `experimentalTensorInternal` globally. Do not use Tensor/Internal as the Gemma4 QAT attached MTP production path until a separate candidate proves better long-context behavior.

### Raw LM Studio Command Line as Sole Verification

Status: rejected

Reason:

The raw `llama-server.exe` command line shows LM Studio's original arguments, not the effective b9596 runtime rewrite. Current evidence shows `--tensor-split 0` in the command line while the runtime log correctly reports `target_tensor_split=9,6`.

Decision:

Use the b9596 server log line plus `draft-mtp` initialization as the effective-state proof.

## Known Remaining Risks

### Short-to-Long-to-Short Profile Drift

Status: not fully re-proven after the 2026-06-13 config repair

Reason:

The current smoke proves the corrected attached MTP path and short speed, not the entire long-context sequence.

Required evidence:

- short run
- long run
- short-after-long run
- same runtime, same config, same server log
- no stale override

### LM Studio Variant Selection

Status: open caveat

Evidence:

- `lms load google/gemma-4-31b-qat@q4_0` was rejected by the CLI.
- `lms load google/gemma-4-31b-qat` selected `google/gemma-4-31b-qat@iq4_xs`.
- b9596 then remapped the target to `gemma-4-31B-it-QAT-Q4_0.gguf`.

Required evidence:

GUI should be checked to ensure the intended QAT model selection still maps to the Q4_0 target path.

### Log Noise

Status: partially mitigated

Evidence:

- Current runtime logs `LMSTUDIO_RUNTIME_LOG_VERBOSITY_CAP_B9596`.
- Token-level verbose logs were capped by default unless `LMSTUDIO_RUNTIME_KEEP_VERBOSE_LOGS=1` is set.

Remaining concern:

`slot print_timing` progress lines still appear during long generations. They are useful for performance analysis but can still be noisy in LM Studio logs.

## Cleanup Candidates

Trash only files that are superseded by retained evidence:

- `artifacts/lmstudio-b9596-gemma-qat-assistant-q4-q8-compare-001`
- `artifacts/lmstudio-b9596-gemma-qat-assistant-q4-q8-compare-002`
- `artifacts/lmstudio-b9596-gemma-qat-assistant-q4-q8-compare-003`
- `scripts/compare-lmstudio-gemma-qat-assistants.ps1`

Cleanup performed:

- Moved the three superseded compare directories and the non-curl harness to `artifacts/_trash/b9596-cleanup-20260613-134909`.
- Moved invalid `artifacts/lmstudio-b9596-goal-short-long-short-20260613-1350` because the generated prompt was `98036` tokens against `ctx=65536`.
- Wrote `artifacts/_trash/b9596-cleanup-20260613-134909/TRASH-MANIFEST.json`.
- Redacted stored LM Studio `--api-key` values from artifact command-line captures.
- Verified that the remaining `--api-key` match is only the upstream documentation placeholder in `tools/server/README.md`.

Retain:

- `artifacts/lmstudio-b9596-gemma-qat-assistant-selected-q4-summary.json`
- `artifacts/lmstudio-b9596-gemma-qat-assistant-completion-audit-smoke-001`
- `artifacts/lmstudio-b9596-goal-smoke-20260613-1344`
- `artifacts/lmstudio-b9596-qwen-native-q8-q4-001`
- `artifacts/lmstudio-b9596-targetonly-qwen2-smoke-001`
- `scripts/compare-lmstudio-gemma-qat-assistants-curl.ps1`
