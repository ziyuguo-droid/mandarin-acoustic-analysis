# Deterministic synthetic data only: no participant observations.
set.seed(20261106)
d <- expand.grid(speaker=sprintf("S%02d",1:8),item_pair=sprintf("%02d",1:8),construction=c("SN","NPC"),block=c("B01","B02"),stringsAsFactors=FALSE)
d$token_id <- paste("SYNTHETIC",d$speaker,d$item_pair,d$construction,d$block,sep="_"); d$synthetic <- TRUE
sp<-rnorm(8,0,18);it<-rnorm(8,0,8);ss<-rnorm(8,0,7);ii<-rnorm(8,0,4)
s<-match(d$speaker,unique(d$speaker));i<-as.integer(d$item_pair);npc<-as.numeric(d$construction=="NPC")
d$syllable_duration_ms<-200+sp[s]+it[i]+npc*(-35+ss[s]+ii[i])+rnorm(nrow(d),0,12)
d$vowel_proportion<-plogis(.3+npc*(-.2)+rnorm(nrow(d),0,.2));d$vowel_duration_ms<-d$syllable_duration_ms*d$vowel_proportion
d$nonvocalic_duration_ms<-d$syllable_duration_ms-d$vowel_duration_ms
for(measure in c("onset","mean","offset"))d[[paste0("f0_",measure,"_st")]]<-switch(measure,onset=4,mean=2,offset=0)+sp[s]/30+it[i]/20+npc*(-.8+ss[s]/15)+rnorm(nrow(d),0,.6)
d$f0_fall_st<-d$f0_onset_st-d$f0_offset_st;d$f0_range_st<-abs(d$f0_fall_st)+runif(nrow(d),.3,1)
d$articulation_rate<-4.8+sp[s]/100+npc*(-.2)+rnorm(nrow(d),0,.2)
d$reference_rate_syll_s<-ave(d$articulation_rate,d$speaker,FUN=mean)
d$rate_normalized_syllable_duration_ms<-d$syllable_duration_ms*d$articulation_rate/d$reference_rate_syll_s
for(tm in seq(5,95,10))d[[sprintf("F0_t%02d_ST",tm)]]<-(1-tm/100)*d$f0_onset_st+tm/100*d$f0_offset_st+rnorm(nrow(d),0,.1)
d$f0_mean_st[c(1,10)]<-NA;d$F0_t05_ST[1:4]<-NA
write.csv(d,"synthetic_measurements.csv",row.names=FALSE,na="")
