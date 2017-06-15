namespace eval testscript {
    proc # args {
        set cmd [dict get [info frame [expr {[info frame]-1}]] cmd]
        regsub {^[^#]*#} $cmd "\n\\#" cmd
        real_puts "$cmd"
    }
    proc % {args} {
        set cmd [dict get [info frame [expr {[info frame]-1}]] cmd]
        regsub {^[^%]*%} $cmd "--%" cmd
        real_puts "$cmd"
        set r [uplevel 1 $args]
        if {$r ne ""} {
            real_puts "# $r"
        }
    }

    proc o: args {}
    proc E: args {}
    proc --% args {tailcall % {*}$args}

    proc real_puts args {
        tailcall ::puts {*}$args
    }

    proc test_puts {args} {
        if {[llength $args] == 1} {
            real_puts [list o: {*}$args]
        } elseif {[llength $args] == 2 && [lindex $args 0] == "stderr"} {
            real_puts [list E: {*}$args]
        } else {
            real_puts {*}$args
        }
    }

    proc testscript {script} {
        if {[info exists ::argv0] && ($::argv0 eq [uplevel 1 info script])} {
            namespace eval :: [list namespace import [list [namespace which -command %]]]
            rename [namespace current]::real_puts {}
            rename ::puts [namespace current]::real_puts
            rename [namespace current]::test_puts ::puts
            try $script
        }
    }
    namespace export testscript %
}

namespace path [list [namespace path] ::testscript]
