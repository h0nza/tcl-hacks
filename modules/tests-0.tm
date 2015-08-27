#
# tcltest looks at ::argv, and dies if it doesn't like what it sees, in several places
# hence this crap
#

package require pkg
package require fun

pkg tests {
    # require early and disable tests for fun
    proc disable {} {
        proc tests args {}
    }

    proc tests {args} {
        if {[info exists ::argv0] && $::argv0 eq [uplevel 1 {info script}]} {
            tailcall RunTests {*}$args
        } else {
            # if we're in debug/devel mode, it might be nice to register the script
            # maybe.  But this implies declaring tests inside the namespace, which might be too early
            # a -pkg argument sounds sounder
            set ns [uplevel 1 {namespace current}]
            tailcall proc RunTests {} "
                    [namespace current]::RunTests $args
            "
        }
    }

    proc RunTests {args} {
        if {[catch {package present tcltest}]} {
            foreach argv $::argv ::argv {} {}
            package require tcltest
        }
        namespace eval ::tcltests {
            namespace path ::tcltest
        }
        try {
            puts "Running tests for $::argv0 .."
            namespace eval ::tcltests [concat {*}$args]
        } on error {e o} {
            puts "$::argv0 test error: $e"
            pdict $o
        } on ok {} {
            puts "$::argv0 tests complete!"
        } finally {
            namespace delete ::tcltests
        }
    }
}
