# Mandarin Acoustic Analysis Toolkit

Praat and R utilities for a repeated-measures phonetics study comparing Mandarin *bu* in **sentential negation (SN)** and **negative potential complements (NPC)**.

## Scope

- `check_textgrids.praat`: manually inspect, replay and label intervals; save reviewed TextGrid copies without overwriting original audio or annotations.
- `analyze_acoustics.R`: validate token-level CSV measurements; fit crossed speaker/item linear mixed-effects models; record diagnostics, warnings, failures and confidence intervals.
- `plot_f0_contours.R`: descriptive, equally speaker-weighted ten-bin F0 contours with missing-data counts.

Measures include syllable, vowel and nonvocalic duration; vowel proportion; F0 onset, mean, offset, fall and range; articulation rate; and supplied rate-normalised duration. **This repository does not provide a complete WAV/TextGrid acoustic-extraction pipeline.** Measurements and their upstream definitions must be independently verified.

## Requirements and quick start

R with `lme4` and `lmerTest`; Praat for annotation review. No Python is required.

```r
install.packages(c("lme4", "lmerTest"))
```

Run from a local checkout (use a NEW output directory for each run):

```sh
Rscript analyze_acoustics.R synthetic_measurements.csv results/demo --block
Rscript plot_f0_contours.R synthetic_measurements.csv results/contours
# Optional sensitivity analyses, without replacing the original-scale models:
Rscript analyze_acoustics.R synthetic_measurements.csv results/log_demo --block --log-duration
# Study-specific legacy CSV folder:
Rscript analyze_acoustics.R path/to/S results/study --block
```

Open `check_textgrids.praat` in Praat, run it and choose the folder/tier/resume position. Leave `Test_actions` at `none` for manual use. Original matching WAV/TextGrid files remain unchanged; snapshots, reviewed copies and progress logs go into `reviewed/`. Resume editing from a reviewed copy by placing it alongside a matching WAV **copy** in a separate working folder. See [USAGE.md](USAGE.md).

## Inputs and outputs

One row per token. Required identifiers: `token_id`, `speaker`, `item_pair`, `construction` (`SN`/`NPC`) and `block`. Optional genuine additional repetitions need a `repetition` identifier. Include at least one recognised measurement for analysis and all ten `F0_t##_ST` columns for contour plotting. Folder input reads only `S##_20%.csv`, checks file/speaker consistency, and maps legacy columns. See [USAGE.md](USAGE.md) for units and aliases.

Outputs include QC issues/design cells, input checksums, an analysis configuration, per-model fit logs and RDS files, summaries, diagnostic PDFs, effect CSVs, per-analysis status, and R session metadata. Invalid data stop modelling with a QC report. Suspicious observations are flagged, not automatically removed. Outputs may contain sensitive study identifiers and must remain local.

## Statistical interpretation

The default model retains construction random slopes by speaker and item. A diagnostic uncorrelated fit is saved separately; it never silently replaces the nominated model. Alternative structures require an explicit option and justification. Warning fits retain estimates for inspection but do not receive inferential p values or CIs. CI warnings/failures are separately labelled. Holm-adjusted and unadjusted p values are both reported for the scheduled scalar-analysis family. There are no primary outcomes by default: declare them only if justified by your experimental plan.

Rate-normalised duration and covariate adjustment are different analyses. The latter separates within-speaker rate variation from between-speaker mean rate. Neither establishes causal control. Gaussian duration/proportion models can be misspecified; inspect residuals and the separately requested log-duration sensitivity models. F0 plots are descriptive, with between-speaker SE bars, not pointwise significance tests or paired confidence intervals.

## Tests and limitations

```sh
Rscript run_tests.R
# Optional native Praat integration on synthetic fixtures:
Rscript run_tests.R /path/to/Praat
```

`generate_synthetic.R` reproducibly creates the clearly marked `synthetic_measurements.csv`. Test fixtures contain no participant observations. Scripts remain at the repository root to preserve existing invocation paths; test helpers and example data are clearly named rather than relocating working files solely for appearance.

See [REVIEW_REPORT.md](REVIEW_REPORT.md) for the review findings, executed tests and remaining limitations. Native Praat headless tests exercise navigation, stale-label protection and saving; they do **not** replace manual GUI/playback and drag-boundary testing. No claim is made that CSV checks validate F0 tracking, syllable counts or pauses in recordings.

The code was generated with Codex assistance, iteratively reviewed/revised, and tested as documented. Independent researcher review and scientific validation are still required. This project does not claim publication, academic endorsement or a validated end-to-end extraction workflow.

## Data safety and licence

No real participant WAVs, TextGrids, questionnaires, experimental CSVs or fitted study models are distributed. `.gitignore` is a guardrail, not a security boundary: inspect staged files before publishing. Do not upload local QC/results directories, which can contain identifiers and measurement values.

MIT licensed; see [LICENSE](LICENSE).
