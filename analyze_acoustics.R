# Shared input/QC and mixed-model analysis. Sourceable for tests and plotting.
acoustic_measures <- c("syllable_duration_ms", "vowel_duration_ms", "nonvocalic_duration_ms",
  "vowel_proportion", "f0_onset_st", "f0_mean_st", "f0_offset_st", "f0_fall_st", "f0_range_st",
  "rate_normalized_syllable_duration_ms", "articulation_rate")
read_measurements <- function(input) {
  files <- if (dir.exists(input)) sort(list.files(input, "^S[0-9]+_20%[.]csv$", recursive=TRUE, full.names=TRUE)) else input
  if (!length(files) || any(!file.exists(files))) stop("No input CSV found.")
  read_one <- function(f) {
    # Read UTF-8 without translating through the machine's current locale.
    lines <- readLines(f, encoding="UTF-8", warn=FALSE)
    if (!length(lines)) stop("Empty CSV: ", basename(f))
    lines[1] <- sub("^\ufeff", "", lines[1])
    x <- read.csv(text=paste(lines, collapse="\n"), colClasses="character", check.names=FALSE,
                  na.strings=c("", "NA", "NaN", "undefined", "--undefined--"))
    if (anyDuplicated(names(x))) stop("Duplicate column names in ", basename(f))
    x$.source <- basename(f)
    x
  }
  tables <- lapply(files, read_one)
  # Different optional columns are allowed, with missing columns filled explicitly.
  all_names <- unique(unlist(lapply(tables, names)))
  tables <- lapply(tables, function(x) { for (n in setdiff(all_names,names(x))) x[[n]] <- NA_character_; x[all_names] })
  d <- do.call(rbind,tables)
  mapping <- c(construction="condition", nonvocalic_duration_ms="closure_release_duration_ms",
    vowel_proportion="vowel_ratio", f0_onset_st="F0_onset_ST", f0_mean_st="F0_mean_ST",
    f0_offset_st="F0_offset_ST", f0_fall_st="F0_fall_ST", f0_range_st="F0_range_ST",
    articulation_rate="non_bu_articulation_rate_syll_s")
  conflicts <- character()
  for (n in names(mapping)) if (mapping[[n]] %in% names(d)) {
    if (!n %in% names(d)) d[[n]] <- d[[mapping[[n]]]] else {
      x <- d[[n]]; y <- d[[mapping[[n]]]]; ok <- !is.na(x) & !is.na(y)
      if (any(ok)) {
        nx <- suppressWarnings(as.numeric(x[ok])); ny <- suppressWarnings(as.numeric(y[ok]))
        equal <- x[ok] == y[ok] | (!is.na(nx) & !is.na(ny) & abs(nx-ny)<1e-7)
        if (any(!equal)) conflicts <- c(conflicts,paste(n,mapping[[n]],sep=" vs "))
      }
      # Do not fill an explicitly missing canonical measurement from an alias.
    }
  }
  if (!"item_pair" %in% names(d) && "item_id" %in% names(d)) {
    if (any(is.na(d$item_id) | !grepl("^(SN|NPC)[0-9]+$",d$item_id))) stop("Cannot derive item_pair from item_id.")
    d$item_pair <- sub("^(SN|NPC)","",d$item_id)
  }
  if (!"token_id" %in% names(d) && all(c("speaker","block","sentence_order","item_id") %in% names(d)))
    d$token_id <- do.call(paste,c(d[c("speaker","block","sentence_order","item_id")],sep="_"))
  if ("block" %in% names(d)) {
    d$.block_original <- d$block
    encoded <- !is.na(d$block) & grepl("^S[0-9]+_B[0-9]+$",d$block)
    d$block[encoded] <- sub("^S[0-9]+_", "", d$block[encoded])
  }
  numeric_names <- unique(c(acoustic_measures,grep("^(F0_|f0_|.*_duration_s$|.*_duration_ms$|.*_count$|.*_Hz$|.*_syll_s$)",names(d),value=TRUE),
    "vowel_ratio","reference_rate_syll_s","vowel_onset_s","vowel_offset_s","bu_onset_s","bu_offset_s"))
  bad_numeric <- list()
  for (n in intersect(numeric_names,names(d))) {
    original <- d[[n]]; converted <- suppressWarnings(as.numeric(original))
    bad <- !is.na(original) & is.na(converted)
    if (any(bad)) bad_numeric[[n]] <- which(bad)
    d[[n]] <- converted
  }
  attr(d,"bad_numeric") <- bad_numeric; attr(d,"alias_conflicts") <- conflicts
  attr(d,"files") <- files
  attr(d,"folder_mode") <- dir.exists(input)
  d
}
qc_measurements <- function(d,out) {
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  issues <- data.frame(severity=character(),check=character(),row=integer(),detail=character())
  add <- function(severity,check,rows=0L,detail="") {
    if (!length(rows)) return(invisible(NULL))
    issues <<- rbind(issues,data.frame(severity=severity,check=check,row=as.integer(rows),detail=detail))
  }
  req <- c("token_id","speaker","item_pair","construction","block")
  for (n in setdiff(req,names(d))) add("error","missing_column",detail=n)
  for (n in intersect(req,names(d))) {
    add("error","missing_identifier",which(is.na(d[[n]]) | trimws(d[[n]])==""),n)
    add("error","identifier_whitespace",which(!is.na(d[[n]]) & trimws(d[[n]])!=d[[n]]),n)
  }
  if ("token_id" %in% names(d)) add("error","duplicate_token_id",which(duplicated(d$token_id) | duplicated(d$token_id,fromLast=TRUE)))
  if ("construction" %in% names(d)) add("error","invalid_construction",which(!is.na(d$construction) & !d$construction %in% c("SN","NPC")))
  for (n in names(attr(d,"bad_numeric"))) add("error","nonnumeric_measurement",attr(d,"bad_numeric")[[n]],n)
  for (n in attr(d,"alias_conflicts")) add("error","alias_conflict",detail=n)
  if (isTRUE(attr(d,"folder_mode")) && "speaker" %in% names(d)) {
    expected_speaker <- sub("_20%[.]csv$", "", d$.source)
    add("error","file_speaker_mismatch",which(!is.na(d$speaker) & d$speaker!=expected_speaker))
  }
  if (!nrow(d)) add("error","empty_dataset")
  if (all(req %in% names(d))) {
    natural_key <- do.call(paste,c(d[c("speaker","item_pair","construction","block")],sep="|"))
    # Additional repetitions are legitimate only if explicitly distinguished.
    if ("repetition" %in% names(d)) natural_key <- paste(natural_key,d$repetition,sep="|")
    add("error","duplicate_design_cell",which(duplicated(natural_key) | duplicated(natural_key,fromLast=TRUE)),"Add a repetition identifier for genuine additional repetitions.")
    for (g in c("speaker","item_pair")) for (id in unique(d[[g]])) {
      idx <- which(d[[g]]==id)
      if (!all(c("SN","NPC") %in% d$construction[idx])) add("error","unpaired_condition",idx,paste(g,id))
    }
    grid <- as.data.frame(table(speaker=d$speaker,item_pair=d$item_pair,construction=d$construction,block=d$block))
    names(grid)[5] <- "n_tokens"; write.csv(grid,file.path(out,"design_cells.csv"),row.names=FALSE)
    if (any(grid$n_tokens==0)) add("warning","incomplete_crossing",detail="Some speaker x item x condition x block cells are empty; inspect design_cells.csv.")
    if ("item_id" %in% names(d)) {
      ok <- !is.na(d$item_id) & grepl("^(SN|NPC)[0-9]+$",d$item_id)
      add("error","item_condition_mismatch",which(ok & sub("[0-9]+$","",d$item_id)!=d$construction))
      add("error","item_pair_mismatch",which(ok & suppressWarnings(as.numeric(sub("^(SN|NPC)","",d$item_id)))!=suppressWarnings(as.numeric(d$item_pair))))
    }
  }
  for (n in intersect(acoustic_measures,names(d))) {
    x <- d[[n]]; add("error","nonfinite_measurement",which(!is.finite(x)&!is.na(x)),n)
    add("info","missing_measurement",which(is.na(x)),n)
    if (grepl("duration_ms$",n)) {
      add("error","nonpositive_duration",which(!is.na(x)&x<=0),n)
      add("warning","unusually_long_duration",which(x>1000),n)
    }
    if (n=="vowel_proportion") add("error","invalid_proportion",which(x<0|x>1),n)
    if (n=="articulation_rate") { add("error","nonpositive_rate",which(x<=0),n); add("warning","unusual_rate",which(x>15),n) }
    if (n=="f0_range_st") add("error","negative_f0_range",which(x<0),n)
    if (grepl("^f0_",n)) add("warning","unusual_f0_st",which(abs(x)>36),n)
  }
  consistency <- function(cols,observed,expected,label,tol=1e-4) {
    if (all(cols %in% names(d))) {
      a <- observed(d); b <- expected(d)
      add("error",label,which(is.finite(a)&is.finite(b)&abs(a-b)>tol))
    }
  }
  consistency(c("syllable_duration_ms","vowel_duration_ms","nonvocalic_duration_ms"),function(x)x$syllable_duration_ms,function(x)x$vowel_duration_ms+x$nonvocalic_duration_ms,"duration_components_inconsistent",.05)
  consistency(c("syllable_duration_ms","vowel_duration_ms","vowel_proportion"),function(x)x$vowel_proportion,function(x)x$vowel_duration_ms/x$syllable_duration_ms,"vowel_proportion_inconsistent",1e-4)
  consistency(c("f0_onset_st","f0_offset_st","f0_fall_st"),function(x)x$f0_fall_st,function(x)x$f0_onset_st-x$f0_offset_st,"f0_fall_direction_or_definition",.01)
  for (n in intersect(c("F0_onset_Hz","F0_mean_Hz","F0_offset_Hz","F0_min_Hz","F0_max_Hz"),names(d)))
    add("warning","unusual_f0_hz",which(d[[n]]<40 | d[[n]]>1500),n)
  for (n in intersect(c("F0_onset_Hz","F0_mean_Hz","F0_offset_Hz","F0_min_Hz","F0_max_Hz"),names(d)))
    add("error","nonpositive_f0_hz",which(d[[n]]<=0),n)
  for (n in intersect(c("adjacent_jump_count","octave_candidate_count"),names(d))) add("warning","upstream_pitch_flag",which(d[[n]]>0),n)
  if ("quality_flag" %in% names(d)) add("warning","upstream_quality_flag",which(!is.na(d$quality_flag)&d$quality_flag!="OK"),"Not automatically excluded.")
  if ("speaker_reference_median_Hz" %in% names(d) && "speaker" %in% names(d)) {
    add("error","invalid_f0_reference",which(d$speaker_reference_median_Hz<=0))
    for (sp in unique(d$speaker)) {
      vals <- unique(na.omit(d$speaker_reference_median_Hz[d$speaker==sp]))
      if (length(vals)>1 && diff(range(vals))>1e-6) add("error","inconsistent_speaker_reference",which(d$speaker==sp))
    }
  } else add("warning","f0_reference_unverified",detail="Need upstream extraction script/reference metadata; ST columns alone are insufficient.")
  for(n in intersect(c("pause_duration_s","expected_non_bu_syllable_count"),names(d))) add("error","negative_rate_component",which(d[[n]]<0),n)
  if("reference_rate_syll_s" %in% names(d)) {
    add("error","invalid_rate_reference",which(d$reference_rate_syll_s<=0))
    if("speaker" %in% names(d)) for(sp in unique(d$speaker)) {
      vals <- unique(na.omit(d$reference_rate_syll_s[d$speaker==sp]))
      if(length(vals)>1 && diff(range(vals))>1e-6) add("error","inconsistent_rate_reference",which(d$speaker==sp))
    }
  }
  rate_cols <- c("expected_non_bu_syllable_count","effective_non_bu_articulation_duration_s","articulation_rate")
  if (all(rate_cols %in% names(d))) {
    add("error","invalid_rate_denominator",which(d$effective_non_bu_articulation_duration_s<=0))
    consistency(rate_cols,function(x)x$articulation_rate,function(x)x$expected_non_bu_syllable_count/x$effective_non_bu_articulation_duration_s,"rate_arithmetic_inconsistent",1e-5)
    consistency(c("sentence_duration_s","bu_duration_s","pause_duration_s","effective_non_bu_articulation_duration_s"),function(x)x$effective_non_bu_articulation_duration_s,function(x)x$sentence_duration_s-x$bu_duration_s-x$pause_duration_s,"rate_denominator_inconsistent",1e-5)
  }
  consistency(c("rate_normalized_syllable_duration_ms","syllable_duration_ms","articulation_rate","reference_rate_syll_s"),function(x)x$rate_normalized_syllable_duration_ms,function(x)x$syllable_duration_ms*x$articulation_rate/x$reference_rate_syll_s,"normalised_duration_inconsistent",.05)
  add("warning","upstream_extraction_not_verified",detail="CSV arithmetic checks cannot verify WAV, TextGrid boundaries, actual syllable counts, pauses or F0 tracking. Inspect upstream extraction scripts.")
  if ("articulation_rate" %in% names(d)) add("warning","rate_coupling",detail="Excluding bu reduces direct duration inclusion but denominator uses sentence duration minus bu duration; shared boundaries/errors and condition-related rate remain. Normalisation is not covariate adjustment or causal control.")
  write.csv(issues,file.path(out,"qc_issues.csv"),row.names=FALSE,na="")
  summary <- data.frame(column=names(d),type=vapply(d,function(x)class(x)[1],character(1)),missing=vapply(d,function(x)sum(is.na(x)),integer(1)))
  write.csv(summary,file.path(out,"qc_columns.csv"),row.names=FALSE)
  writeLines(c("Data QC: no rows or outliers automatically deleted.",paste("Rows:",nrow(d)),
    paste("Errors:",sum(issues$severity=="error")),paste("Warnings:",sum(issues$severity=="warning")),
    "Inspect qc_issues.csv and design_cells.csv before interpreting models."),file.path(out,"qc_report.txt"))
  if (any(issues$severity=="error")) stop("Input failed QC; see qc_issues.csv. No models fitted.")
  issues
}
model_formula <- function(response,structure="full",fixed="construction",block=FALSE) {
  random <- switch(structure,full="(1 + npc | speaker) + (1 + npc | item_pair)",
    uncorrelated="(1 + npc || speaker) + (1 + npc || item_pair)",
    intercepts="(1 | speaker) + (1 | item_pair)",stop("Unknown random structure"))
  as.formula(paste(response,"~",fixed,if(block)"+ block" else "", "+",random))
}
fit_candidate <- function(dat,response,structure,fixed="construction",block=FALSE) {
  warns <- messages <- character()
  f <- model_formula(response,structure,fixed,block)
  m <- tryCatch(withCallingHandlers(lmerTest::lmer(f,data=dat,REML=TRUE,
    control=lme4::lmerControl(optimizer="bobyqa",optCtrl=list(maxfun=200000))),
    warning=function(w){warns <<- c(warns,conditionMessage(w));invokeRestart("muffleWarning")},
    message=function(w){messages <<- c(messages,conditionMessage(w));invokeRestart("muffleMessage")}),error=identity)
  singular <- if(inherits(m,"error")) NA else lme4::isSingular(m,tol=1e-4)
  conv <- if(inherits(m,"error")) "fit error" else paste(m@optinfo$conv$lme4$messages,collapse="; ")
  optimizer <- if(inherits(m,"error")) NA else paste(m@optinfo$conv$opt,collapse=";")
  state <- if(inherits(m,"error")) "failed" else if(singular || length(warns) || nzchar(conv) || any(m@optinfo$conv$opt!=0)) "warning" else "success"
  list(model=m,log=data.frame(structure=structure,formula=paste(deparse(f),collapse=" "),status=state,
    singular=singular,optimizer_code=optimizer,warnings=paste(warns,collapse="; "),messages=paste(messages,collapse="; "),
    convergence=conv,error=if(inherits(m,"error"))conditionMessage(m) else ""))
}
profile_interval <- function(m,fun=confint) {
  warns <- character()
  ci <- tryCatch(withCallingHandlers(suppressMessages(fun(m,parm="constructionNPC",method="profile",level=.95)),
    warning=function(w){warns <<- c(warns,conditionMessage(w));invokeRestart("muffleWarning")}),error=identity)
  if (inherits(ci,"error")) return(list(lower=NA_real_,upper=NA_real_,status="failed",detail=conditionMessage(ci)))
  valid <- is.matrix(ci) && ncol(ci)==2 && nrow(ci)==1 && all(is.finite(ci)) && ci[1,1]<=ci[1,2]
  if(!valid) return(list(lower=NA_real_,upper=NA_real_,status="failed",detail="Invalid/nonfinite CI"))
  list(lower=ci[1,1],upper=ci[1,2],status=if(length(warns))"warning" else "success",detail=paste(warns,collapse="; "))
}
prepare_model_data <- function(d,v,adjust_rate=FALSE) {
  cols <- c(v,if(adjust_rate)"articulation_rate")
  idx <- complete.cases(d[cols]); dat <- d[idx,,drop=FALSE]
  dat$construction <- factor(dat$construction,levels=c("SN","NPC"))
  contrasts(dat$construction) <- contr.treatment(c("SN","NPC"),base=1)
  dat$speaker <- factor(dat$speaker); dat$item_pair <- factor(dat$item_pair); dat$block <- factor(dat$block)
  dat$npc <- as.numeric(dat$construction=="NPC")
  if (nrow(dat)<8 || any(table(dat$construction)==0) || nlevels(dat$speaker)<2 || nlevels(dat$item_pair)<2) stop("Insufficient complete observations.")
  # A slope requires within-group condition variation in the actual per-measure subset.
  for(g in c("speaker","item_pair")) if(any(tapply(dat$npc,dat[[g]],function(x)length(unique(x)))<2))
    stop("Missingness leaves a group without both constructions; inspect QC, do not silently remove its slope.")
  if(adjust_rate) {
    dat$rate_between <- ave(dat$articulation_rate,dat$speaker,FUN=mean)
    dat$rate_within <- dat$articulation_rate-dat$rate_between
    dat$rate_between <- dat$rate_between-mean(tapply(dat$articulation_rate,dat$speaker,mean))
    if(sd(dat$rate_within)==0) stop("No within-speaker rate variation.")
  }
  list(data=dat,included=idx)
}
run_analysis <- function(input,out,random="full",include_block=FALSE,log_duration=FALSE,primary=character(),ci=TRUE,reason="") {
  if(dir.exists(out) && length(list.files(out,all.files=TRUE,no..=TRUE))) stop("Output directory must be new or empty (prevents stale results).")
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  if(random!="full" && !nzchar(reason)) stop("Non-default random structure requires --reason=... documenting design justification.")
  for(p in c("lme4","lmerTest")) if(!requireNamespace(p,quietly=TRUE)) stop("Install ",p)
  on.exit(capture.output(sessionInfo(),file=file.path(out,"sessionInfo.txt")),add=TRUE)
  d <- read_measurements(input); qc <- qc_measurements(d,out)
  if(any(!primary %in% acoustic_measures)) stop("Unknown primary measure.")
  write.csv(data.frame(file=basename(attr(d,"files")),md5=unname(tools::md5sum(attr(d,"files")))),file.path(out,"input_inventory.csv"),row.names=FALSE)
  writeLines(c(paste("random structure:",random),paste("reason:",reason),paste("block fixed effect:",include_block),
    paste("primary (user declared; not inferred as preregistration):",paste(primary,collapse=",")),
    "No selection by p value or smallest random slope variance. Alternative fits are diagnostic only."),file.path(out,"analysis_config.txt"))
  jobs <- intersect(acoustic_measures,names(d))
  if(!length(jobs)) stop("No recognised acoustic measurements.")
  specifications <- data.frame(tag=jobs,response=jobs,rate=FALSE,log=FALSE)
  if(all(c("syllable_duration_ms","articulation_rate") %in% jobs)) specifications <- rbind(specifications,data.frame(tag="syllable_duration_ms_rate_adjusted",response="syllable_duration_ms",rate=TRUE,log=FALSE))
  if(log_duration) for(v in jobs[grepl("duration_ms$",jobs)]) specifications <- rbind(specifications,data.frame(tag=paste0(v,"_log_sensitivity"),response=v,rate=FALSE,log=TRUE))
  results <- list(); states <- list()
  for(j in seq_len(nrow(specifications))) {
    spec <- specifications[j,]; tag <- spec$tag; v <- spec$response
    ans <- tryCatch({
      prepared <- prepare_model_data(d,v,spec$rate); dat <- prepared$data
      write.csv(data.frame(token_id=d$token_id,included=prepared$included),file.path(out,paste0(tag,"_inclusion.csv")),row.names=FALSE)
      if(spec$log) dat[[v]] <- log(dat[[v]])
      if(include_block && nlevels(dat$block)<2) stop("Block adjustment requested but only one block remains.")
      fixed <- if(spec$rate) "construction + rate_within + rate_between" else "construction"
      candidates <- unique(c(random,if(random=="full")"uncorrelated"))
      fits <- lapply(candidates,function(s)fit_candidate(dat,v,s,fixed,include_block))
      logs <- do.call(rbind,lapply(fits,`[[`,"log")); logs$selected <- logs$structure==random
      write.csv(logs,file.path(out,paste0(tag,"_fit_log.csv")),row.names=FALSE)
      for(k in seq_along(fits)) if(!inherits(fits[[k]]$model,"error")) saveRDS(fits[[k]]$model,file.path(out,paste0(tag,"_",candidates[k],"_model.rds")))
      selected <- fits[[1]]; if(inherits(selected$model,"error")) stop(selected$log$error)
      m <- selected$model
      capture.output(summary(m),file=file.path(out,paste0(tag,"_summary.txt")))
      pdf(file.path(out,paste0(tag,"_diagnostics.pdf")),width=10,height=8)
      tryCatch({par(mfrow=c(2,2));plot(fitted(m),resid(m),xlab="Fitted",ylab="Residuals");abline(h=0,lty=2)
        qqnorm(resid(m));qqline(resid(m));boxplot(resid(m)~dat$construction,ylab="Residuals",xlab="Construction")
        plot(fitted(m),sqrt(abs(resid(m))),xlab="Fitted",ylab="sqrt(abs(residual))")},finally=dev.off())
      co <- coef(summary(m))["constructionNPC",]
      interval <- list(lower=NA_real_,upper=NA_real_,status="not_requested",detail="")
      inference <- selected$log$status=="success"
      if(ci && inference) interval <- profile_interval(m)
      if(!inference) interval$status <- "withheld_model_warning"
      diagnostics <- if(v=="vowel_proportion")"Gaussian proportion model: bounded outcome; check predictions/residuals; consider beta-type model separately." else "Residual plots require human assessment; no automatic assumption pass."
      if(v=="vowel_proportion" && any(fitted(m)<0 | fitted(m)>1)) diagnostics <- paste(diagnostics,"WARNING: fitted values outside [0,1].")
      writeLines(diagnostics,file.path(out,paste0(tag,"_diagnostic_notes.txt")))
      row <- data.frame(measure=tag,role=if(!spec$log && !spec$rate && v %in% primary)"user_declared_primary" else "exploratory",
        model_status=selected$log$status,qc_warnings=sum(qc$severity=="warning"),ci_status=interval$status,ci_detail=interval$detail,
        n_tokens=nrow(dat),n_speakers=nlevels(dat$speaker),n_items=nlevels(dat$item_pair),
        estimate_NPC_minus_SN=co["Estimate"],SE=co["Std. Error"],df=if(inference)co["df"] else NA_real_,
        p_uncorrected=if(inference)co["Pr(>|t|)"] else NA_real_,ci_lower=interval$lower,ci_upper=interval$upper,
        response_scale=if(spec$log)"natural_log" else if(grepl("f0_",v))"semitones" else "original_units",
        formula=paste(deparse(formula(m)),collapse=" "),row.names=NULL)
      results[[tag]] <- row
      data.frame(measure=tag,status=if(!inference || interval$status %in% c("failed","warning"))"warning" else "success",detail=diagnostics)
    },error=function(e)data.frame(measure=tag,status="failed",detail=conditionMessage(e)))
    states[[tag]] <- ans
  }
  status <- do.call(rbind,states); write.csv(status,file.path(out,"analysis_status.csv"),row.names=FALSE)
  if(length(results)) {
    result <- do.call(rbind,results)
    # Holm across every scheduled scalar analysis, including failed tests in family size.
    result$p_holm_all_scheduled <- p.adjust(result$p_uncorrected,method="holm",n=nrow(specifications))
    write.csv(result,file.path(out,"construction_effects.csv"),row.names=FALSE)
  }
  failed <- status[status$status=="failed",]
  writeLines(if(nrow(failed))paste(failed$measure,failed$detail,sep=": ") else "None.",file.path(out,"failed_analyses.txt"))
  if(all(status$status=="failed")) stop("All analyses failed; see analysis_status.csv.")
  invisible(status)
}
analysis_cli <- function(args=commandArgs(trailingOnly=TRUE)) {
  if(length(args)<2) stop("Usage: Rscript analyze_acoustics.R input.csv_OR_folder NEW_output [--random=full|uncorrelated|intercepts] [--reason=text] [--block] [--log-duration] [--primary=a,b] [--no-ci]")
  opts <- args[-c(1,2)]; get_opt <- function(key,default) {x<-opts[startsWith(opts,paste0(key,"="))]; if(length(x)>1)stop("Repeated option");if(length(x))substring(x,nchar(key)+2) else default}
  known <- grepl("^--(random|reason|primary)=",opts) | opts %in% c("--block","--log-duration","--no-ci")
  if(any(!known))stop("Unknown option: ",paste(opts[!known],collapse=","))
  primary <- get_opt("--primary",""); primary <- if(nzchar(primary))strsplit(primary,",",fixed=TRUE)[[1]] else character()
  run_analysis(args[1],args[2],get_opt("--random","full"),"--block" %in% opts,"--log-duration" %in% opts,primary,!"--no-ci" %in% opts,get_opt("--reason",""))
}
if(sys.nframe()==0L) analysis_cli()
