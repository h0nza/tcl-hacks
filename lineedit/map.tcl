# This will be called [getline].
#
# TODO:
#  x char-wise navigation
#  x line-wise nagivation
#  x prompts
#  x history
#    - history-dump and history-edit
#    - search, rsearch
#  - word-wise nagivation
#  - handle navigation of multi-char [reps] (cursor, editing)
#  - handle navigation of newlines (history, fill, cursor, editing)
#    - these would be simpler if input was a list and we kept an index rather than moreinput
#    - with a parallel list of display-lengths. -1 for newline?
#     emit [rep] is broken.  I need [emit-rep chars ?rep?].  Which makes N:M ...
#    - note that this is going beyond readline or ipython!
#  - word navigation
#  - simple colour
#  - completion callback
#  - objectify so handlers can call one another (and take args!)

package require sqlite3
sqlite3 db {}

source keymap.tcl
keymap::init

source tty.tcl

source histdb.tcl
histdb::init ::db


proc init {} {
    variable input ""
    variable moreinput ""
    variable yank ""
    variable peek ""
    variable stash ""
    variable histid 0
}

proc _vars {} {
    join [lmap v {input moreinput yank peek stash histid} {
        string cat "variable $v;"
    }]
}

proc _def {name args body} {
    proc $name $args "[_vars]$body"
}

proc _tok {name body} {
    _def t:$name {} $body
}

# I need a group of functions for traversing (manipulating) the output string
# these talk to the tty and need to know the display width of each token
#
# The trick is putting the input modifications and output modifications in
# the right place to keep them in sync and the code reasonably tidy.
#

source util.tcl

# these procs are responsible for maintaining their own models ${(more)?(input|output)}
_def input:insert {c} {}
_def input:left {{n 1}} {}
_def input:right {{n 1}} {}
_def input:erase {{n 1}} {}
_def input:backspace {{n 1}} {}

# o:i can use [rep] if it gets a raw char from above.
_def output:insert {c} {}
_def output:left {{n 1}} {}
_def output:right {{n 1}} {}
_def output:erase {{n 1}} {}
_def output:backspace {{n 1}} {}

# output needs a redraw proc
_def output:redraw {} {}
# and some internal helpers
_def output:_prompt1 {} {}
_def output:_prompt2 {} {}
_def output:_newline {} {}

# input events: home/end, kill-home/end/line are like word-wise events
#  -> input is responsible for finding the target distance and driving primitive output events to match.

foreach {tok body} {
    sigpipe { if {"$input$moreinput" eq ""} {return -level 2 -code break} else bell }
    sigint  { return -level 2 "" }

    newline {
        emit \n
        set input $input$moreinput
        set moreinput ""
        if {[complete? $input\n]} {
            puts "Complete!"
            if {![string is space $input]} {
                histdb::add $input
                set histid ""
            }
            return -code return $input  ;# FIXME: invoke callback
        } else {
            append input \n
            # append input [getline $prompt1]   ;# won't transmit sigint!
            emit [prompt2 $prompt1]
        }
    }

    history-next {
        if {"$input$moreinput" ne ""} {
            set id [histdb::next $histid]
            set histid $id
            set s [histdb::get $histid]
            set n [string length $input]
            emit [tty::left $n]
            incr n [string length $moreinput]
            emit [tty::erase $n]
            emit $s
            set input $s
            set moreinput ""
        } else bell
    }

    history-prev {
        set id [histdb::prev $histid]
        if {$id ne ""} {
            set histid $id
            set s [histdb::get $histid]
            if {$s ne ""} {
                set n [string length $input]
                emit [tty::left $n]
                incr n [string length $moreinput]
                emit [tty::erase $n]
                emit $s
                set input $s
                set moreinput ""
            }
        } else bell
    }

    backspace {
        if {$input ne ""} {
            emit \u8[tty::delete 1]
            set input [string range $input 0 end-1]
        } else bell
    }

    delete {
        if {$moreinput ne ""} {
            emit [tty::delete 1]
            set moreinput [string range $moreinput 1 end]
        } else bell
    }

    back {
        if {$input ne ""} {
            emit \u8
            set moreinput [string index $input end]$moreinput
            set input [string range $input 0 end-1]
        } else bell
    }
    forth {
        if {$moreinput ne ""} {
            set i [string index $moreinput 0]
            set moreinput [string range $moreinput 1 end]
            emit $i
            append input $i
        } else bell
    }
    home {
        emit [tty::left [string length $input]]
        set moreinput $input$moreinput
        set input ""
    }
    end {
        emit $moreinput
        set input $input$moreinput
        set moreinput ""
    }
    swap-mark {
        if {$input eq ""} {
            emit $moreinput
            set input $moreinput
            set moreinput ""
        } else {
            emit [tty::left [string length $input]]
            set moreinput $input$moreinput
            set input ""
        }
    }

    kill-after {
        emit [tty::erase [string length $moreinput]]
        set yank $moreinput
        set moreinput ""
    }
    kill-before {
        set yank $input
        emit [tty::left [string length $input]]
        emit [tty::delete [string length $input]]
        set input ""
    }
    kill-line {
        set yank $input$moreinput
        set n [string length $input]
        emit [tty::left $n]
        incr n [string length $moreinput]
        emit [tty::erase $n]
        set input ""
        set moreinput ""
    }

    redraw {
        # prompt!
        emit [tty::left [string length $input]]
        emit $input$moreinput
        emit [tty::left [string length $moreinput]]
    }

    paste {
        append input $yank
        insert [lmap c $yank {rep $c}]  ;# FIXME: rep a string
    }
} {
    _def t:$tok {} $body
}

