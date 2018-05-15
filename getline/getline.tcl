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
#   - fix line joinage: too much redraw by far
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

proc putl args {puts $args}
proc finally args {
    set ns [uplevel 1 {namespace current}]
    tailcall trace add variable :#\; unset [list apply [list args $args $ns]]
}
proc alias {alias cmd args} {
    set ns [uplevel 1 {namespace current}]
    set cmd [uplevel 1 namespace which $cmd]
    interp alias ${ns}::$alias $cmd {*}$args
}

proc rep {c} {
    if {[string length $c] != 1} {error "Bad input: [binary encode hex $c]"}
    if {[string is print $c]} {return $c}
    return "\\x[binary encode hex $c]"
}

proc srep {s} {
    join [lmap c [split $s ""] {rep $c}] ""
}

proc complete? {s} {info complete $s\n}

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

## class Getline is an "engine".  Methods on it may be addressed in the keymap.
# Getline is a single-line-only getter; Getlines extends on it with line continuation capability
#
oo::class create Getline {

    # state:
    variable Yank

    # options:
    variable Prompt
    variable Chan
    method Complete? {input} { info complete $input\n }
    method Completions {s}   { return "" }
    method History {args} {
        History create History
        oo::objdefine [self] forward History History
        tailcall my History {*}$args
    }

    constructor {args} {
        set Yank ""
        set Prompt "getline> "
        set Chan stdout

        my Configure {*}$args

        Input create             input
        Output create            output $Chan
        keymap::KeyMapper create keymap [expr {$Chan eq "stdout" ? "stdin" : $Chan}]

        input reset
        output reset $Prompt
    }

    method Configure {args} {
        set OptSpec {
            -prompt     { set Prompt $val }
            -chan       { set Chan $val }
            -history    { oo::objdefine [self] forward History [uplevel 1 [list namespace which $val]] }
            -iscomplete { oo::objdefine [self] forward Complete? [uplevel 1 [list namespace which $val]] }
            -completer  { oo::objdefine [self] forward Completions [uplevel 1 [list namespace which $val]] }
        }

        dict for {opt val} $args {
            set pat $opt*
            set matched 0
            dict for {key script} $OptSpec {
                if {[string match $pat* $opt]} {
                    try $script
                    set matched 1
                    break
                }
            }
            if {!$matched} {
                return -code error "Unknown option; expected one of [join [dict keys $OptSpec] ", "]."
            }
        }
    }

    method getline {} {
        set cmds [info object methods [self] -all]

        while 1 {
            # {TOKEN tok {c c c}} or {LITERAL "" {c c c}}
            lassign [keymap gettok] kind tok chars
            if {$kind eq "TOKEN"} {
                try {
                    engine $tok
                    continue
                } trap {TCL LOOKUP METHOD *} {} { }
            }
            foreach char $chars {
                engine insert $char
            }
            # if [getline display-rows] has changed, redraw-following
        }
    }

    method beep {msg} {
        output beep
        if {$msg ne ""} {tailcall output flash-message $msg}
    }

    # action methods:
    method get {} {
        input get
    }

    method sigpipe {} {
        if {[input get] ne ""}  { my beep "sigpipe with [string length [input get]] chars"; return }
        return -level 2 -code break
    }
    method sigint {}      { return -level 2 -code continue }
    method redraw {}      { output redraw }

    method insert {s} {
        foreach c [split $s ""] {
            input insert $c
            output insert [rep $c]  ;# attr?
        }
    }

    method goto {i} {
        if {$i < [input pos]} {
            my back  [expr {[input pos] - $i}]
        } else {
            my forth [expr {$i - [input pos]}]
        }
    }

    method back {{n 1}} {
        if {$n == 0} return
        if {[input pos] < 1} {my beep "back at BOL"; return}
        set n [expr {min($n, [input pos])}]
        if {$n == 0} return
        output back [string length [srep [input back $n]]]
    }
    method forth {{n 1}} {
        if {$n == 0} return
        if {[input rpos] < 1} {my beep "forth at EOL"; return}
        set n [expr {min($n, [input rpos])}]
        if {$n == 0} return
        output forth [string length [srep [input forth $n]]]
    }

    method backspace {{n 1}} {
        if {$n == 0} return
        if {[input pos] < 1} {my beep "backspace at BOL"; return}
        set n [expr {min($n, [input pos])}]
        if {$n == 0} return
        set in [input backspace $n]
        output backspace [string length [srep $in]]
        return $in
    }
    method delete {{n 1}} {
        if {$n == 0} return
        if {[input rpos] < 1} {my beep "delete at EOL"; return}
        set n [expr {min($n, [input rpos])}]
        if {$n == 0} return
        set in [input delete $n]
        output delete [string length [srep $in]]
        return $in
    }

    method clear {} {
        set r [input get]
        if {[input rpos]} {my kill-after}
        if {[input pos]} {my kill-before}
        return $r
    }
    method replace-input {s} {
        my clear
        my insert $s
    }

    method set-state {{s ""} {p 0}} {
        input set-state $s $p
        ssplit $s $p -> a b
        set a [srep $a]; set b [srep $b]    ;# attrs? :(
        output set-state $Prompt$a$b [string length $Prompt$a]
    }

    method yank {s} { variable Yank ; set Yank $s }
    method paste {} { variable Yank ; my insert $Yank }

    method yank-before {}      { my yank [my kill-before] }
    method yank-after {}       { my yank [my kill-after] }
    method yank-word-before {} { my yank [my kill-word-before] }
    method yank-word-after {}  { my yank [my kill-word-after] }

    method home {}             { my back      [input pos] }
    method end {}              { my forth    [input rpos] }
    method kill-before {}      { my backspace [input pos] }
    method kill-after {}       { my delete   [input rpos] }

    method back-word {}        { my back      [word-length-before [input get] [input pos]] }
    method forth-word {}       { my forth     [word-length-after  [input get] [input pos]] }
    method kill-word-before {} { my backspace [word-length-before [input get] [input pos]] }
    method kill-word-after {}  { my delete    [word-length-after  [input get] [input pos]] }
    # softbreak tab

    method history-prev {} {
        set s [my History prev [my get]]
        if {$s eq ""}   { my beep "no more history!"; return }
        my replace-input $s
    }
    method history-next {} {
        set s [my History next [my get]]
        if {$s eq ""}   { my beep "no more history!"; return }
        my replace-input $s
    }
    method history-prev-starting {} {
        set pos [input pos]
        set s [my History prev-starting [input pre] [my get]]
        if {$s eq ""}   { my beep "no more matching history!"; return }
        my kill-after
        my insert [string range $s $pos end]
        my goto $pos
    }
    method history-next-starting {} {
        set pos [input pos]
        set s [my History next-starting [input pre] [my get]]
        if {$s eq ""}   { my beep "no more matching history!"; return }
        my kill-after
        my insert [string range $s $pos end]
        my goto $pos
    }

    method accept {} {
        set input [my get]
        if {![string is space $input]}  { my History add $input }
        my end
        output emit \n
        return -code return $input  ;# FIXME: forcing [tailcall accept] is terrible
    }

    method newline {} {
        tailcall my accept
    }

    method editor {} {
        set fd [file tempfile fn]
        puts $fd [input get]
        close $fd
        exec $::env(VISUAL) $fn <@ stdin >@ stdout 2>@ stderr
        set fd [open $fn r]
        set data [read $fd]
        set data [string trimright $data \n]
        close $fd
        file delete $fn
        my clear
        my insert $data
    }
}


