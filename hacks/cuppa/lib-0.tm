namespace eval lib {

    proc putl args {puts $args}

    proc main {arglist body} {
        set m [uplevel 1 {expr {[info exists ::argv0]
                && [file dirname [file normalize $::argv0/...]]
                eq [file dirname [file normalize [info script]/...]]}}]
        if {$m} {
            set ns [uplevel 1 {namespace current}]
            tailcall apply [list $arglist $body $ns] {*}$::argv
        }
    }
    
    proc lsub script {    ;# [sl] from the wiki
        set res {}
        set parts {}
        foreach part [split $script \n] {
            lappend parts $part
            set part [join $parts \n]
            #add the newline that was stripped because it can make a difference
            if {[info complete $part\n]} {
                set parts {}
                set part [string trim $part]
                if {$part eq {}} {
                    continue
                }
                if {[string index $part 0] eq {#}} {
                    continue
                }
                #Here, the double-substitution via uplevel is intended!
                lappend res {*}[uplevel list $part]
            }
        }
        if {$parts ne {}} {
            error [list {incomplete parts} [join $parts]]
        }
        return $res
    }

    proc my {cmd args} {
        list [namespace current]::$cmd {*}$args
    }

    proc dictargs {_args defaults} {
        upvar 1 $_args args
        set defaults [uplevel 1 [my lsub $defaults]]
        set bad [dict filter $args script {k _} {
            expr {![dict exists $defaults $k]}
        }]
        if {$bad ne ""} {
            tailcall tailcall throw {TCL BADARGS} "Unexpect arguments \"$bad\"\naccepted arguments are ([dict keys $defaults])"
        }
        set args [dict merge $defaults $args]
        tailcall dict with $_args {}
    }

    proc alias {alias cmd args} {
        set ns [uplevel 1 {namespace current}]
        set ns [string trimright $ns :]
        if {![string match ::* $alias]} {
            set alias ${ns}::${alias}
        }
        if {![string match ::* $cmd]} {
            set cmd ${ns}::${cmd}
        }
        interp alias {} $alias {} $cmd {*}$args
    }

    proc upns {{lvl 1} args} {
        if {$args eq ""} {
            tailcall uplevel $lvl {namespace current}
        } else {
            set ns [uplevel [expr {$lvl+1}] {namespace current}]
            set ns [string trimleft $ns ::]
            set args [lassign $cmd args]
            list ${ns}::$cmd {*}$args
        }
    }
    proc updo {{lvl 1} args} {
        tailcall uplevel 1 $args
    }
}

