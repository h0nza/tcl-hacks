# SYNOPSIS:
#
#   console *windowPath* ?options?
#

# OPTIONS:
#
#     -interp %         - create a new interp.  Can be queried by [$win cget -interp]
#     -interp $int      - use an existing interp.
#
#     -thread %         - create a new thread.  Can be queried by [$win cget -thread]
#     -thread $tid      - use an existing thread.
#
#     -stdout /mode/    - mode is either "tee" or "copy" to copy stdout/err into the console
#                         or "redir" or "move" to redirect stdout/err into the console.
#                         Default is empty:  no touching of stdout/err.
#                         This will do the right thing if -interp or -thread is used.
#
#     -block 0|1|2      - makes sense for -thread:
#                         0 - no blocking;
#                         1 - highlight when blocked (but accept input)
#                         2 - block when blocked
#
#     -eval             - custom evaluator.  Takes a script and returns [list $rc $result $opts]
#
#     -evalprefix       - all commands will be prefixed with this.  Note [cmd subs] are unaffected.
#
#     -prompt           - custom prompt method body.
#
#     -iscomplete       - command to determine whether input is a complete command.
#

# WIDGET COMMANDS:
#
#    cget /option/      - useful for -thread, -interp
#
#    eval /script/      - evaluate a script and return its result
#                         uses a trampoline to return errors and options
#
#    input /text/       - append $text to input, as though it had been typed/pasted by the user
#
#    stdout /text/      - emit $text to the emulated stdout
#
#    stderr /text/      - emit $text to the emulated stderr
#
#    history /subcmd/   - access to input history

# TODO:
#   * tab-completion
#   * history search
#   * share window with statusbar, menu and docked buttonbox (how?)
#   * persistent history
#   * host commands via a sigil

# Wraptext serves as a reference for wrapping Tk widgets in TclOO objects, and
# provides a widget which extends on text:
#
#   option -readonly false boolean
#
#       makes the widget readonly but still cursor-interactive
#       FIXME: use [ins] and [del] and [rep] to move text on it.
#
#   option -maxheight "" integer
#
#       if this is set, the text widget will automatically resize
#       its height to just contain its contents
#
#   option -minheight 1 integer
#
#       interacts with the above - an empty widget will be this high
#

package require Tk          ;# needs to be present at load time for copyBindtags
#package require autoscroll      ;# tklib


namespace eval tksh {

    # the constructor needs some help:
    proc wraptext {win args} {
        set obj [WrapText new $win {*}$args]
        rename $obj ::${win}
        return $win
    }

    oo::class create WrapText {

        # the widget bit:
        variable hull
        constructor {w args} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]   ;# having to do this kinda sucks

            set hull $w
            proc hull args "$hull {*}\$args"

            lassign [my SplitOpts $args] myargs hullargs

            set obj [text $hull {*}$hullargs]
            rename ::${obj} [namespace current]::${obj}
            trace add command [namespace current]::${obj} delete [thunk my destroy]

