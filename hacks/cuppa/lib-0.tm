package require platform

namespace eval lib {

    proc putl args {puts $args}

    proc main {arglist body} {      ;# lib::main {args} {puts "Invoked directly, with $args"}
        set m [expr {[info exists ::argv0]
                && [file dirname [file normalize $::argv0/...]]
                eq [file dirname [file normalize [lib::updo info script]/...]]}]
        if {$m} {
            package require log 0   ;# fixme - circular dependency too!
            set ns [lib::upns]
            set s [updo info script]
            log::warn "$s - running on [platform::identify] ([platform::generic])"
            tailcall apply [list $arglist $body $ns] {*}$::argv
        }
    }
    
    proc lsub script {              ;# [sl] from the wiki
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

    proc my {cmd args} {            ;# create cmdprefixes with local commands
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

    ;# lang-utils
    proc alias {alias cmd args} {
        set alias   [upns 1 $alias]
        set cmd     [upns 1 $cmd]
        interp alias    {} $alias   {} $cmd {*}$args
    }

    proc upns {{lvl 1} args} {  ;# doubles as resolve-cmdname-in-caller
        if {$args eq ""} {
            tailcall uplevel $lvl {namespace current}
        } else {
            set cargs [lassign $args cmd]
            if {[string match :* $cmd]} {
                return $args
            }
            set ns [uplevel [expr {$lvl+1}] {namespace current}]
            set ns [string trimright $ns :]
            return [list ${ns}::$cmd {*}$cargs]
        }
    }
    proc updo {{lvl 1} args} {
        tailcall uplevel $lvl $args
    }

    proc dictable {names list} {
        set args [join [lmap name $names {
            set name [list $name]
            subst -noc {$name [set $name]}
        }] " "]
        lmap $names $list "dict create $args"
    }

}
