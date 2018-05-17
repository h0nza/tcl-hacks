namespace eval getline {

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
        method Completions {s}   { return "" }
        method History {args} {
            History create History
            oo::objdefine [self] forward History History
            tailcall my History {*}$args
        }

        constructor {args} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]
            set Yank ""
            set Lines {""}
            set Lineidx 0
            set Prompt "getline> "
            set Chan stdout

            my Configure {*}$args

            set Prompts [list $Prompt]

            Input create             input
            Output create            output $Chan
            keymap::KeyMapper create keymap [expr {$Chan eq "stdout" ? "stdin" : $Chan}]
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

            my reset

            while 1 {
                # {TOKEN tok {c c c}} or {LITERAL "" {c c c}}
                lassign [keymap gettok] kind tok chars
                if {$kind eq "TOKEN"} {
                    try {
                        my $tok
                        continue
                    } trap {TCL LOOKUP METHOD *} {} { }
                }
                foreach char $chars {
                    my insert $char
                }
            }
        }

        method beep {msg} {
            output beep
            if {$msg ne ""} {tailcall output flash-message $msg}
        }

        method reset {} {
            set Lines {""}
            set Lineidx 0
            input reset
            output reset $Prompt
        }

        method get {} {
            lset Lines $Lineidx [input get]
            join $Lines \n
        }

        # action methods:
        method sigpipe {} {
            if {[input get] ne ""}  { my beep "sigpipe with [string length [input get]] chars"; return }
            return -level 2 -code break
        }
        method sigint {}      { return -level 2 -code continue }

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
            while {$Lineidx > $idx}      { my next-line }
            my goto $pos
        }
        method redraw-following {} {
            set pos [input pos]
            lset Lines $Lineidx [input get]
            set idx $Lineidx
            while {![my is-last-line]} { my next-line }
            output emit [tty::save]         ;# ugh
            output emit \n                  ;# tty::down won't force a scroll
            output emit [tty::erase-line]
            #output emit [tty::up]
            output emit [tty::restore]
            while {$Lineidx > $idx}   { my prior-line }
            my goto $pos
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
            output emit \n
            my next-line
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
            while {$n > [input pos] && ![my is-first-line]} {
                incr n -[input pos]
                incr n -1
                my prior-line
                my end
            }
            if {[input pos] < 1} {my beep "back at BOL"; return}
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
                my home
            }
            if {[input rpos] < 1} {my beep "forth at EOL"; return}
            set n [expr {min($n, [input rpos])}]
            if {$n == 0} return
            output forth [string length [srep [input forth $n]]]
        }

        method backspace {{n 1}} {
            if {$n == 0} return
            while {$n > [input pos] && ![my is-first-line]} {
                incr n -[input pos]
                incr n -1
                my kill-before
                my prior-line
                my end
                set s [my kill-next-line]
                my insert $s
                my redraw-following
            }
            if {[input pos] < 1} {my beep "backspace at BOL"; return}
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
                set rest [my kill-next-line]
                my insert $rest
                my back [string length $rest]
                my redraw-following
            }
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
            while {![my is-last-line]} {my kill-next-line}
            while {![my is-first-line]} {my kill-prior-line}
            return $r
        }
        method replace-input {s {pos 0}} {
            my clear
            my insert $s
            if {[my get] ne $s} {error "didn't work!: [my get] [list $Lines]"}
            my goto $pos
        }
        method set-state {{s ""} {p 0}} {
            input set-state $s $p
            ssplit $s $p -> a b
            set a [srep $a]; set b [srep $b]    ;# attrs? :(
            output set-state $Prompt$a$b [string length $Prompt$a]
        }

        # multi-line helpers
        method is-first-line {}     { expr {$Lineidx == 0} }
        method is-last-line {}      { expr {$Lineidx == [llength $Lines]-1} }

        method prior-line {} {
            if {[my is-first-line]} {my beep "No prior line"; return}
            my home
            lset Lines $Lineidx [input get]
            incr Lineidx -1
            my set-state [lindex $Lines $Lineidx]
            set  nrows [output wrap 0 [output len]]  ;# hmmm
            incr nrows 1
            output emit [tty::up $nrows]
            my redraw-line
        }
        method next-line {} {
            if {[my is-last-line]} {my beep "No next line"; return}
            my end
            lset Lines $Lineidx [input get]
            incr Lineidx 1
            my set-state [lindex $Lines $Lineidx]
            set  nrows [output wrap 0 [output len]]  ;# hmmm
            incr nrows 1
            output emit [tty::down $nrows]
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
            return $r
        }

        method up {{n 1}} {
            if {$n == 0} {return}
            if {[my is-first-line]} {my beep "No more lines!"; return}
            set pos [input pos]
            while {$n > 0 && ![my is-first-line]} {
                my prior-line
                my goto [expr {min($pos,[input rpos])}]
                incr n -1
            }
        }
        method down {{n 1}} {
            if {$n == 0} {return}
            if {[my is-last-line]} {my beep "No more lines!"; return}
            set pos [input pos]
            while {$n > 0 && ![my is-first-line]} {
                my prior-line
                my goto [expr {min($pos,[input rpos])}]
                incr n 1
            }
        }

        method very-home {} {
            my home
            while {![my is-first-line]} { my back 1 ; my home }
        }
        method very-end {} {
            my end
            while {![my is-last-line]} { my forth 1 ; my end }
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
            my redraw
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
            # my replace-input $s $pos
            my kill-after
            my insert [string range $s $pos end]
            my goto $pos
        }
        method history-next-starting {} {
            set pos [input pos]
            set s [my History next-starting [input pre] [my get]]
            if {$s eq ""}   { my beep "no more matching history!"; return }
            # my replace-input $s $pos
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
            set input [my get]
            if {[my Complete? $input]} {
                my very-end
                tailcall my accept
            } else {
                my insert \n
            }
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