oo::class create Getlines {
    superclass Getline

    variable Lines
    variable Lineidx
    variable Prompts        ;# for getlines, there must be a list of prompts!
    variable Prompt         ;# actually belongs to Getline

    constructor {args} {
        set Lines   [list ""]
        set Lineidx 0
        next {*}$args
        set Prompts [list $Prompt]
    }

    method get {} {
        lset Lines $Lineidx [input get]
        join $Lines \n
    }

    method redraw-following {} {
        set line [lindex $Lines $Lineidx]
        set pos [input pos]
        my end
        set idx $Lineidx
        incr idx
        while {$idx < [llength $Lines]} {
            output emit \n
            set l [lindex $Lines $idx]
            my set-state $l [string length $l]
            my redraw
        }
        my set-state $line $pos
    }

    # [insert \n] might create a new line!
    method newline {} {
        set input [my get]
        if {[complete? $input]} {
            # FIXME: go down
            tailcall my accept
        }
        my insert \n
    }

    method insert {s} {
        foreach c [split $s ""] {
            if {$c ne "\n"} {
                next $c
            } elseif {[info complete [my get]\n]} {
                tailcall my accept
            } else {
                my insert-newline
            }
        }
    }

    method insert-newline {} {
        set rest [my kill-after]
        set Lines [linsert $Lines $Lineidx+1 $rest]
        set rows [output wrap [output pos] [output rpos]]
        output emit [tty::down $rows]          ;# hmmm
        output emit \n
        incr Lineidx
        my set-state [lindex $Lines $Lineidx]
        my redraw
    }

    method prior-line {} {
        if {$Lineidx == 0} {my beep "no prev line"; return}
        my home
        output emit [tty::up 1]
        lset Lines $Lineidx [input get]
        incr Lineidx -1
        my set-state [lindex $Lines $Lineidx]
        set nrows [output wrap 0 [output len]]    ;# hmmm
        output emit [tty::up $nrows]               ;# hmmm
        my redraw
    }
    method next-line {} {
        if {$Lineidx + 1 == [llength $Lines]} {my beep "no next line"; return}
        my end
        lset Lines $Lineidx [input get]
        incr Lineidx 1
        my set-state [lindex $Lines $Lineidx]
        output emit [tty::down 1]                  ;# hmmm
        my redraw
    }

    method kill-next-line {} {
        set r [lindex $Lines $Lineidx+1]
        set Lines [lreplace $Lines $Lineidx+1 $Lineidx+1]
        return $r
    }
    method kill-prev-line {} {
        set r [lindex $Lines $Lineidx-1]
        set Lines [lreplace $Lines $Lineidx-1 $Lineidx-1]
        return $r
    }

    method back {{n 1}} {
        if {$n <= [input pos]} {
            next $n
        } elseif {$Lineidx > 0} {
            my prior-line
            my end
        } else {my beep "back at beginning of input"}
    }
    method forth {{n 1}} {
        if {$n <= [input rpos]} {
            next $n
        } elseif {$Lineidx+1 < [llength $Lines]} {
            my next-line
            my home
        } else {my beep "forth at end of input"}
    }

    method backspace {{n 1}} {
        if {$n <= [input pos]} {
            next $n
        } elseif {$Lineidx > 0} {
            my prior-line
            my end
            set s [my kill-next-line]
            my insert $s
            my redraw
            my redraw-following
        } else {my beep "backspace at beginning of input"}
    }
    method delete {{n 1}} {
        if {$n <= [input rpos]} {
            next $n
        } elseif {$Lineidx+1 < [llength $Lines]} {
            set rest [my kill-next-line]
            my insert $rest
            my back [string length $rest]
            my redraw
            my redraw-following
        } else {my beep "delete at end of input"}
    }

    method up {{n 1}} {
        if {$Lineidx > 0} {
            set pos [input pos]
            my prior-line
            my home
            set pos [expr {min($pos,[input rpos])}]
            my forth $pos
        }
    }
    method down {{n 1}} {
        if {$Lineidx + 1 < [llength $Lines]} {
            set pos [input pos]
            my next-line
            my home
            set pos [expr {min($pos,[input rpos])}]
            my forth $pos
        }
    }

}


proc getline {{prompt "> "}} {

    # prompt history inchan outchan
    Getlines create engine -prompt \[[info patchlevel]\]%\ 
    finally engine destroy
    try {
        return [engine getline]
    } on break {} {
        return -code break
    } on continue {} {
        return -code continue
    }
    error "Must not get here!  [input reset]"
}

proc main {args} {
    exec stty raw -echo <@ stdin
    trace add variable args unset {apply {args {exec stty -raw echo <@ stdin}}}
    chan configure stdin -blocking 0
    chan configure stdout -buffering none
    chan event stdin readable [info coroutine]
    set prompt "\[[info patch]\]% "
    while 1 {
        set input [getline]             ;# can return -code break/continue
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
