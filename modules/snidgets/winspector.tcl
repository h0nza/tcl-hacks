#
# A silly inspector for ttk widgets
#
package require Tk
package require Ttk
package require snit


# this is just awfully painful
namespace eval parse_ttk_layout {
    proc parse_layout {layout {parent ""}} {
        set opts [lassign $layout element]
        set key [linsert $parent end $element]
        set result [list $key [nokids $opts]]
        set kids [getkids $opts]
        foreach kid [getkids $opts] {
            lappend result {*}[parse_layout $kid $key]
        }
        return $result
    }

    proc nokids {o} {
        dict unset o -children
    }

    proc getkids {o} {
        if {![dict exists $o -children]} {
            return ""
        }
        set kids [dict get $o -children]
        set k $kids
        set result {}
        for {set i 1} {$i < [llength $kids]} {incr i 2} {
            if {![string match -nocase -* [lindex $kids $i]]} {
                lappend result [lrange $kids 0 $i-1]
                set kids [lrange $kids $i end]
            }
        }
        if {$kids ne ""} {
            lappend result $kids
        }
        return $result
    }
}
proc parse_ttk_layout {l} {
    parse_ttk_layout::parse_layout $l
}

snit::widgetadaptor Winspector {

    variable Target
    variable Current

    component tframe
    component   current
    component   gobutton
    component   target

    component bframe
    component   bindings

    component sframe
    component   styles

    constructor {args} {
        installhull     using toplevel

        install tframe      using ttk::frame      $win.tframe
        install current     using ttk::label      $win.current  -textvariable [myvar Current] -anchor center
        install gobutton    using ttk::button     $win.gobutton -command [mymethod StartChoose] -text "Choose widget"
        install target      using ttk::entry      $win.target   -textvariable [myvar Target] -state readonly

        install bframe      using ttk::labelframe $win.bframe   -text "Bindings"
        install sframe      using ttk::labelframe $win.sframe   -text "Style"

        install bindings    using ttk::treeview   $win.bindings -columns {Tag Event Script} -show {tree}
        install styles      using ttk::treeview   $win.styles   -columns {Attr Data} -show {headings tree}

        grid $tframe    -           -sticky nsew
        grid $bframe    $sframe     -sticky nsew
        grid rowconfigure $win 1 -weight 1
        grid columnconfigure $win {0 1} -weight 1

            grid $current   -           -sticky nsew -in $tframe
            grid $gobutton  $target     -sticky nsew -in $tframe

            grid $bindings              -sticky nsew -in $bframe
            grid $styles                -sticky nsew -in $sframe

        grid rowconfigure $bframe 0 -weight 1
        grid rowconfigure $sframe 0 -weight 1
        grid columnconfigure $bframe 0 -weight 1
        grid columnconfigure $sframe 0 -weight 1

        grid anchor $tframe center
        grid anchor $current center


        bind all <Enter> [mymethod Enter %W]
    }

    method StartChoose {} {
        $gobutton configure -text "Click on target widget"
        grab $target
        bind $target <1> [mymethod ChooseTarget]
    }

    method Enter {w} {
        set Current $w
        #puts "Entered $w"
    }

    method ChooseTarget {} {
        set Target [winfo containing {*}[winfo pointerxy .]]
        $gobutton configure -text "Choose widget"
        grab release $target
        bind $target <1> {}
        after idle [mymethod RefreshDisplay]
    }

    method RefreshDisplay {} {
        puts "Refreshing display for $Target"
        $self RefreshBindings
        $self RefreshStyles
    }

    method RefreshBindings {} {
        $bindings delete [$bindings children {}]
        foreach bindtag [bindtags $Target] {
            $bindings insert {} end -id $bindtag -text $bindtag -values [list]
            foreach event [lsort [bind $bindtag]] {
                set script [bind $bindtag $event]
                set script [string trim $script \n]
                $bindings insert $bindtag end -text $event -values [list $script]
                # FIXME: needs tooltip on hover
            }
        }
    }

    method RefreshStyles {} {
        set class [winfo class $Target]
        set style [$Target cget -style]

        $styles delete [$styles children {}]
        $styles insert {} end -id name   -text "name"   -values [list $Target]
        $styles insert {} end -id class  -text "class"  -values [list $class]
        $styles insert {} end -id style  -text "style"  -values [list $style]
        $styles insert {} end -id map    -text "map"    -values [list]
        $styles insert {} end -id layout -text "layout" -values [list]
        $styles insert {} end -id opts   -text "opts"   -values [list]
        if {$style eq ""} {
            set style $class
        }

        set map [ttk::style map $style]
        set layout [ttk::style layout $style]
        set parts [parse_ttk_layout $layout]
        set odict {}
        foreach {part opts} $parts {
            set part [lindex $part end]
            set opts [ttk::style element options $part]
            foreach opt $opts {
                dict set odict $part $opt [ttk::style lookup $style $opt]
            }
        }

        dict for {opt d} $map {
            $styles insert "map" end -id [list "map" $opt] -text $opt -values [list]
            dict for {st val} $d {
                $styles insert [list "map" $opt] end -text $st -values [list $val]
            }
        }

        dict for {key opts} $parts {
            set pkey [lrange $key 0 end-1]
            $styles insert [list "layout" {*}$pkey] end -id [list "layout" {*}$key] -text [lindex $key end] -value $opts
        }

        dict for {key opts} $odict {
            $styles insert "opts" end -id [list "opts" $key] -text $key
            foreach {k v} $opts {
                $styles insert [list "opts" $key] end -text $k -values [list $v]
            }
        }
    }
}

