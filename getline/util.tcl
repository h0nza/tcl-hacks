
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

proc ssplit {str i -> _a _b} {
    upvar 1 $_a a $_b b
    if {[string match end* $i]} {
        set a [string range   $str 0 $i]
        set b [string replace $str 0 $i]
    } else {
        set a [string replace $str $i end]
        set b [string range   $str $i end]
    }
}

proc prepend {_str prefix} {
    upvar 1 $_str str
    set str $prefix$str
}

proc watchproc {name} {
    rename $name _$name
    proc $name args [format {
        puts "> %1$s $args"
        set r [uplevel 1 _%1$s $args]
        puts "< $r"
        return $r
    } $name]
}

proc lshift {varName} {
    upvar 1 $varName ls
    if {$ls eq ""} {
        throw {LSHIFT EMPTY} "Attempt to shift empty list\$$varName"
    }
    set ls [lassign $ls r]
    return $r
}
