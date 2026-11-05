# Code review and validation report

Date: 2026-11-06. Baseline: `ec053d16db0fdf6919a0044fce1287c1152f67b1`. Proposed branch: `review/scientific-validation`. This report accompanies a review request; main is not to be merged without owner approval.

## Review scope and decisions

All six original files and repository history were inspected before edits. The three existing workflows remain: manual TextGrid review, scalar mixed-model analysis and descriptive F0 plotting. No Python runtime/dependency is introduced. Root invocation paths are retained to avoid unnecessary file relocation; clearly named test/generator files and synthetic CSV provide reproducibility without a cosmetic directory rewrite.

## Findings: bugs, methods, risks and optional work

| Category | Actual finding in baseline | Resolution |
| --- | --- | --- |
| Program/data safety | Backward empty-interval navigation clamps to interval 1 and can repeatedly revisit the same empty interval | Bounded search; redisplay the last reviewed interval when no previous nonempty interval exists; all-empty files terminate |
| Program/data safety | Popup edits write to interval number even after boundaries/count/label change | Guard count, bounds and previous label; reject stale edits; reanchor navigation by midpoint; check tier layout |
| Program/data safety | Original TextGrid is overwritten without a backup | Original untouched; unique reviewed outputs and pre-edit snapshots; read-back tier count; collision checks |
| Program | Save and exit does not override disabled auto-save; resume has no interval field | Explicit exit always saves; add Start_from_interval and progress logs |
| Program/QC | Missing block, absent paired conditions, repeated design rows or source-file duplicates are not adequately checked | Structured QC reports and blocking errors; no silent dropping |
| Program | R locale forcing is platform-specific; missing numeric columns may infer logical/character types | Read UTF-8 as strings then explicitly convert recognised numeric fields, logging bad entries; preserve string IDs |
| Program | Old output directory can retain failure/model files from earlier runs | Require a new/empty output directory |
| Program | CI failure becomes NA without a reliable per-result state; fit warnings are incompletely captured | Explicit model/CI/analysis states, captured warnings/messages/errors, configuration, saved candidates and session metadata |
| Program | F0 plot y limits depend only on SE bounds; one-speaker/all-missing curves can fail | Include finite means; support undefined SE; report all-missing curves clearly |
| Statistical method | Smallest-variance random-slope deletion is automatic | Removed; preserve full nominated model and diagnostic uncorrelated alternative separately; alternatives require explicit structure plus justification |
| Statistical method | Rate covariate blends within- and between-speaker variation | Explicit within-speaker and between-speaker terms for conditional duration adjustment |
| Statistical method | Primary outcomes are hardcoded, no multiplicity summary | Default exploratory; user-declared outcomes recorded without claiming preregistration; report unadjusted and Holm p values |
| Statistical risk | Gaussian duration/proportion assumptions can fail despite convergence | Retain baseline, add requested log-duration sensitivity, diagnostic plots and bounded-proportion notes; no automatic significance-based replacement |
| Upstream risk | CSV values do not verify pitch tracking, pauses, reference derivation or syllable counts | Arithmetic/metadata checks where possible and explicit upstream-verification warnings |
| Optional future work | GUI automation, beta-type proportion models, recording/serial dependence and random rate slopes | Documented; not silently added to this scoped repair |

## Changed and added files

| File | Main change |
| --- | --- |
| check_textgrids.praat | Bounded navigation, editor-identity guards, original-safe copies/snapshots, resume fields, progress and synthetic headless test actions |
| analyze_acoustics.R | Sourceable input/QC/model functions; explicit model structures and warning states; rate decomposition; diagnostic/log options; reproducible run outputs |
| plot_f0_contours.R | Reuse input/QC; speaker-weighted summaries/counts; safe missing/one-speaker plotting; descriptive interpretation |
| README.md | English scope, installation, commands, inputs/outputs, validation limits and data safety |
| USAGE.md | Detailed units/aliases, QC rules, formulas, inference, missingness, safe Praat workflow and remaining assumptions |
| .gitignore | Ignore case variants of recordings/annotations, outputs/test artifacts; narrow exception for synthetic CSV |
| LICENSE | MIT, explicitly selected by the owner |
| generate_synthetic.R | Fixed-seed synthetic example generator |
| synthetic_measurements.csv | 256 fully synthetic tokens, 8 simulated speakers, 8 simulated pairs, 2 conditions and 2 blocks; every row marked synthetic |
| run_tests.R | Base-R validation/integration suite, with optional real Praat executable |
| test_fixtures.praat | Generates silent WAVs and multi-tier TextGrids exclusively for synthetic tests |
| REVIEW_REPORT.md | Findings, executed validation, limits and research-code readiness assessment |

## Model specification and rationale

The default nominated formula remains:

```r
y ~ construction + (1 + npc | speaker) + (1 + npc | item_pair)
```

