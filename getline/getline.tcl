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
        #output flash-message [list [self] reset from [info level -1] from [info level -2]]
        input reset
        output reset $Prompt
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
        #if {[string match "*% " $s]} {output flash-message [list [self] insert from [info level -1] from [info level -2]]}
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
    method replace-input {s {pos 0}} {
        my clear
        my insert $s
        my goto $pos
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

