package require Tk
package require Ttk
package require snit
package require options


snit::widgetadaptor FileEntry {

    # one of {open save directory}
    #  - also support directory?  less options
    #  - also support multi?  doesn't work with a single [entry]
    option          -type   -default {open} -configuremethod setOpt

    # for tk_get*File:  see [method DlgOpts]
    option      -confirmoverwrite   -default true
    option      -defaultextension   -default ""
    option      -filetypes          -default ""
    option      -initialdir         -default ""
    option      -message            -default "\ufffd"
    option      -title              -default "\ufffd"
    # -parent is automatic
    # -typevariable is not used yet
    # -multiple is with -type multi
    # for tk_chooseDirectory
    option      -mustexist          -default true

    delegate option -width          to entry
    delegate option -variable       to entry as -textvariable

    delegate option -textvariable   to button
    delegate option -text           to button

    delegate method get             to entry

    constructor args {
        installhull using ttk::frame
        install entry using entry $win.entry
        install button using button $win.button -command [mymethod Invoke]
        bind $entry <Return> [mymethod Invoke]
        grid $entry $button -sticky nsew
        if {![dict exists $args -text]} {
            dict set args -text "Browse"
        }
        $self configurelist $args
    }

    method set {fn} {
        $entry delete 0 end
        $entry insert end $fn
        after idle [mymethod SetSel]
    }

    method setOpt {opt val} {
        switch -exact $opt {
            -type {
                if {$val ni {open save directory}} {
                    return -code error "Illegal option -type \"$val\": must be in {open save directory}"
                }
            }
            default {
                return -code error "Unknown options $option"
            }
        }
        set options($opt) $val
    }

    method DlgOpts {} {
        lappend res -parent $win
        set fn [$entry get]
        if {$fn eq ""} {
            set dir [pwd]
        } else {
            set dir [file dirname $fn]
        }
        lappend res -initialdir $dir
        if {$options(-type) eq "directory"} {
            set opts {
                -mustexist
            }
        } else {
            lappend res -initialfile $fn
            set opts {
                -defaultextension
                -filetypes
                -initialdir
                -message
                -title
            }
        }
        if {$options(-type) eq "multi"} {
            lappend res -multiple yes
        }
        if {$options(-type) eq "save"} {
            lappend opts -confirmoverwrite
        }
        foreach opt $opts {
            set val $options($opt)
            if {$val ne "\ufffd"} {
                lappend res $opt $val
            }
        }
        return $res
    }

    method Invoke {} {
        set fn [
            switch -exact $options(-type) {
                "open" - "multi" {
                    tk_getOpenFile {*}[$self DlgOpts]
                }
                "save" {
                    tk_getSaveFile {*}[$self DlgOpts]
                }
                "directory" {
                    tk_chooseDirectory {*}[$self DlgOpts]
                }
            }
        ]
        if {$fn ne ""} {
            set fn [file nativename $fn]
            $entry delete 0 end
            $entry insert end $fn
            after idle [mymethod SetSel 1]
        }
    }

    method SetSel {{focus 0}} {
        set fn [$entry get]
        set l [string length $fn]
        set a [expr {$l - [string length [file tail $fn]]}]
        set b [expr {$l - [string length [file extension $fn]]}]
        $entry selection range $a $b
        $entry xview end
        $entry icursor $b
        if {$focus} {
            focus $entry
        }
    }
}


