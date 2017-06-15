package require tip288

namespace eval fancyargs {

    variable parseargs [list ::tip288::arguments]

    ::proc proc {name argspec body} {
        variable parseargs
        set body "$parseargs [list $argspec]\;$body"
        uplevel 1 [list ::proc $name args $body]
        register_formalargs [uplevel 1 [list namespace which $name]] $argspec
        return ""
    }

    ::proc lambda {argspec body args} {
        variable parseargs
        set body "$parseargs [list $argspec]\;$body"
        list apply [list args $body] {*}$args
    }
    # lambda@ exercise for the reader

    namespace eval class {
        upvar 1 parseargs parseargs
        namespace path [list [namespace parent]]
        apply [list {} {
            # install initial oo::define forwards:
            foreach cmd [info commands ::oo::define::*] {
                set cmd [namespace tail $cmd]
                ::proc $cmd {args} [format {
                    upvar 1 classname classname
                    tailcall ::oo::define $classname %s {*}$args
                } [list $cmd]]
            }
            return ""
        } [namespace current]]

        ::proc self {args} {
            upvar 1 classname classname
            if {$args eq ""} {
                return $classname
            } else {
                tailcall ::oo::define $classname self {*}$args
            }
        }

        ::proc constructor {argspec body} {
            upvar 1 classname classname
            ::variable parseargs
            set body "$parseargs [list $argspec]\;$body"
            uplevel 1 [list ::oo::define $classname constructor args $body]
            register_formalargs [self] $argspec
        }

        ::proc method {name argspec body} {
            upvar 1 classname classname
            ::variable parseargs
            set body "$parseargs [list $argspec]\;$body"
            uplevel 1 [list ::oo::define $classname method $name args $body]
            register_formalargs [self] $name $argspec
        }

        ::proc create {classname script} {
            set classname [uplevel 1 [list ::oo::class create $classname]]
            try $script
            return $classname
        }
        namespace export *
        namespace ensemble create
    }
    # objdefine exercise for the reader

    ::proc register_formalargs {args} {
        variable argspecs
        set val [lindex $args end]
        set cmd [lrange $args 0 end-1]
        dict set argspecs $cmd $val
    }

    ::proc formalargs {cmd args} {
        variable argspecs
        set cmd [uplevel 1 [list namespace which $cmd]]
        set args [linsert $args 0 $cmd]
        if {[dict exists $argspecs $args]} {
            dict get $argspecs $args
        } elseif {[llength $args] == 1} {
            lmap arg [info args $cmd] {
                if {[info default $cmd $arg default]} {
                    list $arg $default
                } else {
                    list $arg
                }
            }
        } elseif {[info object isa object $cmd]} {
            lindex [info object definition {*}$args] 0
        }
    }

    namespace export *
}

package require testscript
testscript {
    --% namespace import ::fancyargs::*
    --% proc foo {x {y 2} args {z 3} w} {
            puts "x=$x, y=$y, args=$args, z=$z, w=$w"
        }

    \# procs work, and are inspectable
    --% foo one two three
    o: {x=one, y=two, args=, z=3, w=three}
    --% puts [formalargs foo]
    o: {x {y 2} args {z 3} w}

    \# lambdas work:
    --% {*}[lambda {x {y 2} args {z 3} w} {
            puts "x=$x, y=$y, args=$args, z=$z, w=$w"
        } one two three] four five
    o: {x=one, y=two, args=three, z=four, w=five}

    \# classes work:
    --% class create Foo {
            variable A B
            constructor {{A nay!} {B sir!}} {   ;# variable initialisation as a handy side effect
            }
            method frob {x {y 2} args {z 3} w} {
                puts "A=$A, B=$B"
                puts "x=$x, y=$y, args=$args, z=$z, w=$w"
            }
        }
    # ::testscript::Foo
    --% Foo create fod Aye Cap
    # ::testscript::fod
    --% fod frob Ex Why Zed
    o: {A=Aye, B=Cap}
    o: {x=Ex, y=Why, args=, z=3, w=Zed}

    \# and are inspectable:
    --% puts [formalargs Foo frob]
    o: {x {y 2} args {z 3} w}
}
