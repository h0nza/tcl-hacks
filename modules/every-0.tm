# taking some of the best wisdom from http://wiki.tcl.tk/9299 and putting it in an object
# why an object?  Mostly for convenient variables.  Independent instances that can clean
# up after themselves is possibly compelling too.
#
# Needs tests.
#
# Supports:
#  - cancel from within script with [break].  [continue] is harmless.
#  - [continue 100] - re-sets interval for 100ms
#  - cancel by id(s)
#  - kill (cancel all) - aka [cancel all] or [cancel *]
#  - pause/resume by id(s).  The clock keeps ticking, but events are skipped until resumed.
#  - info returns a dict

namespace eval every {

    # too nice to omit:
    proc callback args {
        tailcall namespace code $args
    }

    ::oo::class create namedclass {
        superclass ::oo::class
        self method create {name args} {
            tailcall my createWithNamespace $name $name {*}$args
        }

        method create {name args} {
            tailcall my createWithNamespace $name $name {*}$args
        }
    }

    # suggest importing these if you can:
    interp alias {} [namespace current]::continue   {}  ::return -level 0 -code continue
    interp alias {} [namespace current]::break      {}  ::return -level 0 -code break

    # might as well have a nice cleanup version of this too:
    namedclass create After {
        variable Afters

        constructor {} {
            set Afters [dict create]
        }

        destructor {
            dict for {id aid} $Afters {
                after cancel $aid
            }
        }

        method idle {args} {
            if {[llength $args] < 1} {
                tailcall ::after {*}$args
            }
            set args [lassign $args cmd]
            if { ! ([string is entier -strict $cmd] || $cmd in {idle}) } {
                tailcall ::after $cmd {*}$args
            }
            variable AfterID
            incr AfterID
            dict set Afters $AfterID [::after idle [callback my Bang $AfterID {*}$args]]
        }

        method Bang {id args} {
            dict unset Afters $ID
            uplevel #0 {*}$args
        }
    }

    namedclass create Every {
        variable Cancel
        variable Paused
        variable Active
        variable Afters

        constructor {} {
            set Active [dict create]
            set Cancel [dict create]
            set Paused [dict create]
            set Afters [dict create]
        }

        destructor {
            dict for {id aid} $Afters {
                after cancel $id
            }
        }

        # after <ms>
        method unknown {ms script} {
            variable EveryID
            if {![string is entier -strict $ms]} {
                return -code error "Invalid argument \"$ms\" - expected [join [info class methods Every] ", "] or an integer"
            }
            if {[string trim $script] eq ""} {return}
            set id every#[incr evID]
            dict set Active $id $script
            # after idle?
            dict set Afters $id [after 0 [callback my Tick $id $ms $script]]
            return $id
        }

        # public methods:
        method cancel {args} {
            if {$args in {all *}} {
                tailcall my kill
            }
            foreach id $args {
                dict set Cancel $id {}
            }
        }
        method kill {} {
            dict for {id _} $Active {
                dict set Cancel $id {}
            }
        }
        method pause {args} {
            foreach id $args {
                dict set Paused $id {}
            }
        }
        method resume {args} {
            foreach id $args {
                dict unset Paused $id
            }
        }
        method info {args} {
            if {$args eq ""} {
                return $Active
            }
            foreach id $args {
                dict set result $id [dict get $Active $id]
            }
            return $result
        }

        # internal implementation:
        method Tick {id interval script} {
            dict unset Afters $id
            if {[dict exists $Cancel $id]} {
                dict unset Active $id
                dict unset Cancel $id
                dict unset Paused $id   ;# to be safe
                my Log Cancelled $id
                return
            }
            set start   [clock milliseconds]
            if {[dict exists $Paused $id]} {
                my Log Paused $id
            } else {
                try {
                    uplevel #0 $script
                } on break {} {
                    dict unset Active $id
                    dict unset Cancel $id
                    dict unset Paused $id   ;# to be safe
                } on continue {r o} {
                    if {[string is integer -strict $r]} {
                        set interval $r     ;# support [continue newIntervalMilliseconds]
                    }
                } on error {e o} {
                    my Log BGERROR $id
                    dict unset Active $id
                    dict incr o -level -1
                    return -code error -options $o $e   ;# pass to bgerror (?)
                }
            }
            set end     [clock milliseconds]
            set elapsed [expr {$end - $start}]
            if {$elapsed > $interval} {
                my Log TOO LONG $id - $elapsed vs $interval
                set elapsed [expr {$elapsed % $interval}]
            }
            set delay [expr {$interval - $elapsed}]
            dict set Afters $id [after $delay [callback my Tick $id $interval $script]]
            return ""   ;# polite from event handlers.  Avoids bugs elsewhere.
        }

        method Log {args} {
            #puts stderr "[self] $args"
        }
    }

    Every create every

    namespace export every
}

namespace import every::every
