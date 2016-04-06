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
        constructor {win args} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]   ;# having to do this kinda sucks

            set hull $win
            proc hull args "$win {*}\$args"

            lassign [my SplitOpts $args] myargs hullargs

            set obj [text $win {*}$hullargs]
            rename ::${obj} [namespace current]::${obj}
            trace add command [namespace current]::${obj} delete [thunk my destroy]

            set defaults [dict map {opt spec} [my OptSpec] {lindex $spec 3}]    ;# yuck
            set myargs   [dict merge $defaults $myargs]
            #my SetupOptTrace
            my Configure $myargs
            return $win
        }

        destructor {
            #puts "Destroying: [self]"
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
        }

        # utility for configuration: separate options into hull (passthrough) and local
        method SplitOpts {optargs} {    ;# lassign [my SplitOpts] hullopts myopts
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
            return $Options($option)
        }
        method CgetSpec {args} {
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
        variable win

        variable Options

        constructor {w args} {
            namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]   ;# having to do this kinda sucks

            set win $w
            set obj [toplevel $win]     ;# FIXME: hullargs?
            rename ::${obj} [namespace current]::${obj}
            trace add command [namespace current]::${obj} delete [thunk my destroy]

            frame $win.top -bg red
            frame $win.bottom -bg blue

            #scrollbar $win.output_scrolly -orient v -command [list $win.output yview]
            #scrollbar $win.input_scrolly  -orient v -command [list $win.input yview]

            wraptext $win.output  -height 24 -width 80 -wrap char  -readonly 1 \
                ;#-yscrollcommand [list $win.output_scrolly set]
            wraptext $win.input   -height 1  -width 80 -wrap char  -maxheight 5 -undo 1 \
                ;#-yscrollcommand [list $win.input_scrolly set]
            bindtags $win.output [string map {Text ConsoleOutput.Text} [bindtags $win.output]]

            History create history {{parray ::tcl_platform}}

            #pack $win.top -side top -expand yes -fill both
            #pack $win.bottom -side top -expand yes -fill both
            grid $win.top -sticky nsew
            grid $win.bottom -sticky nsew
            grid columnconfigure $win $win.top -weight 1
            grid rowconfigure $win $win.top -weight 1
            grid propagate $win 1

            #pack $win.output_scrolly -in $win.top    -side right -fill y
            #pack $win.input_scrolly  -in $win.bottom -side right -fill y

            pack $win.output -in $win.top    -expand yes -fill both
            pack $win.input  -in $win.bottom -expand yes -fill both

            # FIXME: autoscroll isn't doing what I want, particularly on .output
            #autoscroll::autoscroll $win.output_scrolly
            #autoscroll::autoscroll $win.input_scrolly

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
            }
            my Configure $args
            focus $win.input    ;# FIXME: ???
            return $win
        }

        method OnDestroy {script} {
            variable DestroyList
            lappend DestroyList $script
        }

        destructor {
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
        method input {s} {
            my Input $s
        }
        method clearInput {} {
            my SetInput ""
        }
        method stdout {str} {
            $win.output ins end $str stdout
            $win.output see end
        }
        method stderr {str} {
            $win.output ins end $str stderr
            $win.output see end
        }

        # silent eval:
        method eval {script} {
            lassign [my Evaluate $script] rc res opts
            return -code $rc -options $opts $res
        }

        # useful for pulling the interp/thread out of a console:
        method cget {option} {
            try {
                return $Options($option)
            } on error {} {
                throw [list TK LOOKUP OPTION $option] "unknown option \"$option\""
            }
        }

        # runtime configuration is NOT SUPPORTED
        # because most options only make sense at creation time
        # and a means to mark options "readonly" is not yet available

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
                if {$Options(-stdout) ne ""} {
                    if {$Options(-thread) ne ""} {
                        my PlumbThread $Options(-thread) $Options(-stdout)
                    } elseif {$Options(-interp) ne ""} {
                        my PlumbInterp $Options(-interp) $Options(-stdout)
                    } else {
                        my Plumb $Options(-stdout)
                    }
                }
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
            }

            $win.output configure {*}$textopts
            $win.input configure  {*}$textopts

            dict for {tag opts} [array get tagconfig] {
                $win.output tag configure $tag {*}$opts ;#[dict merge $defaults $opts]
            }
        }

        method SetupBinds {} {
            bind $win.input <Control-Return> [callback my <Control-Return>]
            bind $win.input <Return>         [callback my <Return>]
            bind $win.input <Up>             [callback my <Up>]
            bind $win.input <Down>           [callback my <Down>]
            bind $win.input <Next>           [callback my <Next>]
            bind $win.input <Prior>          [callback my <Prior>]
            bind $win.input <Control-Up>     [callback my <Control-Up>]
            bind $win.input <Control-Down>   [callback my <Control-Down>]
            bind $win.input <Control-y>      {event generate %W <<Redo>>; break}    ;# FIXME: tkImprover does this better

            bind $win.output <Tab>           "[list ::focus $win.input]\nbreak"
            bind $win.output <<ReadOnly>>    [callback my Flash $win.output]        ;# delegate to <<Alert>> event?
        }

        method Flash {w} {
            $w configure -background red
            after 50 [list $w configure -background black]
        }

        method <Return> {} {
            set script [my GetInput]
            # FIXME: check for meta-commands
            if {![my IsComplete $script]} {
                return -code continue
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
            my SetInput [history prev [my GetInput]]
        }
        method <Down> {} {
            my SetInput [history next [my GetInput]]
        }
        method <Control-Down> {} {
            focus $win.output
            event generate $win.output <Down>
        }
        method <Control-Up> {} {
            focus $win.output
            event generate $win.output <Up>
        }
        method <Next> {} {
            focus $win.output
            event generate $win.output <Next>
        }
        method <Prior> {} {
            focus $win.output
            event generate $win.output <Prior>
        }

        # input simplified accessors
        method Input {s} {
            $win.input insert insert $s
        }
        method SetInput {text} {
            $win.input replace 1.0 end $text
        }
        method GetInput {} {
            string range [$win.input get 1.0 end] 0 end-1   ;# strip newline!
        }

        # evaluate current input, also make a history entry
        method Execute {script} {
            $win.output ins end [my Prompt] prompt
            $win.output ins end $script\n input
            history add $script
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
                    $win.output ins end $res result
                }
            } else {
                $win.output ins end "\[$rc\]: $res" error
            }
            # FIXME: store last command result
            $win.output see end
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

            set ID [history size]
            set resultvar [namespace current]::evalresult($ID)

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
                $win.input configure -background gray -state disabled
            } else {
                $win.input configure -background gray
            }
        }
        method UnblockInput {} {
            variable BlockDepth
            incr BlockDepth -1
            if {$BlockDepth == 0} {
                $win.input configure -background black -state normal
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
            interp alias $int :Stdout {} $win stdout
            interp alias $int :Stderr {} $win stderr
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
                    $win $basechan [read $r]
                }} $win $r $basechan]

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
    bind ConsoleOutput.Text <Key> {Console.Output.Key %W %K}

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
            unset -nocomplain left
            unset -nocomplain right
            if {$entry ne "" && $entry ne [lindex $history end]} {
                lappend history $entry
            }
            return ""   ;# no result
        }
        method prev {curr} {
            if {![info exists left]} {
                set left $history
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
                lappend cmd [encoding convertfrom $enc $data]
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
            set sy [ttk::scrollbar $w.sy -orient vert -command [list $w yview]]
            pack $sy -in $w -side right -fill y
            $w configure -yscrollcommand [list autoscrollCmd2 $w $sy]
        }
    }
    proc autoscrollCmd2 {w sy min max} {
        if {$min <= 0.0 && $max >= 1.0} {
            destroy $sy
            $w configure -yscrollcommand [list autoscrollCmd $w]
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

    console .console -thread % -stdout tee
    set i [.console cget -thread]

    .console eval { ;# {} - fix syntax
        lappend ::argv              ;# these make threads much happier
        append ::argv0 {}
        set ::tcl_interactive 1     ;# we like this in scripts
    }

    update
    tksh::autoscroll .console.output

    puts "Interpreter is $i"
    puts "Console says [.console eval {package require Tcl}]"
}
