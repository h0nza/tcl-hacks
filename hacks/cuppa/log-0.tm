::tcl::tm::path add [pwd]
package require lib

namespace eval log {

    variable levels { error warn info debug }   ;# wtf is "notice" anyway?
    variable profiles {:: 1}        ;# default gets {error warn} but not {info debug}

    apply {{levels} {
        set i -1
        foreach l $levels {
            lib::updo 1 lib::alias $l log [incr i]
        }
    }} $levels

    proc level {{n ""}} {
        variable levels
        variable profiles
        set ns [lib::upns]
        if {$n eq ""} {
            return [getlevel $ns]
        } elseif {$n in {0 1 2 3}} {
        } elseif {-1 != [set i [lsearch -exact $levels $n]]} {
            set n $i
        } else {
            error "Invalid level \"$n\": should be an integer or in ($levels)"
        }
        dict set profiles $ns $n
        return $n
    }

    proc getlevel {ns} {
        variable profiles
        while {![dict exists $profiles $ns]} {
            set ns [namespace parent $ns]
        }
        dict get $profiles $ns
    }

    variable start [clock milliseconds]
    proc runtime {} {
        variable start
        set now [clock milliseconds]
        set elapsed [expr {$now - $start}]
        set s  [expr {$elapsed / 1000}]
        set ms [expr {$elapsed % 1000}]
        set ms [format %03d $ms]
        clock format $s -format "%H:%M:%S.$ms"
    }

    variable chans {}

    proc copy {chan {name ""}} {
        if {$name eq ""} {set name $chan}
        variable chans
        dict set chans $chan $name
    }
    proc close {chan} {
        variable chans
        dict unset chans $chan
    }

    proc log {l args} {
        variable levels
        set level [getlevel [lib::upns]]
        if {$l > $level} return
        set args [lmap a $args {lib::updo 1 subst $a}]
        set msg "[now]: [lindex $levels $l]: $args"
        puts $msg
        dict for {chan name} $chans {
            try {
                puts $chan $msg
            } on error {e o} {
                puts "[now]: warn: closed $name due to $e"
                close $chan
            }
        }
    }
}
