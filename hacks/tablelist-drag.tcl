# the point of this package is to have a two-level tablelist whose second-level items can be dragged around to anywhere on that second level
# the problem is in the last line of a level 1 entry:
#
#  ` foo
#    ` bar
#         <-- bad here
#  ` baz
#    ` qux
#         <-- ok here
#
# In the "bad" location, tablelist will only treat the drop as a root-level drop, which is not what we want.  So by binding the <<TablelistRowMoved>>
# event, we redirect the item.
#
# after idle after 0 ... seems to avoid Tcl_Panic("TkBTreeLinesTo couldn't find line"); .. and is a good idea anyway.
#
package require Tk
package require tablelist
namespace import tablelist::tablelist

proc acceptChildCmd {tbl targetParent sourceRow} {
#    try {
        set pdepth [$tbl depth $targetParent]
        expr { $pdepth <= 1 }
#    } on ok {r} {
#        puts "Child: $tbl $sourceRow -> $targetParent ($pdepth) (result: $r)"
#        return $r
#    }
}
proc acceptDropCmd {tbl targetRow sourceRow} {
#    try {
        set rowCount [$tbl size]
        if {$targetRow == 0} {
            expr 0  ;# never accept a drop at the top
        } elseif {$targetRow >= $rowCount} {
            expr 1  ;# always accept a drop at the end
        } else {
            set depth [$tbl depth $targetRow]
        }
#    } on ok {r} {
#        puts "Drop: $tbl $sourceRow -> $targetRow [if {[info exists depth]} {string cat ($depth)}] (result: $r)"
#        return $r
#    }
}

proc <<TablelistRowMoved>> {data} {
    lassign $data sourceIndex targetParent targetIndex
    if {$targetParent eq "root" && $targetIndex > 0} {
        set siblingKeys [.t childkeys "root"]
        set parent [lindex $siblingKeys $targetIndex-1]
        # special case for dragging to the end:
        if {$parent eq $sourceIndex} {
            set parent [lindex $siblingKeys $targetIndex-2]
        }
        # re-move the row:
        #puts "TablelistRowMoved:  .t move $sourceIndex $parent end"
        after idle [list after 0 [list .t move $sourceIndex $parent end]]
    }
}

grid [tablelist .t \
            -treestyle plastik \
            -columns {0 table 0 filename 0 title 0 checkbox} \
            -movablerows 1 \
            -selectmode single \
            -acceptdropcommand acceptDropCmd \
            -acceptchildcommand acceptChildCmd \
            -stretch all \
            ;#
] -sticky nsew
grid rowconfigure    . 0 -weight 1
grid columnconfigure . 0 -weight 1
bind .t <<TablelistRowMoved>> {<<TablelistRowMoved>> %d}

set r1 [.t insertchild root end {"Foo" "" foo 1}]
.t insertchild $r1 end {"" "foo_1.csv"}
.t insertchild $r1 end {"" "foo_2.csv"}
set r [.t insertchild $r1 end {}]
#.t rowconfigure $r -hide 1
set r2 [.t insertchild root end {"Bar" "" bar 1}]
.t insertchild $r2 end {"" "bar_1.csv"}
.t insertchild $r2 end {}
#puts "r1 = $r1; r2 = $r2"

#
# |   Table Name: | [ foo     ]   | [x] - inspect    |
# |        `file: | bar_1.csv     |  [x] - headings  |
# |        `file: | bar_2.csv     |  [x] - headings  |
# |   Table Name: | [ foo     ]   | [x] - inspect    |
# |        `file: | bar_1.csv     |  [x] - headings  |
