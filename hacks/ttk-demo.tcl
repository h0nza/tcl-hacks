if 0 {

    This is a simple visual demo for most of the Ttk widgets.

    Use the "theme" treeview to select themes, and see what different ones look like.

    Widgets *not* (yet) included are:

        ::ttk::frame
        ::ttk::notebook
        ::ttk::panedwindow
        ::ttk::scrollbar
        ::ttk::sizegrip

    Missing features include:

      * progress bar animation
      * menus for the menu buttons
      * showing off more of treeview
      * compound buttons and other stuff with images
      * included images and dialogs
      * colour-scheme selection

    Included widgets are:

        ::ttk::button
        ::ttk::checkbutton
        ::ttk::combobox
        ::ttk::entry
        ::ttk::label
        ::ttk::labelframe
        ::ttk::menubutton
        ::ttk::progressbar
        ::ttk::radiobutton
        ::ttk::scale
        ::ttk::separator
        ::ttk::spinbox
        ::ttk::treeview
}

package require Tk
package require Ttk

grid [
    ttk::labelframe .lf -text "Label relief" -padding 4
] - [
    ttk::labelframe .tvf -text "Treeview" -padding 4
] -padx 6 -pady 6 -sticky nsew

    set rs {flat groove raised ridge solid sunken}
    set i 0
    grid {*}[lmap r $rs {
        ttk::label .lf.l[incr i] -text [string totitle $r] -relief $r
    }] -padx 4 -pady 4 -sticky nsew

grid [
    ttk::labelframe .bf -text "Buttons" -padding 4
] - ^ -padx 6 -pady 6 -sticky nsew

    grid [
        ttk::button .bf.b1 -text "Normal Button"
    ] [
        ttk::button .bf.b2 -text "Disabled Button" -state disabled
    ] [
        ttk::button .bf.b3 -text "Undefaultable" -default disabled
    ] [
        ttk::button .bf.b4 -text "Default" -default active
    ] -sticky nsew

grid [
    ttk::labelframe .tbf -text "Toolbuttons" -padding 4
] - ^ -padx 6 -pady 6 -sticky nsew

    grid [
        ttk::button .tbf.bt1 -text "Tool 1" -style Toolbutton
    ] [
        ttk::button .tbf.bt2 -text "Disabled 2" -style Toolbutton -state disabled
    ] [
        ttk::button .tbf.bt3 -text "Undefaultable 3" -style Toolbutton -default disabled
    ] [
        ttk::button .tbf.bt4 -text "Default 4" -style Toolbutton -default active
    ] -sticky nsew

grid [
    ttk::labelframe .cf -text "Checkbuttons" -padding 4
] - ^ -padx 6 -pady 6 -sticky nsew

    grid [
        ttk::checkbutton .cf.b1 -text "Normal Button"
    ] [
        ttk::checkbutton .cf.b2 -text "Disabled Button" -state disabled
    ] [
        ttk::checkbutton .cf.bt1 -text "Tool 1" -style Toolbutton
    ] [
        ttk::checkbutton .cf.bt2 -text "Tool 2" -style Toolbutton
    ] [
        ttk::checkbutton .cf.bt3 -text "Disabled 3" -style Toolbutton -state disabled
    ] -sticky nsew

grid [
    ttk::labelframe .rf -text "Radiobuttons" -padding 4
] - ^ -padx 6 -pady 6 -sticky nsew

    grid [
        ttk::radiobutton .rf.b1 -value b1 -variable radio1 -text "Normal Button"
    ] [
        ttk::radiobutton .rf.b2 -value b2 -variable radio1 -text "Disabled Button" -state disabled
    ] [
        ttk::radiobutton .rf.bt1 -value bt1 -variable radio1 -text "Tool 1" -style Toolbutton
    ] [
        ttk::radiobutton .rf.bt2 -value bt2 -variable radio1 -text "Tool 2" -style Toolbutton
    ] [
        ttk::radiobutton .rf.bt3 -value bt3 -variable radio1 -text "Disabled 3" -style Toolbutton -state disabled
    ] -sticky nsew

grid [
    ttk::labelframe .ef -text "Entries" -padding 4
] - - -padx 6 -pady 6 -sticky nsew
    set e1 "Normal"
    set e2 "Disabled"
    set e3 "Readonly"
    grid [
        ttk::label .ef.l1 -text $e1
    ] [
        ttk::entry .ef.e1 -textvariable e1
    ] [
        ttk::label .ef.l2 -text $e2
    ] [
        ttk::entry .ef.e2 -textvariable e2 -state disabled
    ] [
        ttk::label .ef.l3 -text $e3
    ] [
        ttk::entry .ef.e3 -textvariable e3 -state readonly
    ] -sticky nsew -padx 4

    # justification
    set e4 "Left"
    set e5 "Right"
    set e6 "Center"
    grid [
        ttk::label .ef.l4 -text $e4
    ] [
        ttk::entry .ef.e4 -textvariable e4 -justify [string tolower $e4]
    ] [
        ttk::label .ef.l5 -text $e5
    ] [
        ttk::entry .ef.e5 -textvariable e5 -justify [string tolower $e5]
    ] [
        ttk::label .ef.l6 -text $e6
    ] [
        ttk::entry .ef.e6 -textvariable e6 -justify [string tolower $e6]
    ] -sticky nsew -padx 4

    
