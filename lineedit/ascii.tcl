
set s [list 2@  3\[ 4\\ 5\] 6 7 8]

foreach cs $s {
    set cs [split $cs ""]
    set cs [lreverse $cs]
    set cs [lmap c $cs {
        if {![string is print $c]} {binary encode hex $c} else {set c}
    }]
    puts $cs
}

set alpha ABCDEFGHIJKLMNOPQRSTUVWXYZ
set alpha [split $alpha ""]
set x 0
foreach c $alpha {
    #scan $c %c x
    incr x
    set x [expr {$x % 0x1f}]
    puts -nonewline "  $c [format 0x%02x $x]"
    #puts [list [format %02x $x] $c]
}
puts ""
