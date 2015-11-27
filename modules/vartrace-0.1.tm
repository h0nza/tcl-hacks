# SYNOPSIS:
#
#   A persistent trace for namespace variables.
#     [vartrace add varName ops cmdPrefix]
#     [vartrace info varName]
#     [vartrace remove varName ops cmdprefix]
#     [vartrace suspend varName script]
#
#   vartrace implicitly adds an [unset] trace which will restore the vartraces.
#
#   Differences from trace:
#     * [trace info] returns a list of pairs.  [vartrace info] flattens it.
#     * this doesn't work with locals, so it attempts to qualify the passed varName.  It should error if you attempt to pass a local.
#     * [vartrace remove varName] will remove all traces
#
# See `binder.tcl` for some fairly thorough tests.
#
catch {namespace delete ::vartrace}
package require adebug
namespace eval ::vartrace {
    #debug off

    proc _qualify {varName} {
        debug assert {[string match ::* $varName]}
        return $varName ;# qualifying is a bad idea
        #uplevel 2 namespace which -variable [list $varName]
    }

    proc add {varName ops cmdPrefix} {
        set varName [_qualify $varName]
        trace add variable $varName $ops $cmdPrefix
        trace add variable $varName unset [list ::vartrace::_handler $varName $ops $cmdPrefix]
    }

    proc _handler {varName ops cmdPrefix name1 name2 unset} {
debug what
        # varName is already qualified here
        set ns [namespace qualifiers $varName]
        if {$ns eq "" || [namespace exists $ns]} {
            debug log {restoring vartraces on $varName}
            tailcall add $varName $ops $cmdPrefix
        } else {
            debug log {not restoring vartraces on $varName - namespace has gone away}
        }
    }

    proc info {varName} {
        set varName [_qualify $varName]
        set traces [concat {*}[trace info variable $varName]]

        lconcat {ops cmdPrefix} $traces {
            if {[lindex $cmdPrefix 0] ne "::vartrace::_handler"} {
                continue
            }
            lassign $cmdPrefix _ _ ops cmdPrefix
            list $ops $cmdPrefix
        }
    }

    # remove varName ?ops cmdPrefix? ...
    # .. if no args are provided, it returns *all* vartraces
    proc remove {varName args} {
        debug assert {[llength $args] % 2 == 0}
        set varName [_qualify $varName]
        if {[llength $args] eq 0} {
            set args [::vartrace info [list $varName]]
        }
        foreach {ops cmdPrefix} $args {
            debug log {removing vartrace: [list $varName $ops $cmdPrefix]}
            trace remove variable $varName $ops $cmdPrefix
            trace remove variable $varName unset [list ::vartrace::_handler $varName $ops $cmdPrefix]
        }
        return $args
    }

    proc suspend {varName script} {
        ;# !! FIXME: this should take optional middle args
        set traces [::vartrace remove $varName]
        try {
            uplevel 1 $script
        } finally {
            foreach {ops cmdPrefix} $traces {
                ::vartrace add $varName $ops $cmdPrefix
            }
        }
    }

    namespace export {[a-z]*}
    namespace ensemble create
}

