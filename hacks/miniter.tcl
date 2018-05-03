# composing filters over iterators is really composing a script
# maybe there's something in that?

proc putl args {puts $args}

# definition helper to enforce iterator protocol.
proc defiter {name args body} {
    set pre { yield [info coroutine] }
    set post { while 1 {yieldto throw {ITERATOR DONE} "Iterator exhausted!" } }
    tailcall proc $name $args "$pre\n$body\n$post"
}

# the essential iterator
defiter range_ {start stop step} {
    for {set i $start} {$i < $stop} {incr i} {
        yield $i
    }
}

# arg parsing wrapper
proc range {args} {
    set start 0
    set stop Inf
    set step 1
    switch [llength $args] {
        3 { lassign $args start stop step }
        2 { lassign $args start stop }
        1 { lassign $args stop }
        default { return -code error "Invalid arguments, expected <stop>, <start stop>, or <start stop step>" }
    }
    range_ $start $stop $step
}

# iterator control:
proc start {args} {
    tailcall {*}$args
}
proc next {iter} {
    $iter
}
proc destroy {iter} {
    rename $iter {}
}
defiter memo {varName iter} {
    upvar 1 $varName cache
    foriter i $iter {
        lappend cache $i
        yield $i
    }
}

proc gensym {{name gensym#}} {
    regexp {(.*)(#\d*)?} $name -> name suffix
    set i -1
    while {[namespace which -command [set n $name#$i]] ne ""} { incr i }
    return $n
}

defiter dup {iter} {
    # nope, too wild
    set old [gensym $iter]
    rename $iter $old
    rename [memo cache $old] $iter
    start fromcache cache $iter
}

defiter fromcache {list iter}
proc push {iter args} {
    $iter {*}$args
}
proc done? {iter} {
}

# control structure for consuming iterators:
proc foriter {args} {
    if {[llength $args] % 2 == 0} {
        return -code error "Invalid arguments, expected \"iterate varName iterable ?varName iterable ..? script\""
    }
    set script [lindex $args end]
    foreach {v i} [lrange $args 0 end-1] {
        lappend vars $v
        lappend iters $i
        append setup    [format {::set %s [start %s];}    [list $v] $i]
        append pre      [format {::set %s [next %s];}    [list $v]   [list $v]]
        append cleanup  [format {catch {rename %s ""}}          [list $i]]
    }
    set script $pre$script
    set script [list ::while 1 $script]
    puts $setup
    uplevel 1 $setup
    putl ::try $script trap {ITERATOR DONE} {} $cleanup
    tailcall ::try $script trap {ITERATOR DONE} {} $cleanup
}

# conversions:
proc tolist {iter} {
    foriter i $iter {lappend result $i}
    lappend result
}
defiter fromlist {xs} {
    foreach x $xs {yield $x}
}

proc assert {expr {msg ""}} {
    if {$msg eq ""} {set msg $expr}
    if {![uplevel 1 [list ::expr $expr]]} {
        throw {ASSERT FAILED} $msg
    }
}

append test {
    assert {[tolist {range 10}] eq {0 1 2 3 4 5 6 7 8 9 10}}
    #assert {[iterator tolist [iterator fromlist {a b c d e}]] eq {a b c d e}}
}

# filters: skipping elements
defiter take {n iter} {
    foriter i $iter {
        if {[incr n -1]<0} break
        yield $i
    }
}
defiter drop {n iter} {
    foriter i $iter {
        if {[incr n -1]>=0} continue
        yield $i
    }
}

# filters: mixing
defiter iconcat args {
    foreach iter $args {
        foreach i $iter {
            yield $i
        }
    }
}

# interleave stops as soon as one iterator is exhausted
# it consumes them all - the still-open ones cannot be
# continued
defiter interleave {xs ys} {    ;# must break early!
    set xs [$xs]
    set ys [$ys]
    foriter _ [range] {
        yield [xs]
        yield [ys]
    }
}

# zip returns "" for missing elements
defiter zip {xs ys} {           ;# must break late!
    foriter x $xs y $ys {
        yield $x
        yield $y
    }
}

# filters: conditions
# defiter ifilter {i_ iter cond} {
#     upvar 1 $i_ i
#     foreach i $iter {
#         if {!$cond} continue
#         yield $i
#     }
# }
# defiter iwhile {i_ iter cond} {
#     upvar 1 $i_ i
#     foreach i $iter {
#         if {!$cond} break
#         yield $i
#     }
# }
# defiter iuntil {i_ iter cond} {
#     upvar 1 $i_ i
#     foreach i $iter {
#         if {!$cond} break
#         yield $i
#     }
# }

# those are easier with:
defiter icase {_i iter args} {
    upvar 1 $_i i
    foreach i $iter {
        foreach {cond then} $args {
            if $cond $then
        }
        yield $i
    }
}
defiter ifilter {_i iter cond} { tailcall icase $_i $iter !($cond) continue }
defiter iwhile  {_i iter cond} { tailcall icase $_i $iter !($cond) break }
defiter iuntil  {_i iter cond} { tailcall icase $_i $iter $cond break }

defiter even {iter} {ifilter i $iter {$i % 2 == 0}}
defiter odd  {iter} {icase i $iter {$i % 2} continue}


# now, we've already seen a pattern where iterators are modified by a limited number of means.
# What constraints can we stand?

# an iterator that needs state:
defiter uniq {iter} {
    # we can cheat by instantiating the iterator twice!
    foriter j [take 1 $iter] {
        yield $j
    }
    # we have already yielded the first element as $j,
    # so it will be considered a dup.
    foriter i $iter {
        if {$i ne $j} {yield $i}
        set j $i
    }
}

set Nat {{}for {set x 0} {1} {$x+1} {yield $x}}

set Even? {{}for {} {} {} {if {$x%2} continue}}

eval $test
