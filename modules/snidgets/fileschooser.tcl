#
# SYNOPSIS:
#
#   FilesChooser .fc -text "Choose some files" \
#       -multiple yes \
#       -filetypes {{txt *.txt} {common {*.csv *.tsv *.txt}} {all *.*}} \
#       -listvariable filenames
#
package require fun ;# maxlen, format_size, isodate

snit::widget FilesChooser {
    hulltype ttk::labelframe

    variable filenames  {}
    variable display    {}

    option -listvariable -default {} -configuremethod setOption
    option -command      -default {}

    # these are delegated to tk_get{Open,Save}File in chooseFiles
    option -multiple -default {}    ;# yes
    option -filetypes -default {}   ;# {{all *.*}}
    option -defaultextension -default {}
    option -initialdir -default {}
    option -title -default {}
    option -type -default tk_getOpenFile

    delegate method * to hull
    delegate option * to hull

    constructor args {
        $self buildWidgets
        $self configurelist $args
        $self setDisplay
    }

    method buildWidgets {} {
        grid [label $win.filenames -anchor nw -justify left -font TkFixedFont -textvariable [myvar display]] \
             [button $win.b_load -text "Choose Files" -command [mymethod chooseFiles]] \
            -in $win -sticky nsew -padx 5 -pady 5
        grid ^ \
             [button $win.b_clear -text "Clear" -command [mymethod clearFiles]] \
            -in $win -sticky nsew -padx 5 -pady {0 5}
        grid ^ \
             x \
            -in $win -sticky nsew

        grid columnconfigure $win 0 -weight 1
        grid columnconfigure $win 1 -weight 0
        grid rowconfigure $win 0 -weight 0
        grid rowconfigure $win 1 -weight 0
        grid rowconfigure $win 2 -weight 1
    }

    method setOption {option value} {
        switch -exact -- $option {
            -listvariable {
                set options(-listvariable) $value
                # it would be nice if we could simply:   upvar #0 $value filenames
                upvar #0 $value it
                if {[info exists it]} {
                    set filenames $it
                    $self setDisplay
                } else {
                    set it $filenames
                }
            }
            default {
                return -code error "Unknown option $option"
            }
        }
    }

    method chooseFiles {} {
        set params {}
        foreach opt {-multiple -filetypes -defaultextension -initialdir -title} {
            if {$options($opt) ne ""} {
                lappend params $opt $options($opt)
            }
        }
        set fs [$options(-type) {*}$params]
        if {$fs ne ""} {
            set filenames $fs
            if {$options(-listvariable) ne ""} {uplevel #0 [list set $options(-listvariable) $filenames]}
            $self setDisplay
        }
    }

    method setDisplay {} {
        set display [$self formatFilenames $filenames]
        if {$options(-command) ne ""} {
            after 0 [list {*}$options(-command) $filenames]
        }
    }

    method formatFilenames {fs} {
        if {$fs eq ""} {
            return "\nNo Files Chosen\n"
        } else {
            set dir [file dirname [lindex $filenames 0]]
            set fs [map {file tail} $filenames]
            set maxlen [maxlen $fs]
            set n [llength $fs]
            set files [expr {$n != 1 ? "files" : "file"}]
            set txt "$n $files from $dir:\n"
            foreach fn $filenames {
                set size [format_size [file size $fn]]
                set mtime [isodate [file mtime $fn]]
                set fn [file tail $fn]
                append txt [format "\n  %-${maxlen}s  %10s  %19s" $fn $size $mtime]
            }
            return $txt
        }
    }

    method clearFiles {} {
        set filenames {}
        if {$options(-listvariable) ne ""} {uplevel #0 [list set $options(-listvariable) $filenames]}
        $self setDisplay
    }
}
