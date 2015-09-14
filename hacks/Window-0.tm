#
# An experiment in TclOO widgets as a transparent facade layer over Tk
#
# .. looks pretty good, so far.  There's plenty of undesirable overlap with names unless we're very careful.
# Capitalising window names might be sufficient safety?
#
# probably wants more methods for ttk ..
#
# options needs opts, and learning from snit.
# tk/library/megawidget.tcl simply does:
#  configure -> tclParseConfigSpec optarray optspeclist "" $args
# an OptSpec looks like:
#  {-commandlineswitch resourceName ResourceClass defaultValue verifier}
# snit provides -default -verifier -configuremethod -cgetmethod
# I think options belong in class definition, whilst this is (so far) object definition
#
# making classes out of these is going to be the kicker!
#
# Hierarchical bindtags a la bindtags(n) example looks interesting
#

tcl::tm::path add [file normalize [info script]/../../modules]

package require Tk

package require pkg
package require tests
package require debug 0 ;# not tcllib

pkg -export * Window {

    proc windowcontext {} {}

    oo::class create Widget {
        variable w
        constructor {cmd args} {
            set w [uplevel 1 windowcontext].[namespace tail [self object]]
            $cmd $w {*}$args
            rename $w [namespace current]::$w
            namespace export $w
            namespace eval :: [list namespace import [namespace current]::$w]
            proc windowcontext {} [list return $w]
            set griddefaults {}
            bind $w <Destroy> [list catch [my callback Reaper %W]]  ;# we still need to catch
                                                                    ;# because tear-down order
            self
        }
        destructor {
            bind $w <Destroy> {}
            catch next
        }


        export varname  ;# this will be useful for consumers
                        ;# as will this:
        method callback {method args} {
            namespace code [list my $method {*}$args]
        }

        method Reaper {W} {
            if {$W eq $w} {
                debug log {[self] Dying on <Destroy>}
                my destroy
            } else {
                debug log {WARNING: [self] Reaper $W (doing nothing)}
            }
        }

        method w {} {return $w}
        method widget {cmd name args} {
            Widget create $name $cmd {*}[my WidgetArgs $args]
            oo::objdefine [self] forward $name $name
            oo::objdefine [self] export $name
            return $name
        }
        method WidgetArgs {arglist} {
            set q 0
            lmap a $arglist {
                if {$q} {
                    if {![string match ::* $a]} {
                        if {[string match *(*) $a]} {   ;# unwrap array name
                            set n [lindex [split $a (] 0]
                        } else {
                            set n $a
                        }
                        debug assert {$n in [info object variables [self]]}
                        set q 0
                        my varname $a
                    } else {
                        set a
                    }
                } else {
                    if {[string match -*variable $a]} {
                        set q 1
                    }
                    set a
                }
            }
        }

        method configure args {
            if {![llength $args]} {
                tailcall $w configure
            }
            if {[string match -* [lindex $args 0]]} {
                tailcall $w configure $args
            }
            set args [lassign $args cmd]
            [$cmd w] configure {*}[my WidgetArgs $args]
        }

        method destroy args {
            if {$args eq ""} {
                bind $w destroy {}
                next    ;# destroy self, taking window with
            } else {
                destroy {*}[my ItemArgs $args]
            }
        }

        variable griddefaults
        method griddefaults args {
            set griddefaults $args
        }
        method packdefaults args {
            set griddefaults $args
        }

        method grid {cmd args} {
            if {$cmd in "anchor bbox location size propagate slaves configure rowconfigure columnconfigure"} {
                grid $cmd $w {*}[my ItemArgs {*}$args]
            } else {
                grid {*}[my GridArgs $cmd {*}$args] -in $w
            }
        }
        method pack {cmd args} {
            if {$cmd in "propagate slaves"} {
                pack $cmd $w {*}[my ItemArgs {*}$args]
            } else {
                pack {*}[my GridArgs $cmd {*}$args] -in $w
            }
        }
        method ItemArgs {args} {
            set i 0
            set args [lmap a $args {
                if {[string match -* $a]} {
                    incr i
                }
                expr {$i ? $a : [$a w]}
            }]
        }
        method GridArgs {args} {
            set i 0
            array set def $griddefaults
            set args [lmap a $args {
                if {[string match -* $a]} {
                    unset -nocomplain def($a)
                    incr i
                }
                expr {$i ? $a : [$a w]}
            }]
            concat $args [array get def]
        }

        method bind {event argspec body args} {
            oo::objdefine [self] method $event [my BindArgs $argspec] $body
            oo::objdefine [self] export $event
            set cmdargs [my BindCmdArgs $argspec]
            bind [my w] $event [list [self] $event {*}$cmdargs {*}$args]
        }
        method BindArgs {argspec} {
            lmap a $argspec {
                string trimleft $a %
            }
        }
        method BindCmdArgs {argspec} {
            lmap a $argspec {
                if {![string match %* $a]} break
                set a
            }
        }

        method bindtags args {
            tailcall bindtags [my w] {*}$args
        }

        variable options
        method options {} {
            lsort -dictionary [concat [array values options] [$w configure]]
        }
        method option {option resource class default verifier} {
            # -commandlineswitch resourceName ResourceClass defaultValue verifier
            set options($option) [list $option $resource $class $default $verifier]
            # .. learn more from snit
        }

        method method {name argspec body} {
            oo::objdefine [self] method $name $argspec $body
            oo::objdefine [self] export $name
        }
        method variable args {
            oo::objdefine [self] variable {*}$args
        }
        method upvar {name} {
            oo::objdefine [self] variable $name
            set upvar [uplevel 1 namespace current]::$name 
            set myvar [my varname $name]
            upvar 1 $upvar $myvar
            return $myvar
        }
        method get {name} {
            set [my varname $name]
        }
        method set args {
            foreach {name val} $args {
                set [my varname $name] $val
            }
        }
        method getdict {} {
            lconcat name [info object variables [self]] {
                list $name [set [my varname $name]]
            }
        }

        method unknown {args} {
            if {$args eq ""} {
                return [my w]
            } else {
                tailcall [my w] {*}$args
            }
        }
    }
}

if 0 {
    catch {rename After {}}
    oo::class create After {    ;# a mixin that cancels afters when the object is destroyed
        variable Afters
        method AfterCancel {id} {
            if {[info exists Afters($id)]} {
                after cancel $Afters($id)
                unset Afters($id)
            }
        }
        method After {id delay script args} {
            my AfterCancel $id
            if {[info exists Afters($id)]} {
                after cancel $Afters($id)
            }
            set Afters($id) [after $delay [namespace code [concat $script {*}$args]]]
        }
        destructor {
            foreach k [array names Afters] {
                my AfterCancel $k
            }
            catch next    ;# eww .. but it's a mixin
        }
    }

    oo::class create Notebook {
        variable w
        constructor {} {
            set w [Widget win]
            w griddefauts -sticky nsew
            w grid [w widget ttk::frame tabs]
            w grid [w widget ttk::frame main]
            w grid [w widget ttk::frame status]
            w grid rowconfigure main -weight 1
        }
        method index {} {
        }
        method itemconfigure {index args} {
        }
        method itemcget {index args} {
        }
        method insert {index id pane} {
        }
        method remove {index} {
        }
        method move {id index} {
        }
    }

    oo::class create Winspector {
        superclass Widget
        mixin After
        constructor {} {
            next toplevel
#            proc windowcontext {} [list return [namespace tail [self]]]

            #Widget create w toplevel
            #oo::objdefine [self] forward w w
            my variable name
            my variable class
            my variable bindtags
            my widget label _name -textvariable name
            my widget label _class -textvariable class
            my widget label _bindtags -textvariable bindtags
            my griddefaults -sticky nsew
            my grid _name _class
            my grid _bindtags -
            #bind all <Enter> [namespace code {my Enter %W}]
            my Refresh
        }
        method Refresh {} {
            try {
                set xy [winfo pointerxy .]
                set name [winfo containing {*}$xy]
                if {$name eq ""} return
        #        if {[string match [[self]]* $name]} return
                set class [winfo class $name]
                set bindtags [bindtags $name]
                my set xy $xy name $name class $class bindtags $bindtags
            } finally {
                my After refresh 300 {my Refresh}
            }
        }
    }
    Winspector create win

}
if 0 {
    Widget create t toplevel
    t widget entry e1
    t widget button b1 -command {puts hello}
    t griddefaults -sticky nsew
    t grid e1
    t grid b1   ;# -weight 1
    t grid [t widget button b2 -text okde]
    t grid rowconfigure b1 -weight 1
    t e1 insert end "lalala"
    t configure b1 -text "Press me"
    t bind <1> {%W %x %y a} {           ;# implicitly creates a method on the object ..
        puts "$W $x $y: $ack ($a)"      ;# that can resolve object variables!
    } five                              ;# remember: % args must come first!
    t variable ack
    t configure e1 -textvariable ack    ;# ack is resolved in t's scope!
}

if 0 {
    package require repl
    chan configure stdin -blocking 0
    chan configure stdout -buffering none
    coroutine repl repl::chan stdin stdout
    puts vwaiting
    vwait forever
}

if 0 {

    Window create notebook toplevel
    notebook widget tabs frame
    notebook widget main frame
    set tabs [notebook tabs]
}

if 1 {
    ;# illustrating the use of [method upvar]
    package require Tk
    oo::class create ChoiceForm {
        variable choices
        constructor {dict} {
            Widget create w toplevel
            w upvar choices     ;# share this variable with w
            dict for {k v} $dict {
                set b check_[incr i]
                w widget checkbutton $b -text $k -variable choices($v)
                w grid $b -
            }
            w widget button invert -command [namespace code {my Invert}] -text "Invert selections"
            w widget button print -command [namespace code {my Print}] -text "Print values"
            w grid invert print
        }
        method Invert {} {
            dict for {k v} [array get choices] {
                set choices($k) [expr {!$v}]
            }
        }
        method Print {} {
            parray choices
        }
    }
    ChoiceForm create c {"One fine day" tomorrow "Never comes" around "There once was a" "little blue pony"}
}
