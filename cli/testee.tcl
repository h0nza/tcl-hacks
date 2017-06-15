#!/usr/bin/env tclsh
#

proc lshift {varName} {
    upvar 1 $varName ls
    if {$ls eq ""} {
        throw {LSHIFT EMPTY} "Attempt to shift empty list\$$varName"
    }
    set ls [lassign $ls r]
    return $r
}

proc echo {args} {
    if {[catch {puts {*}$args}]} {exit}
}

proc main {args} {
    set rc 0
    set output ""
    while {$args ne ""} {
        switch [lshift args] {
            -r {set rc [lshift args]}
            -o {lappend output stdout [lshift args]}
            -e {lappend output stderr [lshift args]}
        }
    }
    foreach {channel data} $output {
        after 100
        echo $channel $data
    }
    after 100
    return $rc
}

exit [main {*}$::argv]
