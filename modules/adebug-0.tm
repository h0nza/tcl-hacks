# Usage:
#   try {package require debug} on error {} {proc debug args {}}
#
package require fun     ;# ?
package require extend  ;# dict get?

# this is intended to help with transcripts, but it ain't there yet
proc % args {
    #puts L:[info level [info level]]
    #puts F:[info frame -1]
    puts [dict get [info frame -1] cmd]
    #puts "% [debug level -1]"
    set rc [catch {uplevel 1 $args} e o]
    if {$rc} {
        ei
    } elseif {$e ne ""} {
        puts $e
    }
    return {*}$o $e
}

namespace eval debug {
    # gather context information for display:
    proc what {} {
        lograw [string repeat " " [info level]][uplevel 1 namespace current]::[info level -1]
    }
    proc level {{l -1}} { ;# this doesn't seem to work in the repl, and I'm not sure why
        incr l [info level]
        for {set f 1} {1} {incr f} {
            set fr [info frame $f]
            if {[dict exists $fr level] && [dict get $fr level]==$l} {
                return [dict get $fr cmd]
            }
        }
    }

    proc watch {varName} {
        set varName [uplevel 1 [list namespace which -variable $varName]]
        debug log {WATCH- tracing $varName}
        trace add variable $varName write [lambda {varName args} {
            debug log {WATCH: $varName = [set $varName]}
            debug log {WATCH  in [debug stack]}
        }]
    } 
    proc watcharray {varName} {
        set varName [uplevel 1 [list namespace which -variable $varName]]
        debug log {WATCH- tracing $varName}
        trace add variable $varName write [lambda {varName key args} {
            debug log {WATCH: ${varName}($key) = [set ${varName}($key)]}
            debug log {WATCH  in [debug stack]}
        }]
    }
    proc stack {} {
        set l [info level]
        set res {}
        while {[incr l -1] >= 0} {
            lappend res [info level $l]
        }
        set res
    }
    proc frames {} {
        set l [info frame]
        set res {}
        while {[incr l -1] >= 0} {
            lappend res [info frame $l]
        }
        set res
    }

    proc vars {{patterns *}} {
        set res {}
        foreach varName [concat {*}[map {uplevel 1 info vars} $patterns]] {
            if {![uplevel 1 [list info exists $varName]]} {
                # declared but uninitialised variables - ignore them
            } elseif {[uplevel 1 [list array exists $varName]]} {
                # ignore arrays
            } else {
                dict set res $varName [uplevel 1 [list set $varName]]
            }
        }
        set res
    }

    proc locals {{patterns *}} {
        foreach varName [concat {*}[map {uplevel 1 info locals} $patterns]] {
            if {[Uplevel 1 array exists $varName]} {
                Uplevel 1 parray $varName
            } else {
                Uplevel 1 debug show \$[list $varName]
            }
        }
    }

    proc getproc {name} {
        set argList [info args $name]
        set args [lmap arg [info args $name] {
            if {[info default $name $arg default]} {
                list $arg $default
            } else {
                set arg
            }
        }]
        set body [info body $name]
        return [list proc $name $args $body]
    }

    # just dumps info to stdout.  Here because introspection is fun.
    proc dumpns {{ns ::}} {
        # transitive closure:
        foreach ns [tclose {namespace children} ::] {
            foreach cmd [info commands ${ns}::*] {
                puts [list command $cmd]
            }
            foreach var [info vars ${ns}::*] {
                try {
                    if {[array exists $var]} {
                        puts [list array $var [array get $var]]
                    } else {
                        puts [list variable $var [set $var]]
                    }
                } on error {} {
                    puts [list UNREADABLE $var]
                }
            }
        }
    }

    proc ::noop args {}     ;# this goes in global space
    proc ::no-op args {}    ;# some call it no-op

