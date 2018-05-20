# WIBNI: continuation prompts, colours, completion
#  - M-: to issue commands directly to getline
#  - M-digit digit .. counts so \e5^X^E opens an editor with LAST FIVE LINES OMG
#  - factor command definitions for symmetry, but don't go overboard
#  - attrs
#  - use exceptions for beep, result
#  - inter-line nav without excessive redraw
#  - a manual, with that call graph
# TODO:
#  x char-wise nav
#  x line-wise nav
#  x wrap handling
#  x word-wise nav
#  x history (basic)
#  x history-search
#  x basic yank
#  x C-x C-e EDITOR (get smarter)
#  x flash message
#  x tcloo'ify
#  x multi-line input (debug further)
#   x fix line joinage: too much redraw by far
#   x continuation prompts
#   x multi-line redraw (just a keymap / action naming thing?)
#  x fix up history
#  x objectify keymap
#  x -options to Getline, move history etc into components
#  x chan independence
#  x up/down navigation in lines
#  x actions can have arguments (but not user-controlled eg counts)
#  - use throw for accept and beep
#  - support modes for:
#   - cumulative yank
#   - completion
#   - history-incremental-search
#  - output attrs
#  ? prefix keymaps (eg: ^L=redraw-line; ^L^L=redraw-all-lines)
#  ? numeric arguments
#  - yank-last-arg?  Not yank ring, stuff that.
#  ? mark
#  ? transpositions
#  ? undo
#  ? ^search^replace and !! and !prefix and !-n
# OPTIMISATION:
#  - don't redraw so greedily when forthing
#  - incrementally fix up lines

source getline.tcl

namespace path ::getline

proc main {args} {
    exec stty raw -echo <@ stdin
    trace add variable args unset {apply {args {exec stty -raw echo <@ stdin}}}

    chan configure stdin -blocking 0
    chan configure stdout -buffering none
    chan event stdin readable [info coroutine]

    set prompt "\[[info patch]\]% "
    Getline create getline -prompt $prompt

    #watchexec getline

    finally getline destroy

    while 1 {
        set input [getline getline]             ;# can return -code break/continue
        puts " -> {[srep $input]}"
    }
}

if 0 {
    proc complete? {s} {info complete $s\n}
    proc complete-tcl-command {s} {
        # .. use procmap
        # return list of possible completions
    }
    # complete modes: first, cycle, showbelow, ..
    Getline create getline \
                    -chan stdin \
                    -prompt "\[[info patchlevel]\]% " \
                    -history % \
                    -iscomplete complete? \
                    -complete-mode cycle \
                    -completer complete-tcl-command
    getline add-maps [read $mapsfile]
    while 1 {
        set cmd [getline getline]
        try {
            uplevel #0 $cmd
        } on ok {res opt} {
            # getline emit " $res" {bold}
            puts " $res"
        } on error {err opt} {
            # getline emit " $error" {fg red bold}
            puts stderr "Error: $err"
        }
    }
    getline destroy
}

coroutine Main try {
    main {*}$argv
    exit
}
vwait forever
