# an experiment in how hard we can overload [loop]
# nb: args are not tip288-decomposable!
proc loop args {
    tailcall loop/[llength $args] {*}$args
}

proc loop/1 script {
    tailcall while 1 $script
}

proc loop/2 {iters script} {
    for {set i 0} {$i < $iters} {incr i} {
        uplevel 1 $script
    }
}

proc loop/3 {varName iters script} {
    upvar 1 $varName i
    for {set i 0} {$i < $iters} {incr i} {
        uplevel 1 $script
    }
}

proc loop/4 {varName from to script} {
    upvar 1 $varName i
    set i $from
    set incr [expr {$to > $from ? 1 : -1}]
    set cont [expr {$from > $to}]
    for {set i $from} {($i > $to) == $cont} {incr i $incr} {
        uplevel 1 $script
    }

}

proc loop/5 {varName from to incr script} {
    upvar 1 $varName i
    set i $from
    set cont [expr {$from > $to}]
    for {set i $from} {($i > $to) == $cont} {incr i $incr} {
        uplevel 1 $script
    }
}

proc test {} {
    loop {  ;# would loop forever
        loop 2 {
            puts "Do this twice"
        }
        loop i 2 {
            puts "Twice with index: $i"
        }
        loop i 9 7 {
            puts "Nine and Eight: $i"
        }
        loop i 9 0 -2 {
            puts "Descending odd digits: $i"
        }
        break   ;# otherwise loop forever
    }
}

test
