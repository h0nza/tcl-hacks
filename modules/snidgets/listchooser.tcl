package require snit
package require adebug
package require tests
package require vartrace

snit::widgetadaptor ListChooser {

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

        installhull using listbox
        bind $win <<ListboxSelect>> [list after idle [mymethod lbSelect]]
        $self configure -variable [myvar var_]
        $self configurelist $args
    }

    destructor {
        vartrace remove [myvar var] write [mymethod traceHandler]
    }

    method lbSelect {} {
        debug what
        set var [$self get [$self curselection]]

        if {$options(-command) ne ""} {
            after idle [list {*}$options(-command) $var]
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
                if {$var ni [$self get 0 end]} {
                    debug log {Initialising $value to 0!}
                    set var [$self get 0]
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

    method select {val} {
        set idx [lsearch -exact [$self get 0 end] $val]
        $self selection clear 0 end
        $self activate $idx
        $self selection set $idx $idx
    }

    method traceHandler args {
        debug log {$self traceHandler $args: $var}
        $self select $var
        #$self configure -state [expr {$var ? "disabled" : "normal"}]
    }
}

tests {
    proc test {} {
        package require Tk
        set ::l {one two three four five six}
        set ::v four
        pack [ListChooser .l -listvariable ::l -variable ::v -command {debug log CHOSE}]
        #pack [listbox .lb -listvariable ::l]
    }
    test
}
