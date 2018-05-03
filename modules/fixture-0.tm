# --- WORK IN PROGRESS ---
proc putl args {puts $args}
# a test framework inspired by c++ Catch
#
# Test sections can nest
#
# For each nested section, the enclosing pre/postludes must happen once
#
# This means the sections must evaluate in a loop, finishing only when all their subsections are exhausted.
# This is simplest to discover by running until *no* subsections evaluate.
#
# And each subsection must:
#  - calculate its own index
#  - check whether it is due to execute on this run
#  - check whether it should execute based on filters from the user
#  - record whether it has executed for its parent and successors to know
#
# So the puzzle is in-order traversal of a tree with N leaves, N times,
# such that on the Nth traversal only the Nth leaf and its ancestors "fire"
#
# A section
#   can calculate its index on entry
#   knows it is a leaf after evaluation

# reporting.  Do I just want to log to sqlite?
# leaf: PASS/FAIL (x asserts)
# section: PASS/FAIL (x/n sections, k asserts)
# total: N failures out of K leaf sections. X asserts passed.
# (count skipped asserts? hmm not by execution)
proc lincr {_xs idx n} {
    upvar 1 $_xs xs
    set x [lindex $xs $idx]
    if {$x eq ""} {set x 0}
    incr x $n
    lset xs $idx $x
}

proc lmatch {pattern xs} {
    while {[llength $pattern]} {
        set pattern [lassign $pattern p]
        if {$p eq "**"} {
            if {$pattern ne ""} {
                error "Double-wildcard (**) not allowed before end"
            }
            return true
        }
        if {[llength $xs] == 0} {
            return false
        }
        set xs [lassign $xs x]
        if {![string match $p $x]} {
            return false
        }
    }
    if {$pattern eq $list} {
        return true
    }
    return false
}

oo::class create Fixture {
    # the logic in here is a little complicated.  Sections can nest arbitrarily,
    # forming a tree.  Sections depend on their parents (setup/teardown), but
    # should be isolated from their siblings.  Hence we need to run through the
    # testset N times, where N is the number of /leaf/ sections.  On the kth run,
    # only the kth leaf section and its parents should be executed.
    #
    # For arbitrary reasons, I don't want to do this by pre-processing the tree
    # to enumerate its leaves up front.  Instead, the fixture loops until all
    # sections have been exhausted.
    #
    # Each section is identified by name.  ${context} stores the path to the
    # currently evaluating section and ${depth} our the current level of the tree
    # ([llength $context] == $depth).  We also track tests, as lists of numbers
    # representing their index path in the tree (${numbrer}).  These are updated
    # by [section] only on entry, so that after evaluation it can detect that it
    # is a leaf node by the fact that $context has not changed.
    #
    # To support the required iteration, we keep track in ${upto} of the most
    # recently executed-to-completion section, or "" if the next section must
    # be run.
    variable testname   ;# name of the topmost grouping
    variable context    ;# where are we now?
    variable number     ;# like context, but integers
    variable sections   ;# trail recorded as we go
    variable depth      ;# to know if we are ascending or descending
    variable upto       ;# which leaf test did we last run?
    constructor {} {}

    # testsets are run in a new scope within the namespace they are declared.
    method tests {name script} {
        set testname $name
        set context {}
        set sections {}
        set depth 0
        set ns [uplevel 1 {namespace current}]
        set upto ""
        while 1 {
            set number {}
            apply [list {} $script $ns]
            if {$upto eq ""} break
        }
        puts "We ran all these tests:"
        puts \t[join $sections \n\t]
    }

    method section {name script} {
        if {$depth < [llength $context]-1} {                ;# keep track of current section
            set context [lreplace $context $depth end]
            set number  [lreplace $number  $depth+1 end]
        }
        lset context $depth $name
        lincr number $depth 1
        incr depth
        set mycontext $context
        #puts "Entering section $context : ($depth) $number"

        try {
            if {$upto eq ""} {                                  ;# ready to run this section, whatever it is
                try {
                    uplevel 1 $script
                } trap {FIX ASSERT FAIL} {err eopt} {
                    puts "FAIL: $testname $context:  $err"
                    puts " at [dict get $eopt -location]"
                } on ok {} {
                    puts "PASS: $testname $context"
                } finally {
                    if {$context eq $mycontext} {                   ;# is this a leaf section?
                        set upto $context                               ;# record that we ran it
                        lappend sections $context
                    }
                }
            } elseif {$upto eq $context} {                      ;# ran this section on the previous iteration
                set upto ""                                         ;# follow the next branch!
            } elseif {[lmatch [concat $context **] $upto]} {    ;# last run was a child of this section
                uplevel 1 $script
                if {$upto eq ""} {                              ;# did our last child just execute?
                    set upto $mycontext                             ;# then this section is complete!
                }
            } else {                                            ;# $upto must be a future section
            }
        } finally {
            incr depth -1       ;# don't reset $context or $number - caller must see it
        }
    }

    # When actually running the tests, errors need to be handled.
    # {FIX ASSERT FAIL} errors need to be trapped by the innermost
    # section, where they can be reported and then we simply return
    # to the enclosing scope for cleanup and running the rest of
    # the suite.
    # Other errors should not be trapped: they indicate setup/teardown
    # has gone wrong, and the world might be in an inconsistent
    # state.
    #
    # This bakes in a couple of assumptions:
    #  - the first [assert] failure in a [section] is what's reported
    #  - cleanup is robust against inner [section]s' [assert] failures
    # which is similar to tcltest's requirements of -setup -cleanup.
    method assert {cond {msg ""}} {
        set rc [uplevel 1 [list ::expr $cond]]
        if {!$rc} {
            if {$msg eq ""} {
                set msg [list $cond [uplevel 1 [list ::subst -noc -nob $cond]]]
            } else {
                set msg [list $msg [uplevel 1 [list ::subst -noc -nob $cond]]]
            }
            # capture error location from [info frame]
            set f 0
            while 1 {
                set frame [info frame [incr f -1]]
                try {
                    set file [dict get $frame file]
                    set line [dict get $frame line]
                    break
                } on error {} continue
            }
            return -code error -errorcode {FIX ASSERT FAIL} -location $file:$line "Assertion failed: $msg"
        }
    }
}

