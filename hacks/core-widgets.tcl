# first, ensure the package autoload commands are all initialised:
catch {package require nonexistent}

# get all the toplevel commands
set before [info commands ::*]

# load Tk
package require Tk
wm withdraw .

# see what commands exist now
set after [info commands ::*]

set commands [lmap c $after {
    expr {$c in $before ? [continue] : $c}
}]

proc is_widget {c} {
    try {
        info args $c
    } on ok {} {
        return false    ;# it's a proc, not a widget
    } on error {} {
        ;# it might be a widget!  Carry on ..
    }
    try {
        $c
    } trap {TCL WRONGARGS} {e o} {
        if {[string match "wrong # args: should be \"$c pathName ?-option value ...?\"" $e]} {
            return true         ;# it's a widget!
        } else {
            puts stderr "Probably not $c"
        }
    } trap { * } {} {
        ;# any other error - not a widget
    } on ok {} {
        ;# no error - oops!
        puts stderr "Sorry!  Shouldn't have run $c"
    }
    return false
}

set widgets [lmap c $commands {
    expr {[is_widget $c] ? $c : [continue]}
}]


# now try Ttk:
package require Ttk
set commands [info commands ::ttk::*]

lappend widgets {*}[lmap c $commands {
    expr {[is_widget $c] ? $c : [continue]}
}]

puts "** Widgets **"
puts [join [lsort $widgets] \n]

# now inspect their runtime state:
foreach w $widgets {
    destroy .test
    $w .test
    set class($w) [winfo class .test]
    set opts [.test configure]
    set opts [lmap o $opts {
        expr {[llength $o] == 2 ? [continue] : [lindex $o 0]}   ;# skip aliases
    }]
    set opts [lsort -dictionary $opts]
    set options($w) $opts
}
parray class
#parray options
#

exit
