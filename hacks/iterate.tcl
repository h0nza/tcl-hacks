# coroutines are famously good at two things:
#  - asynchronous code that yields to the event loop
#  - generators
#
# I was lamenting the fact that these can't be combined, when a legitimate
# use of [yieldto yield] occurred to me.  This is that nightmare.
#
# Particularly fun:  draw what happens to the coroutine stack when
# [::iterators::yieldfor] is used!

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

    # this is the magic.  Example:  [yieldfor fileevent $chan readable]
    proc ::yieldfor {cmd args} {
        set cmd [uplevel 1 [list namespace which -command $cmd]]
        $cmd {*}$args [info coroutine]
        yield
    }

    # but when used inside an iterator, [yieldfor] means something else
    proc yieldfor {cmd args} {
        set cmd [uplevel 1 [list namespace which -command $cmd]]
        yieldto try "
            [list yieldfor $cmd {*}$args]
            continue
        "
    }

    # so we need coroutine::util analogues that use [yieldfor]
    # for any asynchronous functions we want to use in our generators
    # this is the 80% solution
    proc gets {chan varname} {
        upvar 1 $varname var
        while 1 {
            if {[::gets $chan x] >= 0} {
                tailcall set $varname $x
            }
            if {[::chan eof $chan]} {
                return -1
            }
            if {[::chan blocked $chan]} {
                yieldfor ::chan event $chan readable
            }
        }
    }

    proc after {ms args} {
        if {$args eq "" && ($ms eq "idle" || [string is digit -strict $ms])} {
            tailcall yieldfor ::after $ms
        } else {
            tailcall ::after $ms {*}$args
        }
    }

    # now we just define some iterators to test with.
    # notice this one uses asynchronous gets!
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

namespace path ::iterators

# notice that
chan configure stdin -blocking 0

proc main {} {
    set iter [iterate input stdin]
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
