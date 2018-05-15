#
# The sticky point right now is the relationship between Getline and Getlines:
# as a subclass, Getlines wants to redefine some of its parent's methods to
# provide whole-input behaviour, while other methods it wants to preserve as
# single-line actions.  This, in an inheritance scenario, leads to some odd
# conflicts.
#
# I think the solution is (of course) composition:
#  - Getlines has-a Getline
#  - Getlines getline tries to dispatch on its own methods first
#  - those explicitly call down to Getline where appropriate
#  - whole-input-replacing actions (history-*) need to "call up"

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
#   - continuation prompts
#   - multi-line redraw (just a keymap / action naming thing?)
#  x fix up history
#  x objectify keymap
#  x -options to Getline, move history etc into components
#  x chan independence
#  - use throw for accept .. and beep?
#  ? prefix keymaps (eg: ^L=redraw-line; ^L^L=redraw-all-lines)
#  - history-incremental-search .. this is a mode!
#  - output attrs
#  - completion ... with ui!
#  ? numeric arguments
#  - cumulative yank (mode?)
#  - yank-last-arg?  Not yank ring, stuff that.
#  ? mark
#  ? transpositions
#  ? undo
#  ? ^search^replace and !! and !prefix and !-n
# OPTIMISATION:
#  - don't redraw so greedily when forthing
#  - incrementally fix up lines
source input.tcl
source output.tcl
source keymap.tcl
source history.tcl
source util.tcl     ;# ssplit

proc rep {c} {
    if {[string length $c] != 1} {error "Bad input: [binary encode hex $c]"}
    if {[string is print $c]} {return $c}
    return "\\x[binary encode hex $c]"
}

proc srep {s} {
    join [lmap c [split $s ""] {rep $c}] ""
}

proc word-length-before {s i} {
    set j 0
    foreach ab [regexp -inline -indices -all {.\m} $s] {
        lassign $ab a b
        incr a
        if {$a >= $i} break
        set j $a
    }
    expr {$i - $j}
}
proc word-length-after {s i} {
    if {![regexp -indices -start $i {\M} $s ab]} {return $i}
    lassign $ab a b
    expr {$a - $i}
}

source getline.tcl
source getlines.tcl

proc main {args} {
    exec stty raw -echo <@ stdin
    trace add variable args unset {apply {args {exec stty -raw echo <@ stdin}}}

    chan configure stdin -blocking 0
    chan configure stdout -buffering none
    chan event stdin readable [info coroutine]

    set prompt "\[[info patch]\]% "
    Getlines create getline -prompt $prompt

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
    Getlines create getline \
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
