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
#  x use throw for accept and beep
#  x basic completion interface
#  ? modes support
#  - output attrs
#  - history-incremental-search
#  - cumulative yank
#  ? completion UI choices
#  ? prefix keymaps (eg: ^L=redraw-line; ^L^L=redraw-all-lines)
#  ? numeric arguments
#  ? yank-last-arg?  Not yank ring, stuff that.
#  ? mark
#  ? transpositions
#  ? undo
#  ? ^search^replace and !! and !prefix and !-n
# OPTIMISATION:
#  - don't redraw so greedily when forthing
#  - incrementally fix up lines

source getline.tcl

namespace path ::getline

proc complete-tcl-command {s t} {
    set j [string length $s]
    while {[info complete [string range $s $j end]\n} {incr j -1}
    incr j
    # now get clever with procmap
}

proc complete-word {s t} {
    regexp {([a-zA-Z0-9_:-]*)$} $s -> w
    if {$w eq ""} {return}
    set l [string length $w]
    set cs [info commands ${w}*]            ;# here's the dictionary!
    if {[llength $cs] == 1} {
        lassign $cs comp
        set comp [string range $comp [string length $w] end]
        return [list insert "$comp "]
    } else {
        return [list flash-message $cs]     ;# FIXME: abbreviate
    }
}


proc main {args} {
    exec stty raw -echo <@ stdin
    trace add variable args unset {apply {args {exec stty -raw echo <@ stdin}}}

    chan configure stdin -blocking 0
    chan configure stdout -buffering none
    chan event stdin readable [info coroutine]

    set prompt "\[[info patch]\]% "
    Getline create getline \
                        -prompt $prompt \
                        -completer complete-word \
    ;#
    # -iscomplete complete?
    # -history $obj
    #getline add-maps [read $mapsfile]

    finally getline destroy

    while 1 {
        set input [getline getline]             ;# can return -code break/continue
        try {
            uplevel #0 $input
        } on ok {res opt} {
            if {$res eq ""} continue
            puts [tty::attr bold]\ [list $res][tty::attr]
        } on error {res opt} {
            puts [tty::attr fg red bold]\ $res[tty::attr]
        }
    }
}

coroutine Main try {
    main {*}$argv
    exit
}
vwait forever
