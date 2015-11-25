package require Tk
package require Ttk

# better selection behaviour
proc ::ttk::combobox::TraverseIn w {
    $w instate {!disabled} {
        $w selection range 0 end
        $w icursor end
    }
}
proc ::ttk::combobox::TraverseOut w {
    $w selection clear
}
bind TCombobox <<TraverseOut>> [list ::ttk::combobox::TraverseOut %W]

# necessary on linux: (from http://wiki.tcl.tk/1959)
ttk::style map TCombobox -fieldbackground {readonly white disabled #d9d9d9} 

# jcowgar's improved completion
#source misctcl/combobox/combobox.tcl

;# FIXME: still weird selection behaviour on change
