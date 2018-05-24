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
        set comp [common-prefix $cs]
        set comp [string range $comp [string length $w] end]
        if {$comp ne ""} {
            return [list insert $comp]
        } else {
            return [list flash-message $cs]     ;# FIXME: abbreviate
        }
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
