#!/usr/bin/env tclsh
#
lappend auto_path [file normalize [info script]/../modules]
::tcl::tm::path add [file normalize [info script]/../modules]

if {$::argv ne ""} {
    proc info_cmdline {} [list list [info nameofexe] $::argv0 $::argv]      ;# hack for restartability
    set ::argv [lassign $::argv ::argv0]
    source $::argv0
} else {
    return
    # async repl:
    package require repl
    coroutine main repl::chan stdin stdout stderr
    trace add command main delete {unset ::forever; #}
    vwait forever
}
