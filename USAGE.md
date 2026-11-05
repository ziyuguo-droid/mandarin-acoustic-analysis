# Usage and statistical specification

## 1. Input contract

Use UTF-8 comma-separated CSV, one token per row. Blank/NA/NaN/undefined/--undefined-- measurements are missing, never zero-filled. UTF-8 BOM is supported without forcing a machine-specific locale. Identifier strings (including leading zeros) are retained. Duplicate column names, conflicting canonical/legacy aliases, nonnumeric or infinite measurements are rejected. Different optional columns across files are filled with missing values explicitly.

Required columns: `token_id`, `speaker`, `item_pair`, `construction` and `block`. Token IDs must be globally unique. Construction is exactly `SN` or `NPC`. Each speaker and item pair must have both conditions in the input. Missing conditions are errors; incomplete crossing within speaker/item/block is reported. Repeated genuine tokens in the same design cell require a `repetition` column; otherwise duplicated design cells are errors, even when IDs differ.

A folder input recursively reads only `S##_20%.csv`; each file must match its speaker ID. `item_pair` can be derived from matching `SN01`/`NPC01` item IDs; verify that equal numeric suffixes really represent experimental pairs. The derived pair is shared across blocks, not a separate item for each condition/block. If absent, token IDs are derived from speaker, block, sentence_order and item_id. Legacy blocks such as S01_B01 become B01 for modelling; the original string is retained internally. Other block labels are not guessed or recoded.

| Canonical column | Unit / definition | Legacy alias |
| --- | --- | --- |
| syllable_duration_ms | Strictly positive target syllable duration, milliseconds | same |
| vowel_duration_ms | Strictly positive vowel duration, milliseconds | same |
| nonvocalic_duration_ms | Strictly positive nonvocalic duration, milliseconds | closure_release_duration_ms |
| vowel_proportion | vowel_duration_ms / syllable_duration_ms, 0–1 | vowel_ratio |
| f0_onset_st | Upstream onset window summary, semitones | F0_onset_ST |
| f0_mean_st | Upstream vowel mean, semitones | F0_mean_ST |
| f0_offset_st | Upstream offset window summary, semitones | F0_offset_ST |
| f0_fall_st | onset minus offset; positive means a fall | F0_fall_ST |
| f0_range_st | 12 log2(max Hz/min Hz), nonnegative | F0_range_ST |
| articulation_rate | Non-target-bu syllables per effective second, excluding pauses and target bu | non_bu_articulation_rate_syll_s |
| rate_normalized_syllable_duration_ms | Supplied duration × token rate / speaker pooled reference rate | same |

Canonical and legacy columns can coexist only when nonmissing values agree. An explicitly missing canonical value is not silently filled from an alias. Optional measures need not all be present. All-missing measures are reported as failed analyses, rather than causing complete-case deletion across unrelated outcomes.

## 2. QC and upstream verification

QC writes `qc_issues.csv` (severity/check/input-row/detail), `qc_columns.csv`, `design_cells.csv` and `qc_report.txt`. No token/outlier is automatically deleted. Structural/physically impossible values stop fitting; missing measurements are listed as information. Values above 1000 ms, >15 syllables/s, |ST| >36, or Hz outside 40–1500 are **review flags**, not universal exclusion criteria. Existing quality/jump/octave flags are retained and reported. Thresholds are screening heuristics and should not be used as automatic data cleaning.

When columns are available, arithmetic is checked: duration components, vowel proportion, fall direction, rate numerator/denominator and normalisation. Consistency tolerances: 0.05 ms for duration arithmetic, 1e-4 for proportions, 0.01 ST for fall, 1e-5 for rate arithmetic. Nonpositive duration/rate, negative range and out-of-range proportions are errors. The supplied positive-duration convention does not support true zero-length components; adjudicate them upstream before using this pipeline. Plausible outliers remain in every applicable model.

`non_bu_articulation_rate_syll_s` should equal non-bu syllable count / (sentence duration − bu duration − confirmed within-sentence pauses). Where metadata exist, CSV arithmetic is checked; actual syllable counts, pause placement, TextGrid boundaries and waveform accuracy are **not verified**. If metadata or upstream extraction scripts are unavailable, mark the calculation as requiring upstream review. Removing bu from the denominator reduces direct target inclusion, but the denominator still uses shared boundaries and subtraction; timing errors and condition effects can couple the measures. Rate is not a randomised covariate.

For F0, semitone conversion must already be complete: 12 log2(Hz/reference_Hz). References must be positive and constant within speaker; the study may use a speaker-specific reference from all voiced frames across blocks. Record its exact source. Speaker-relative ST values compare relative pitch positions, not absolute vocal pitch. Onset/offset window widths and mean aggregation must match across conditions. Mean of framewise ST is not generally ST of arithmetic-mean Hz. No conversion is inferred from summary values. Missing voiced frames stay missing. Pitch jumps and undefined frames need upstream audio/frame review, not automatic interpolation. A positive fall is not an error in a falling tone. These scalar metrics describe contour properties but do not fit a continuous contour model.