proc getline {} {
    variable input ""
    variable moreinput ""
    variable yank
    variable peek
    variable stash
    variable histid

    set prompt1 [prompt1]
    emit $prompt1

    if {$stash ne ""} {
        emit $stash
        set input $stash
        set stash ""
    }

    set cmds [info commands t:*]

    while 1 {
        lassign [keymap::gettok] kind tok chars
        switch $kind {
            TOKEN {
                set cmd t:$tok
                if {$cmd in $cmds} {
                    $cmd
                } else {
                    append input [join $chars ""]
                    insert [rep $tok]   ;# this is a rep covering N>1 input chars!
                }
            }
            LITERAL {
                append input [join $tok ""]
                foreach char $tok {
                    if {[string is print $char]} {
                        insert $char
                    } else {
                        insert [rep $char]
                    }
                }
            }
        }
    }
}

# There's already some repetition with general movement .. let's see if we can factor that decently.

# handling rep properly means consulting it for all cursor movement, including overdrawing
# this argues for storing both input and inputrep.
proc rep {char} {
    if {[string length $char] > 1} {
        return \[$char\]
    } elseif {[string is print $char]} {
        return $char
    } else {
        return <[binary encode hex $char]>
    }
}

proc insert {s} {
    variable moreinput
    if {$moreinput ne ""} {
        emit [tty::insert [string length $s]]
    }
    emit $s
}

proc emit {s {repeat 1}} {
    while {[incr repeat -1] >= 0} {
        foreach c [split $s ""] {
            after 10
            puts -nonewline $c
        }
    }
}

proc bell {} {
    puts -nonewline \x07
}

proc prompt1 {} {
    string cat \[ [file tail [info script]] \] " "
}

# takes prompt1 as argument, so it can copy its length
proc prompt2 {p} {
    set p [prompt1]
    regsub -all .   $p "."  p
    regsub -all ..$ $p ": " p
    return $p
}

proc complete? {input} {
    info complete $input
}

#proc trieverse {varName trie script {prefix ""}} {
#    upvar 1 $varName var
#    dict for {key subtrie} $trie {
#        if {$subtrie eq ""} {
#            set var [list {*}$prefix $key]
#            uplevel 1 $script
#        } else {
#            uplevel 1 [list trieverse $varName $subtrie $script [list {*}$prefix $key]]
#        }
#    }
#}

proc main {} {
    try {
        init
        exec stty raw -echo
        chan configure stdin -blocking no
        chan configure stdout -buffering none
        chan event stdin readable [info coroutine]
        while {![eof stdin]} {
            puts ">>[getline]<<"
        }
    } on error {e o} {
        puts "ERROR: $e"
        array set {} $o
        parray {}
    } finally {
        exec stty -raw echo
    }
    exit
}

coroutine MAIN main {*}$::argv
vwait forever

#trieverse keys $trie {
#    puts [lmap k $keys {binary encode hex $k}]
#}
