# tclconfig is configuration for tcl; configtcl is tcl for configuration!
#
# mini config script with a slave interp, for https://pastebin.mozilla.org/8883694
#
# If terminals were dicts with a key of {} (or lists of length 1), the config
# could be pretty-printed quite easily.

proc loadconf {filename} {
    set cint [interp create -safe]
    foreach cmd [$cint eval {info commands}] {
        # you can expose commands if you like:
        if {$cmd ni "foreach if"} {
            $cint hide $cmd
        }
    }
    # I like to expose [source] as [Include]:
    interp alias $cint Include {} interp invokehidden $cint source
    # give unknown handler a funny name so it doesn't collide:
    interp alias $cint #unknown {} cunk $cint
    interp invokehidden $cint namespace unknown #unknown
    # expose these for the lambda:
    foreach cmd {try set} {
        if {$cmd in [interp hidden $cint]} {
            interp alias $cint #$cmd {} interp invokehidden $cint $cmd
        } else {
            interp alias $cint #$cmd $cint $cmd
        }
    }
    interp invokehidden $cint set Config {}
    try {
        interp invokehidden $cint source $filename
    } on error {e o} {
        puts "Config error: $e"
    } finally {
        interp delete $cint
    }
}

proc readfile {filename} {
    try {
        set fd [open $filename r]
        read $fd
    } finally {
        close $fd
    }
}

proc cunk {cint args} {
    switch [llength $args] {
        1   {
            cerror $cint "Expected value for \"$args\""
        }
        2 {
            lassign $args key value
            set keys [list $key]
        }
        3 {
            lassign $args key1 key2 value
            set keys [list $key1 $key2]
        }
        default {
            cerror $cint "Too many arguments for [lindex $args 0]"
        }
    }
    if {[dict exists [interp invokehidden $cint set Config] {*}$keys]} {
        cerror $cint "Redefinition of $keys"
    }
    if {[string match \n* $value]} {
        set value [interp invokehidden $cint apply [list {{Config {}}} [list #try $value on ok {} {\#set Config}]]]
    }
    interp invokehidden $cint dict set Config {*}$keys $value
}

proc cerror {cint msg} {
    set ctx [interp invokehidden $cint info frame 0]
    set ctx "[dict get $ctx file]:[dict get $ctx line]"
    interp invokehidden $cint return -code error "$msg!\n  at $ctx"
}

foreach filename $::argv {
    puts [loadconf $filename]
}
