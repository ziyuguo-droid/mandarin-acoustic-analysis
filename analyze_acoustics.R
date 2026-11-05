# Mandarin duration and F0 analysis
# Usage: Rscript analyze_acoustics.R measurements.csv results
# Install once: install.packages(c("lme4", "lmerTest"))
# One row per token; see USAGE.md for columns and units.
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("Usage: Rscript analyze_acoustics.R measurements.csv_OR_S_folder [output_directory]")
for (pkg in c("lme4", "lmerTest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install required package: ", pkg)
}
out <- if (length(args) >= 2L) args[2L] else "results"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
if (dir.exists(args[1L])) {
  files <- list.files(args[1L], pattern = "^S[0-9]+_20%[.]csv$", recursive = TRUE, full.names = TRUE)
  if (!length(files)) stop("No S##_20%.csv files found in input directory.")
  tables <- lapply(files, read.csv, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE, na.strings = c("", "NA", "NaN"))
  if (!all(vapply(tables, function(x) identical(names(x), names(tables[[1L]])), logical(1)))) stop("CSV schemas differ.")
  d <- do.call(rbind, tables)
  write.csv(data.frame(source_file = files, n_tokens = vapply(tables, nrow, integer(1))), file.path(out, "input_inventory.csv"), row.names = FALSE)
  d$token_id <- paste(d$speaker, d$block, d$sentence_order, d$item_id, sep = "_")
  d$construction <- d$condition
  # SN01 and NPC01 form item pair 01, shared across blocks.
  if (!all(grepl("^(SN|NPC)[0-9]+$", d$item_id))) stop("Unexpected item_id format.")
  d$item_pair <- sub("^(SN|NPC)", "", d$item_id)
  mapping <- c(nonvocalic_duration_ms = "closure_release_duration_ms", vowel_proportion = "vowel_ratio",
    f0_onset_st = "F0_onset_ST", f0_mean_st = "F0_mean_ST", f0_offset_st = "F0_offset_ST",
    f0_fall_st = "F0_fall_ST", f0_range_st = "F0_range_ST", articulation_rate = "non_bu_articulation_rate_syll_s")
  for (target in names(mapping)) {
    if (!mapping[[target]] %in% names(d)) stop("Missing input column: ", mapping[[target]])
    d[[target]] <- d[[mapping[[target]]]]
  }
} else {
  d <- read.csv(args[1L], fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE, na.strings = c("", "NA", "NaN"))
}
required <- c("token_id", "speaker", "item_pair", "construction")
if (!all(required %in% names(d))) stop("Missing columns: ", paste(setdiff(required, names(d)), collapse = ", "))
if (anyNA(d[required]) || any(vapply(d[required], function(x) any(trimws(as.character(x)) == ""), logical(1)))) stop("Identifiers and construction cannot be empty.")
if (anyDuplicated(d$token_id)) stop("token_id must be unique.")
if (!all(d$construction %in% c("SN", "NPC"))) stop("construction must be SN or NPC.")
d$construction <- factor(d$construction, levels = c("SN", "NPC"))
d$speaker <- factor(d$speaker)
d$item_pair <- factor(d$item_pair)
# Numeric coding allows independent random slopes with ||.
d$npc <- as.numeric(d$construction == "NPC")
measures <- c("syllable_duration_ms", "vowel_duration_ms", "nonvocalic_duration_ms", "vowel_proportion",
              "f0_onset_st", "f0_mean_st", "f0_offset_st", "f0_fall_st", "f0_range_st",
              "rate_normalized_syllable_duration_ms")
