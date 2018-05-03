source util.tcl

namespace eval input {
    # provides insert, delete, backspace
    # each of which returns a triple {operation replist extlist ?attr?}
    # representing the change in output+extents
    # suitable for feeding to a display system
    # a higher abstraction would be [replace p1 p2 newtext], either side of point
    variable point    0 ;#
    variable input   "" ;# a string - the "literal" input sequence
    variable output  "" ;# another string - physical characters represented on the terminal
    variable extents {} ;# a list, indexed by input.  0=part of previous grapheme; -1=newline.
    variable attr    {} ;# a list, indexed by input.  tty attributes of output extent.
    proc init {} {}

    # rep knows how to turn an input string
    # into a list of graphemes
    # it should probably do attr as well
    proc rep {chars} {
        lmap c [split $chars ""] {
            if {[string is print $c]} {
                set c
            } else {
                string cat < [binary encode hex $c] >
            }
        }
    }

    proc _def {name args body} {
        proc $name $args "
            variable point
            variable input
            variable output
            variable extents
            variable attr
            $body
        "
    }

    _def left {{n 1}} {
        set n [expr {min($n, $point)}]
        if {$n == 0} {return [list]}
        set to [expr {$point - $n}]
        set ext [lrange $extents $to $point-1]
        set point $to
        return [list left [sum $ext]]
    }

    _def right {{n 1}} {
        set n [expr {min($n, [string length $input] - $point)}]
        if {$n == 0} {return [list]}
        set to [expr {$point + $n}]
        set ext [lrange $extents $point $to-1]
        set point $to
        return [list right [sum $ext]]
    }

    # if you specify a rep, the sequence will be inserted all as one
    _def insert {chars {rep ""}} {
        # always occurs at point
        if {$rep ne ""} {
            # ""/0 is part-of-previous-graph
            set rep [lrepeat [string length $chars] ""]
            lset rep 0 $rep
        } else {
            set rep [rep $chars]
        }
        # -1 is newline
        set ext [lmap r $rep {expr {$r eq "\n" ? -1 : [string length $r]}}]
        set input   [sinsert $input   $point    $chars]
        set output  [linsert $output  $point {*}$rep]
        set extents [linsert $extents $point {*}$ext]
        incr point [string length $chars]
        return [list insert [join $rep ""] [sum $ext]]
    }

    _def delete {to} {
        # erase forward
        if {$to eq "end"} {
            set to [string length $input]
        } else {
            set to [expr {$point + abs($to)}]
        }
        set rep        [lrange $output  $point $to-1]
        set ext        [lrange $extents $point $to-1]
        set input    [sreplace $input   $point $to-1]
        set output   [lreplace $output  $point $to-1]
        set extents  [lreplace $extents $point $to-1]
        set point $point
        return [list delete [join $rep ""] [sum $ext]]
    }

    _def backspace {to} {
        # erase backward
        if {$to eq "start"} {
            set to 0
        } else {
            set to [expr {$point - abs($to)}]
        }
        set rep        [lrange $output  $to $point-1]
        set ext        [lrange $extents $to $point-1]
        set input    [sreplace $input   $to $point-1]
        set output   [lreplace $output  $to $point-1]
        set extents  [lreplace $extents $to $point-1]
        set point $to
        return [list backspace [join $rep ""] [sum $ext]]
    }
}
