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
#   - continuation prompts
#   - multi-line redraw (just a keymap / action naming thing?)
#  x fix up history
#  x objectify keymap
#  - work out lifetimes properly (long-lived Getline contains all other objs)
#  - chan independence
#  - use throw for accept .. and beep?
#  - prefix keymaps (eg: ^L=redraw-line; ^L^L=redraw-all-lines)
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

package require sqlite3
sqlite3 db {}

keymap::KeyMapper create keymap stdin
History create history
Input create input
Output create output stdout

proc beep {msg} {
    puts -nonewline \x07
    flash-message $msg
}

# probably belongs to output
proc flash-message {msg} {
    variable flashid
    catch {after cancel $flashid}
    output emit [tty::save]
    lassign [exec stty size] rows cols
    output emit [tty::goto 0 [expr {$cols - [string length $msg] - 2}]]
    output emit [tty::attr bold]
    output emit " $msg "
    output emit [tty::attr]
    output emit [tty::restore]
    if {[string is space $msg]} return
    regsub -all . $msg " " msg
    set flashid [after 1000 [list flash-message $msg]]
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
## TOKENS:  these are defined in keymap
oo::class create Getline {

    # history traversal is permitted when:
    #  - histid is "" and [input::get] is ""
    #  - histid is not ""
    variable histid
    variable yank
    variable prompt

    constructor {pr} {  ;# input output history iscomplete accept? completer
        set histid ""
        set yank ""
        set prompt $pr
        input reset
        output reset $prompt
    }

    method get {} {
        input get
    }

    method sigpipe {} {
        if {[input get] ne ""}  { beep "sigpipe with [string length [input get]] chars"; return }
        return -level 2 -code break
    }
    method sigint {}      { return -level 2 -code continue }
    method redraw {}      { output redraw }

    method insert {s} {
        variable histid
        foreach c [split $s ""] {
            input insert $c
            output insert [rep $c]  ;# attr?
        }
        set histid ""
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
        if {[input pos] < 1} {beep "back at BOL"; return}
        set n [expr {min($n, [input pos])}]
        if {$n == 0} return
        output back [string length [srep [input back $n]]]
    }
    method forth {{n 1}} {
        if {$n == 0} return
        if {[input rpos] < 1} {beep "forth at EOL"; return}
        set n [expr {min($n, [input rpos])}]
        if {$n == 0} return
        output forth [string length [srep [input forth $n]]]
    }

    method backspace {{n 1}} {
        if {$n == 0} return
        if {[input pos] < 1} {beep "backspace at BOL"; return}
        set n [expr {min($n, [input pos])}]
        if {$n == 0} return
        set in [input backspace $n]
        output backspace [string length [srep $in]]
        return $in
    }
    method delete {{n 1}} {
        if {$n == 0} return
        if {[input rpos] < 1} {beep "delete at EOL"; return}
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
        variable prompt
        input set-state $s $p
        ssplit $s $p -> a b
        set a [srep $a]; set b [srep $b]    ;# attrs? :(
        output set-state $prompt$a$b [string length $prompt$a]
    }

    method yank {s} { variable yank ; set yank $s }
    method paste {} { variable yank ; my insert $yank }

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
        set s [history prev [my get]]
        if {$s eq ""}   { beep "no more history!"; return }
        my replace-input $s
    }
    method history-next {} {
        set s [history next [my get]]
        if {$s eq ""}   { beep "no more history!"; return }
        my replace-input $s
    }
    method history-prev-starting {} {
        set pos [input pos]
        set s [history prev-starting [input pre] [my get]]
        if {$s eq ""}   { beep "no more matching history!"; return }
        my kill-after
        my insert [string range $s $pos end]
        my goto $pos
    }
    method history-next-starting {} {
        set pos [input pos]
        set s [history next-starting [input pre] [my get]]
        if {$s eq ""}   { beep "no more matching history!"; return }
        my kill-after
        my insert [string range $s $pos end]
        my goto $pos
    }

    method accept {} {
        set input [my get]
        if {![string is space $input]}  { history add $input }
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

    variable lines
    variable lineidx
    variable prompts        ;# for getlines, there must be a list of prompts!

    constructor {pr} {
        set prompts [list $pr]
        set lines   [list ""]
        set lineidx 0
        next $pr
    }

    method get {} {
        lset lines $lineidx [input get]
        join $lines \n
    }

    method redraw-following {} {
        set line [lindex $lines $lineidx]
        set pos [input pos]
        my end
        set idx $lineidx
        incr idx
        while {$idx < [llength $lines]} {
            output emit \n
            set l [lindex $lines $idx]
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
        set lines [linsert $lines $lineidx+1 $rest]
        set rows [output wrap [output pos] [output rpos]]
        output emit [tty::down $rows]          ;# hmmm
        output emit \n
        incr lineidx
        my set-state [lindex $lines $lineidx]
        my redraw
    }

    method prior-line {} {
        if {$lineidx == 0} {beep "no prev line"; return}
        my home
        output emit [tty::up 1]
        lset lines $lineidx [input get]
        incr lineidx -1
        my set-state [lindex $lines $lineidx]
        set nrows [output wrap 0 [output len]]    ;# hmmm
        output emit [tty::up $nrows]               ;# hmmm
        my redraw
    }
    method next-line {} {
        if {$lineidx + 1 == [llength $lines]} {beep "no next line"; return}
        my end
        lset lines $lineidx [input get]
        incr lineidx 1
        my set-state [lindex $lines $lineidx]
        output emit [tty::down 1]                  ;# hmmm
        my redraw
    }

    method kill-next-line {} {
        set r [lindex $lines $lineidx+1]
        set lines [lreplace $lines $lineidx+1 $lineidx+1]
        return $r
    }
    method kill-prev-line {} {
        set r [lindex $lines $lineidx-1]
        set lines [lreplace $lines $lineidx-1 $lineidx-1]
        return $r
    }

    method back {{n 1}} {
        if {$n <= [input pos]} {
            next $n
        } elseif {$lineidx > 0} {
            my prior-line
            my end
        } else {beep "back at beginning of input"}
    }
    method forth {{n 1}} {
        if {$n <= [input rpos]} {
            next $n
        } elseif {$lineidx+1 < [llength $lines]} {
            my next-line
            my home
        } else {beep "forth at end of input"}
    }

    method backspace {{n 1}} {
        if {$n <= [input pos]} {
            next $n
        } elseif {$lineidx > 0} {
            my prior-line
            my end
            set s [my kill-next-line]
            my insert $s
            my redraw
            my redraw-following
        } else {beep "backspace at beginning of input"}
    }
    method delete {{n 1}} {
        if {$n <= [input rpos]} {
            next $n
        } elseif {$lineidx+1 < [llength $lines]} {
            set rest [my kill-next-line]
            my insert $rest
            my back [string length $rest]
            my redraw
            my redraw-following
        } else {beep "delete at end of input"}
    }

    method up {{n 1}} {
        if {$lineidx > 0} {
            set pos [input pos]
            my prior-line
            my home
            set pos [expr {min($pos,[input rpos])}]
            my forth $pos
        }
    }
    method down {{n 1}} {
        if {$lineidx + 1 < [llength $lines]} {
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
    Getlines create engine $prompt
    finally engine destroy
    set cmds [info object methods engine -all]

    while 1 {
        # {TOKEN tok {c c c}} or {LITERAL "" {c c c}}
        lassign [keymap gettok] kind tok chars
        if {$kind eq "TOKEN" && $tok in $cmds} {
            engine $tok                    ;# can return -level 1
        } else {
            foreach char $chars {
                engine insert $char
            }
        }
        # if [getline display-rows] has changed, redraw-following
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

coroutine Main try {
    main {*}$argv
    exit
}
vwait forever
