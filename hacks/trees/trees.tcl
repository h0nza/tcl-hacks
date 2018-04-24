source util.tcl
source debug.tcl
#cmdtrace enforest
#
# Take the straightforward embedding of a tree into a dictionary:
#
#     A
#   B   C
#      D E
#
set tree1 {A {B {}
              C {D {}
                 E {}}}}
# which we walk thus:
proc preorder {tree} {
    dict for {node children} $tree {
        lappend res $node
        lappend res {*}[preorder $children]
    }
    lappend res
}
assert {[preorder $tree1] eq "A B C D E"}
# To describe this in words:
#   a tree is a dict
#     whose keys are node labels
#     and whose values are empty (at leaves) or subtrees
#   dict = {NODE {}}
#        | {NODE {CHILDNODE SUBTREE ...}}
#
# Here's another:
#     A
#   B   C
#      E D
set tree2 {A {B {}
              C {E {}
                 D {}}}}
assert {[preorder $tree2] eq "A B C E D"}
# .. and another:
#     A
#   B   C
#  D E
set tree3 {A {B {D {}
                 E {}}
              C {}}}
assert {[preorder $tree3] eq "A B D E C"}
#
# Now consider that we have a set of distinct trees.  We can encode all in a single structure, as follows:
#   a forest is a list of dicts
#     whose elements are dicts
#       whose keys are node labels
#       and whose values are forests (lists of dicts)
#   forest = {( {} | {NODE SUBFOREST ...} ) ...}
#
# This is the above definition of tree, with every "dict" replaced by "list of dicts".  Instead of [set], [lappend].
# Instead of [dict set], [dict lappend].
#
# the forest of tree1 + tree2 looks like.  Simpler examples follow later.
set forest12 {{A {{B {{}}
                   C {{D {{}}
                       E {{}}}
                      {E {{}}
                       D {{}}}}}}}}

# one could also think of this as a "non-deterministic tree"

# we can perform the encoding like this:
proc enforest {forest args} {
    foreach tree $args {
        set merged false
        for {set i 0} {$i < [llength $forest]} {incr i} {
            set ft [lindex $forest $i]
            if {[dict keys $ft] eq [dict keys $tree]} {
                lset forest $i [dict map {k fv} $ft {
                    set tv [dict get $tree $k]
                    enforest $fv $tv
                }]
                set merged true
            }
        }
        if {!$merged} {
            lappend forest [dict map {tk tv} $tree {
                enforest {} $tv
            }]
        }
    }
    return $forest
}

assert {[enforest {} $tree1 $tree2] eq [regsub -all {\s+} $forest12 " "]}

# some more examples:
assert {[enforest {} {A {}}]            eq {{A {{}}}}}
assert {[enforest {} {A {}} {A {}}]     eq {{A {{}}}}}          ;# note: sets!
assert {[enforest {} {A {B {}}}]        eq {{A {{B {{}}}}}}}
assert {[enforest {} {A {}} {B {}}]     eq {{A {{}}} {B {{}}}}}
assert {[enforest {} {A {} B {}} {A {}}] eq {{A {{}} B {{}}} {A {{}}}}}
assert {[enforest {} {A {B {}}} {A {}}] eq {{A {{B {{}}} {}}}}}
assert {[enforest {} {A {}} {A {B {}}}] eq {{A {{} {B {{}}}}}}}

# the first and last tree are easy to obtain:
proc first-tree {forest} {
    set tree [lindex $forest 0]
    set tree [dict map {node subforest} $tree {
        first-tree $subforest
    }]
    return $tree
}
proc last-tree {forest} {
    set tree [lindex $forest end]
    set tree [dict map {node subforest} $tree {
        last-tree $subforest
    }]
    return $tree
}

# and tests:
set trees {
    {A {}}      {A {B {}}}      {A {B {} C {}}}     {A {B {C {}}}}
}
foreach tree $trees {
    assert {[first-tree [enforest {} $tree]] eq $tree}
    assert {[last-tree  [enforest {} $tree]] eq $tree}
}
foreach t $trees {
    foreach s $trees {
        assert {[first-tree [enforest {} $t $s]] eq $t}
        assert {[last-tree  [enforest {} $t $s]] eq $s}
    }
}


# .. so ... how does one enumerate the trees in this packed forest?

puts ok