    # like assert.h's NDEBUG: make everything a noop
    proc ndebug {} {
        interp alias {} ::debug {} ::noop
    }
    proc off {} {
        interp alias {} [uplevel 1 namespace current]::debug {} ::noop
    }

    proc show {args} {
        foreach s $args {
            try {
                puts "\[DEBUG\]: [list $s -> [uplevel 1 subst [list $s]]]"
            } on error e {
                puts "\[DEBUG-ERROR\]: $e evaluating [list $s]"
            }
        }
    }

    proc pdict {d} {
        dict for {k v} $d {
            if {[string length $v] > 100} {
                set v [string range $v 0 99]\u2026
            }
            debug log { $k -> $v}
        }
    }

    proc transcript {args} {
        foreach cmd [cmdsplit [concat {*}$args]] {
            debug log "% $cmd\n"
            try {
                set res [uplevel 1 $cmd]
                if {$res ne ""} {debug log "#  $res"}
            } on error {e o} {
                debug perror $e $o
            }
        }
    }

    # this should support logging to a different chan
    # facilities and level filtering ..
    # facility: namespace of caller?  first known namespace on call stack?
    proc lograw {args} {
        puts "\[DEBUG\]: $args"
    }

    proc ms {} {
        clock format [clock seconds] -format %M:%S
    }
    proc log {args} {
        try {
            puts "[ms]:\[DEBUG\]: [uplevel 1 subst [list $args]]"
        } on error e {
            puts "\[DEBUG-ERROR\]: $e evaluating [list $args]"
        }
        return
        try {
            puts "\[DEBUG\]: [uplevel 1 subst [list $s]]"
        } on error e {
            puts "\[DEBUG-ERROR\]: $e evaluating [list $s]"
        }
    }

    proc assert {x {msg ""}} {
        if {![uplevel 1 expr [list $x]]} {
            catch {
                set y [uplevel 1 [list subst -noc $x]]
                if {$y ne $x} {
                    set x "{$y} from {$x}"
                }
            }
            throw ASSERT "[concat "Assertion failed!" $msg] $x"
        }
    }

    proc demo args {
        log {% $args}
        set rc [catch {uplevel 1 $args} e o]
        if {$rc} {
            log {  --> ERROR($rc): $e [dict get $o -errorcode]}
        } else {
            log {  --> $e}
        }
        return {*}$o $e
    }
    proc where {{lvl 0}} {
        incr lvl -1
        set d [info frame $lvl]
        string cat "[dict get? $d type] [dict get? $d proc] at [dict get? $d file]:[dict get? $d line]"
    }
    proc do args {
        set where [debug where -1]
        log {DOING at $where: {$args}}
        set rc [catch {uplevel 1 $args} e o]
        log {RESULT : $rc {$e}}
        return {*}$o $e
    }
    proc eval {args} {
        log {TRACE => {$args}}
        set rc [catch {uplevel 1 $args} e o]
        log {TRACE <= $rc {$e}}
        return {*}$o $e
    }

    namespace eval tracer {
        namespace path [namespace parent [namespace current]]
        variable depth
        proc enter {command _} {
            variable depth
            log {TRACE [string repeat \  $depth]$command}
            incr depth
        }
        proc leave {command code result _} {
            variable depth
            incr depth -1
            log {TRACE [string repeat \  $depth]= ($code) {$result}}
        }
    }

    proc tracecmd {cmd} {
        set cmd [uplevel 1 [list namespace which $cmd]]
        trace add execution $cmd enter ::[namespace current]::tracer::enter
        trace add execution $cmd leave ::[namespace current]::tracer::leave
    }

    proc errorproc {tid error} {
        debug log {THREAD ERROR from $tid: $error}
    }

    proc bgerror {err opts} {
        debug log {BGERROR $err}
        debug pdict $opts
    }

    proc perror {err opts} {
        debug log {ERROR: $err}
        debug pdict $opts
    }

    namespace export {[a-z]*}
    namespace ensemble create
}

