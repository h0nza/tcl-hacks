source util.tcl

namespace eval display {
    variable prompt
    variable output ""
    variable pos 0
    variable row 0
    variable col 0

    proc _def {name args body} {
        proc $name $args "
            variable prompt
            variable output
            variable row
            variable col
        "
    }

    _def init {{p "% "}} {
        set prompt $p
        set output ""
        set pos 0
        set row 0
        set col 0
    }

    _def prompt1 {} {
        puts -nonewline $prompt
    }

    _def prompt2 {} {
        regsub -all . $prompt . prompt2
        puts -nonewline $prompt2
    }

    # if no newlines
    _def _insert {s} {
        set l [string length $s]
        set output [sinsert $output $pos $s]
        incr pos $l
        incr col $l
        emit [tty::insert $l]
        emit $s
    }

    _def emit-more {} {
        set s [string range $output $pos end]
        set lines 0
        while {[regexp {^(.*?)\n(.*)$} $s -> line s]} {
            incr lines
            prompt2
            emit $line
            emit \n
        }
        prompt2
        emit $s
        # take the cursor back!
        emit [tty::up $lines]
        emit [tty::goto-col [expr {$col + [string length $prompt]}]]
    }

    _def insert {s} {
        # set p [string length $s]
        # while {[string last \n $s p] > -1} .. uhg
        while {[regexp {^(.*?)\n(.*)$} $s -> line s]} {
            _insert $line
            newline
        }
        _insert $s
    }

    _def newline {} {
        if {$pos eq [string length $output]} {
            append output \n
            incr pos
            incr row
            set col 0
            emit \n
            prompt2
        } else {
            set output [sinsert $output $pos \n]
            incr pos
            incr row
            set col 0
            emit [tty::erase-to-end]
            emit \n
            emit-more
        }
    }

    _def erase {{n 1}} {
        # FIXME: newlines!
        set n [expr {min($n, [string length $input] - $point)}]
        set input [string replace $input $pos [expr {$pos + $n - 1}]
        emit [tty::delete $n]
    }
    _def backspace {{n 1}} {
        # FIXME: newlines!
        set n [expr {min($n, $pos)}]
        incr pos -$n
        set input [string replace $input $pos [expr {$pos + $n - 1}]
        emit [tty::delete $n]
    }

    _def left {{n 1}} {
        # FIXME: newlines!
        set pos [expr {min($n, $pos)}]
        emit [tty::left $n]
        incr pos -$n
    }
    _def right {{n 1}} {
        # FIXME: newlines!
        set n [expr {min($n, [string length $input] - $point)}]
        emit [tty::right $n]
        incr pos $n
    }
}
