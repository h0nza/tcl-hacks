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
# Hierarchical bindtags (bubbling) a la bindtags(n) example looks interesting
#
# method upvar is indeed cool, but I've broken [my variable].
#
#  Do we want instead [myvariable] and [mymethod] ?  I think we do, because [variable] is a useful method name.
#
#
# w container constructor ?...? {script}] can put things in a container
# gridconfigure to hide things
#
# containers make visible hierarchies, which will be interesting
#
#
# To make forms:
#   * frames (also panes and tabs)
#   * onchange and condition need a bit of work
#   * collections are still a bit icky
#
# Some tidy up is due:
#   * widget/varnames should be Upper Cased but the Tk name has to be .lOwer
#   * options want to come from a metaclass.  But remember I want item options too.
#   * a trace mixin would tidy thing some
#
# I almost want to make these namespace ensembles rather than objects
#
package require Tk
package require snidgets

package require pkg
package require tests
package require adebug
#package require repl

pkg -export * Window {

    proc windowcontext {} {}

    oo::class create Widget {
        variable w
        constructor {cmd args} {
            # if the first argument is a window path, we adopt that window
            # otherwise, it is a window constructor
            if {[string match .* $cmd]} {
                set w $cmd
                $w configure {*}$args
            } else {
                set w [uplevel 1 windowcontext].[namespace tail [self object]]
                $cmd $w {*}$args
            }
            # move the window into this object's namespace
            rename $w [namespace current]::$w
            namespace export $w
            namespace eval :: [list namespace import [namespace current]::$w]

            # init vars
            if {$w eq "."} {
                proc windowcontext {} {return ""}
            } else {
                proc windowcontext {} [list return $w]
            }
            set griddefaults {}

            bind $w <Destroy> [list catch [my callback Reaper %W]]  ;# we still need to catch
                                                                    ;# because tear-down order
            return [self]
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

        method eval {script} {
            try $script
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
            if {[info exists autolayout] && $autolayout ne ""} {
                set largs [lassign $autolayout method]
                my $method $name {*}$largs
            }
            return [namespace which $name]
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
                    if {[string match -*variable $a] || [string match -*var $a]} {
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

        variable autolayout
        method autolayout args {
            multiargs {
                {packer args} {
                    my GM $packer
                    set autolayout [list $packer {*}$args]
                }
                {} {
                    return $autolayout
                }
            }
        }

        variable griddefaults
        method griddefaults args {
            set griddefaults $args
        }
        method packdefaults args {
            set griddefaults $args
        }

        method GM {args} {
            variable GM
            if {$args eq ""} {
                debug assert {$GM ne ""}
                return [list [self] $GM]    ;# returns a commandprefix to its own method
            } else {
                debug assert {[llength $args] eq 1}
                lassign $args arg
                debug assert {![info exists GM] || ($GM in [list "" $arg])}
                set GM $arg
            }
        }

        method grid {cmd args} {
            my GM grid
            if {$cmd in "anchor bbox location size propagate slaves configure rowconfigure columnconfigure forget"} {
                grid $cmd $w {*}[my ItemArgs {*}$args]
            } else {
                grid {*}[my GridArgs $cmd {*}$args] ;#-in $w
            }
        }
        method pack {cmd args} {
            my GM pack
            if {$cmd in "propagate slaves forget"} {
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
                expr {$i ? $a : [my WinArg $a]}
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
                expr {$i ? $a : [my WinArg $a]}
            }]
            concat $args [array get def]
        }
        method WinArg {w} {
            if {[string match .* $w]} {
                return $w
            } else {
                return [$w w]
            }
        }

        method bind args {
            multiargs {
                {event script} {
                    bind [my w] $event $script
                }
                {event argspec body args} {
                    oo::objdefine [self] method $event [my BindArgs $argspec] $body
                    oo::objdefine [self] export $event
                    set cmdargs [my BindCmdArgs $argspec]
                    bind [my w] $event [list [self] $event {*}$cmdargs {*}$args]
                }
            }
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

        method upvar {name} {   ;# this wants more arguments, but their selection is subtle
            oo::objdefine [self] variable $name
            set upvar [uplevel 1 namespace current]::$name 
            set myvar [my varname $name]
            upvar 1 $upvar $myvar
            return $myvar
        }

        method get args {
            if {[llength $args] eq 1} {
                set [my varname $name]
            } elseif {$args eq ""} {
                my getdict
            } else {
                throw {TCL WRONGARGS} [list [self class] get ?name?]
            }

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
                return [self] ;#[my w]
            } else {
                tailcall [my w] {*}$args
            }
        }
    }
}


# used in the "notebook class" demo
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


if 0 {  ;# shell
    chan configure stdin -blocking 0
    chan configure stdout -buffering none
    coroutine repl repl::chan stdin stdout
    puts vwaiting
    vwait forever
}

if 0 {
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
}


set demos {
    "winspector" {
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
    "tabs" {
        Widget create notebook toplevel
        notebook widget frame tabs
        notebook widget frame main
        set tabs [notebook tabs]
    }

    "basic multi-function Tk example" {
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

    "container widgets" {
        Widget create t toplevel
        t widget ttk::labelframe one -text "First set"
        t widget entry e1
        t widget checkbutton cb1 -text "Really?"
        t widget ttk::labelframe two -text "Next set"
        t widget entry e2
        t widget checkbutton cb2 -text "are you sure?"
        t grid one
        t grid two
        puts [t e1]
        t one grid [t e1]
        t one grid [t cb1]
        t two grid [t e2]
        t two grid [t cb2]
    }


    "choiceform with method upvar" {
        oo::class create ChoiceForm {
            variable choices
            constructor {dict} {
                Widget create w toplevel
                w upvar choices         ;# shares this variable with the Widget
                dict for {k v} $dict {
                    set b b[incr i]
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

    "a basic form" {
        oo::class create ::FormWidget {
            superclass Widget

            variable OnChange
            variable Conditions

            constructor args {
                next {*}$args
            }

            method onchange {varname script} {
                my SetTrace $varname
                variable OnChange
                dict set OnChange $varname $script
            }
            method condition {w option expr args} {
                my SetTrace {}  ;# hack?
                variable Conditions
                multiargs {
                    {}              { set true true; set false false }
                    {true}          { set false "" }
                    {true false}    {  }
                }
                dict set Conditions $expr [list w $w option $option expr $expr true $true false $false]
            }

            method SetTrace {varname} {
                trace remove variable [my varname $varname] write "[my callback HandleTrace $varname]; --"
                trace remove variable [my varname $varname] unset "[my callback SetTrace $varname]; --"
                trace add variable [my varname $varname] write "[my callback HandleTrace $varname]; --"
                trace add variable [my varname $varname] unset "[my callback SetTrace $varname]; --"
            }

            method HandleTrace {varname} {
                variable Triggers
                dict incr Triggers $varname
                after 0 [list after idle [my callback Trigger]]
            }
            method Trigger {} {
                variable Triggers
                variable OnChange
                variable Conditions
                if {![info exists Triggers]} return
                foreach varname [dict keys $Triggers] {
                    if {[dict exists $OnChange $varname]} {
                        my Apply [dict get $OnChange $varname]
                    }
                    dict unset Triggers $varname
                }
                dict for {expr cond} $Conditions {
                    dict with cond {}
                    set new [expr {[my Apply expr $expr] ? $true : $false}]
                    set old [$w cget $option]
                    if {$new ne $old} {
                        my configure $w $option $new
                    }
                }
            }
            method Apply {cmd args} {
                variable {}
                try [concat $cmd $args]
            }

        }


        oo::class create ::FormBase {

            variable {} ;# the form

            constructor {args} {
                FormWidget create w {*}$args    ;# FIXME: use args better than just for this
                w upvar {}
                w method frame {name args} {
                    set script [lindex $args end]
                    set args [lreplace $args end end]
                    set win [my widget ::ttk::labelframe $name {*}$args]
                    set win [$name w]

                    set al [my autolayout]
                    my autolayout {*}$al -in $win
                    try {
                        my eval $script
                    } finally [my callback autolayout {*}$al]
                }
                my Construct
            }

            method Cancel {} {
                my Result Cancel
            }
            method Okay {} {
                parray {}
                my Result Okay
            }

            method Callback {method args} {
                namespace code [list my $method {*}$args]
            }
            
            method wait {} {    ;# wait is to be called in a coroutine
                #debug assert {[my cget -command] eq ""}

                my On Cancel [info coroutine] false
                my On *      [info coroutine] true

                set res [yieldm]
                lassign $res rc

                debug log {[info object class [self]]: wait($res)}

                after 0 [list after idle [my Callback destroy]]
                if {!$rc} {
                    return -code break
                } else {
                    return [my result]
                }
            }

            method result {} {
                array get {}
            }

            method On {what cmd args} {
                my variable On
                dict set On $what [list $cmd {*}$args]
            }

            method Result {what} {
                my variable On
                if {[info exists On]} {
                    dict for {pat cmd} $On {
                        if {[string match $pat $what]} {
                            tailcall {*}$cmd
                        }
                    }
                }
                debug log {ERROR: no trigger for $what}
            }
        }

        oo::class create ::FormClass {
            superclass oo::class
            self method create {name script} {
                set script "superclass ::FormBase; $script"
                next $name $script
            }

            # this could take:
            #  - a dictionary of values
            #  - a script to run on success (or nothing on failure?)
            method run {{w toplevel}} {
                set i [my new $w]
                try {
                    set res [$i wait]
                    puts "Got result:"
                    pdict $res
                } on break {} {
                    puts "Cancelled!"
                }
            }
        }

        FormClass create Inliner {

            method Construct {} {
                w autolayout grid -sticky nsew
                w widget FilesChooser   files   -listvariable (files) -text "Choose HTML file"   -multiple yes
                w frame selections -text " Selections: " {
                    # the -variable args work because of [w upvar ""] in the constructor
                    my widget checkbutton    do_toc  -variable (do_toc)    -text "Generate ToC"
                    my widget checkbutton    do_js   -variable (do_js)     -text "Inline JS"
                    my widget checkbutton    do_css  -variable (do_css)    -text "Inline CSS"
                    my widget checkbutton    do_img  -variable (do_img)    -text "Inline images"
                }

                w onchange (do_js) {puts lalala:\$(do_js)}
                w condition do_js -state {$(do_toc)} normal disabled
                #w condition selections 

                set (do_toc) 1
                set (do_js)  1
                set (do_css) 1
                set (do_img) 1

                w widget frame buttons

                #map {w grid} {files do_toc do_js do_css do_img buttons}

                w buttons grid [
                    w buttons widget button bCancel -text "Cancel"  -command [my Callback Cancel]
                ] [
                    w buttons widget button bOkay   -text "Okay"    -command [my Callback Okay]
                ]
            }
        }

        catch {
            source [file normalize [info script]/../../modules/inspect-0.tcl]
            pdict [inspect Inliner]
        }

        puts "lalala"
        coroutine run {*}[namespace code {
            puts "lololo"
            puts [namespace which Inliner]
            puts [info object call Inliner run]
            Inliner run
            puts "lilili"
            incr ::done
        }]
        puts "lululu"
        vwait done
        puts "lolwat"
    }
}

# run demos

proc restart {} {
    try {
        set cmd [info_cmdline]
    } on error {} {
        set cmd [list [info nameofexe] $::argv0 {*}$::argv]
    }
    puts "Executing: $cmd"
    exec {*}$cmd &
    exit
}

proc run_demo {key} {
    set script [dict get $::demos $key]
    catch {namespace delete ::demo}
    namespace eval ::demo {}
    apply [list {} $script ::demo]
}

if {$::argv eq ""} {
    Widget create main .    ;# adopt the root window
    main griddefaults -sticky nsew
    set i 0
    dict for {label script} $demos {
        main widget button b[incr i] -text $label -command [list run_demo $label]
        main grid b$i
    }
    main grid [main widget button bRestart -text "Restart" -command restart]
    main grid [main widget button bQuit -text "Quit" -command exit]
} else {
    coroutine main apply {{} {
        foreach a $::argv {
            foreach k [dict keys $::demos $a] {
                puts "** running demo: \"$a\""
                run_demo $a
                yieldto after 1000 [info coroutine]
            }
        }
    }}
}
