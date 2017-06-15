# meta-framework for command language interfaces
proc args {argspec} {
    upvar 1 args args
    tailcall apply [list $argspec {tailcall mset {*}[locals]}] {*}$args
}

proc locals {} {
    set res {}
    foreach name [uplevel 1 {info locals}] {
        dict set res $name [uplevel 1 [list set $name]]
    }
    return $res
}

proc mset {args} {
    dict for {name value} $args {
        uplevel 1 [list set $name $value]
    }
}

proc lshift {varName} {
    upvar 1 $varName ls
    if {$ls eq ""} {
        throw {LSHIFT EMPTY} "Attempt to shift empty list\$$varName"
    }
    set ls [lassign $ls r]
    return $r
}

proc alias {alias args} {
    if {![string match ::* $alias]} {
        set ns [uplevel 1 {namespace current}]
        set alias ${ns}::${alias}
    }
    tailcall interp alias {} $alias {} {*}$args
}

proc evalsession {alias namespace} {
    set ns [uplevel 1 {namespace current}]
    if {![string match ::* $alias]} {
        set alias ${ns}::${alias}
    }
    if {![string match ::* $namespace]} {
        set namespace ${ns}::${namespace}
    }
    coroutine $alias apply [list {} {   ;# Vars automatically visible to client scripts:
        set ? 0                         ;# the last command's return code (0=ok)
        set % {-level 0}                ;# the last command's error dictionary
        set _ [info coroutine]          ;# the last command's result
        while 1 {
            set ! [yieldto return {*}${%} $_]
            set ! [concat {*}${!}]      ;# the current command
            set ? [catch ${!} _ %]
        }
    } $namespace]
}

proc repl {cmdPrefix {in stdin} {out ""} {err ""}} {
    if {$out eq ""} {set out $in}
    if {$err eq ""} {set err $out}
    if {$out eq "stdin"} {set out "stdout"}
    if {$err eq "stdin"} {set err "stderr"}
    chan configure $in -blocking 0
    chan event $in readable [info coroutine]
    set command ""
    while 1 {
        if {$command eq ""} {
            puts -nonewline $out "% "; flush $out
        } else {
            puts -nonewline $out "- "; flush $out
        }
        yield
        append command [read $in]
        if {$command eq "" && [eof $in]} {
            break
        }
        if {$command ne "" && [info complete $command]} {
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

proc ?? {} {
    puts $::errorInfo
    puts -nonewline \[$::errorCode\]
    flush stdout
}

proc main {args} {

    set repl 0              ;# invoke interactive repl?  default if no args are given
    set use "namespace"     ;# kind of evaluation context: "namespace" or "interp"
    set source {}           ;# scripts to preload?  Specified with -s
    set unknown 1           ;# provide [unknown] command

    # parse options:
    while {[string match -* [lindex $args 0]]} {
        set opt [lshift args]
        switch -exact $opt {
            -i { set repl 1 }
            -s { lappend source [lshift args] }
            -nu { set unknown 0 }
            -- break
            default {set args [linsert $args 0 opt]; break}
        }
    }

    if {!$repl} {set repl [expr {$args eq ""}]}


    # create the "app" object whose subcommands will be exposed
    source hexed.tcl
    Hexed create app
    set obj [namespace which -command app]
    set methods [info object methods $obj -all]     ;# not -private

    # create the eval context and alias all the subcommands of "app" to it.

    if {$use eq "interp"} {             ;# interp method:  makes upvar/level and sharing variables awkward
        set interp [interp create]
        foreach meth $methods {
            interp alias $interp $meth {} $obj $meth
        }
        if {$unknown} {
            interp alias $interp unknown $interp ::exec <@ stdin >@ stdout 2>@ stderr
        }

        alias ::interactive $interp eval
        if {$source in [interp hidden $interp]} {
            alias ::interactive_source $interp invokehidden [list source $argv0]
        } else {
            alias ::interactive_source $interp eval [list source $argv0]
        }

    } elseif {$use eq "namespace"} {    ;# namespace + coro method:  being out of :: has its drawbacks.  Not bad though.
        namespace eval ::interactive {}
        foreach meth $methods {
            alias ::interactive::$meth $obj $meth
        }
        if {$unknown} {
            namespace eval ::interactive {
                namespace unknown {::exec <@ stdin >@ stdout 2>@ stderr}
            }
        }

        evalsession ::interactive ::interactive
        alias ::interactive_source ::interactive source

    } else {error "Bad use \"$use\""}

    foreach script $source {
        ::interactive_source $script
    }

    # main script?
    if {$args ne ""} {
        set args [lassign $args argv0]
        #set script [readfile $argv0]
        ::interactive [list set ::argv0 $argv0]
        ::interactive [list set ::args $args]
        ::interactive_source $argv0
    }
    if {$repl} {
        repl ::interactive stdin
    }
}

coroutine run main {*}$::argv
if {![catch {trace add command run delete {lappend ::forever}}]} {
    vwait ::forever
}
