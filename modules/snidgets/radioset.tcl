#
# SYNOPSIS:
#
#   RadioSet -choices {blue "The colour of the sky" green "at the gills with envy"}
#
# TODO:
#  give it a -dictvariable
#  think about indices
#
#  add = insert idx (key value ?-tabopt ...?)
#
#
package require Tk
package require snit
#tcl::tm::path add ..
package require fun

snit::widgetadaptor RadioSet {

    option -command     -default {}     -configuremethod setOpt
    option -variable    -default {}     -configuremethod setOpt
    option -choices     -default {}     -configuremethod setOpt
    option -packside    -default left   -configuremethod setOpt
    option -itemstyle   -default {}     -configuremethod setOpt

    #variable var   ;# we don't keep a local stash of var, because upvar+traces killed me
    variable items

    constructor args {
        set var {}
        set items {}
        installhull using ttk::frame
        $self configurelist $args
    }

    method get {} {return $var}

    method setOpt {name value} {
        switch $name {
            -command {
                $self configitems -command $value
            }
            -variable {
                $self configitems -variable $value
            }
            -choices {
                set items $value
                $self build
            }
            -packside {
                set options($name) $value
                $self build
            }
            -itemstyle {
                $self configitems -style $value
            }
        }
        set options($name) $value
    }

    # this could do with insert and delete methods as well, to be complete as a container
    method build {} {
        map destroy [winfo children $win]
        set n 0
        dict for {value text} $items {
            set r [ttk::radiobutton [$self widget $n] -text $text -value $value \
                    -variable $options(-variable) -command $options(-command)]
            if {$options(-itemstyle) ne ""} {
                $r configure -style $options(-itemstyle)
            }
            bindtags $r [list $win {*}[bindtags $r]]
            pack $r -side $options(-packside)
            incr n
        }
    }

    method inputvar args {
        switch [llength $args] {
            0 {
                my varname inputs
            }
            1 {
                my varname inputs([lindex $args 0])
            }
            default {
                error "Incorrect arguments - expected 0 or 1"
            }
        }
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
        } elseif {$idx in {current selected}} {
            # lookup by value
            tailcall $self widget $var
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
        [$self widget $idx] {*}$args    ;# configure ?
    }

    method under {x y} {
        ;# FIXME
    }
    method insert {idx ...} {
        ;# FIXME
    }
    method delete {idx} {
        ;# FIXME
    }

    method traceHandler args {
        debug log {tracing $args: $var}
        if {"" ne $options(-command)} {
            after idle [list {*}$options(-command) $var]
        }
    }
}

if 0 {
    set side left
    pack [RadioSet .side -variable side -choices {left left right right top top bottom bottom} -command {.rs configure -packside $::side}]
    pack [RadioSet .rs -choices {blue "The colour of the sky" green "at the gills with envy"} -variable foo -command {puts "You chose $::foo"}]
    set choices [.rs cget -choices]
    pack [text .t]
    .t insert end $choices
    pack [button .b -command {.rs configure -choices [.t get 1.0 end]}]
    #.side configitems -style Toolbutton
    .side configure -itemstyle Toolbutton
    bind .side <Button-2> {puts Three}
    after 1000 {set foo blue}
    after 2000 {set foo green}
}
