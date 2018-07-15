# playing along with https://swtch.com/~rsc/thread/squint.pdf
#
# the streams paradigm is tricky in Tcl - it really needs a manager built (see csp?).
# This would be interesting to play along in Go, or probably Haskell.  Or Gerbil?
#

#rename yield _yield
#proc yield {args} {
#    puts "[info coroutine] [info level -1] -> $args"
#    _yield {*}$args
#}

proc yieldm {args} {yieldto list {*}$args}

proc go {cmd args} {
    variable goro
    set cmd [uplevel 1 [list namespace which $cmd]]
    coroutine ::goro#[incr goro] Go $cmd {*}$args
}

proc Go {cmd args} {
    yield [info coroutine]
    $cmd {*}$args
    return -code break
}

proc count {} {
    while 1 {
        yield [incr i]
    }
}

proc buffer {} {
    while 1 {
        lappend buf {*}[yieldm]
        if {$buf eq ""} break
        set buf [lassign $buf elem]
        yield $elem
    }
}

proc Copy {initial from args} {
    set buffer [list $initial]
    while 1 {
        if {$buffer eq ""} {
            set elem [$from]
            foreach peer $args {
                $peer $elem
            }
        } else {
            set buffer [lassign $buffer elem]
        }
        set push [yield $elem]
        while {$push ne ""} {
            lappend buffer $push
            set push [yield]
        }
    }
}

proc clone {coro} {
    set source $coro#[info cmdcount]
    rename $coro $source
    set initial [$source]
    set copy0 [go Copy $initial $source $coro]
    set copy1 [go Copy $initial $source $copy0]
    rename $copy1 $coro
    return $copy0
}

#set counter [go count]
#set clone [clone $counter]
#while 1 {
#    puts "[$counter] [$clone]"
#}

proc evaluate {terms coro} {
    set res 0.0
    while {$terms > 0} {
        set res [expr {$res + [$coro]}]
        incr terms -1
    }
    return $res
}

proc exp {X} {
    set exp 0
    set coef 1
    set mul 1
    while 1 {
        yield [expr {($X ** $exp) * 1.0/$coef}]
        set coef [expr {$coef * $mul}]
        set exp [expr {$exp + 1}]
        set mul [expr {$mul + 1}]
    }
}

proc add {F G} {
    while 1 {
        yield [expr {[$F] + [$G]}]
    }
}

proc mul_const {x F} {
    while 1 {
        yield [expr {$x * [$F]}]
    }
}

proc mul_x {F} {
    yield 0
    while 1 {
        yield [$F]
    }
}

proc mul {F G} {
    set F0 [$F]
    set G0 [$G]
    yield [expr {$F0 * $G0}]
    set F_ [clone $F]
    set G_ [clone $G]
    set M [go add [go add [go mul_const $F0 $G] [go mul_const $G0 $F]] [go mul_x [go mul $F_ $G_]]]
    while 1 {
        yield [$M]
    }
}

proc compose {F G} {    ;# yow.  UNTESTED!
    yield [$F]
    set F_ [clone $F]
    set FoG [go compose $F_ $G]
    set G_ [clone $G]
    set g [$G_]
    set GFoG [go mul $G_ $FoG]
    while 1 {
        yield [$GFoG]
    }
}

set i 10
puts "exp(x) to $i terms:  [evaluate $i [go exp 1.0]]"

puts "exp(x)+exp(x) to $i terms:  [evaluate $i [go add [go exp 1.0] [go exp 1.0]]]"

set t1 [go exp 1.0]
set t2 [clone $t1]
puts "exp(x)+exp(x) to $i terms:  [evaluate $i [go add $t1 $t2]]"

puts "2*exp(x) to $i terms:  [evaluate $i [go mul_const 2.0 [go exp 1.0]]]"

puts "exp(x)**2 to $i terms:  [evaluate $i [go mul [go exp 1.0] [go exp 1.0]]]"


