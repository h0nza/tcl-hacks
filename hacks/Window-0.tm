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
# TODO:
#   * ttk-ify everything
#     * panedwindow container
#     * notebook container
#   * tooltips!
#   * some kind of options support
#
package require Tk
package require snidgets

package require pkg
package require tests
package require adebug
#package require repl

package require tkImprover


pkg -export * Window {

    ::ttk::style theme use alt

    proc putl args {puts $args}

    proc callback {args} {
        tailcall namespace code $args
    }

    proc windowcontext {} {}

    oo::class create Widget {
        variable w
        constructor {cmd args} {
            namespace path [linsert [namespace path] end ::ttk]
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

            bind $w <Destroy> [list catch [callback my Reaper %W]]  ;# we still need to catch
                                                                    ;# because tear-down order
            return [self]
        }

        destructor {
            bind $w <Destroy> {}
            catch next
        }

        export varname  ;# this will be useful for consumers

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
                    my GM $packer [my GetIn $args]
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

        method GM args {
            multiargs {
                {} {
                    list [self] [dict get $GM $w]
                }
                {packer container} {
                    if {![string match .* $container]} {
                        set container [$container w]
                    }
                    if {[info exists GM] && [dict exists $GM $container]} {
                        set gm [dict get $GM $container]
                        if {$gm ne $packer} {
                            throw {GM CONFLICT} "Geometry manager is already $gm!"
                        }
                    }
                    dict set GM $container $packer
                }
            }
        }
        method GetIn {opts} {
            set idx [lsearch -exact $opts -in]
            if {$idx == -1} {
                return $w
            } else {
                lindex $opts $idx+1
            }
        }

        method grid {cmd args} {
            my GM grid [my GetIn $args]
            if {$cmd eq "anchor"} {
                multiargs {
                    {slave} {
                        grid $cmd [my WinArg $slave]
                    }
                    {slave anchor} {
                        grid $cmd [my WinArg $slave] $anchor
                    }
                }
            } elseif {$cmd in "bbox location size propagate slaves configure rowconfigure columnconfigure forget"} {
                putl grid $cmd $w {*}[my ItemArgs {*}$args]
                grid $cmd $w {*}[my ItemArgs {*}$args]
            } else {
                grid {*}[my GridArgs $cmd {*}$args] ;#-in $w
            }
        }
        method pack {cmd args} {
            my GM pack [my GetIn $args]
            if {$cmd in "propagate slaves forget"} {
                pack $cmd $w {*}[my ItemArgs {*}$args]
            } else {
                pack {*}[my GridArgs $cmd {*}$args] ;#-in $w
            }
        }
        method ItemArgs {args} {
            set j [lsearch -glob $args -*]
            if {$j == -1} {
                set preargs $args
                set opts {}
            } else {
                set preargs [lrange $args 0 [expr {$j-1}]]
                set opts [lrange $args $j end]
            }
            puts "preargs = $preargs"
            set preargs [lmap a $preargs {my WinArg $a}]
            puts "postargs = $preargs"
            if {[dict exists $opts -in]} {
                dict set opts -in [my WinArg [dict get $opts -in]]
            }
            concat $preargs $opts
        }
        method GridArgs {args} {
            set j [lsearch -glob $args -*]
            if {$j == -1} {
                set preargs $args
                set opts {}
            } else {
                set preargs [lrange $args 0 [expr {$j-1}]]
                set opts [lrange $args $j end]
            }
            set preargs [lmap a $preargs {my WinArg $a}]
            set opts [dict merge $griddefaults $opts]
            if {[dict exists $opts -in]} {
                dict set opts -in [my WinArg [dict get $opts -in]]
            }
            concat $preargs $opts
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

        method dialog {args} {
            if {[llength $args]%2} {
                set args [linsert $args end-1 -message]
            }
            if {![dict exists $args -parent]} {
                dict set args -parent [my w]
            }
            tk_messageBox {*}$args
        }

        method choosefile {args} {
            if {[llength $args]%2} {
                set args [linsert $args 0 -type]
            }
            if {![dict exists $args -type]} {
                throw {TCL BADARGS} "Must specify -type!"
            }
            switch -exact $type {
                "multi" {
                    set cmd tk_getOpenFile
                    dict set args -multiple yes
                }
                "open" {
                    set cmd tk_getOpenFile
                }
                "save" {
                    set cmd tk_getSaveFile
                }
                "dir" - "folder" {
                    set cmd tk_chooseDirectory
                }
            }
            if {![dict exists $args -parent]} {
                dict set args -parent [my w]
            }
            $cmd {*}$args
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
            upvar 0 $upvar $myvar
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
                namespace path [linsert [namespace path] end ::ttk]
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
                trace remove variable [my varname $varname] write "[callback my HandleTrace $varname]; --"
                trace remove variable [my varname $varname] unset "[callback my SetTrace $varname]; --"
                trace add variable [my varname $varname] write "[callback my HandleTrace $varname]; --"
                trace add variable [my varname $varname] unset "[callback my SetTrace $varname]; --"
            }

            method HandleTrace {varname} {
                variable Triggers
                dict incr Triggers $varname
                after 0 [list after idle [callback my Trigger]]
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
                my update
            }
            method update {} {
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
                namespace path [linsert [namespace path] end ::ttk]
                FormWidget create w {*}$args    ;# FIXME: use args better than just for this
                #array set {} {}
                w upvar {}
                w method frame {name args} {
                    if {[llength $args] % 2} {
                        set script [lindex $args end]
                        set args [lreplace $args end end]
                    } else {
                        set script ""
                    }
                    if {[dict exists $args -text] || [dict exists $args -labelwidget]} {
                        set win [my widget ::ttk::labelframe $name {*}$args]
                    } else {
                        set win [my widget ::ttk::frame $name {*}$args]
                    }
                    set win [$name w]

                    if {$script ne ""} {
                        set al [my autolayout]
                        my autolayout {*}$al -in $win
                        try {
                            my eval $script
                        } finally [callback my autolayout {*}$al]
                    }
                }

                my Construct

                w bind <<Submit>> [callback my Submit]
                w bind <<Cancel>> [callback my Cancel]
                w update
                my Defaults
            }

            forward dialog w dialog

            method buttons {script} {
                w frame buttons
                set w [w buttons w]
                set al [w autolayout]
                puts "Autolayout was: $al"
                w autolayout pack -in $w -side left -expand yes -fill x
                puts "Autolayout is: [w autolayout]"
                try {
                    my eval $script
                } finally [callback w autolayout {*}$al]
            }

            method button {text args} {
                set name b$text
                if {![dict exists $args -command]} {
                    if {$text in [info object methods [self] -all -private]} {
                        dict set args -command [callback my $text]
                    } else {
                        dict set args -command [callback my Return $text]
                    }
                }
                w widget button $name -text $text {*}$args
            }

            method Defaults {} {
                variable Defaults
                set Defaults [array get {}]
            }

            method changed? {} {
                variable Defaults
                dict for {k v} $Defaults {
                    if {$v ne $($k)} {
                        return true
                    }
                }
                return false
            }

            method Cancel {} {
                if {![my changed?] || [my ConfirmCancel]} {
                    my Return ""
                }
            }

            method Submit {} {
                if {![my Validate]} {
                    # highlight errors
                    my dialog -type okay -message "Please complete the form before pressing Okay"
                    return
                }
                my Return [my get]
            }


            method ConfirmCancel {} {
                my dialog -type yesno -message "Really cancel?"
            }

            method Validate {} {
                return true
            }
            
            method wait {} {    ;# wait is to be called in a coroutine
                my ReturnTo  [info coroutine]
                return [yield]
            }

            method get {} {
                array get {}
            }

            method ReturnTo {args} {
                variable ReturnTo
                set ReturnTo $args
            }

            method Return {what} {
                variable ReturnTo
                # after idle?
                tailcall {*}$ReturnTo $what
            }
        }

        oo::class create ::FormClass {
            superclass oo::class
            self method create {name script} {
                set script "superclass ::FormBase; variable {}; $script"
                next $name $script
            }

            method run {{w toplevel} args} {
                set i [my new $w {*}$args]
                try {
                    $i wait
                } finally {
                    $i destroy
                }
            }
        }

        FormClass create Inliner {

            method Construct {} {
                w autolayout grid -sticky nsew
                w frame wrapper -padding 10 
                w grid anchor wrapper center
                w autolayout grid -sticky nsew -in [w wrapper w]
                w eval {
                    my widget FilesChooser   files   -listvariable (files) -text "Choose HTML file"   -multiple yes
                    my frame selections -text " Selections: " {
                        # the -variable args work because of [w upvar ""] in the constructor
                        my widget checkbutton    do_toc  -variable (do_toc)    -text "Generate ToC"
                        my widget checkbutton    do_js   -variable (do_js)     -text "Inline JS"
                        my widget checkbutton    do_css  -variable (do_css)    -text "Inline CSS"
                        my widget checkbutton    do_img  -variable (do_img)    -text "Inline images"
                    }
                }

                w onchange (do_js) {puts lalala:\$(do_js)}
                w condition do_js -state {$(do_toc)} normal disabled
                #w condition selections 

                set (do_toc) 0
                set (do_js)  1
                set (do_css) 1
                set (do_img) 1

                w autolayout grid -sticky nsew
                my buttons {
                    my button "Cancel"
                    my button "Show"
                    my button Submit -text "Okay"    -default active
                }
            }

            method Show {} {
                my dialog "[array get {}]"
            }


        }

        coroutine main {*}[namespace code {
            set d [Inliner run toplevel]
            if {$d eq ""} {
                puts "Form cancelled!"
            } else {
                puts "Form submitted!"
                pdict $d
            }
        }]

        catch {
            source [file normalize [info script]/../../modules/inspect-0.tcl]
            puts "== inspecting Inliner =="
            pdict [inspect Inliner]
            puts ""
        }
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

if 1 {
    package require tkcon
    tkcon show
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
