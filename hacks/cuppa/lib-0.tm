namespace eval lib {
    proc main {arglist body} {
        set m [uplevel 1 {expr {[info exists ::argv0]
                && [file dirname [file normalize $::argv0/...]]
                eq [file dirname [file normalize [info script]/...]]}}]
        if {$m} {
            set ns [uplevel 1 {namespace current}]
            tailcall apply [list $arglist $body $ns] {*}$::argv
        }
    }
    proc putl args {puts $args}
}

