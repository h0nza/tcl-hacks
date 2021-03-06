# SYNOPSIS:
#
#  output control
#
#   log::to stderr
#   log::copy chan ?name?
#   loc::close chan
#
#  Levels set by namespace from {debug info warn error}
#
#   log::level ?level?
#
#  Messages are not substituted if level not exceeded - beware side effects
#
#   log::info {message $subst string}
#
::tcl::tm::path add [pwd]
package require lib

namespace eval log {

    variable to {stderr}
    lib::alias to set [namespace current]::chan

    variable levels { error warn info debug }   ;# wtf is "notice" anyway?
    variable profiles { :: 2 }      ;# default (root ns) gets {error warn}

    apply {{levels {i -1}} {
        foreach l $levels {
            lib::updo 1 lib::alias $l log [incr i] $l
        }
    }} $levels

    proc never {args} {
        foreach level $args {
            log::warn {suppressing $level}
            catch {
                lib::alias $level list
            }
        }
    }

    proc level {{n ""}} {
        variable levels
        variable profiles
        set ns [lib::upns]
        if {$n eq ""} {
            return [Getlevel $ns]
        } elseif {$n in {0 1 2 3}} {
        } elseif {-1 != [set i [lsearch -exact $levels $n]]} {
            set n $i
        } else {
            error "Invalid level \"$n\": should be an integer or in ($levels)"
        }
        dict set profiles $ns $n
        return $n
    }

    proc Getlevel {ns} {
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
        #string trimleft [clock format $s -gmt 1 -format "%H:%M:%S.$ms"] 0:
        clock format $s -gmt 1 -format "%H:%M:%S.$ms"
    }

    variable copies {}
    proc copy {chan {name ""}} {
        if {$name eq ""} {set name $chan}
        variable copies
        dict set copies $chan $name
    }
    proc close {chan} {
        variable copies
        dict unset copies $chan
    }

    proc log {l level args} {
        variable to
        variable copies
        set ns [lib::upns]
        set t [Getlevel $ns]
        if {$l > $t} return
        set args [lmap a $args {lib::updo 1 subst $a}]
        if {[llength $args] == 1} {lassign $args args}
        set context [lib::updo namespace which [lindex [::info level -1] 0]]
        set lvl [dict get {
            debug   "d   "
            info    "in  "
            warn    "wrn "
            error   "ERR!"
        } $level]
        set msg "[runtime] $lvl $context | $args"
        puts $to $msg
        dict for {copy name} $copies {
            try {
                puts $copy $msg
            } on error {e o} {
                puts $to "[runtime]: warn: closed $name due to $e"
                close $copy
            }
        }
    }

}
