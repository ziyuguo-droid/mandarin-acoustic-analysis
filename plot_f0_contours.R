# Descriptive time-normalised F0 contours; speaker-weighted means, no pointwise tests.
# Usage: Rscript plot_f0_contours.R S_folder output_directory
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 2) stop("Supply S folder and output directory.")
dir.create(a[2], recursive = TRUE, showWarnings = FALSE)
f <- list.files(a[1], pattern = "^S[0-9]+_20%[.]csv$", recursive = TRUE, full.names = TRUE)
if (!length(f)) stop("No matching files.")
d <- do.call(rbind, lapply(f, read.csv, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE))
times <- seq(5, 95, 10)
rows <- list()
for (tm in times) {
  col <- sprintf("F0_t%02d_ST", tm)
  if (!col %in% names(d)) stop("Missing ", col)
  for (cond in c("SN", "NPC")) {
    z <- d[d$condition == cond, ]
    sp <- tapply(z[[col]], z$speaker, function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE))
    sp <- sp[is.finite(sp)]
    rows[[length(rows)+1]] <- data.frame(time_percent = tm, construction = cond,
      mean_st = if (length(sp)) mean(sp) else NA_real_,
      se_between_speakers = if (length(sp)>1) sd(sp)/sqrt(length(sp)) else NA_real_,
      n_speakers = length(sp), n_tokens = sum(is.finite(z[[col]])))
  }
}
r <- do.call(rbind, rows)
write.csv(r, file.path(a[2], "f0_contour_descriptive.csv"), row.names = FALSE)
png(file.path(a[2], "f0_contours.png"), width = 1800, height = 1200, res = 180)
par(mar = c(5, 5, 4, 2))
lims <- range(c(r$mean_st-r$se_between_speakers, r$mean_st+r$se_between_speakers), finite = TRUE)
plot(NA, xlim = c(0,100), ylim = lims, xlab = "Normalised vowel time (%)", ylab = "F0 (semitones relative to speaker reference)",
  main = "Mandarin bu: descriptive F0 contours", sub = "Equal-weight speaker means; error bars show +/- 1 SE across speakers")
abline(h = 0, col = "grey85", lty = 3)
colors <- c(SN = "#2767A0", NPC = "#BA562B")
for (cond in names(colors)) {
  z <- r[r$construction == cond, ]
  lines(z$time_percent, z$mean_st, type = "b", pch = if (cond == "SN") 16 else 17, lwd = 2, col = colors[cond])
  ok <- is.finite(z$mean_st) & is.finite(z$se_between_speakers)
  arrows(z$time_percent[ok], z$mean_st[ok]-z$se_between_speakers[ok],
    z$time_percent[ok], z$mean_st[ok]+z$se_between_speakers[ok], angle = 90, code = 3, length = .04, col = colors[cond])
}
legend("topright", legend = c("SN", "NPC"), col = colors, lty = 1, pch = c(16,17), bty = "n")
dev.off()