grid [
    ttk::labelframe .vf -text "Validated Entries (max length 8)" -padding 4
] [
    ttk::labelframe .cbf -text "Comboboxes" -padding 4
] - -padx 6 -pady 6 -sticky nsew

    set vcmd {expr {!(%d && ([string length %s]>7))}}
    set ivcmd {%W delete 0 end; %W insert end [string range %s 0 7]}
    set vmodes {none focus focusin focusout key all}

    set ev0 "Password"
    grid [
        ttk::label .vf.lp0 -text $ev0
    ] [
        ttk::entry .vf.p0 -textvariable ev0 -validate "all" -validatecommand $vcmd  -show *
    ] -sticky nsew

    grid [
        ::ttk::separator .vf.sep0 -orient horiz
    ] - -pady 6 -sticky nsew

    set spin 12.5
    grid [
        ttk::label .vf.ls0 -text "Spinbox"
    ] [
        ::ttk::spinbox .vf.s0 -from 0.0 -to 100.0 -increment 12.5 -textvariable spin -format %.1f
    ] -sticky nsew

    grid [
        ::ttk::separator .vf.sep1 -orient horiz
    ] - -pady 6 -sticky nsew

    set i 0
    foreach vmode $vmodes {
        set ev[incr i] $vmode
        grid [
            ttk::label .vf.l$i -text [set ev$i]
        ] [
            ttk::entry .vf.e$i -textvariable ev$i -validate $vmode -validatecommand $vcmd -invalidcommand $ivcmd
        ] -sticky nsew
    }


# comboboxes
    set values "One Two Buckle My Shoe"
    grid [
        ::ttk::label .cbf.l1 -text "Combobox"
    ] [
        ::ttk::combobox .cbf.c1 -values $values     -width 10
    ] [
        ::ttk::label .cbf.l2 -text "Readonly"
    ] [
        ::ttk::combobox .cbf.c2 -values $values -state readonly     -width 10
    ] [
        ::ttk::label .cbf.l3 -text "Disabled"
    ] [
        ::ttk::combobox .cbf.c3 -values $values -state disabled     -width 10
    ] -sticky nsew

grid ^ [
    ttk::labelframe .mf -text "Menubuttons" -padding 4
] [
    ttk::labelframe .pf -text "Scale and Progressbar" -padding 4
] -padx 6 -pady 6 -sticky nsew

    set menu {}
    set dirs {above below left right flush}
    set i 0
    foreach dir $dirs {
        set mb[incr i] $dir
        grid [
            ttk::label .mf.l$i -text [set mb$i]
        ] [
            ttk::menubutton .mf.e$i -text [set mb$i] -direction $dir -menu $menu
        ] -sticky nsew
    }

    set p0 10
    set p1 10
    set pv0 10
    set pv1 10
    grid [
        ::ttk::progressbar .pf.p0 -orient horiz -mode determinate -variable p0
    ] [
        ::ttk::separator .pf.sep -orient vert
    ] [
        ::ttk::progressbar .pf.pv0 -orient vert -mode determinate -variable pv0
    ] [
        ::ttk::scale .pf.sv0 -orient vert -from 0 -to 100 -variable pv0
    ] [
        ::ttk::progressbar .pf.pv1 -orient vert -mode indeterminate -variable pv1
    ] [
        ::ttk::scale .pf.sv1 -orient vert -from 0 -to 100 -variable pv1
    ] -sticky nsew -padx 6 -pady 6

    grid [
        ::ttk::scale .pf.s0 -orient horiz -from 0 -to 100 -variable p0
    ] ^ ^ ^ ^ ^ -sticky nsew -padx 6 -pady 6
    grid [
        ::ttk::progressbar .pf.p1 -orient horiz -mode indeterminate -variable p1
    ] ^ ^ ^ ^ ^ -sticky nsew -padx 6 -pady 6
    grid [
        ::ttk::scale .pf.s1 -orient horiz -from 0 -to 100 -variable p1
    ] ^ ^ ^ ^ ^ -sticky nsew -padx 6 -pady 6


grid [
    ::ttk::treeview .tvf.tv -columns {Theme} -show {headings}
] -sticky nsew -padx 4 -pady 4

foreach style [::ttk::style theme names] {
    .tvf.tv insert {} end -id $style -text $style -values [list "Use the \"$style\" theme"]
}

.tvf.tv heading Theme -text Theme
.tvf.tv selection set [list [::ttk::style theme use]]

bind .tvf.tv <<TreeviewSelect>> {
    ::ttk::style theme use [%W selection]
}