Construction uses explicit SN-reference treatment contrasts; npc is 0/1 for random slopes. REML estimates with crossed intercepts/slopes represent the within-speaker and within-pair contrast. `--block` adds block as a fixed effect; prefixed block IDs are normalised to the shared block label. This is an explicitly documented design option rather than a silent baseline change.

The saved diagnostic alternative removes only correlations:

```r
y ~ construction + (1 + npc || speaker) + (1 + npc || item_pair)
```

No automatic slope deletion, optimizer/p-value search or fallback selection is performed. The nominated formula is fixed by configuration; a warning full fit is not silently replaced by the alternative. Other structures require a recorded scientific justification, not the smallest variance or a more significant result. Retaining a singular model for diagnostics does not make its inference reliable; p/df/CI are withheld by default.

Rate-adjusted duration adds `rate_within + rate_between`, optionally block, to the same random structure. Supplied rate-normalised duration is a separate derived outcome. These are not interchangeable or causal estimands. Log-duration models are additional, labelled sensitivity fits. Proportion baseline remains Gaussian with limitations; no unrequested beta model replaces it.

## Validation actually executed

Environment: Windows x64; R 4.6.2; lme4 2.1-0; lmerTest 3.2-1; Praat 7.0.02. Tests used the native executables, not fabricated expected-output files. Full synthetic test run: **43 tests passed**. The executable integration tests bypass GUI/playback and act directly on in-memory synthetic TextGrid objects.

Coverage includes normal input, missing columns, duplicate IDs and design cells, duplicates across files, invalid/nonfinite values, absent SN/NPC globally/by speaker/by item, undefined/all-missing F0, alias conflicts, per-outcome inclusion, singularity and failure logging, explicit contrasts, CI warnings/failures, within-speaker centring, rate arithmetic, prefixed blocks, end-to-end model/CI/log/block outputs, refusing stale outputs, missing contour columns, equal-speaker means, all-missing curves and one-speaker curves.

Native Praat tests cover previous/replay/next-file/save-exit, initial empty intervals, all-empty files, labels and read-back saves, split-boundary stale labels, same-count moved boundaries, conflicting editor/popup labels, resume fields, explicit exit with auto-save disabled, preserving other tiers/points, new output prefixes, and unchanged original WAV/TextGrid MD5 checksums.

The existing local study CSVs were also read and analysed locally (no source edits/uploads). The validation run used block adjustment and explicitly declared the three previously specified primary outcomes. It found no blocking QC errors, but flags/upstream-verification warnings remained. Selected full models include warning/singular fits; they are not converted to successes by dropping slopes. These observations demonstrate handling of real input, not confirmation of scientific assumptions. No real analysis CSV, model, recording, TextGrid or participant metadata is included in the branch.

## Not executed / unresolved

- Actual mouse-dragging, pause-dialog behaviour, GUI editor object routing and audible playback were not exercised interactively. Headless tests verify the shared navigation/writeback/save logic, not the GUI commands. Manual GUI acceptance is required before relying on this tool on valuable annotation copies.
- No original WAV/F0 extraction pipeline was audited. Frame selection, octave errors, annotation boundaries, actual reading/syllable counts and pauses remain upstream checks.
- The original-scale duration residuals previously showed nonconstant variance and tail deviations. The optional log alternative must be assessed alongside baseline diagnostics; no model is declared scientifically valid automatically.
- Beta-type proportion inference, additional recording/serial dependence, condition-by-rate interactions and random rate slopes are not implemented or declared unnecessary. They require design-specific decisions.
- Profile CIs may fail or warn, especially for sparse/singular fits. Those states remain explicit. Singular nominated fits can require independent statistical review or a justified regularised model.
- No fixed preregistration, universal random-effects simplification rule or causal interpretation is inferred from the code.
- Safe saving preserves originals and snapshots but is not a crash-proof atomic save system. Use disposable working copies and the explicit exit button; retain external backups.

## Privacy, security and public research-code use

Only source/docs, MIT text and clearly synthetic examples are proposed for upload. Original study files remain untouched. Local QC/inclusion tables and RDS models can contain study IDs/values; .gitignore reduces accidental additions but does not guarantee privacy or remove already tracked files. Review the staged file list before every publication. Praat full-trust execution is used only for reviewed local scripts on synthetic fixtures and does not change global security settings.

After owner review and the outstanding manual Praat acceptance test, this is suitable to present as an openly documented, developing research-code project in a PhD application. Describe the actual contribution, Codex assistance and validation scope accurately. It is not a validated end-to-end extraction pipeline, peer-reviewed method, publication or evidence that every thesis model is reliable. Do not merge automatically.

Method references and executable commands are in USAGE.md. Re-run `Rscript run_tests.R /path/to/Praat` to reproduce the suite; its local CSV/session records are not participant data and are ignored by Git.
