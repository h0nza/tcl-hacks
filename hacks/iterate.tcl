# coroutines are famously good at two things:
#  - asynchronous code that yields to the event loop
#  - generators
#
# I was lamenting the fact that these can't be combined, when a legitimate
# use of [yieldto yield] occurred to me.  This is that nightmare.
#
# Particularly fun:  draw what happens to the coroutine stack when sleepon:chan
# is used.
#
namespace eval iterators {

    namespace export {iterate iterator}

    # define an interator that uses the "standard" protocol.
    # see also tcllib generator
    proc iterator {name arglist body} {
        proc $name $arglist "
            ::yield \[info coroutine\]
            try {
                $body
                return -code break
            }
        "
    }

    # start an iterator.
    proc iterate {cmd args} {
        variable NUM
        coroutine iter#[incr NUM] $cmd {*}$args
    }

    # this is the magic
    proc ::sleepon:chan {chan} {
        puts "Yielding [info coroutine] to $chan"
        chan event $chan readable [list [info coroutine]]
        yield; tailcall continue
    }
    proc sleepon:chan {chan} {
        puts "Yielding [info coroutine] up the stack"
        yieldto try "
            [list sleepon:chan $chan]
            puts {Continuing from [info coroutine]}
            continue
        "
    }

    proc gets {chan varname} {
        upvar 1 $varname var
        while 1 {
            if {[::gets $chan x] >= 0} {
                puts "Gets $chan $varname $x"
                tailcall set $varname $x
            }
            if {[::chan eof $chan]} {
                return -1
            }
            if {[::chan blocked $chan]} {
                sleepon:chan $chan
            }
        }
    }

    # now we just define some iterators.
    iterator input {{chan stdin}} {
        while {[gets $chan line] >= 0} {
            yield $line
        }
    }

    iterator range {{n 10}} {
        while {[incr i] < 10} {
            yield $i
        }
    }

    proc _yield {args} {
        if {$args eq ""} {
            puts "yieldto!"
            yieldto try {yield; continue}
        } else {
            puts "yielding $args"
            ::yield {*}$args
        }
    }

    iterator double {iterator} {
        while 1 {
            set x [$iterator]
            yield $x$x
        }
    }
    iterator squares {iterator} {
        while 1 {
            set x [$iterator]
            yield [expr {$x*$x}]
        }
    }
}

namespace eval coroutine::util {
    namespace import ::iterators::yield
}

namespace path ::iterators

chan configure stdin -blocking 0

proc main {} {
    set iter [iterate input]
    set iter [iterate double $iter]
    set iter [iterate double $iter]
    puts "Innermost iter: $iter"
    while 1 {
        set i [$iter]
        puts "Got: $i"
    }
    puts done
    exit
}
coroutine Main main
vwait ::forever
exit
