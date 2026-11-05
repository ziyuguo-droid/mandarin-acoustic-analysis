# check_textgrids.praat
# 逐个区间快速检查 TextGrid：自动缩放到当前区间、自动播放，用按钮切换，不用拖进度条
# 用法：Praat > Open Praat script... > Run
# 要求：音频和 TextGrid 在同一文件夹，且同名（如 a.wav / a.TextGrid）

form 快速检查 TextGrid
    sentence Folder D:/data
    word Sound_extension .wav
    natural Tier 1
    boolean Skip_empty_intervals 1
    boolean Auto_play 1
    positive Padding_(s) 0.15
    natural Start_from_file 1
    boolean Save_on_leaving_file 1
endform

clearinfo
folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)
list = Create Strings as file list: "files", folder$ + "/*" + sound_extension$
nFiles = Get number of strings
if nFiles = 0
    removeObject: list
    exitScript: "文件夹里没有找到 *" + sound_extension$ + " 文件"
endif

quit = 0
lastFile = start_from_file
f = start_from_file
while f <= nFiles and quit = 0
    lastFile = f
    selectObject: list
    soundName$ = Get string: f
    base$ = soundName$ - sound_extension$
    tgPath$ = folder$ + "/" + base$ + ".TextGrid"

    if fileReadable(tgPath$)
        sound = Read from file: folder$ + "/" + soundName$
        dur = Get total duration
        tg = Read from file: tgPath$
        nTiers = Get number of tiers
        tierOK = 0
        if tier <= nTiers
            tierOK = Is interval tier: tier
        endif

        if tierOK
            selectObject: sound, tg
            View & Edit
            i = 1
            dir = 1
            forcePlay = 0
            nextFile = 0
            while nextFile = 0 and quit = 0
                selectObject: tg
                nInt = Get number of intervals: tier
                if i < 1
                    i = 1
                    dir = 1
                endif
                if i > nInt
                    nextFile = 1
                else
                    lab$ = Get label of interval: tier, i
                    if skip_empty_intervals and index_regex(lab$, "\S") = 0
                        i = i + dir
                    else
                        t1 = Get start time of interval: tier, i
                        t2 = Get end time of interval: tier, i
                        editor: tg
                            Zoom: max(0, t1 - padding), min(dur, t2 + padding)
                            Select: t1, t2
                            if auto_play or forcePlay
                                Play: t1, t2
                            endif
                        endeditor
                        forcePlay = 0

                        beginPause: "检查 TextGrid"
                            comment: "文件 " + string$(f) + " / " + string$(nFiles) + "：  " + base$
                            comment: "区间 " + string$(i) + " / " + string$(nInt) + "    (" + fixed$(t1, 3) + " – " + fixed$(t2, 3) + " s)"
                            comment: "可直接在下面改标注；边界请在编辑窗口里拖"
                            sentence: "Label", lab$
                        clicked = endPause: "上一个", "重播", "下一个", "下个文件", "保存并退出", 3

                        # 如果在弹窗里改了标注，写回 TextGrid
                        if label$ <> lab$
                            selectObject: tg
                            nInt = Get number of intervals: tier
                            if i <= nInt
                                Set interval text: tier, i, label$
                            endif
                        endif

                        if clicked = 1
                            dir = -1
                            i = i - 1
                        elsif clicked = 2
                            forcePlay = 1
                        elsif clicked = 3
                            dir = 1
                            i = i + 1
                        elsif clicked = 4
                            nextFile = 1
                        else
                            quit = 1
                        endif
                    endif
                endif
            endwhile
        else
            appendInfoLine: "跳过（第 ", tier, " 层不存在或不是 interval tier）: ", base$
        endif

        if save_on_leaving_file and tierOK
            selectObject: tg
            Save as text file: tgPath$
        endif
        removeObject: sound, tg
    else
        appendInfoLine: "跳过（没有同名 TextGrid）: ", soundName$
    endif
    f = f + 1
endwhile

removeObject: list
if quit
    appendInfoLine: "已退出，停在第 ", lastFile, " 个文件（", base$, "）。下次 Start_from_file 填 ", lastFile, " 即可接着检查。"
else
    appendInfoLine: "全部 ", nFiles, " 个文件检查完毕。"
endif
