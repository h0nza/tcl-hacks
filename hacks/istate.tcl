namespace eval istate {
    namespace export {[a-z]*}

    proc putl args {puts $args}

    proc pdict {_ {name ""}} {
        array set $name $_
        parray $name
    }

    proc lshift {varName} {
        upvar 1 $varName ls
        if {$ls eq ""} {
            throw {LSHIFT EMPTY} "Attempt to shift empty list\$$varName"
        }
        set ls [lassign $ls r]
        return $r
    }

    proc sldiff {as bs} {
        set res {- "" + ""}
        try {
            set a {}; set b {}
            while 1 {
                while {$a eq $b} {
                    if {$as eq {} || $bs eq {}} {throw {LSHIFT EMPTY} ""}
                    set a [lshift as]
                    set b [lshift bs]
                    continue
                }
                while {[string compare $a $b] < 0} {
                    dict lappend res - $a
                    set a [lshift as]
                }
                while {[string compare $a $b] > 0} {
                    dict lappend res + $b
                    set b [lshift bs]
                }
            }
        } trap {LSHIFT EMPTY} {} {
            if {$as ne ""} {dict lappend res - {*}$as}
            if {$bs ne ""} {dict lappend res + {*}$bs}
        }
        return $res
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

    # interactively watch changes:
    #   coroutine co#watch watch 2000 stdout        ;# report every 2s on stdout
    proc watch {ms {chan stdout} args} {
        set old_state [inspect {*}$args]
        while 1 {
            after $ms [info coroutine]
            yield
            set now [clock seconds]
            set new_state [inspect {*}$args]
            set cmds [sldiff [dict get $old_state cmds] [dict get $new_state cmds]]
            set vars [sldiff [dict get $old_state vars] [dict get $new_state vars]]
            set old_state $new_state

            if {[set ls [dict get $cmds -]] ne ""} { puts $chan "$now cmds - $ls" }
            if {[set ls [dict get $cmds +]] ne ""} { puts $chan "$now cmds + $ls" }
            if {[set ls [dict get $vars -]] ne ""} { puts $chan "$now vars - $ls" }
            if {[set ls [dict get $vars +]] ne ""} { puts $chan "$now vars + $ls" }
        }
    }
}


if {[info script] eq $::argv0} {
    proc finally {script} {
        tailcall trace add variable :#finally#: unset [list apply [list args $script]]
    }

    proc repl {cmdPrefix {in stdin} {out ""} {err ""}} {
        if {$out eq ""} {set out $in}
        if {$err eq ""} {set err $out}
        if {$out eq "stdin"} {set out "stdout"}
        if {$err eq "stdin"} {set err "stderr"}
        chan configure $in -blocking 0 -buffering line
        set oldev [chan event $in readable]
        chan event $in readable [info coroutine]
        finally [list chan event $in readable $oldev]
        set command ""
        while 1 {
            if {$command eq ""} {
                puts -nonewline $out "% "; flush $out
            } else {
                puts -nonewline $out "- "; flush $out
            }
            yield
            set chunk [gets $in]
            if {$chunk eq "" && [eof $in]} {
                break
            }
            append command \n$chunk
            if {![string is space $command] && [info complete $command]} {
                set rc [catch {{*}$cmdPrefix $command} result opts]
                if {$rc == 0} {
                    {*}$cmdPrefix [list set _ $result]
                    puts $out $result
                } else {
                    puts $err "\[$rc\]: $result"
                }
                set command ""
            }
        }
    }

    coroutine co#watch istate::watch 2000
    coroutine co#repl repl ::eval stdin
    trace add command co#repl delete {apply {args exit}}
    vwait forever
}
