source util.tcl     ;# sinsert
source tty.tcl

oo::class create Output {

    variable chan
    variable output
    variable pos
    variable cols
    variable rows
    variable flashid

    constructor {Chan} {
        namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]
        set pos 0
        set output ""
        lassign [exec stty size <@ stdin] rows cols
        set chan $Chan
    }

    destructor {
        catch {after cancel $flashid}
    }

    method emit {s} {
        if {[string match \x1b* $s]} {
            puts -nonewline $chan $s
        } else {
            foreach c [split $s ""] {
                puts -nonewline $chan $c
                #after 10       ;# for debugging!
            }
        }
    }

    method wrap {i j} {
        set j [expr {($i + $j) / $cols}]
        set i [expr {$i / $cols}]
        return [expr {abs($i-$j)}]
    }
    method eol? {p} {expr {$p % $cols == 0}}

    method get {} {return $output}
    method len {} {string length $output}
    method pos {}  {return $pos}
    method rpos {} {expr {[string length $output]-$pos}}

    method reset {prompt} {
        set r [my get]
        set output ""
        set pos 0
        my emit [tty::goto-col 0]
        my emit [tty::erase-to-end]
        my insert $prompt
        #my redraw
        return $r
    }
    method set-state {s p} {
        set output $s
        set pos $p
    }

    method redraw {} {
        lassign [exec stty size <@ stdin] rows cols     ;# because no SIGWINCH
        set dy [my wrap 0 [my pos]]
        if {$dy} {my emit [tty::up $dy]}
        my emit [tty::goto-col 0]
        my emit [tty::erase-to-end]
        my emit $output
        set dy [my wrap [my pos] [my rpos]]
        if {$dy} {my emit [tty::up $dy]}
        my emit [tty::goto-col [expr {1 + $pos % $cols}]]
    }
    method redraw-rest {} {
        if {[my rpos] == 0} {
            if {![my eol? $pos]} {my emit [tty::erase-to-end]}
            return
        }
        set dy [my wrap $pos [my rpos]]
        my emit [string range $output $pos end]
        if {[my eol? [expr {$pos + [my rpos]}]]} {
            my emit " \u8"
        }
        my emit [tty::erase-to-end]
        if {$dy} {my emit [tty::up $dy]}
        my emit [tty::goto-col [expr {1 + $pos % $cols}]]
    }

    method insert {s} {
        # update state
        set n [string length $s]
        set output [sinsert $output $pos $s]
        set dy [my wrap $pos [my rpos]]
        incr pos $n
        # draw
        if {[my rpos]} {my emit [tty::insert $n]}
        my emit $s
        if {$dy} {
            my redraw-rest
        }
        if {[my eol? $pos]} {
            my emit " \u8"
        }
    }
    method back {{n 1}} {
        # update state
        incr pos -$n
        set dy [my wrap $pos $n]
        if {$dy} {
            my emit [tty::up $dy]
            my emit [tty::goto-col [expr {1 + $pos % $cols}]]
        } else {
            my emit [tty::left $n]
        }
    }
    method forth {{n 1}} {
        # update state
        incr pos $n
        my emit [string range $output $pos-$n $pos-1]
        #emit [tty::right $n]
        if {[my eol? $pos]} {
            set c [string index $output $pos]
            if {$c eq ""} {set c " "}
            my emit $c
            my emit [tty::left 1]
        }
    }
    method delete {{n 1}} {
        set dy [my wrap $pos [my rpos]]
        # update state
        set output [string replace $output $pos [expr {$pos+$n-1}]]
        if {$dy} {
            my redraw-rest     ;# add space!
        } else {
            my emit [tty::delete $n]
        }
    }
    method backspace {{n 1}} {
        my back $n
        my delete $n
    }

    method beep {} {
        my emit \x07
    }
    method flash-message {msg} {
        catch {after cancel $flashid}
        my emit [tty::save]
        lassign [exec stty size] rows cols
        my emit [tty::goto 0 [expr {$cols - [string length $msg] - 2}]]
        my emit [tty::attr bold]
        my emit " $msg "
        my emit [tty::attr]
        my emit [tty::restore]
        if {[string is space $msg]} return
        regsub -all . $msg " " msg
        set flashid [after 1000 [list [self] flash-message $msg]]
    }
}
