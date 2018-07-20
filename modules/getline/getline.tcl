namespace eval getline {

    source [file dirname [info script]]/input.tcl
    source [file dirname [info script]]/output.tcl
    source [file dirname [info script]]/keymap.tcl
    source [file dirname [info script]]/history.tcl
    source [file dirname [info script]]/util.tcl     ;# ssplit
    source [file dirname [info script]]/tty.tcl

    proc rep {c} {
        if {[string length $c] != 1}    { error "Bad input: [binary encode hex $c]" }
        if {[string is print $c]}       { return $c }
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
        if {![regexp -indices -start $i {\M} $s ab]} { return $i }
        lassign $ab a b
        expr {$a - $i}
    }

    ## class Getline is an "engine".  Methods on it may be addressed in the keymap.
    # Getline is a single-line-only getter; Getlines extends on it with line continuation capability
    #
    oo::class create Getline {

        # state:
        variable Yank

        # multi-line state:
        variable Lines
        variable Lineidx
        variable Prompts

        # options:
        variable Prompt
        variable Chan
        method Complete? {input} { info complete $input\n }
        method Completions {s t}   { return "" }
        method History {args} {
            History create History
            oo::objdefine [self] forward History History
            History add "0123456789012345678901234567890123456789"
            History add "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxX\nYyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyY\nZzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
            tailcall my History {*}$args
        }

        constructor {args} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]
            set Yank ""
            set Lines {""}
            set Lineidx 0
            set Prompt "getline> "
            set Chan stdin

            my Configure {*}$args

            if {$Chan eq "stdout"} {set Chan stdin}
            set outchan [expr {$Chan eq "stdin" ? "stdout" : $Chan}]

            chan configure $Chan -blocking 0
            chan configure $outchan -buffering none

            set Prompts [list $Prompt]

            Input create             input
            Output create            output $outchan
            keymap::KeyMapper create keymap $Chan
        }

        method Configure {args} {
            set OptSpec {
                -prompt     { set Prompt $val }
                -chan       { set Chan $val }
                -history    { oo::objdefine [self] forward History     [uplevel 1 [list namespace which $val]] }
                -iscomplete { oo::objdefine [self] forward Complete?   [uplevel 1 [list namespace which $val]] }
                -completer  { oo::objdefine [self] forward Completions [uplevel 1 [list namespace which $val]] }
            }

            dict for {opt val} $args {
                set pat $opt*
                set matched 0
                dict for {key script} $OptSpec {
                    if {[string match $pat* $key]} {
                        try $script
                        set matched 1
                        break
                    }
                }
                if {!$matched} {
                    return -code error "Unknown option \"$opt\"; expected one of [join [dict keys $OptSpec] ", "]."
                }
            }
        }

        method Prompt {} {
            if {[lindex $Prompts $Lineidx] eq ""} {
                regexp {^(.*)(\S)(\s*)$} $Prompt -> prefix char space
                regsub -all . $prefix " " prefix
                set prompt2 $prefix$char$space
                lset Prompts $Lineidx $prompt2
            }
            lindex $Prompts $Lineidx
        }

        # for mixins to intercept user actions:
        method Invoke {cmd args} {
            try {
                my $cmd {*}$args
            } trap [list TCL LOOKUP METHOD $cmd] {} {
                throw {GETLINE BEEP} "No such command: $cmd"
            }
        }

        method Mode {mixin args} {
            oo::objdefine [self] mixin $mixin
        }

        method getline {} {

            if {[info coroutine] eq ""} {
                return -code error "getline must be called within a coroutine!"
            }

            finally chan event $Chan readable [chan event $Chan readable]
            chan event $Chan readable [info coroutine]

            my reset

            while 1 {
                # {TOKEN tok {c c c}} or {LITERAL "" {c c c}}
                lassign [keymap gettok] kind tok chars
                if {$kind eq "TOKEN"} {
                    try {
                        my Invoke {*}$tok
                        continue
                    } trap {GETLINE BEEP} {msg} {
                        my beep $msg
                        continue
                    } trap {GETLINE RETURN} {res} {
                        return $res
                    } trap {GETLINE BREAK} {} {
                        return -code break
                    } trap {GETLINE CONTINUE} {} {
                        return -code continue
                    }
                }
                foreach char $chars {
                    my insert $char
                }
            }
        }

        forward flash-message   output flash-message
        method beep {msg} {
            output beep
            if {$msg ne ""} { my flash-message $msg }
        }

        method reset {} {
            set Lines {""}
            set Lineidx 0
            input reset
            output reset [my Prompt]
        }

        method get {} {
            lset Lines $Lineidx [input get]
            join $Lines \n
        }
        method pre {} {
            if {[my is-first-line]} {
                return [input pre]
            } else {
                return [string cat  [join [lrange $Lines 0 $Lineidx-1] \n]  \n  [input pre]]
            }
        }
        method post {} {
            if {[my is-last-line]} {
                return [input post]
            } else {
                return [string cat  [input post]  \n  [join [lrange $Lines $Lineidx+1 end] \n]]
            }
        }

        # action methods:
        method sigpipe {} {
            if {[input get] ne ""}  { throw {GETLINE BEEP} "sigpipe with [string length [input get]] chars" }
            throw {GETLINE BREAK} ""
        }
        method sigint {}            { throw {GETLINE CONTINUE} "" }

        method redraw {} {
            my redraw-preceding
            my redraw-following
            my redraw-line
        }

        method redraw-line {} { output redraw }
        # these redraw too much by virtue of next/prior-line'ing over the whole input
        method redraw-preceding {} {
            set pos [input pos]
            lset Lines $Lineidx [input get]
            set idx $Lineidx
            while {![my is-first-line]} { my prior-line }
            while {$Lineidx < $idx}      { my next-line }
            my goto-column $pos
        }
        method redraw-following {} {
            set pos [input pos]
            lset Lines $Lineidx [input get]
            set idx $Lineidx
            while {![my is-last-line]} { my next-line }
            my goto-column end
            output emit [tty::save]
            output emit [tty::erase-to-end]
            output emit \n                  ;# tty::down won't force a scroll
            output emit [tty::erase-line]
            output emit [tty::restore]
            while {$Lineidx > $idx}   { my prior-line }
            my goto-column $pos
        }

        method insert {s} {
            foreach c [split $s ""] {
                if {$c eq "\n"} {
                    my insert-newline
                } else {
                    input insert $c
                    output insert [rep $c]  ;# attr?
                }
            }
        }

        method insert-newline {} {
            set rest [my kill-after]
            lset Lines $Lineidx [my get]
            set Lines [linsert $Lines $Lineidx+1 $rest]
            my next-line
        }

        # these need to be better named
        method abs-pos {} {
            for {set i 0} {$i < $Lineidx} {incr i} {
                incr r [string length [lindex $Lines $i]]
                incr r 1
            }
            incr r [input pos]
        }
        method goto {i} {
            set p [my abs-pos]
            set delta [expr {$i - $p}]
            if {$delta < 0} {
                set delta [expr {-$delta}]
                while {$delta > [input pos]} {
                    incr delta -[input pos]
                    my prior-line
                    incr delta -1
                    my goto-column end
                }
                my back $delta
            } else {
                while {$delta > [input rpos]} {
                    incr delta -[input rpos]
                    my next-line
                    incr delta -1
                    my goto-column 0
                }
                my forth $delta
            }
        }

        method goto-column {i} {
            if {$i eq "end"} {
                my forth [input rpos]
            } elseif {$i < [input pos]} {
                my back  [expr {[input pos] - $i}]
            } else {
                my forth [expr {$i - [input pos]}]
            }
        }

        method back {{n 1}} {
            if {$n == 0} return
            while {$n > [input pos] && ![my is-first-line]} {
                incr n -[input pos]
                incr n -1
                my prior-line
                my goto-column end
            }
            if {[input pos] < 1}    { throw {GETLINE BEEP} "back at BOL" }
            set n [expr {min($n, [input pos])}]
            if {$n == 0} return
            output back [string length [srep [input back $n]]]
        }
        method forth {{n 1}} {
            if {$n == 0} return
            while {$n > [input rpos] && ![my is-last-line]} {
                incr n -[input rpos]
                incr n -1
                my next-line
                my goto-column 0
            }
            if {[input rpos] < 1}   { throw {GETLINE BEEP} "forth at EOL" }
            set n [expr {min($n, [input rpos])}]
            if {$n == 0} return
            output forth [string length [srep [input forth $n]]]
        }

        method backspace {{n 1}} {
            if {$n == 0} return
            while {$n > [input pos] && ![my is-first-line]} {
                incr n -[input pos]
                incr n -1
                if {[input pos]} {my kill-before}
                my prior-line
                my goto-column end
                set rest [my kill-next-line]
                my insert $rest
                my back [string length $rest]
                my redraw-following
            }
            if {$n == 0} return
            if {[input pos] < 1}    { throw {GETLINE BEEP} "backspace at BOL" }
            set n [expr {min($n, [input pos])}]
            if {$n == 0} return
            set in [input backspace $n]
            output backspace [string length [srep $in]]
            return $in
        }
        method delete {{n 1}} {
            if {$n == 0} return
            while {$n > [input rpos] && ![my is-last-line]} {
                incr n -[input rpos]
                incr n -1
                if {[input rpos]} {my kill-after}
                set rest [my kill-next-line]
                my insert $rest
                my back [string length $rest]
                my redraw-following
            }
            if {[input rpos] < 1}   { throw {GETLINE BEEP} "delete at EOL" }
            set n [expr {min($n, [input rpos])}]
            if {$n == 0} return
            set in [input delete $n]
            output delete [string length [srep $in]]
            return $in
        }

        method clear {} {
            set r [input get]
            if {[input rpos]}           { my kill-after }
            if {[input pos]}            { my kill-before }
            while {![my is-last-line]}  { my kill-next-line  }
            while {![my is-first-line]} { my kill-prior-line }
            return $r
        }
        method replace-input {s {pos 0}} {
            my clear
            my insert $s
            my goto $pos
        }
        method set-state {{s ""} {p 0}} {
            input set-state $s $p
            ssplit $s $p -> a b
            set a [srep $a]; set b [srep $b]    ;# attrs? :(
            output set-state [my Prompt]$a$b [string length [my Prompt]$a]
        }

        # multi-line helpers
        method is-first-line {}     { expr {$Lineidx == 0} }
        method is-last-line {}      { expr {$Lineidx == [llength $Lines]-1} }

        method prior-line {} {
            if {[my is-first-line]} { throw {GETLINE BEEP} "No prior line" }
            my goto-column 0
            lset Lines $Lineidx [input get]
            incr Lineidx -1
            ### the following could be (to eliminate set-state)
            # set line [lindex $Lines $Lineidx]
            # input set-state $line [string length $line]
            # set rep [srep $line]
            # set wraps [output wrap 0 [string length [my Prompt]$rep]]    ;# output repwrap {*}[my Prompt] + {*}$rep
            # output emit [tty::up [expr {1+$wraps}]]
            # output reset [my Prompt]
            # output insert $rep
            ## my goto-column $col
            my set-state [lindex $Lines $Lineidx]
            set  nrows [output wrap 0 [output len]]  ;# hmmm
            incr nrows 1
            output emit [tty::up $nrows]
            my redraw-line
        }
        method next-line {} {
            if {[my is-last-line]}  { throw {GETLINE BEEP} "No next line" }
            my goto-column end
            lset Lines $Lineidx [input get]
            incr Lineidx 1
            my set-state [lindex $Lines $Lineidx]
            output emit \n
            my redraw-line
        }

        method kill-next-line {} {
            set r [lindex $Lines $Lineidx+1]
            set Lines [lreplace $Lines $Lineidx+1 $Lineidx+1]
            return $r
        }
        method kill-prior-line {} {
            set r [lindex $Lines $Lineidx-1]
            set Lines [lreplace $Lines $Lineidx-1 $Lineidx-1]
            incr Lineidx -1
            return $r
        }

        method up {{n 1}} {
            if {$n == 0}    { return }
            if {[my is-first-line]} {
                if {[input pos]} { my home } else { my history-prev }
                return
            }
            set pos [input pos]
            while {$n > 0 && ![my is-first-line]} {
                my prior-line
                my goto-column [expr {min($pos,[input rpos])}]
                incr n -1
            }
        }
        method down {{n 1}} {
            if {$n == 0}    { return }
            if {[my is-last-line]} {
                if {[input rpos]} { my end } else { my history-next }
                return
            }
            set pos [input pos]
            while {$n > 0 && ![my is-last-line]} {
                my next-line
                my goto-column [expr {min($pos,[input rpos])}]
                incr n -1
            }
        }

        method very-home {} {
            my goto-column 0
            while {![my is-first-line]} { my back 1 ; my goto-column 0 }
        }
        method very-end {} {
            my goto-column end
            while {![my is-last-line]} { my forth 1 ; my goto-column end }
        }

        method yank {s} { variable Yank ; set Yank $s }
        method paste {} { variable Yank ; my insert $Yank }

        method yank-before {}       { my yank [my kill-before] }
        method yank-after {}        { my yank [my kill-after] }
        method yank-word-before {}  { my yank [my kill-word-before] }
        method yank-word-after {}   { my yank [my kill-word-after] }

        method home {} {
            if       {[input pos]}          { my back      [input pos]
            } elseif {![my is-first-line]}  { my prior-line ; my home
            }
        }
        method end {} {
            if       {[input rpos]}         { my forth    [input rpos]
            } elseif {![my is-last-line]}   { my next-line  ; my end
            }
        }
        method kill-before {} {
            if       {[input pos]}          { my backspace [input pos]
            } elseif {![my is-first-line]}  { my prior-line ; my kill-line
            }
        }
        method kill-after {} {
            if       {[input rpos]}         { my delete   [input rpos]
            } elseif {![my is-last-line]}   { my next-line  ; my kill-line
            }
        }
        method kill-line {} {
            my end
            my kill-before
        }

        method back-word {} {
            if       {[input pos]}          { my back      [word-length-before [input get] [input pos]]
            } elseif {![my is-first-line]}  { my prior-line ; my end    ; my back-word
            }
        }
        method forth-word {} {
            if       {[input pos]}          { my forth     [word-length-after  [input get] [input pos]]
            } elseif {![my is-last-line]}   { my next-line ; my end    ; my forth-word
            }
        }
        method kill-word-before {} {
            if       {[input pos]}          { my backspace [word-length-before [input get] [input pos]]
            } elseif {![my is-first-line]}  { my prior-line ; my end    ; my kill-word-before
            }
        }
        method kill-word-after {} {
            if       {[input pos]}          { my delete    [word-length-after  [input get] [input pos]]
            } elseif {![my is-last-line]}   { my next-line  ; my home   ; my kill-word-after
            }
        }
        # softbreak tab

        method history-prev {} {
            set s [my History prev [my get]]
            if {$s eq ""}   { throw {GETLINE BEEP} "no more history!" }
            my replace-input $s
        }
        method history-next {} {
            set s [my History next [my get]]
            if {$s eq ""}   { throw {GETLINE BEEP} "no more history!" }
            my replace-input $s
        }
        method history-prev-starting {} {
            set pos [input pos]
            set s [my History prev-starting [input pre] [my get]]
            if {$s eq ""}   { throw {GETLINE BEEP} "no more matching history!" }
            my replace-input $s $pos
        }
        method history-next-starting {} {
            set pos [input pos]
            set s [my History next-starting [input pre] [my get]]
            if {$s eq ""}   { throw {GETLINE BEEP} "no more matching history!" }
            my replace-input $s $pos
        }

        method accept {} {
            set input [my get]
            if {![string is space $input]}  { my History add $input }
            my very-end
            output emit \n
            throw {GETLINE RETURN} $input
        }

        method newline {} {
            set input [my get]
            if {[my Complete? $input]} {
                my accept
            } else {
                my insert \n
            }
        }

        method tab {} {
            set comps [my Completions [my pre] [my post]]
            if {$comps eq ""}   { throw {GETLINE BEEP} "no completions" }

            # wait for it ..
            my {*}$comps
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
}
