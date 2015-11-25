# not really a snidget, but widget::dialog is!
# 
package require widget::dialog

proc choiceDialog {choices} {
    set w .choiceDialog[llength [info commands .choiceDialog*]]
    set dlg [widget::dialog $w -separator 1 -type custom]
    set frame [frame $w.f]
    label $frame.l -text "Choose target table"
    set lb [listbox $frame.lb]
    $lb insert end {*}$choices
    grid $frame.l -sticky nsew
    grid $frame.lb -sticky nsew
    grid columnconfigure $frame 0 -weight 1
    grid rowconfigure $frame 1 -weight 1
    $dlg setwidget $frame
    $dlg add button -text Okay -command [format {%s close [list ok [%s get active]]} [list $dlg] [list $lb]]
    $dlg add button -text Cancel -command [list $dlg close cancel]
    set result [$dlg display]
    destroy $dlg
    return [lindex $result 1]   ;# because widget::dialog binds <Escape> to {close cancel}
}

proc comboDialog {default choices} {
    set w .choiceDialog[llength [info commands .choiceDialog*]]
    set dlg [widget::dialog $w -separator 1 -type custom]
    set frame [frame $w.f]
    label $frame.l -text "Choose target table"
    entry $frame.e -exportselection yes
    $frame.e insert end $default
    set lb [listbox $frame.lb -exportselection yes]
    $lb insert end {*}$choices

    grid $frame.l -sticky nsew
    grid $frame.e -sticky nsew
    grid $frame.lb -sticky nsew

    grid columnconfigure $frame 0 -weight 1
    grid rowconfigure $frame $frame.lb -weight 1

    bind $frame.e <1> "$frame.e configure -state normal; $frame.lb configure -state disabled"
    bind $frame.lb <1> "$frame.lb configure -state normal; $frame.e configure -state disabled"

    $dlg setwidget $frame
    $dlg add button -text Okay -command [list {*}[lambda {dlg} {
        set f $dlg.f
        if {[$f.e cget -state] ne "disabled"} {
            $dlg close [list ok [$f.e get]]
        } else {
            $dlg close [list ok [$f.lb get [$f.lb curselection]]]
        }
    }] $dlg]
    $dlg add button -text Cancel -command [list $dlg close cancel]
    set result [$dlg display]
    destroy $dlg
    return [lindex $result 1]   ;# because widget::dialog binds <Escape> to {close cancel}
}
