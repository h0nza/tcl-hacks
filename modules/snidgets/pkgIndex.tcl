package ifneeded snidgets 0.1 [list apply {{dir} {
    package require Tk
    package require Ttk
    package require snit
    foreach file [glob -dir $dir *.tcl *.tm] {
        if {[file tail $file] eq "pkgIndex.tcl"} continue
        source $file
    }
    package provide snidgets 0.1
}} $dir]
