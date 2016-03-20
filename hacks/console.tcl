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
        set defaults [dict map {opt spec} [my OptSpec] {lindex $spec 3}]
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
        # snit provides -default -verifier -configuremethod -cgetmethod
        return {
            -readonly   {-readonly      readOnly    ReadOnly    false   {string is boolean}}
            -maxheight  {-maxheight     maxHeight   MaxHeight   {}      {string is integer}}
            -minheight  {-minheight     minHeight   MinHeight   1       {string is integer}}
        }
        # FIXME: add delegates
    }

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

    method Configure {optargs} {
        foreach {option value} $optargs {
            my Verify $option $value
        }
        foreach {option value} $optargs {
            set Options($option) $value
        }
    }
    method Verify {option value} {
        set cmd [lindex [dict get [my OptSpec] $option] 4]
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
                lappend speclist $spec
            }
            return $speclist
        }
        set spec [my OptSpec]
        return [lmap option $args {
            if {[dict exists $spec $option]} {
                dict get $spec $option
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

    # basic text wrappers:
    forward ins hull insert
    forward del hull delete
    forward rep hull replace
    method insert args {
        if {$Options(-readonly)} return
        try {
            $hull insert {*}$args
        } finally {
            my <<TextChanged>>  ;# not really an event
        }
    }
    method replace args {
        if {$Options(-readonly)} return
        try {
            $hull replace {*}$args
        } finally {
            my <<TextChanged>>  ;# not really an event
        }
    }
    method delete args {
        if {$Options(-readonly)} return
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
        wraptext $win.input   -height 1  -width 80 -wrap char  -maxheight 5
        wraptext $win.output  -height 24 -width 80 -wrap char  -readonly 1

        History create history {{parray ::tcl_platform}}

        #pack $win.top -side top -expand yes -fill both
        #pack $win.bottom -side top -expand yes -fill both
        grid $win.top -sticky nsew
        grid $win.bottom -sticky nsew
        grid columnconfigure $win $win.top -weight 1
        grid rowconfigure $win $win.top -weight 1
        grid propagate $win 1
        pack $win.input  -in $win.bottom -expand yes -fill both
        pack $win.output -in $win.top    -expand yes -fill both

        my SetupTags
        my SetupBinds
        #my Configure $args
        return $win
    }

    method SetupTags {} {
        array set tagconfig {
            * {-background black -foreground white}
            prompt {-foreground green}
            input  {-foreground darkgray}
            stdout {-foreground lightgray}
            stderr {-foreground red}
            result {}
            error  {-foreground red -underline yes}
        }
        set textopts {-border 0 -insertbackground blue -highlightbackground darkgray -highlightcolor lightgray}
        set defaults $tagconfig(*)
        unset tagconfig(*)
        $win.output configure
        $win.output configure {*}$defaults {*}$textopts
        $win.input configure {*}$defaults {*}$textopts
        dict for {tag opts} [array get tagconfig] {
            $win.output tag configure $tag {*}[dict merge $defaults $opts]
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

    method Input {s} {
        $win.input insert insert $s
    }
    method SetInput {text} {
        $win.input replace 1.0 end $text
    }
    method GetInput {} {
        string range [$win.input get 1.0 end] 0 end-1   ;# strip newline!
    }

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

    method Prompt {}            {return "\n% "}
    method IsComplete {script}  {info complete $script\n}
    method Evaluate {script}    {list [catch [list uplevel #0 $script] e o] $e $o}

    method stdout {str} {
        $win.output ins end $str stdout
        $win.output see end
    }
    method stderr {str} {
        $win.output ins end $str stderr
        $win.output see end
    }
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
        if {$entry ne [lindex $history end]} {
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

# channel redirector - assumes encoding will not change on the fly
namespace eval teecmd {
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
console .console
chan push stdout {teecmd {.console stdout} utf-8}
chan push stderr {teecmd {.console stderr} utf-8}

