# Descriptive, equally speaker-weighted ten-bin contours; no pointwise tests.
script_dir <- function() {
  f <- grep("^--file=",commandArgs(),value=TRUE)
  if(length(f)) dirname(normalizePath(sub("^--file=","",f[1]))) else getwd()
}
if(!exists("read_measurements",mode="function")) source(file.path(script_dir(),"analyze_acoustics.R"))
plot_contours <- function(input,out) {
  if(dir.exists(out) && length(list.files(out,all.files=TRUE,no..=TRUE))) stop("Output directory must be new or empty.")
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  d <- read_measurements(input)
  times <- seq(5,95,10); cols <- sprintf("F0_t%02d_ST",times)
  # QC is shared: duplicate tokens, absent conditions and corrupt values cannot silently pass.
  qc_measurements(d,out)
  if(!all(cols %in% names(d))) stop("Missing contour columns: ",paste(setdiff(cols,names(d)),collapse=", "))
  if(any(vapply(d[cols],function(x)any(!is.finite(x)&!is.na(x)),logical(1)))) stop("Nonfinite contour value.")
  unusual <- do.call(rbind,lapply(cols,function(col) {
    idx <- which(abs(d[[col]])>36)
    if(length(idx))data.frame(token_id=d$token_id[idx],column=col,value=d[[col]][idx]) else NULL
  }))
  if(!is.null(unusual)) write.csv(unusual,file.path(out,"contour_flags.csv"),row.names=FALSE)
  rows <- list(); speaker_rows <- list()
  for(j in seq_along(times)) for(cond in c("SN","NPC")) {
    z <- d[d$construction==cond,,drop=FALSE]
    vals <- split(z[[cols[j]]],z$speaker)
    means <- vapply(vals,function(x)if(all(is.na(x)))NA_real_ else mean(x,na.rm=TRUE),numeric(1))
    counts <- vapply(vals,function(x)sum(is.finite(x)),integer(1))
    speaker_rows[[length(speaker_rows)+1]] <- data.frame(time_percent=times[j],construction=cond,speaker=names(means),mean_st=unname(means),n_tokens=counts)
    sp <- means[is.finite(means)]
    rows[[length(rows)+1]] <- data.frame(time_percent=times[j],construction=cond,mean_st=if(length(sp))mean(sp) else NA_real_,
      se_between_speakers=if(length(sp)>1)sd(sp)/sqrt(length(sp)) else NA_real_,n_speakers=length(sp),n_tokens=sum(counts))
  }
  r <- do.call(rbind,rows)
  write.csv(r,file.path(out,"f0_contour_descriptive.csv"),row.names=FALSE,na="")
  write.csv(do.call(rbind,speaker_rows),file.path(out,"f0_contour_speaker_means.csv"),row.names=FALSE,na="")
  if(!any(is.finite(r$mean_st))) stop("All F0 contour values are missing; CSV summaries saved, no plot produced.")
  # Include means even when SE is undefined (e.g. one contributing speaker).
  lims <- range(c(r$mean_st,r$mean_st-r$se_between_speakers,r$mean_st+r$se_between_speakers),finite=TRUE)
  if(diff(lims)==0)lims<-lims+c(-.5,.5)
  png(file.path(out,"f0_contours.png"),width=1800,height=1200,res=180)
  on.exit(dev.off(),add=TRUE);par(mar=c(5.5,5,4,2))
  plot(NA,xlim=c(0,100),ylim=lims,xlab="Normalised vowel time (%)",ylab="F0 (ST relative to speaker reference)",
    main="Mandarin bu: descriptive F0 contours",sub="Equal-weight speaker means; bars: +/-1 SE across speakers (not a paired CI)")
  abline(h=0,col="grey85",lty=3);colors<-c(SN="#2767A0",NPC="#BA562B")
  for(cond in names(colors)) {
    z<-r[r$construction==cond,];lines(z$time_percent,z$mean_st,type="b",pch=if(cond=="SN")16 else 17,lwd=2,col=colors[cond])
    ok<-is.finite(z$mean_st)&is.finite(z$se_between_speakers)
    if(any(ok))arrows(z$time_percent[ok],z$mean_st[ok]-z$se_between_speakers[ok],z$time_percent[ok],z$mean_st[ok]+z$se_between_speakers[ok],angle=90,code=3,length=.04,col=colors[cond])
  }
  legend("topright",legend=c("SN","NPC"),col=colors,lty=1,pch=c(16,17),bty="n")
  writeLines(c("Descriptive only; no pointwise significance tests or missing-frame interpolation.",
    "Per-bin contributing speaker sets may change with missingness. Inspect speaker means and counts.",
    "SE bars show between-speaker variability within each condition, not uncertainty in the paired contrast.",
    "Upstream F0 extraction/reference/window definitions require independent verification."),file.path(out,"contour_notes.txt"))
  invisible(r)
}
if(sys.nframe()==0L) {
  a<-commandArgs(trailingOnly=TRUE);if(length(a)!=2)stop("Usage: Rscript plot_f0_contours.R input.csv_OR_folder NEW_output")
  plot_contours(a[1],a[2])
}