## 3. Mixed models and random effects

Baseline, for each scalar outcome y:

```r
y ~ construction + (1 + npc | speaker) + (1 + npc | item_pair)
```

`construction` uses explicit treatment contrasts with SN as reference; coefficient `constructionNPC` is NPC−SN. `npc` is numeric 0/1 solely for random slopes and compatible `||` syntax. REML is used. Crossed speaker and item intercepts represent repeated observations; construction slopes allow the contrast to vary across both sampled grouping factors, because construction is manipulated within them. The two blocks are not independent speakers/items.

`--block` adds `+ block` as a fixed nuisance effect for repeat/order differences; the original baseline without it remains available. Whether block adjustment belongs in a confirmatory plan requires a design decision. There are no token-specific random intercepts with one observation per token. Extra recording/serial dependence is not modelled and must be evaluated if relevant.

For a full nominated model, the script also fits the prespecified diagnostic alternative:

```r
y ~ construction + (1 + npc || speaker) + (1 + npc || item_pair)
```

This removes covariance parameters while retaining both design-supported slopes and intercepts. **It never silently replaces the nominated full model.** The old smallest-variance slope deletion rule has been removed. Singularity is not identical to nonconvergence and is logged separately. Both fits/models are retained. Warning fits receive no inferential p values or CIs by default; their estimates remain inspectable.

To explicitly nominate a correlation-free structure, use `--random=uncorrelated --reason="design justification"`. An intercept-only structure is also available via `--random=intercepts --reason="..."` for clearly justified sensitivity work; it is not an automatic fallback. Small estimated variance alone is not sufficient justification. Inspect design support, uncertainty, singularity, covariance and optimizer diagnostics; consider alternative optimizers or regularised/Bayesian models in separate research decisions. Do not compare p values to select structures. The script does not claim that one universal random-effects strategy is scientifically optimal.

For each outcome, only rows missing that outcome (and rate when required) are omitted from that model and documented in an inclusion CSV. If remaining data leave a speaker/item without both conditions, that analysis fails explicitly; no slope is quietly removed or group silently dropped.

## 4. Rate adjustment and duration alternatives

Rate itself is modelled as a scalar outcome. Supplied normalised duration is modelled separately; its reference-rate arithmetic is checked when available. It is a derived variable and can incorporate rate effects/noise mechanically.

For statistical adjustment of raw syllable duration, the script separates speaker mean rate from within-speaker variation:

```r
syllable_duration_ms ~ construction + rate_within + rate_between +
  (1 + npc | speaker) + (1 + npc | item_pair)
```

`rate_within = token rate − speaker mean rate`; `rate_between` is that speaker mean minus the equally weighted grand mean of speaker means. Means are computed on the outcome/rate-complete subset and saved in the fitted model frame. With `--block`, add block. The construction coefficient is conditional on these rate covariates under a common rate slope; it is not equivalent to duration normalisation or a causal direct effect. The model does not estimate construction-by-rate interactions or random rate slopes; consider them only with an independently justified design and enough support.

Original-scale Gaussian duration models remain the baseline. `--log-duration` additionally fits log(y) models for strictly positive durations, labelled exploratory sensitivity analyses; a construction effect is on the natural-log scale and can be exponentiated as a ratio. Never relabel it milliseconds. These do not replace the original model or select a preferred p value. Inspect residual spread, Q–Q tails, construction-wise residuals and scale-location plots. Model convergence does not validate assumptions. Vowel proportion retains a Gaussian baseline for comparability, with explicit bounded-outcome warnings and checks for fitted values outside [0,1]. Beta-type alternatives may be appropriate, require care with exact 0/1, and are not silently substituted.

## 5. Inference and reproducibility

By default all outcomes are exploratory. `--primary=vowel_duration_ms,f0_onset_st,f0_mean_st` records a **user declaration**, not proof of preregistration. Use only if supported by your experimental plan. lmerTest supplies Satterthwaite degrees of freedom and p values. CIs use lme4 profile likelihood; this profiling may internally refit REML estimates using ML. Warnings/errors/nonfinite intervals are labelled; no silent Wald fallback occurs. `--no-ci` explicitly skips profiling and labels it not_requested.

`model_status` distinguishes success/warning; analysis failure is in `analysis_status.csv`. Selected-model singularity, nonconvergence or captured warnings withhold p/df/CI. CI-only warnings may retain the interval with a warning status for inspection. Default success describes computation only. Inspect `qc_warnings` and diagnostics before interpreting any coefficient.

`p_uncorrected` and `p_holm_all_scheduled` are both saved. Holm uses the full number of scheduled scalar tests, including failed and log/rate sensitivity tests, not only significant/successful results. This is a conservative convenience family, not a substitute for a prespecified confirmatory family; predeclare any different family independently. No p values are computed for the ten F0 bins. Emphasise effect sizes, intervals, missingness and consistency, particularly with few speakers/items.

