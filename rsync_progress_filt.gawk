#!/bin/gawk -f

BEGIN {
    RS = "[\n\r]"
    last_percent = ""
}

{
    # If the input record was terminated by a carriage return it's a progress
    # line (rsync prints progress with \r). Use RT to preserve the original
    # last character when printing.
    if (RT == "\r") {
        line = $0

        # Extract percent - look for pattern like "12%" or "100%"
        if (match(line, /[0-9]+%/)) {
            percent = substr(line, RSTART, RLENGTH)

            # If same as last percent, send to stderr with CR; if changed,
            # send to stdout with newline.
            if (percent == last_percent) {
                printf "%s\r", line > "/dev/stderr"
            } else {
                printf "%s\n", line
                last_percent = percent
            }
        } else {
            # No percent found, treat as normal progress-like line: print with NL
            printf "%s\n", line
        }
    } else {
        # Not a progress line, send to stdout preserving the original terminator
        if (RT != "")
            printf "%s%s", $0, RT
        else
            printf "%s", $0
    }
}