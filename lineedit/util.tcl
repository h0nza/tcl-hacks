
proc sum ls {::tcl::mathop::+ {*}$ls}

proc sreplace {str i j {new ""}} {
    # handle indices
    set end [expr {1 + [string length $str]}]
    regsub end $i $end i
    regsub end $j $end j
    set i [expr $i]
    set j [expr $j]
    if {$j < $i} {set j [expr {$i - 1}]}
    set pre [string range $str 0 $i-1]
    set suf [string range $str $j+1 end]
    set str $pre$new$suf
}

proc sinsert {str i new} {
    if {$i eq "end+1"} {
        append str $new
    } else {
        set pre [string range $str 0 $i-1]
        set suf [string range $str $i end]
        set str $pre$new$suf
    }
}