primary <- c("vowel_duration_ms", "f0_onset_st", "f0_mean_st")
measures <- intersect(measures, names(d))
if (!length(measures)) stop("No recognised acoustic columns; see USAGE.md.")
for (v in measures) {
  if (!is.numeric(d[[v]])) stop("Measurement must be numeric: ", v)
  if (any(!is.finite(d[[v]]) & !is.na(d[[v]]))) stop("Infinite value in ", v)
  if (grepl("duration_ms$", v) && any(d[[v]] < 0, na.rm = TRUE)) stop("Negative duration in ", v)
}
if ("vowel_proportion" %in% measures && any(d$vowel_proportion < 0 | d$vowel_proportion > 1, na.rm = TRUE)) stop("vowel_proportion must lie between 0 and 1.")
fit_ok <- function(m) {
  !inherits(m, "error") && !lme4::isSingular(m, tol = 1e-4) &&
    is.null(m@optinfo$conv$lme4$messages) && all(m@optinfo$conv$opt == 0)
}
fit_model <- function(dat, response, fixed = "construction") {
  slopes <- c(speaker = TRUE, item_pair = TRUE)
  correlated <- TRUE
  attempts <- list()
  repeat {
    terms <- vapply(names(slopes), function(g) {
      if (!slopes[[g]]) paste0("(1 | ", g, ")") else
        paste0("(1 + npc ", if (correlated) "|" else "||", " ", g, ")")
    }, character(1))
    f <- as.formula(paste(response, "~", fixed, "+", paste(terms, collapse = " + ")))
    m <- tryCatch(lmerTest::lmer(f, data = dat, REML = TRUE,
      control = lme4::lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 200000))), error = identity)
    attempts[[length(attempts) + 1L]] <- data.frame(formula = paste(deparse(f), collapse = " "),
      acceptable = fit_ok(m), detail = if (inherits(m, "error")) conditionMessage(m) else
        paste(c(if (lme4::isSingular(m)) "singular fit", m@optinfo$conv$lme4$messages), collapse = "; "))
    log_tag <- paste0(response, if (fixed != "construction") "_rate_adjusted" else "")
    write.csv(do.call(rbind, attempts), file.path(out, paste0(log_tag, "_fit_log.csv")), row.names = FALSE)
    if (fit_ok(m)) return(list(model = m, attempts = do.call(rbind, attempts)))
    if (correlated) { correlated <- FALSE; next }
    if (!any(slopes)) stop("No acceptable model after simplification: ", response)
    # Drop the remaining construction slope with the smallest estimated variance.
    if (inherits(m, "error")) stop("Model failed before slope variances could be estimated: ", conditionMessage(m))
    vc <- as.data.frame(lme4::VarCorr(m))
    vars <- vapply(names(slopes)[slopes], function(g) {
      z <- vc$vcov[startsWith(vc$grp, g) & vc$var1 == "npc" & is.na(vc$var2)]
      if (length(z) != 1L || !is.finite(z)) stop("Cannot identify slope variance for ", g)
      z
    }, numeric(1))
    slopes[names(which.min(vars))] <- FALSE
  }
}
results <- list(); failures <- list()
run_one <- function(v, rate_adjusted = FALSE) {
  cols <- c(v, if (rate_adjusted) "articulation_rate")
  dat <- d[complete.cases(d[cols]), , drop = FALSE]
  if (nrow(dat) < 8L || any(table(dat$construction) == 0L) ||
      nlevels(droplevels(dat$speaker)) < 2L || nlevels(droplevels(dat$item_pair)) < 2L) stop("Insufficient data for ", v)
  if (rate_adjusted) dat$rate_c <- dat$articulation_rate - mean(dat$articulation_rate)
  tag <- paste0(v, if (rate_adjusted) "_rate_adjusted" else "")
  fit_result <- fit_model(dat, v, if (rate_adjusted) "construction + rate_c" else "construction")
  m <- fit_result$model
  write.csv(fit_result$attempts, file.path(out, paste0(tag, "_fit_log.csv")), row.names = FALSE)
  saveRDS(m, file.path(out, paste0(tag, "_model.rds")))
  capture.output(summary(m), file = file.path(out, paste0(tag, "_summary.txt")))
  co <- coef(summary(m))["constructionNPC", ]
  ci <- tryCatch(suppressMessages(confint(m, parm = "constructionNPC", method = "profile", level = .95)), error = function(e) {
    warning("Profile CI failed for ", tag, ": ", conditionMessage(e)); matrix(c(NA_real_, NA_real_), nrow = 1)
  })
  pdf(file.path(out, paste0(tag, "_diagnostics.pdf")), width = 9, height = 4.5)
  tryCatch({
    par(mfrow = c(1, 2)); plot(fitted(m), resid(m), xlab = "Fitted", ylab = "Residuals"); abline(h = 0, lty = 2)
    qqnorm(resid(m)); qqline(resid(m))
  }, finally = dev.off())
  data.frame(measure = tag, status = if (v %in% primary && !rate_adjusted) "primary" else "exploratory",
    n_tokens = nrow(dat), n_speakers = length(unique(dat$speaker)), n_items = length(unique(dat$item_pair)),
    estimate_NPC_minus_SN = co["Estimate"], SE = co["Std. Error"], df = co["df"],
    p_uncorrected = co["Pr(>|t|)"], ci_lower = ci[1,1], ci_upper = ci[1,2],
    formula = paste(deparse(formula(m)), collapse = " "), row.names = NULL)
}
if ("articulation_rate" %in% names(d)) {
  if (!is.numeric(d$articulation_rate) || any(!is.finite(d$articulation_rate) & !is.na(d$articulation_rate)) || any(d$articulation_rate <= 0, na.rm = TRUE)) stop("articulation_rate must contain positive numeric values or NA.")
}
jobs <- c(measures, if ("articulation_rate" %in% names(d)) "articulation_rate")
for (v in jobs) {
  ans <- tryCatch(run_one(v), error = identity)
  if (inherits(ans, "error")) failures[[v]] <- conditionMessage(ans) else results[[v]] <- ans
}
if (all(c("articulation_rate", "syllable_duration_ms") %in% names(d))) {
  ans <- tryCatch(run_one("syllable_duration_ms", TRUE), error = identity)
  if (inherits(ans, "error")) failures[["rate_adjusted"]] <- conditionMessage(ans) else results[["rate_adjusted"]] <- ans
}
if (length(results)) write.csv(do.call(rbind, results), file.path(out, "construction_effects.csv"), row.names = FALSE)
capture.output(sessionInfo(), file = file.path(out, "sessionInfo.txt"))
if (length(failures)) {
  writeLines(paste(names(failures), unlist(failures), sep = ": "), file.path(out, "failed_analyses.txt"))
  warning("Some analyses failed; inspect failed_analyses.txt.")
}
if (!length(results)) stop("No successful analyses.")
message("Finished. Results: ", normalizePath(out))

