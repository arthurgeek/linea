# Only these four results vary with host capability. Preserve every other byte.
BEGIN {
    gpu["gpu.completed map preserves GPU subnormals and refuses unsupported ordinary bodies"] = 1
    gpu["gpu.matrix dimensions follow nested array lengths"] = 1
    gpu["gpu.opening a device reports unavailable capability or owns a device"] = 1
    gpu["gpu.upload preserves raw bits and checks zero dimensions before overflow"] = 1
}
substr($0, 7) in gpu {
    name = substr($0, 7)
    if (seen[name]++ || ($1 != "ok" && $1 != "SKIP")) {
        bad = 1
        print
        next
    }
    pending_skip = $1 == "SKIP"
    if (pending_skip) skipped_gpu++
    print "GPU   " name
    next
}
/^        GPU device unavailable$/ && pending_skip { pending_skip = 0; next }
/^[0-9]+ passed, [0-9]+ failed(, [0-9]+ skipped)?$/ {
    summaries++
    skipped = NF == 6 ? $5 : 0
    if ($3 != 0 || $1 + skipped != expected || skipped != skipped_gpu) bad = 1
    print "non-GPU: " $1 - (4 - skipped_gpu) " passed, " $3 " failed"
    next
}
{ pending_skip = 0; print }
END {
    for (name in gpu) if (seen[name] != 1) bad = 1
    if (summaries != 1 || bad) exit 1
}
