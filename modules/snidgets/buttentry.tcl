#
# SYNOPSIS:
#
#  ButtEntry -command {tk_getOpenFile}
#
# A readonly entry which invokes -command on Invoke
# the result of -command becomes the new value
#
package require snit
package require vartrace

snit::widgetadaptor ButtEntry {

    option -command     -default {}

    delegate option -variable to hull as -textvariable  ;# go team!

    delegate option * to hull
    delegate method * to hull

    constructor args {
        installhull using entry
        $self configurelist $args
        $self configure -state readonly ;# yuck
        bind $win <1> [mymethod activate]
        bind $win <Return> [mymethod activate]
        bind $win <<Invoke>> [mymethod activate]
    }
    method activate args {
        # after idle ?
        set newval [uplevel #0 $options(-command) [list [$self get]]]  ;# how does this get arguments?
        $self configure -state normal   ;# yuck
        $self delete 0 end
        $self insert 0 $newval
        $self configure -state readonly ;# yuck
        #debug show {$self $newval}
        #debug show {[$self configure -textvariable]}
    }
}

snit::widgetadaptor OnButton {

    option -variable    -default {} -configuremethod setOpt
    option -command     -default {} -configuremethod setOpt

    delegate option * to hull
    delegate method * to hull

    variable var
    variable var_

    constructor args {
        set var_ 0
        upvar #0 [myvar var_] [myvar var]
        vartrace add [myvar var] write [mymethod traceHandler]

        installhull using ttk::button -command [mymethod activate]
        $self configure -variable [myvar var_]
        $self configurelist $args
    }

    destructor {
        vartrace remove [myvar var] write [mymethod traceHandler]
    }

    method activate args {
        debug what
        # after idle ?
        after idle [list set [myvar var] 1]
        #set var 1
        if {$options(-command) ne ""} {
            $options(-command)
        }
    } 

    method setOpt {name value} {
        debug what
        switch $name {
            -variable {
                vartrace suspend [myvar var] {
                    upvar 0 $value [myvar var]
                }
                variable var
                debug log {rebound to $value == $var [set [myvar var]]}
                if {![string is boolean -strict $var]} {
                    debug log {Initialising $value to 0!}
                    set var 0
                }
            }
            -command {
            }
            default {
                error "Unknown option: $name"
            }
        }
        set options($name) $value
    }

    method traceHandler args {
        debug log {$self traceHandler $args: $var}
        $self configure -state [expr {$var ? "disabled" : "normal"}]
    }
}
