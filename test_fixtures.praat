# Generates synthetic Praat fixtures only. Run in a NEW empty directory.
form Synthetic fixtures
    sentence Folder .
endform
createFolder: folder$
for fileIndex from 1 to 2
    sound = Create Sound from formula: "synthetic", 1, 0, 1, 16000, "0"
    Save as WAV file: folder$ + "/test" + string$(fileIndex) + ".wav"
    tg = To TextGrid: "target other points", "points"
    Insert boundary: 1, 0.25
    Insert boundary: 1, 0.75
    Set interval text: 1, 2, "bu"
    Set interval text: 2, 1, "untouched"
    Insert point: 3, 0.5, "point"
    Save as text file: folder$ + "/test" + string$(fileIndex) + ".TextGrid"
    removeObject: sound, tg
endfor
