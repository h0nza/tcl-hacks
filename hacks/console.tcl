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
                puts "Changing height: $DLines -> $dlines"
                my configure -height $dlines
            }
        }
    }
}

proc console {w} {
    if {![winfo exists $w]} {
        toplevel $w
    }
    frame $w.top -bg red
    frame $w.bottom -bg blue
    wraptext $w.input   -height 1  -width 80 -wrap char  -maxheight 5
    wraptext $w.output  -height 24 -width 80 -wrap char  -readonly 1
    #pack $w.top -side top -expand yes -fill both
    #pack $w.bottom -side top -expand yes -fill both
    grid $w.top -sticky nsew
    grid $w.bottom -sticky nsew
    grid columnconfigure $w $w.top -weight 1
    grid rowconfigure $w $w.top -weight 1
    grid propagate $w 1
    pack $w.input  -in $w.bottom -expand yes -fill both
    pack $w.output -in $w.top    -expand yes -fill both
    bind $w.input <Return> [list apply {{w} {
        $w.output ins end [$w.input get 1.0 end]
        $w.input delete 1.0 end
        return -code break
    }} $w]
}


wm withdraw .
console .console