Fixture create f
f tests "Counting" {
    incr a 1
    f section "one" {
        incr b 1
        f assert {$a == $b}
    }
    f section "two" {
        incr b 1
        f assert {$a != $b}
    }
}
exit
f tests "The set" {
    f section "1" {
        puts "1>"
        f section "a" {
            puts "1.a>"
            f section "i" {
                puts "1.a.i"
            }
            f section "ii" {
                puts "1.a.ii"
            }
            puts "1.a<"
        }
        f section "A" {
            puts "-- interlude --"
        }
#        f section "b" {
#            puts "1.b>"
#            f section "i" {
#                puts "1.b.i"
#            }
#            f section "ii" {
#                puts "1.b.ii"
#            }
#            puts "1.b<"
#        }
        puts "1<"
    }
    f section "2" {
        puts "-- finale --"
    }
}
exit
f testset "The set" {
    f section "Top section" {
        puts start
        f section "Subsection one" {
            puts ONE!
        }
        f section "Subsection two" {
            puts TWO!
        }
        puts done
    }
}

exit

#
# From a test failure report, I want:
#  - the expression that failed
#    - substituted version .. or better, its environment
#  - sufficient information to find and read the text
#    - context stack
#    - names of all enclosing sections
#  - how to target this particular test
#    - its id, made by indexing all the enclosing sections
#
# I want to be able to target tests:
#  - individually, by id    x.y.z.w
#  - by globbing id         x.y.*
#  - by globbing name       /fixture/section/subsection
#
# BDD-style nesting:  given - when - then

namespace eval fix {
    proc fail {msg} {
        # find caller location
        set frame [info frame -2]
        set file [file tail [dict get $frame file]]
        set line [dict get $frame line]
        set msg [format {%s:%d %s} $file $line $msg]
        return -code error -level 2 -errorcode {FIX FAIL} $msg
    }
    proc assert {cond {msg ""}} {
        set rc [uplevel 1 [list ::expr $cond]]
        if {!$rc} {
            if {$msg eq ""} {
                set msg [list $cond [uplevel 1 [list ::subst -nocommands $cond]]]
            } else {
                set msg [list $msg [uplevel 1 [list ::subst -nocommands $cond]]]
            }
            fail "assert $msg"
        }
    }

    proc test_case {name body} {
        variable context [list "Test case: $name"]
        variable section {}
        variable depth -1
        tailcall try $body trap {eFIX FAIL} {msg eo} [format {
            #puts $eo; puts $msg; exit
            puts [info errorstack]
            dict append eo -errorinfo %s
            dict incr eo -level
            return -options $eo
        } [list "\nDuring test case: $context"]]
    }
    proc section {name body} {
        variable context
        variable section
        variable depth
        if {$depth < [llength $section]} {
            incr depth 1
            lappend section 0
        } else {
            lincr section $depth
            if {![Want $section]} return
            uplevel 1 $body
        }
    }
}

if {[info exists ::argv0] && $::argv0 eq [info script]} {
    fix::test_case "Basics" {
        fix::assert {1 == 0} "Arithmetic is unsound"
    }
}
