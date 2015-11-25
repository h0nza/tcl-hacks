#
# SYNOPSIS:  a direct analogue of radioset
#
package require Tk
package require snit
package require adebug

snit::widgetadaptor CheckSet {

    option -command -default {} -configuremethod setOpt
    option -variable -default {} -configuremethod setOpt    ;# this is a list
    option -choices -default {} -configuremethod setOpt
    option -choicesvariable -default {} -configuremethod setOpt
    option -value -default {} -configuremethod setOpt

    variable items
    variable state      ;# this is an array, bound to the individual checkbuttons
                        ;# a trace on state updates the -variable, if present
    variable listvariable   ;# declared here so that methods see it

    constructor args {
        debug off
        set var {}
        set items {}
        array set state {}
        trace add variable [myvar state] write [mymethod stateTrace]
        installhull using frame
        $self configurelist $args
    }

    method get {} {return $listvariable}

    method set {ls} {
        set listvariable $ls
    }

    method setOpt {name value} {
        debug what
        switch $name {
            -command {
                $self configitems -command $value
            }
            -variable {
                if {[info exists listvariable]} {
                    unset listvariable  ;# takes traces with it
                }
                upvar #0 $value [myvar listvariable]
                trace add variable [myvar listvariable] write [mymethod variableTrace]
            }
            -choicesvariable {
                if {[info exists items]} {
                    unset items
                }
                upvar #0 $value [myvar items]
                trace add variable [myvar items] write [mymethod itemsTrace]
                $self build
            }
            -choices {
                set items $value
                $self build
            }
            -value {
                $self set $value
                return
            }
        }
        set options($name) $value
    }

    # this could do with insert and delete methods as well, to be complete as a container
    method build {} {
        map destroy [winfo children $win]
        set n 0
        dict for {value text} $items {
            if {![info exists state($value)]} {
                set state($value) 0
            }
            grid [checkbutton [$self widget $n] -text $text -anchor w \
                    -variable [myvar state($value)] -command $options(-command)] -sticky nsew
            grid rowconfigure $win $n -weight 1
            incr n
        }
        grid columnconfigure $win 0 -weight 1
    }

    method widget {idx} {
        if {[string is integer $idx]} {
            if {($idx < 0) || ($idx >= [dict size $items])} {
                return -code error "Index out of bounds: $idx"
            }
            return $win.r$idx
        }
        if {[dict exists $items $idx]} {
            set n [dict search $items $idx]
            tailcall $self widget $n
        } elseif {$idx in {end last}} {
            tailcall $self widget [expr {[dict size $items]-1}]
        }
        return -code error "Bad index: $idx"
    }

    method widgets {} {
        lmap idx [range [dict size $items]] {
            subst {$win.r$idx}
        }
    }

    method configitems {args} {
        lmap iw [$self widgets] {
            $iw configure {*}$args
        }
    }
    method itemconfig {idx args} {
        [$self widget $idx] {*}$args
    }

    variable notrace 0
    method notrace {script} {
        if {!$notrace} {
            incr notrace
            try {
                uplevel 1 $script
            } finally {
                incr notrace -1
            }
        }
        debug log {notrace skipping!}
    }

    method variableTrace args {
        debug log {variable changed}
        $self notrace {
            array set state [lconcat {k v} [array get state] {
                list $k [expr {$k in $listvariable}]
            }]
        }
    }

    method itemsTrace args {
        debug log {items changed}
        after idle [list $self build]
    }

    method stateTrace args {
        debug log {state changed}
        $self notrace {
            set listvariable [lmap {k v} [array get state] {
                if {!$v} continue
                set k
            }]
        }
    }
}

if 0 {
    package require Tk
    pack [CheckSet .rs -choices {blue "The colour of the sky" green "at the gills with envy"} -variable foo -command {puts "You chose $::foo"}]
}
