#!/usr/bin/env tclsh
#
# Try to be faithful to readline control chars.
#
# Rely only on /bin/stty (raw, echo, query size or parseable -a)
#
# No signals, so ^L needs to substitute for SIGWINCH

oo::class create Tty {
    variable input
    variable moreinput  ;# everything to the right of the cursor
    variable pushbuf
    variable yank
    constructor {} {
        set input ""
        set moreinput ""
        set pushbuf ""
        set yank ""
        exec stty raw -echo
        interp bgerror {} [list [namespace which my] bgerror]
        chan configure stdin -blocking 0
        chan configure stdout -buffering none
        coroutine run my run
        chan event stdin readable [namespace which run]
    }
    destructor {
        chan event stdin readable ""
        chan configure stdin -blocking 1
        chan configure stdout -buffering line
        exec stty -raw echo
    }
    method bgerror {err opts} {
        puts "BGERROR: $err"
        array set {} $opts
        parray {}
        my destroy
    }
    method geom {} {
        try {
            exec stty size
        } on error {} {
            set out [exec stty -a]
            # Linux style
            if {![regexp {rows (= )?(\d+); columns (= )?(\d+)} $out -> rows cols]} {
                # BSD style
                if {![regexp { (\d+) rows; (\d+) columns;} $err - rows cols]} {
                    list 80 24
                }
            }
            list $rows $cols
        }
    }
    method wait {} {
        set run [namespace which -command run]
        if {$run ne ""} {
            set var [my varname Wait]
            trace add command run delete "[list incr $var];list"
            vwait $var
        }
        my destroy
    }
    method push {chars} {
        set pushbuf $chars$pushbuf
    }
    # getch might as well return special sequences as multiple chars
    # I'm not sure about it throwing signals
    method getch {} {
        if {$pushbuf ne ""} {
            regexp (.)(.*) $pushbuf -> c pushbuf
            return $c
        }
        yield
        set c [read stdin 1]
        switch $c {
            ""      { if {[eof stdin]} { throw SIGPIPE "EOF" } }
            \u3     { throw SIGINT "Control-C" }
            \u4     { if {$input eq ""} { throw SIGPIPE "Control-D" } }
            \x1b    {
                try {
                # escape!
                # [A up [B down [C right [D left
                set lb [my getch]
                if {$lb eq "\u7f"} {
                    set c \u07
                } elseif {$lb ne "\["} {
                    my push $lb
                } else {
                    set d [my getch]
                    switch -exact $d {
                        A  { set c \u10 }
                        B  { set c \u0e }
                        C  { set c \u06 }
                        D  { set c \u02 }
                        default { my push $lb$d }
                    }
                }
            } on error {e o} {puts ERR:$e; exit}
            }
        }
        return $c
    }
    method emit {chars {times 1}} {
        while {[incr times -1] >= 0} {
            foreach char [split $chars ""] {
                #after 20
                puts -nonewline $char
            }
        }
    }
    method run {} {
        try {
            while 1 {
                try {
                    set c [my getch]
                    switch -exact $c {
                        \r - \n {       ;# newline
                            # what happens in the middle of a command?
                            append input $c
                            my emit \n
                            if {[info complete $input]} {
                                # do something!
                                puts "> [binary encode hex $input]"
                                set input $moreinput
                                set moreinput ""
                                if {$input eq ""} break
                                my emit $input
                            }
                            # prompt!
                        }
                        \u0f {          ;# ^O submit without clearing
                        }
                        \u8 - \u7f {    ;# ^H backspace
                            if {$input ne ""} {
                                my emit \u8\ \u8    ;# FIXME: handle moreinput
                                set input [string range $input 0 end-1]
                            }
                        }
                        \u14 {          ;# ^T transpose
                        }
                        \u2 {           ;# ^B back
                            if {$input ne ""} {
                                my emit \u8
                                set moreinput [string index $input end]$moreinput
                                set input [string range $input 0 end-1]
                            }
                        }
                        \u6 {           ;# ^F forward
                            if {$moreinput ne ""} {
                                set i [string index $moreinput 0]
                                set moreinput [string range $moreinput 1 end]
                                my emit $i
                                append input $i
                            }
                        }
                        \u1 {           ;# ^A home
                            my emit \u8 [string length $input]
                            set moreinput $input$moreinput
                            set input ""
                        }
                        \u5 {           ;# ^E end
                            my emit $moreinput
                            set input $input$moreinput
                            set moreinput ""
                        }
                        \ub {           ;# ^K kill after
                            # \e[K
                            my emit " " [string length $moreinput]
                            my emit \u8 [string length $moreinput]
                            set yank $moreinput
                            set moreinput ""
                        }
                        \u15 {          ;# ^U kill before
                            # \e[1K
                            set yank $input
                            my emit \   [string length $moreinput]
                            my emit \u8 [string length $moreinput]
                            my emit \u8 [string length $input]
                            my emit \   [string length $input]
                            my emit \u8 [string length $input]
                            set input $moreinput
                            my emit $input
                        }
                        \u19 {          ;# ^Y paste
                            my push $yank
                            set yank ""
                        }
                        \uc {           ;# ^L redraw
                            my emit \u8 [string length $input]
                            my emit $input$moreinput
                            my emit \u8 [string length $moreinput]
                        }
                        \u07 {          ;# ^G softbreak
                            if {$input eq ""} {
                                my emit \   [string length $moreinput]
                                my emit \u8 [string length $moreinput]
                                set moreinput ""
                            } else {
                                my emit \   [string length $moreinput]
                                my emit \u8 [string length $moreinput]
                                my emit \u8 [string length $input]
                                my emit \   [string length $input]
                                my emit \u8 [string length $input]
                                my emit $moreinput
                                my emit \u8 [string length $moreinput]
                                set input ""
                            }
                        }
                        \u17 {          ;# ^W kill word
                        }
                        \u1a {          ;# ^Z suspend
                            # process control!
                        }
                        \u9 {           ;# ^I tab
                            # needs to interact with completion
                        }
                        \u10 {          ;# ^P prev
                            # needs to interact with history
                        }
                        \u0e {          ;# ^N next
                            # needs to interact with history
                        }
                        \u12 {          ;# ^R reverse-isearch
                            # needs to interact with history
                            # and abstractions for clear/redraw
                        }
                        \u13 {          ;# ^S scroll-lock
                        }
                        \u11 {          ;# ^Q scroll-lock
                        }
                        \u18 {          ;# ^X extended
                            # ^X^E -> $EDITOR
                        }
                        \u16 {          ;# ^V quote
                            set c [my getch]
                            append input $c
                            if {$moreinput ne ""} {my emit \x1b\[1@}    ;# insert space for 1 char
                            my emit $c
                        }
                        default {
                            append input $c
                            if {$moreinput ne ""} {my emit \x1b\[1@}    ;# insert space for 1 char
                            my emit $c
                        }
                    }
                } trap SIGINT {} {
                    puts {[INTR]}
                    if {$input eq ""} break
                    set input ""
                }
            }
        } trap SIGPIPE {} {
            puts {[EOF]}
            my destroy
        }
    }
}

#coroutine Main main {*}$::argv
#trace add command Main delete {incr ::forever;list}
#vwait forever
#exec stty -raw echo
Tty create tty
tty wait