Use a new/empty output directory; the script refuses nonempty output directories to prevent stale failures/models from prior runs. Input files are never modified. Checksums are recorded, raw absolute input paths are not written to the inventory. Session metadata, nominated random structure, justification, block option and declared primary outcomes are saved. Fitted models and inclusion files contain study data and must remain private.

## 6. F0 contour plotting

```sh
Rscript plot_f0_contours.R input.csv_OR_folder results/new_contours
```

Required ST columns: `F0_t05_ST`, `F0_t15_ST`, …, `F0_t95_ST`. They represent means of voiced frames in ten equal-duration vowel bins (centres 5–95%), not instantaneous samples. Use consistent upstream ST references and bin definitions. No missing-frame interpolation occurs.

At each bin, average available tokens within each speaker/condition, then average available speaker means with equal weight. Output both group and speaker-level means and their token counts. Different missingness can change the contributing speaker set by bin/condition; inspect these tables. Error bars are ±1 between-speaker SE within condition, **not a paired contrast CI**. Lines are visual guides between aggregated bins, not reconstruction of missing individual trajectories or significance tests. One-speaker input can be plotted with undefined SE; all-missing curves stop after saving tabular summaries rather than crashing with infinite axis limits.

## 7. Praat review and safe saving

Open the script in Praat and run it. WAV and TextGrid must be in the chosen folder and share a base name. The script reads WAV only. Pick an interval tier, optional empty-label skipping/playback, padding, starting file (sorted Praat file-list order) and starting interval. Tier names, other tiers and points are not changed by the script. Intentional boundary edits change interval structure in memory; additions/removals/renames of tiers are not supported while reviewing.

Buttons: Previous searches backward without wrapping; at the first nonempty interval it redisplays that interval. Replay stays on the current anchored interval. Next searches forward; exhaustion moves to the next file. Next file leaves immediately. Save and exit always saves the current reviewed copy, even when Save_on_leaving_file is false. Closing the review dialog maps to Save and exit. Other script/runtime interruption is not guaranteed to save in-memory edits: use the explicit button and retain the snapshot.

Each file review allocates a fresh `reviewed/base.reviewN` prefix. `*.before.TextGrid` is a pre-edit object snapshot; `*.TextGrid` is the reviewed output; `*.progress.txt` records visited interval/buttons and stale-label decisions. Existing prefixes are never reused. No original TextGrid or previous reviewed output is overwritten. Saving failures stop with the original and snapshot intact, and the in-memory object remains available for manual recovery. Reading back verifies tier count; integration tests additionally check tier names/points/labels on synthetic fixtures. This is not an atomic filesystem transaction or a byte-for-byte backup format conversion.

Editor changes update the same TextGrid object. A popup label edit is applied only when the original interval count, start/end boundaries and label are unchanged. Otherwise the popup edit is rejected (not redirected to an uncertain interval); editor edits are preserved. Navigation reanchors by the old midpoint. If a boundary/label was edited in the editor, review again before applying a new popup label. Keep tier layout unchanged; invalid structure stops and requires saving manually to a new file. The script does not automatically judge whether a boundary or label is scientifically correct.

On exit, use the printed file/interval or progress log as a resume position. To continue **the saved edits**, put the reviewed TextGrid and a matching WAV copy into a separate working folder; starting against the original folder rereads the original TextGrid, not the reviewed copy. Check file ordering after adding/removing files.

`Test_actions=none` is mandatory for manual use. Other values run deterministic headless actions on synthetic test fixtures only, bypassing GUI/playback; do not use this mode on research data. Praat 7 command-line tests require its per-script `--FULL-TRUST` option to write synthetic files; inspect the scripts and use only a disposable fixture directory. This does not change global Praat/OS settings. GUI editor/playback behaviour remains a separate manual acceptance check.

## 8. Tests, licensing and method references

Run `Rscript run_tests.R [Praat_executable]` from the root. The suite writes local TEST_RESULTS.csv and TEST_SESSION.txt and uses temporary synthetic fixtures. It does not read or modify participant data. See REVIEW_REPORT.md for tests actually executed and limits. Regenerate synthetic CSV with `Rscript generate_synthetic.R`; its seed is fixed and every token is marked synthetic.

MIT: LICENSE. No real participant data are licensed or distributed here.

Official references: [lmer](https://lme4.github.io/lme4/reference/lmer.html), [singularity](https://lme4.github.io/lme4/reference/isSingular.html), [convergence](https://lme4.github.io/lme4/reference/convergence.html), [profile CIs](https://lme4.github.io/lme4/reference/confint.merMod.html), [Praat pause controls](https://www.fon.hum.uva.nl/praat/manual/Scripting_6_6__Controlling_the_user.html), [Praat file commands](https://www.fon.hum.uva.nl/praat/manual/Scripting_6_4__Files.html).
