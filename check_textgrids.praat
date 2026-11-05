# Manual interval review, NOT automatic annotation validation.
# Original WAV/TextGrid files are never overwritten. Reviewed copies and snapshots
# are created in reviewed/. Read USAGE.md before use. Test_actions is for synthetic tests only.
form Review TextGrid intervals
    sentence Folder .
    word Sound_extension .wav
    natural Tier 1
    boolean Skip_empty_intervals 1
    boolean Auto_play 1
    positive Padding_(s) 0.15
    natural Start_from_file 1
    natural Start_from_interval 1
    boolean Save_on_leaving_file 1
    sentence Test_actions none
endform

clearinfo
folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)
list = Create Strings as file list: "review_files", folder$ + "/*" + sound_extension$
nFiles = Get number of strings
if nFiles = 0
    removeObject: list
    exitScript: "No matching audio files."
endif
if start_from_file > nFiles
    removeObject: list
    exitScript: "Start_from_file exceeds the file count."
endif
createFolder: folder$ + "/reviewed"
quit = 0
f = start_from_file
lastFile = f
lastInterval = start_from_interval
actionIndex = 0
headless = test_actions$ <> "none"
remainingActions$ = test_actions$
while f <= nFiles and quit = 0
    lastFile = f
    selectObject: list
    soundName$ = Get string: f
    base$ = left$(soundName$, length(soundName$) - length(sound_extension$))
    tgPath$ = folder$ + "/" + base$ + ".TextGrid"
    if fileReadable(tgPath$)
        # Read failures stop explicitly before any original is written.
        sound = Read from file: folder$ + "/" + soundName$
        dur = Get total duration
        tg = Read from file: tgPath$
        tgStart = Get start time
        tgEnd = Get end time
        if tgStart < 0 or tgEnd > dur + 1e-6
            exitScript: "TextGrid domain extends outside the audio; original is untouched."
        endif
        nTiers = Get number of tiers
        for tierIndex from 1 to nTiers
            savedTierName$[tierIndex] = Get tier name: tierIndex
            savedTierType[tierIndex] = Is interval tier: tierIndex
        endfor
        tierOK = 0
        if tier <= nTiers
            tierOK = Is interval tier: tier
        endif
        if tierOK
            tierName$ = Get tier name: tier
            version = 1
            repeat
                prefix$ = folder$ + "/reviewed/" + base$ + ".review" + string$(version)
                output$ = prefix$ + ".TextGrid"
                backup$ = prefix$ + ".before.TextGrid"
                progress$ = prefix$ + ".progress.txt"
                collisionList = Create Strings as file list: "existing_review_prefix", prefix$ + "*"
                collisionCount = Get number of strings
                removeObject: collisionList
                selectObject: tg
                collision = collisionCount > 0
                version = version + 1
            until collision = 0
            # Snapshot of the original in-memory object, before editing. Original remains untouched.
            Save as text file: backup$
            if not fileReadable(backup$)
                exitScript: "Could not create review snapshot; original is untouched."
            endif
            if not headless
                selectObject: sound, tg
                View & Edit
            endif
            i = 1
            if f = start_from_file
                i = start_from_interval
            endif
            selectObject: tg
            nInt = Get number of intervals: tier
            if i > nInt
                exitScript: "Start_from_interval exceeds the interval count; original is untouched."
            endif
            dir = 1
            nextFile = 0
            forcePlay = 0
            while nextFile = 0 and quit = 0
                selectObject: tg
                # A changed tier layout cannot safely be addressed by the original tier index.
                currentTiers = Get number of tiers
                if currentTiers <> nTiers
                    exitScript: "Tier structure changed in editor. Save manually to a NEW file; original is untouched."
                endif
                @checkTierLayout
                currentName$ = Get tier name: tier
                currentIntervalTier = Is interval tier: tier
                if currentName$ <> tierName$ or currentIntervalTier = 0
                    exitScript: "Review tier identity changed. Save manually to a NEW file."
                endif
                nInt = Get number of intervals: tier
                # Each search is bounded; reversing past the first interval does not wrap or clamp repeatedly.
                candidate = i
                found = 0
                while candidate >= 1 and candidate <= nInt and found = 0
                    candidateLabel$ = Get label of interval: tier, candidate
                    if skip_empty_intervals = 0 or index_regex(candidateLabel$, "\S") <> 0
                        found = 1
                    else
                        candidate = candidate + dir
                    endif
                endwhile
                if found = 0
                    if dir < 0
                        # No earlier nonempty interval: redisplay last reviewed interval.
                        i = lastInterval
                        dir = 1
                    else
                        nextFile = 1
                    endif
                else
                    i = candidate
                    lastInterval = i
                    lab$ = Get label of interval: tier, i
                    t1 = Get start time of interval: tier, i
                    t2 = Get end time of interval: tier, i
                    beforeCount = nInt
                    if not headless
                        editor: tg
                            Zoom: max(0, t1 - padding), min(dur, t2 + padding)
                            Select: t1, t2
                            if auto_play or forcePlay
                                Play: t1, t2
                            endif
                        endeditor
                    endif
                    forcePlay = 0
                    label$ = lab$
                    if headless
                        actionIndex = actionIndex + 1
                        action$ = extractWord$(remainingActions$, "")
                        remainingActions$ = replace_regex$(remainingActions$, "^\S+\s*", "", 1)
                        clicked = 3
                        if action$ = "previous"
                            clicked = 1
                        elsif action$ = "replay"
                            clicked = 2
                        elsif action$ = "next_file"
                            clicked = 4
                        elsif action$ = "save_exit" or action$ = ""
                            clicked = 5
                        elsif action$ = "label"
                            label$ = "synthetic_checked"
                            clicked = 2
                        elsif action$ = "split"
                            Insert boundary: tier, (t1 + t2) / 2
                            label$ = "must_not_be_written"
                            clicked = 2
                        elsif action$ = "boundary_move"
                            Remove left boundary: tier, i
                            Insert boundary: tier, t1 + 0.05
                            label$ = "must_not_be_written"
                            clicked = 5
                        elsif action$ = "editor_conflict"
                            Set interval text: tier, i, "editor_edit"
                            label$ = "must_not_be_written"
                            clicked = 5
                        elsif action$ = "editor_label"
                            Set interval text: tier, i, "editor_edit"
                            clicked = 2
                        elsif action$ <> "next"
                            exitScript: "Unknown synthetic test action."
                        endif
                    else
                        beginPause: "Review TextGrid"
                            comment: "File " + string$(f) + "/" + string$(nFiles) + ": " + base$
                            comment: "Interval " + string$(i) + ": " + fixed$(t1, 3) + "-" + fixed$(t2, 3) + " s"
                            comment: "Edit boundaries in the editor. If identity changes, popup label edits are rejected."
                            sentence: "Label", lab$
                        # Closing the dialog maps to Save and exit; no ambiguous Stop/discard button.
                        clicked = endPause: "Previous", "Replay", "Next", "Next file", "Save and exit", 3, 5
                    endif
                    selectObject: tg
                    currentTiers = Get number of tiers
                    if currentTiers <> nTiers
                        exitScript: "Tier layout changed; save manually to a NEW file."
                    endif
                    @checkTierLayout
                currentName$ = Get tier name: tier
                    if currentName$ <> tierName$
                        exitScript: "Tier name changed; save manually to a NEW file."
                    endif
                    currentCount = Get number of intervals: tier
                    safe = currentCount = beforeCount
                    if safe
                        currentStart = Get start time of interval: tier, i
                        currentEnd = Get end time of interval: tier, i
                        currentLabel$ = Get label of interval: tier, i
                        safe = abs(currentStart - t1) < 1e-9 and abs(currentEnd - t2) < 1e-9 and currentLabel$ = lab$
                    endif
                    if label$ <> lab$
                        if safe
                            Set interval text: tier, i, label$
                        else
                            appendInfoLine: "Rejected stale popup label: ", base$, " interval ", i
                        endif
                    endif
                    # Re-anchor navigation after boundary edits to the old interval midpoint.
                    anchor = Get interval at time: tier, (t1 + t2) / 2
                    if anchor < 1
                        anchor = 1
                    endif
                    lastInterval = anchor
                    appendFileLine: progress$, "file=", f, " interval=", anchor, " button=", clicked, " popup_safe=", safe
                    if clicked = 1
                        dir = -1
                        i = anchor - 1
                    elsif clicked = 2
                        dir = 1
                        i = anchor
                        forcePlay = 1
                    elsif clicked = 3
                        dir = 1
                        i = anchor + 1
                    elsif clicked = 4
                        nextFile = 1
                    else
                        quit = 1
                        i = anchor
                    endif
                endif
            endwhile
            if save_on_leaving_file or quit
                selectObject: tg
                Save as text file: output$
                verify = Read from file: output$
                verifyTiers = Get number of tiers
                removeObject: verify
                if verifyTiers <> nTiers
                    exitScript: "Saved file failed tier-count verification. Original is untouched."
                endif
                appendInfoLine: "Saved reviewed copy: ", output$
            else
                appendInfoLine: "Reviewed changes not saved (Save_on_leaving_file=0): ", base$
            endif
        else
            appendInfoLine: "Skipped: missing/non-interval tier in ", base$
        endif
        removeObject: sound, tg
    else
        appendInfoLine: "Skipped missing TextGrid: ", base$
    endif
    f = f + 1
endwhile
removeObject: list
appendInfoLine: "Last visited file=", lastFile, " interval=", lastInterval, ". Resume via Start_from_file and Start_from_interval."



procedure checkTierLayout
    for layoutTier from 1 to nTiers
        layoutName$ = Get tier name: layoutTier
        layoutType = Is interval tier: layoutTier
        if layoutName$ <> savedTierName$[layoutTier] or layoutType <> savedTierType[layoutTier]
            exitScript: "Tier layout changed; save manually to a NEW file. Original is untouched."
        endif
    endfor
endproc
