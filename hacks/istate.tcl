namespace eval istate {
    namespace export {[a-z]*}

    proc tclose {cmdPrefix seed} {
        set stack [list $seed]
        #puts "Starting with $seed .."
        for {set i 0} {$i < [llength $stack]} {incr i} {
            set el [lindex $stack $i]
            set kids [map {tclose $cmdPrefix} [{*}$cmdPrefix $el]]
            set kids [concat {*}$kids]
            set kids [ldiff $kids $stack]   ;# avoid cycles
            lappend stack {*}$kids
            #lappend stack {*}[concat {*}[map {tclose $cmdPrefix} [{*}$cmdPrefix $el]]]
        }
        set stack
    }

    proc lshift {varName} {
        upvar 1 $varName ls
        if {$ls eq ""} {
            throw {LSHIFT EMPTY} "Attempt to shift empty list\$$varName"
        }
        set ls [lassign $ls r]
        return $r
    }

    proc inspect args {
        set res {cmds {} vars {}}
        if {$args eq ""} {
            set args [list ::]
        }
        set queue $args
        while {$queue ne {}} {
            set ns [lshift queue]
            lappend queue {*}[namespace children $ns]
            dict lappend res cmds {*}[info commands ${ns}::*]
            dict lappend res vars {*}[info vars ${ns}::*]
        }
        dict with res {
            set cmds [lsort $cmds]
            set vars [lsort $vars]
        }
        return $res
    }
}

