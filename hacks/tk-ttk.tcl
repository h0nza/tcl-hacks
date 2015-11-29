# DEMO:  differences between Tk and Ttk widgets
#
# == -variable options ==
#
#  Tk widgets will create the var if it doesn't exist;  ttk won't.
#
# == radiobutton default -value ==
#
#  Tk's default is "";  ttk's is "1"
#
# == tri-state ==
#
#  Tk's radio/check have configurable -tristatevalue (default "") and -tristateimage;
#  ttk tristate on the variable being unset and indicate it with "selected" or "alternate" in [$w state]
#
#
# == notebook style ==
#
#  Tk radio/check are easier for notebook-like behaviour using simple options:
#    -indicatoron false  -relief -offrelief -image -selectimage -tristateimage
#
#  ttk's require ttk::style hackery to do the same.
#
package require Tk
package require Ttk
namespace eval foo {    ;# just to prove we don't have clever var resolution
    variable {}
    pack [checkbutton .c -variable (c) -text checkbutton]
    pack [ttk::checkbutton .tc -variable (tc) -text ttk::checkbutton]
    pack [radiobutton .r -variable (r) -text radiobutton]
    pack [ttk::radiobutton .tr -variable (tr) -text ttk::radiobutton]
    pack [entry .e -textvariable (e)]
    pack [ttk::entry .te -textvariable (te)]
}
puts "\n== exists check =="
foreach name {(c) (tc) (r) (tr) (e) (te)} {
    if {![info exists $name]} {
        puts "::$name\t--"
    } else {
        puts "::$name\t\"[set $name]\""
    }
}
puts "\n== values =="
foreach w {.c .tc .r .tr} {
    foreach o {-value -tristatevalue} {
        catch {puts $w:\t[$w configure $o]}
    }
}
puts "\n== ttk::state =="
foreach w {.tc .tr} {
    puts [list $w state]:\t[$w state]
}
puts "\n== trace =="
trace add variable {} write {apply {{_ name op} {
    puts "TRACE: $name = $::($name)"
    if {[string match t* $name]} {
        puts [list .$name state]:\t[.$name state]
    }
}}}