            set defaults [dict map {opt spec} [my OptSpec] {lindex $spec 3}]    ;# yuck
            set myargs   [dict merge $defaults $myargs]
            #my SetupOptTrace
            my Configure $myargs
        }

        destructor {
            #after 0 [list after idle [list puts "Destroyed: [self]"]]
        }

        method unknown args {
            tailcall $hull {*}$args
        }

        # options:
        variable Options

        # public interface:
        method cget {option} {
            if {[info exists Options($option)]} {
                my Cget $option
            } else {
                $hull cget $option
            }
        }
        method configure {args} {
            if {[llength $args] < 2} {
                tailcall my CgetSpec {*}$args
            }
            lassign [my SplitOpts $args] myargs hullargs
            $hull configure {*}$hullargs
            if {$myargs ne ""} {
                my Configure $myargs
            }
        }

        # private interface:
        # this could be a variable, shared with
        #   namespace upvar [info object namespace [self class]] OptSpec OptSpec
        # but a method is syntactically convenient, and the tclobj will be cached
        method OptSpec {} {
            #  {-commandlineswitch resourceName ResourceClass defaultValue verifier}
            # snit provides -default -verifier -configuremethod -cgetmethod, [delegate]
            return {
                -readonly   {-readonly      readOnly    ReadOnly    false   {string is boolean}}
                -maxheight  {-maxheight     maxHeight   MaxHeight   {}      {string is integer}}
                -minheight  {-minheight     minHeight   MinHeight   1       {string is integer}}
            }
            # FIXME: add delegates
            #
            #
            # Each option is identified by name (-switch)
            # and must have:
            #   -resource StudlyCaps
            # and may have:
            #   -delegate           <component name>
            #   -configuremethod    <mymethod ?arg ..?>
            #   -cgetmethod         <mymethod ?arg ..?>
            #   -verifier           <cmdprefix returning bool>
            #   -default            <value>
            #   -readonly           <bool>
            #     option can only be set at construction time
            #
            # Wildcard delegation:
            #   option * -delegate hull
            #     * any unrecognised option (cget/configure)
            #       will be given to the hull
            #     * getting all configuration will splice
            #       in (non-colliding) * from the hull
            #   Otherwise this option is ignored.
        }

        # utility for configuration: separate options into hull (passthrough) and local
        method SplitOpts {optargs} {    ;# lassign [my SplitOpts] hullopts myopts
            # delegated options are local for this purpose
            set myargs {}
            set spec [my OptSpec]
            set hullargs [dict map {option value} $optargs {
                if {[dict exists $spec $option]} {
                    dict set myargs $option $value
                    continue
                } else {
                    set value
                }
            }]
            list $myargs $hullargs
        }

        # configuration private interface:
        method Configure {optargs} {
            # needs to handle:
            #   * readonly options (constructor time only)
            #   * delegation
            #   * hull options
            #   * verify
            #   * configuremethod
            #   * maintaining array
            dict for {option value} $optargs {
                my Verify $option $value
            }
            dict for {option value} $optargs {
                set Options($option) $value
            }
        }
        method Verify {option value} {
            set cmd [lindex [dict get [my OptSpec] $option] 4]  ;# yuck
            if {![uplevel #0 $cmd [list $value]]} {
                throw {TK BAD OPTION} "Bad value for \"$option\", should be \[$cmd\], not \"$value\""
            }
        }
        method Cget {option} {
            # return the options's value: must handle:
            #   * delegation
            #   * hull options
            #   * cgetmethod
            #   * maintaining array
            return $Options($option)
        }
        method CgetSpec {args} {
            # returns Tk optspec list:
            #  {-switch resName ResClass defValue value}
            # must handle:
            #   * delegation
            #   * hull options
            #   * cgetmethod
            if {$args eq ""} {
                set speclist [$hull configure]
                foreach {option spec} [my OptSpec] {
                    set spec [lreplace $spec 4 end $Options($option)]   ;# yuck
                    lappend speclist $spec
                }
                return $speclist
            }
            set spec [my OptSpec]
            return [lmap option $args {
                if {[dict exists $spec $option]} {
                    lreplace [dict get $spec $option] 4 end $Options($option)   ;# yuck
                } else {
                    $hull configure $option
                }
            }]
        }

        # declaring an option adds an entry to the class's OptInfo dict
        #    {-option} {default verifier configuremethod cgetmethod delegate}
        # delegate links a default configure/cgetmethod
        method SetupOptTrace {} {
            #namespace upvar .. [myclass OptInfo]?
            foreach {option info} {} {
                if {[dict exists $info configuremethod]} {
                    trace add variable Options($option) write [callback my [dict get $info configuremethod]]
                }
                if {[dict exists $info cgetmethod]} {
                    trace add variable Options($option) read  [callback my [dict get $info cgetmethod     ]]
                }
                if {[dict exists $info delegate]} {
                    # TODO: handle *
                    trace add variable Options($option) write [callback my DelegateOption $option [dict get $info delegate]]
                    trace add variable Options($option) read  [callback my DelegateOption $option [dict get $info delegate]]
                }
            }
        }
        method DelegateOption {option cmdprefix _ _ op} {
            # FIXME: avoid reentry?
            switch $op {
                "write" {
                    {*}$cmdprefix configure $option $Options($option)
                }
                "read" {
                    set Options($option) [{*}$cmdprefix cget $option]
                }
            }
        }

        # basic text wrappers .. looks like it wants AOP:
        forward ins hull insert
        forward del hull delete
        forward rep hull replace
        method insert args {
            if {$Options(-readonly)} {
                event generate $hull <<ReadOnly>> -data [list insert {*}$args]
                return
            }
            try {
                $hull insert {*}$args
            } finally {
                my <<TextChanged>>  ;# not really an event
            }
        }
        method replace args {
            if {$Options(-readonly)} {
                event generate $hull <<ReadOnly>> -data [list replace {*}$args]
                return
            }
            try {
                $hull replace {*}$args
            } finally {
                my <<TextChanged>>  ;# not really an event
            }
        }
        method delete args {
            if {$Options(-readonly)} {
                event generate $hull <<ReadOnly>> -data [list delete {*}$args]
                return
            }
            try {
                $hull delete {*}$args
            } finally {
                my <<TextChanged>>  ;# not really an event
            }
        }

        method <<TextChanged>> {} {
            if {$Options(-maxheight) ne ""} {
                variable DLines
                incr DLines 0
                set dlines [$hull count -displaylines 1.0 end]
                set dlines [expr {max( $Options(-minheight) , $dlines )}]
                set dlines [expr {min( $dlines , $Options(-maxheight) )}]
                if {$dlines != $DLines} {
                    set DLines $dlines
                    my configure -height $dlines
                }
            }
        }
    }


    # 
    # A simple vertically-oriented button box with convenient methods for adding buttons
    proc buttonbox {win args} {
        set obj [ButtonBox new $win {*}$args]
        rename $obj ::${win}
        return $win
    }
    oo::class create ButtonBox {
        variable hull
        variable Options
        variable Buttons
        variable ID

        constructor {w args} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]   ;# having to do this kinda sucks

            set hull $w
            proc hull args "$hull {*}\$args"

            set obj [ttk::frame $hull]     ;# FIXME: hullargs?

            rename ::${obj} [namespace current]::${obj}
            trace add command [namespace current]::${obj} delete [thunk my destroy]
        }

        method unknown args {
            tailcall $hull {*}$args
        }


        method add {text cmd args} {
            set id $text
            set btn $hull.b[incr ID]
            lassign [::tk::UnderlineAmpersand $text] label ul
            set accel [string index $label $ul]

            ttk::button $btn -text $label -underline $ul -command $cmd  {*}$args
            pack $btn -side top -fill x

            set top [winfo toplevel $hull]  ;# configureable option?

            set key <Alt-[string tolower $accel]>

            set invoke "
                after 0 {after idle {
                    event generate [list $btn] <<Invoke>>
                }}
            "

            if {[bind $top $key] ne ""} {
                puts "WARNING: $key is already bound!"
            } else {
                bind $top $key $invoke
                trace add command $btn delete [thunk bind $top $key {}]
            }

            return $btn
        }
        method remove args {
            foreach id $args {
                if {[winfo exists $id]} {
                    set btn $id
                    set label [dict get $Buttons widget $btn]
                } elseif {![catch {set btn [dict get $Buttons label $id]}]} {
                    set widget $id
                } else {
                    continue
                }
                destroy $widget
                dict unset Buttons label  $id
                dict unset Buttons widget $btn
            }
        }
    }

    # 
    # This provides a very simple console, suitable for embedding an interactive interpreter (like Tcl!)
    # Its backend configuration is through methods Prompt, IsComplete and Evaluate
    #
    # Illustration here is of a megawidget which does *not* delegate most commands to its hull.  Instead,
    # it has a richer [configure]tion and type-specific methods.  Bindings are more imporant.
    #
    proc console {win args} {
        set obj [Console new $win {*}$args]
        rename $obj ::${win}
        return $win
    }
    oo::class create Console {
        variable hull

        variable Options

        constructor {w args} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]   ;# having to do this kinda sucks

            set hull $w
            set obj [toplevel $hull -padx 5 -pady 5 -bg darkgrey]     ;# FIXME: hullargs?
            rename ::${obj} [namespace current]::${obj}
            trace add command [namespace current]::${obj} delete [thunk my destroy]

            ttk::frame $hull.top -style Tksh.TFrame
            ttk::frame $hull.bottom -style Tksh.TFrame

            #scrollbar $hull.output_scrolly -orient v -command [list $hull.output yview]
            #scrollbar $hull.input_scrolly  -orient v -command [list $hull.input yview]

            wraptext $hull.output  -height 24 -width 80 -wrap char  -readonly 1 \
                ;#-yscrollcommand [list $hull.output_scrolly set]
            wraptext $hull.input   -height 1  -width 80 -wrap char  -maxheight 5 -undo 1 \
                ;#-yscrollcommand [list $hull.input_scrolly set]

            buttonbox $hull.buttons
            oo::objdefine [self] forward buttons $hull.buttons

            #my buttons add "&Packages" [callback my input "after 2000; package names\n"]

            bindtags $hull.output [string map {Text ConsoleOutput.Text} [bindtags $hull.output]]

            History create history {{parray ::tcl_platform}}

            #pack $hull.top -side top -expand yes -fill both
            #pack $hull.bottom -side top -expand yes -fill both
            grid $hull.top -sticky nsew
            grid $hull.bottom -sticky nsew
            grid columnconfigure $hull $hull.top -weight 1
            grid rowconfigure $hull $hull.top -weight 1
            grid propagate $hull 1

            #pack $hull.output_scrolly -in $hull.top    -side right -fill y
            #pack $hull.input_scrolly  -in $hull.bottom -side right -fill y

            pack $hull.buttons -in $hull.top      -side right -anchor n ;#-fill y
            pack $hull.output -in $hull.top    -expand yes -fill both
            pack $hull.input  -in $hull.bottom -expand yes -fill both


            # FIXME: autoscroll isn't doing what I want, particularly on .output
            #autoscroll::autoscroll $hull.output_scrolly
            #autoscroll::autoscroll $hull.input_scrolly

            my SetupTags
            my SetupBinds
            # -block:  0: don't block input;  1: block input;  2: only highlight
            # -interp: % to create a new one, or the handle of an existing interp
            # -thread: % to create a new one, or the id of an existing thread
            # -stdout:  tee/copy or redir/move to appropriately plumb stdout/err in the target
            array set Options {
                -block  1
                -interp ""
                -thread ""
                -stdout ""
                -evalprefix ""
                -resultvar :::
            }
            my Configure $args
            if {$Options(-stdout) ne ""} {
                if {$Options(-thread) ne ""} {
                    my PlumbThread $Options(-thread) $Options(-stdout)
                } elseif {$Options(-interp) ne ""} {
                    my PlumbInterp $Options(-interp) $Options(-stdout)
                } else {
                    my Plumb $Options(-stdout)
                }
            }
            focus $hull.input    ;# FIXME: ???
            return $hull
        }

        method OnDestroy {script} {
            variable DestroyList
            lappend DestroyList $script
        }

        destructor {
            #after 0 [list after idle [list puts "Destroyed: [self]"]]
            variable DestroyList
            if {[info exists DestroyList]} {
                foreach script [lreverse $DestroyList] {
                    try {
                        uplevel #0 $script
                    } on error {e o} {
                        set e "during [self] destructor: \"$e\" in {$script}"
                        after idle [list return -code error -options $o $e]
                    }
                }
            }
        }

        forward history history

        # public interfaces to io:
        method puts {str} {
            my stdout $str\n
        }
        method input {s} {
            my Input $s
        }
        method clearInput {} {
            my SetInput ""
        }
        method stdout {str} {
            set move [expr {1.0 == [lindex [$hull.output yview] 1]}]
            $hull.output ins end $str stdout
            if {$move} {$hull.output see end} ;#else {my Flash $hull.output darkgrey}
        }
        method stderr {str} {
            set move [expr {1.0 == [lindex [$hull.output yview] 1]}]
            $hull.output ins end $str stderr
            if {$move} {$hull.output see end} ;#else {my Flash $hull.output darkgrey}
        }
        method eof {{chan stdout}} {
            $hull.output ins end \u03 $chan
            if {$Options(-thread) ne ""} {
                if {[thread::exists $Options(-thread)]} {
                    return
                }
            } elseif {$Options(-interp) ne ""} {
                if {[interp exists $Options(-interp)]} {
                    return
                }
            }
            set Options(-block) 2   ;# kinda a hack
            my BlockInput
        }

        # silent eval:
        method eval {script} {
            lassign [my Evaluate $script] rc res opts
            # XXX: bypasses -evalprefix.  Is that a good idea?
            #set result [my Evaluate [concat $Options(-evalprefix) $script]]
            return -code $rc -options $opts $res
        }

        # useful for pulling the interp/thread out of a console:
        method cget {option} {
            try {
                return $Options($option)
            } on error {} {
                $hull cget $option
            }
        }

        # runtime configuration is NOT PROPERLY SUPPORTED
        # - this needs OptSpec support for readonly items
        method configure args {
            foreach {option value} $args {
                if {![info exists Options($option)]} {
                    $hull configure $option $value
                } elseif {$option ni {-block -evalprefix -resultvar}} {
                    throw {TK READONLY OPTION} "Option \"$readonly\" is read-only!"
                } else {
                    my Configure [list $option $value]
                }
            }
        }

        method Configure {optargs} {
            variable Options
            dict for {option value} $optargs {
                incr ite [expr {$option in "-interp -thread -eval"}]
                if {$ite > 1} {
                    throw {TCL BADARGS} "Can only provide one of -interp, -thread or -eval"
                }
                switch $option {
                    "-block" {
                        set Options(-block) $value
                    }
                    "-interp" {
                        if {$value eq "%"} {
                            set value [interp create]
                            my OnDestroy [list interp delete $value]
                        }
                        oo::objdefine [self] method Evaluate {script} "my EvalInterp [list $value] \$script"
                    }
                    "-thread" {
                        if {$value eq "%"} {
                            set value [thread::create]
                            my OnDestroy [list thread::release $value]
                        }
                        oo::objdefine [self] method Evaluate {script} "my EvalThread [list $value] \$script"
                    }
                    "-stdout" {
                        if {$value in {"tee" "copy"}} {
                            set value tee
                        } elseif {$value in {"redir" "move"}} {
                            set value redir
                        } else {
                            throw {TCL BADARGS} "Unknown value for option -stdout \"$value\", should be one of \"tee\", \"redir\""
                        }
                    }
                    "-eval" {
                        oo::objdefine [self] method Evaluate {script} "[list {*}$value] \$script"
                    }
                    "-evalprefix"  - "-resultvar" {
                        # just store it
                    }
                    "-prompt" {
                        oo::objdefine [self] method Prompt {} $value
                    }
                    "-iscomplete" {
                        # note the appended \n !
                        oo::objdefine [self] method IsComplete {script} "[list {*}$value] \$script\\n"
                    }
                    default {
                        throw {TCL BADARGS} "Unknown option \"$option\", expected one of -eval, -prompt or -iscomplete"
                    }
                }
                set Options($option) $value
            }
        }

        method SetupTags {} {
            set textopts {-background black -foreground white
                        -insertbackground blue
                        -border 0
                        -highlightbackground darkgray -highlightcolor lightgray}
            array set tagconfig {
                prompt  {-foreground green}
                input   {-foreground darkgray}
                stdout  {-foreground lightgray}
                stderr  {-foreground red}
                sel     {-background darkgreen}
                result  {}
                error   {-foreground red -underline yes}
                error-detail   {-foreground red -underline no -elide 1}
            }

            $hull.output configure {*}$textopts
            $hull.input configure  {*}$textopts

            dict for {tag opts} [array get tagconfig] {
                $hull.output tag configure $tag {*}$opts ;#[dict merge $defaults $opts]
            }
            $hull.output tag bind error         <Double-1>  +[callback my HotError] ;#\;break
            $hull.output tag bind error-detail  <Double-1>  +[callback my HotError] ;#\;break
            # FIXME: it would be nice if the above binds could [break] to prevent selection 
            # but that looks like it's going to need plumbing the main Text bindtags ..
        }

        method SetupBinds {} {
            bind $hull.input <Control-Return> [callback my <Control-Return>]
            bind $hull.input <Return>         [callback my <Return>]
            bind $hull.input <Up>             [callback my <Up>]
            bind $hull.input <Down>           [callback my <Down>]
            bind $hull.input <Next>           [callback my <Next>]
            bind $hull.input <Prior>          [callback my <Prior>]
            bind $hull.input <Control-Up>     [callback my <Control-Up>]
            bind $hull.input <Control-Down>   [callback my <Control-Down>]
            bind $hull.input <Control-y>      {event generate %W <<Redo>>; break}    ;# FIXME: tkImprover does this better

            bind $hull.output <Tab>           "[list ::focus $hull.input]\nbreak"
            bind $hull.output <<ReadOnly>>    [callback my Flash $hull.output]        ;# delegate to <<Alert>> event?
        }

        method Flash {w {colour red}} {
            set oldbg [$w cget -background]     ;# FIXME: use a tag to mimic a ttk style
            $w configure -background $colour
            after 50 [list $w configure -background $oldbg]
        }

        method <Return> {} {
            set script [my GetInput]
            # FIXME: check for meta-commands
            if {$script eq ""} {
                after idle [callback my Flash $hull.input]
                return -code break
            } elseif {![my IsComplete $script]} {
                return -code continue
            } elseif {[my BossKey $script]} {
                after idle [callback my BossExec $script]
                my SetInput ""
                return -code break
            } else {
                after idle [callback my Execute $script]
                my SetInput ""
                return -code break
            }
        }
        method <Control-Return> {} {
            my Input \n
            return -code break
        }
        method <Up> {} {
            lassign [split [$hull.input index insert] .]        insrow inscol
            lassign [split [$hull.input index "end-1 char"] .]  endrow endcol
            if {$insrow > 1}        {return -code continue}
            my SetInput [history prev [my GetInput]]
            return -code break
        }
        method <Down> {} {
            lassign [split [$hull.input index insert] .]        insrow inscol
            lassign [split [$hull.input index "end-1 char"] .]  endrow endcol
            if {$insrow < $endrow}  {return -code continue}
            my SetInput [history next [my GetInput]]
            return -code break
        }
        method <Control-Down> {} {
        if {[string match *\n $s]} {
            my <Return>
        }
            focus $hull.output
            event generate $hull.output <Down>
        }
        method <Control-Up> {} {
            focus $hull.output
            event generate $hull.output <Up>
        }
        method <Next> {} {
            focus $hull.output
            event generate $hull.output <Next>
        }
        method <Prior> {} {
            focus $hull.output
            event generate $hull.output <Prior>
        }

        # input simplified accessors
        method Input {s} {
            # FIXME: check if blocked?
            if {[regexp {^(.*)\n$} $s -> t]} {
                $hull.input insert insert $t
                focus $hull.input
                event generate $hull.input <Return>
            } else {
                $hull.input insert insert $s
            }
        }
        method SetInput {text} {
            $hull.input replace 1.0 end $text
        }
        method GetInput {} {
            string range [$hull.input get 1.0 end] 0 end-1   ;# strip newline!
        }
        method InputPos {} {
            $hull.input count -displaychars 1.0 insert
        }

        # execute in "boss mode" - local escape
        # FIXME: control this with an option, name it better and disable by default
        method BossKey {script}     {
            string match !* $script
        }
        method BossExec {script} {
            $hull.output ins end [my Prompt] prompt
            $hull.output ins end $script\n input
            history add $script
            set script [string range $script 1 end]
            set result [list [catch {uplevel #0 $script} e o] $e $o]
            after idle [list after 0 [callback my ShowResult {*}$result]]
        }

        # evaluate current input, also make a history entry
        method Execute {script} {
            $hull.output ins end [my Prompt] prompt
            $hull.output ins end $script\n input
            history add $script

            if {$Options(-resultvar) ne ":::"} {
                set script "set [list $Options(-resultvar)] \[$script\]"
            }
            if {$Options(-evalprefix) ne ""} {
                set script [list {*}$Options(-evalprefix) $script]
            }
            set result [my Evaluate $script]

            # let the event loop catch up before showing the result (think IO)
            after idle [list after 0 [callback my ShowResult {*}$result]]
        }

        method ShowResult {rc res opts} {
            # this might want to be more clever about:
            #   - insert a leading newline if not at bol
            #   - add a newline at the end
            #   - trimming extremely long output
            if {$rc == 0} {
                if {$res ne ""} {
                    $hull.output ins end $res result
                }
            } else {
                set tag "Err [info cmdcount]"
                $hull.output ins end "\[$rc\]: $res\n" [list error $tag]
                $hull.output ins end [my FormatError $opts] [list error-detail "$tag Detail"]
            }
            $hull.output see end
        }

        method FormatError {d} {
            if {[dict size $d] eq 0} return
            set d [lsort -stride 2 $d]  ;# canonical order is nice for errors
            set maxl [::tcl::mathfunc::max {*}[lmap k [dict keys $d] {string length $k}]]
            set map [list \n [format "\n%-*s   " $maxl ""]]
            ;# [dict for] doesn't see duplicate elements, but I want to:
            foreach {key value} $d {
                set value [string map $map $value]
                append result [format "%-*s = %s\n" $maxl $key $value]
            }
            return $result
        }

        method HotError {} {
            set tags [$hull.output tag names current]
            set tag [lsearch -inline $tags "Err *"]
            if {![string match "* Detail" $tag]} {set tag "$tag Detail"}
            $hull.output tag configure $tag -elide [expr {0 eq [
                $hull.output tag cget $tag -elide
            ]}]
        }

        # configurable items - see [method Configure]:
        method Prompt {}            {return "\n% "}
        method IsComplete {script}  {info complete $script\n}
        method Evaluate {script}    {list [catch {uplevel #0 $script} e o] $e $o}

        # evaluator for -interp:
        method EvalInterp {interp script} {
            set Try {apply {{script} {
                list [catch {uplevel #0 $script} e o] $e $o
            }}}
            set script [list {*}$Try $script]
            $interp eval $script
        }

        # evaluator for -thread (async! using vwait):
        method EvalThread {thread script} {
            set Try {apply {{script} {
                list [catch {uplevel #0 $script} e o] $e $o
            }}}

            if {$Options(-block)} {
                my BlockInput
                finally [callback my UnblockInput]
            }

            variable EvalID
            incr EvalID
            set resultvar [namespace current]::evalresult($EvalID)

            set script [list {*}$Try $script]

            thread::send -async $thread $script $resultvar

            if {[info coroutine] ne ""} {   ;# FIXME: not really a good idea.  See [yieldfor]
                trace add variable $resultvar write [info coroutine]
                yieldto string cat
            } else {
                vwait $resultvar
            }

            return [set $resultvar][unset $resultvar]
        }

        method BlockInput {} {
            variable BlockDepth
            incr BlockDepth
            if {$Options(-block) == 2} {
                ;# FIXME: use a tag to mimic a ttk style
                $hull.input configure -background gray -state disabled
            } else {
                $hull.input configure -background gray
            }
        }
        method UnblockInput {} {
            variable BlockDepth
            incr BlockDepth -1
            if {$BlockDepth == 0} {
                ;# FIXME: use a tag to mimic a ttk style
                $hull.input configure -background black -state normal
            }
        }

        # setup for stdout/stderr in slave
        method Plumb {{kind tee}} {
            if {$kind eq "tee"} {
                chan push stdout [callback transchans::TeeCmd stdout [callback my stdout]]
                chan push stderr [callback transchans::TeeCmd stderr [callback my stderr]]
            } else {
                chan push stdout [callback transchans::RedirCmd stdout [callback my stdout]]
                chan push stderr [callback transchans::RedirCmd stderr [callback my stderr]]
            }

            my OnDestroy {chan pop stderr; chan pop stdout}
        }
        method PlumbInterp {int {kind tee}} {
            # set up aliases in the interp:
            #   :Stdout :Stderr - commands which take a string to write
            interp alias $int :Stdout {} [self] stdout
            interp alias $int :Stderr {} [self] stderr
            if {$kind eq "tee"} {
                set script [transchans::script TeeCmd]
            } elseif {$kind eq "redir"} {
                set script [transchans::script RedirCmd]
            }
            $int eval [list namespace eval StdRedir $script]
            $int eval {
                chan push stdout {StdRedir stdout :Stdout}
                chan push stderr {StdRedir stderr :Stderr}
            }

            my OnDestroy [list $int eval {chan pop stderr; chan pop stdout}]
        }
        method PlumbThread {tid {kind tee}} {
            if {$kind eq "tee"} {
                set script [transchans::script TeeChan]
            } elseif {$kind eq "redir"} {
                set script [transchans::script RedirChan]
            }
            thread::send $tid [list namespace eval StdRedir $script]
            foreach basechan {stdout stderr} {
                lassign [chan pipe] r w
                chan configure $w -buffering none -translation binary -eofchar {}
                chan configure $r -blocking 0 -eofchar {}
                chan configure $r -encoding    [chan configure $basechan -encoding]
                chan configure $r -translation [chan configure $basechan -translation]
                thread::transfer $tid $w
                thread::send $tid [list apply {{chan redir} {
                    chan configure $chan -eofchar {} -buffering none    ;# unbuffer
                    chan push $chan [list StdRedir $redir]
                }} $basechan $w]
                chan event $r readable [list apply {{win r basechan} {
                    set data [read $r]
                    if {$data ne ""} {
                        $win $basechan $data
                    } elseif {[eof $r]} {
                        close $r
                        $win eof $basechan
                    }
                }} $hull $r $basechan]

                my OnDestroy [list chan close $r]   ;# NOTE reverse order
                my OnDestroy [list chan event $r readable ""]
            }
        }

    }


    proc copyBindtags {from to} {
        foreach {event} [bind $from] {
            set script [bind $from $event]
            bind $to $event $script
        }
    }

    copyBindtags Text ConsoleOutput.Text

    bind ConsoleOutput.Text <Key> [namespace code {Console.Output.Key %W %K}]

    # need to make specific binds too to get priority
    bind ConsoleOutput.Text <Return> [namespace code {Console.Output.Key %W %K}]

    proc Console.Output.Key {W K args} {
        set input [winfo parent $W].input
        if {[string match *_* $K]} {return -code continue}  ;# FIXME: imprecise HACK to avoid modifiers
        focus $input
        event generate $input <Key-$K>
        return -code break
    }

    # A simple interactive history gadget.
    #   - [prev] and [next] take the current input as an argument, to stash it
    #     for later retrieval
    #   - adjacent duplicate entries are elided
    oo::class create History {
        variable history
        variable left
        variable right
        constructor {past} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]   ;# having to do this kinda sucks

            set history $past
        }
        method get {} {
            return $history
        }
        method add {entry} {
            unset -nocomplain left right
            if {$entry ne "" && $entry ne [lindex $history end]} {
                lappend history $entry
            }
            return ""   ;# no result
        }
        method prev {curr} {
            if {![info exists left]} {
                set pat $curr*
                set left [lsearch -inline -all -glob $history $pat]
                set right {}
            }
            if {$left eq ""} {
                # complain?
                return $curr
            }
            lpush right $curr
            lpop left
        }
        method next {curr} {
            if {![info exists left]} {
                return $curr
            }
            if {$right eq ""} {
                # complain?
                return $curr
            }
            lpush left $curr
            lpop right
        }
        method size {} {llength $history}
    }

    # essential utilities
    proc callback {args} { tailcall namespace code $args }
    proc thunk {args} { list ::apply [list args $args [uplevel 1 {namespace current}]] }
    proc finally {script} { tailcall trace add variable :#finally_var#: unset "$script\n;#" }

    interp alias {} lpush {} lappend
    proc lpop {_list args} {
        upvar 1 $_list list
        try {
            lindex $list end
        } finally {
            set list [lrange $list 0 end-1]
        }
    }


    # Channel redirection:
    #
    # it's desirable to capture stdout/stderr of embedded interpreters(/threads)
    # for redirection to the console.  We can do this quite nicely with channel
    # transformers (aka transchans - see [chan push]), but there are some details
    # to get right:
    #
    #   * for same-thread (even inter-interp) comms, redirecting to a command
    #     is fine.
    #   * for inter-thread comms, it works better to have a [chan pipe] for
    #     copying data to the main thread.
    #   * in each case, we may want to either retain or suppress output on
    #     the original stdchan.
    #
    # Rather than loading up a single transformer with options, we simply
    # define four:  {Tee,Redir}{Chan,Cmd}
    #
    #   * Tee *copies* its output, leaving a copy on the tty
    #   * Redir *redirects* its output, not letting it reach the tty
    #
    #   * Chan's destination is a channel, which must be in binary mode (and should be unbuffered)
    #   * Cmd's destination is a cmdPrefix, which will receive decoded unicode
    #
    # Only Cmd variants need to receive the underlying chan as an argument.
    #
    # Their [namespace eval] scripts are all stored in variables for conveniently sending
    # to another interp (or thread)
    #
    namespace eval transchans {
        proc script {varname} {
            variable $varname
            return [set $varname]
        }

        # Usage:
        #   chan push $chan [list TeeCmd $chan $cmdPrefix]
        variable TeeCmd {
            proc initialize {chan cmd x mode}  {
                info procs
            }
            proc finalize   {chan cmd x}       { }
            proc write      {chan cmd x data}  {
                set enc [chan configure $chan -encoding]
                if {$enc ne "binary"} {
                    lappend cmd [encoding convertfrom $enc $data]
                } else {
                    lappend cmd $data
                }
                uplevel #0 $cmd
                return $data
            }
            proc flush      {chan cmd x}       { }
            namespace export *
            namespace ensemble create -parameters {chan cmdprefix}
        }
        namespace eval TeeCmd $TeeCmd

        #   chan push $chan [list RedirCmd $chan $cmdPrefix]
        variable RedirCmd {
            proc initialize {chan cmd x mode}  {
                info procs
            }
            proc finalize   {chan cmd x}       { }
            proc write      {chan cmd x data}  {
                set enc [chan configure $chan -encoding]
                lappend cmd [encoding convertfrom $enc $data]
                uplevel #0 $cmd
                return $data
            }
            proc flush      {chan cmd x}       { }
            namespace export *
            namespace ensemble create -parameters {chan cmdprefix}
        }
        namespace eval RedirCmd $RedirCmd


        # if dest is a pipe, be sure to set the read side's encoding
        # to the same as the underlying channel
        #
        # Usage:
        #   chan push $chan [list TeeChan $redir]
        variable TeeChan {
            proc initialize {rechan x mode}  {
                info procs
            }
            proc finalize {rechan x}         { }
            proc write {rechan x data}       {
                puts -nonewline $rechan $data
                return $data
            }
            proc flush {rechan x}            { }
            namespace export *
            namespace ensemble create -parameters {rechan}
        }
        namespace eval TeeChan $TeeChan

        #   chan push $chan [list RedirChan $redir]
        variable RedirChan {
            proc initialize {rechan x mode}  {
                info procs
            }
            proc finalize {rechan x}         { }
            proc write {rechan x data}       {
                puts -nonewline $rechan $data
                return ""
            }
            proc flush {rechan x}            { }
            namespace export *
            namespace ensemble create -parameters {rechan}
        }
        namespace eval RedirChan $RedirChan
    }



    # hacky autoscroll which packs itself *inside* the scrolled widget
    # this would work better if the scrollbar were styled to avoid obscuring text ..
    proc autoscroll {w} {
        pack propagate $w off
        $w configure -yscrollcommand [callback autoscrollCmd $w]
    }

    proc autoscrollCmd {w min max} {
        if {$min > 0.0 || $max < 1.0} {
            set sy [ttk::scrollbar $w.sy -orient vert -command [callback $w yview]]
            pack $sy -in $w -side right -fill y
            $w configure -yscrollcommand [callback autoscrollCmd2 $w $sy]
        }
    }
    proc autoscrollCmd2 {w sy min max} {
        if {$min <= 0.0 && $max >= 1.0} {
            destroy $sy
            $w configure -yscrollcommand [callback autoscrollCmd $w]
        } else {
            tailcall $sy set $min $max
        }
    }

    namespace export console wraptext autoscroll
}

namespace import tksh::console

if {[info exists ::argv0] && $::argv0 eq [info script]} {

    # main script:
    #
    package require Thread
    wm withdraw .

    #console .console -stdout tee
    #set i .console

    #console .console -interp % -stdout tee
    #set i [.console cget -interp]

    console .console -thread % -stdout tee -resultvar ::_
    set i [.console cget -thread]

    #.console buttons add "&Packages" [::tksh::callback .console input "package names\n"]

    .console eval { ;# {} - fix syntax
        lappend ::argv              ;# these make threads much happier
        append ::argv0 {}
        set ::tcl_interactive 1     ;# we like this in scripts
    }

    update
    tksh::autoscroll .console.output

    #puts "Interpreter is $i"
    #puts "Console says [.console eval {package require Tcl}]"

    .console puts "Tcl [package require Tcl]"
    .console puts "Tk [package require Tk]"
    .console puts "Executable [info nameofexecutable]"
    .console puts "Library [info library]"
    .console puts "Architecture $tcl_platform(os) $tcl_platform(machine)"
    catch {boot .console eval}
}
