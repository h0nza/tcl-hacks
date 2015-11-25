package require snit

snit::widgetadaptor passwordentry {

    component entry
    component checkbox

    delegate option * to entry
    delegate method * to entry

    constructor {args} {
        installhull using frame
        install entry using ttk::entry $win.entry -show *
        install checkbox using checkbutton $win.checkbox -command [mymethod toggle]
        grid $entry $checkbox
        grid columnconfigure $win 0 -weight 1
    }

    method toggle {} {
        set show [$self cget -show]
        if {$show eq ""} {
            set show "*"
        } else {
            set show ""
        }
        $self configure -show $show
    }
}
