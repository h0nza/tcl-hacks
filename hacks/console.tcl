#
# This serves as a reference for wrapping Tk widgets in TclOO objects, and
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
package require Tk
#package require autoscroll      ;# tklib

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
        set hull $win
        proc hull args "$win {*}\$args"
        lassign [my SplitOpts $args] myargs hullargs
        set obj [text $win {*}$hullargs]
        rename ::${obj} [namespace current]::${obj}
        set defaults [dict map {opt spec} [my OptSpec] {lindex $spec 3}]    ;# yuck
        set myargs   [dict merge $defaults $myargs]
        #my SetupOptTrace
        my Configure $myargs
        return $win
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

    constructor {w args} {
        set win $w
        set obj [toplevel $win]     ;# FIXME: hullargs?
        rename ::${obj} [namespace current]::${obj}

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
        my Configure $args
        return $win
    }

    method Configure {optargs} {
        dict for {option value} $optargs {
            switch $option {
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
        if {![my IsComplete $script]} {
            return -code continue
        } else {
            my Execute $script
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
        lassign [my Evaluate $script] rc res opts
        if {$rc == 0} {
            if {$res ne ""} {
                $win.output ins end $res result
            }
        } else {
            $win.output ins end "\[$rc\]: $res" error
        }
        $win.output see end
    }

    # configurable items:
    method Prompt {}            {return "\n% "}
    method IsComplete {script}  {info complete $script\n}
    method Evaluate {script}    {list [catch [list uplevel #0 $script] e o] $e $o}

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
}

# essential utilities
proc callback {args} { tailcall namespace code $args }

interp alias {} lpush {} lappend
proc lpop {_list args} {
    upvar 1 $_list list
    try {
        lindex $list end
    } finally {
        set list [lrange $list 0 end-1]
    }
}

# substitute a list using command rules
proc lsub script {              ;# [sl] from the wiki
    set res {}
    set parts {}
    foreach part [split $script \n] {
        lappend parts $part
        set part [join $parts \n]
        #add the newline that was stripped because it can make a difference
        if {[info complete $part\n]} {
            set parts {}
            set part [string trim $part]
            if {$part eq {}} {
                continue
            }
            if {[string index $part 0] eq {#}} {
                continue
            }
            #Here, the double-substitution via uplevel is intended!
            lappend res {*}[uplevel list $part]
        }
    }
    if {$parts ne {}} {
        error [list {incomplete parts} [join $parts]]
    }
    return $res
}

# dict utilities
# SYNOPSIS: dictable {name access} {alice admin bob user charlie guest}
proc dictable {names list} {
    set args [join [lmap name $names {
        set name [list $name]
        subst -noc {$name [set $name]}
    }] " "]
    lmap $names $list "dict create $args"
}

# SYNOPSIS: dict subst {name jack} {Hello, $name!}
proc dict.subst {dict :__unlikely_string_arg_name__} {
    dict with dict {
        subst ${:__unlikely_string_arg_name__]}
    }
}

# SYNOPSIS: dict lsub {a "Hello, %s!\n" b World} {$a $b}
proc dict.lsub {dict :__unlikely_string_arg_name__} {
    dict with dict {
        lsub ${:__unlikely_string_arg_name__]}
    }
}

# channel redirector - assumes encoding will not change on the fly
namespace eval teechan {
    proc initialize {cmd enc x mode}    {
        info procs
    }
    proc finalize {cmd enc x}           { }
    proc write {cmd enc x data}         {
        uplevel #0 $cmd [list [encoding convertfrom $enc $data]]
        return $data
    }
    proc flush {cmd enc x}              { }
    namespace export *
    namespace ensemble create -parameters {cmd enc}
}


wm withdraw .

proc console_in_main {} {
    console .console
    chan push stdout {teechan {.console stdout} utf-8}
    chan push stderr {teechan {.console stderr} utf-8}
}

proc console_interp {} {

    set int [interp create]

    # set up aliases in the interp:
    #   :Stdout :Stderr - commands which take a string to write
    #   :Try - proxy [method Evaluate]
    interp alias $int :Stdout {} .console stdout
    interp alias $int :Stderr {} .console stderr

    $int eval {
        # proxy version of [method Evaluate]
        proc :Try {args} {
            list [catch [list uplevel #0 $args] e o] $e $o]
        }
    }

    set eval        [list $int eval :Try]
    set prompt      {return \n%\ }
    set iscomplete  {info complete}
    console .console -eval $eval -prompt $prompt -iscomplete $iscomplete

    $int eval {
        # channel redirector - assumes encoding will not change on the fly
        namespace eval teechan {
            proc initialize {cmd enc x mode}    {
                info procs
            }
            proc finalize {cmd enc x}           { }
            proc write {cmd enc x data}         {
                uplevel #0 $cmd [list [encoding convertfrom $enc $data]]
                return $data
            }
            proc flush {cmd enc x}              { }
            namespace export *
            namespace ensemble create -parameters {cmd enc}
        }
        chan push stdout {teechan :Stdout utf-8}
        chan push stderr {teechan :Stderr utf-8}
    }

    return $int
}

set i [console_interp]
puts "Interpreter is $i"
