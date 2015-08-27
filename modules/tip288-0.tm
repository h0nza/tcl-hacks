if 0 {

    Extended TIP#288 Arguments

    == Summary

    This module implementes an extension of TIP#288 which can:

      * use "args" in any position in the argspec
      * use optional arguments (with defaults) on either side of "args"

    which is only a slight extension of TIP#288, and suggested by
    easy-to-understand parsing rules.

    Phrased negatively, we impose the following limitations:

      * "args" MAY appear anywhere in the arglist
      * optional arguments MAY appear immediately to the left AND right of "args"
      * required arguments MAY appear at the beginning AND end of the arglist

    Thus, the argspec looks something like:

      {?required ...? ?optional ...? ?args? ?optional ...? ?required ...?}
      {?required ...? ?optional ...? ?args? ?... optional? ?... required?}

    Parameters are assigned in the following order:

      * all required arguments are populated first (order doesn't matter)
      * optional arguments from the LHS, in left-to-right order
      * optional arguments from the RHS, in right-to-left order
      * "args" receives any remaining parameters

    See the tests for some practical (and pathological) examples.  The obvious
    examples all make sense, and the non-obvious can prove useful.


    == Interface

    This script exports:

      tip288::arguments argspec  
                        
        Parses $args according to argspec, setting local variables (and 
        unsetting args) as appropriate.
        
        If matching fails, throws {TCL WRONGARGS} with an appropriate 
        message from the caller's level.  To catch this, one must trap
        return!

      tip288::argdict   argspec arglist

        As above, but returns a dictionary instead of setting locals.
        Will not inspect the stack to put a command name in the message.

      tip288::argscript argspec

        Returns a script which does the same as [tip288::arguments argspec].
        Useful in a "semi-compiled procs" scenario.


    == Implementation Notes

    An argument position may be occupied by either:

      * a required argument (singleton)
      * an optional argument with a default (2-element list)
      * the word "args"

    An argument spec must match the grammar:

      argspec  ::= required* optional* args? optional* required*
      required ::= name
      optional ::= {name default}
      args     ::= "args"

    Thus, "args" can occur in any position, and optional arguments may appear on
    both sides of args.

    The rules for parsing:

      * separate the argspec into {req_l opt_l args opt_r req_r}
      * fail fast if too few or too many args for spec
      * assign required args from the left
      * assign required args from the right
      * assign optional args from the left
      * assign optional args from the right
      * if "args" requested:
        * collect remainder in args
      * else:
        * error if args remain to consume
        * unset args

    This turns out remarkably easy to slice into two parts.  The argspec is parsed
    by a linear state machine into these five parts (ParseArgspec), which are then 
    given to GenArgParser which constructs a script that will set the appropriate
    local variables, or throw {TIP#288 WRONGARGS}.

    To construct the script we use a pipeline operator [~>] which conveniently
    captures the sequence of operations without having to use named variables
    (which might clash).  In ~> arguments, "~" refers to the result of the 
    previous command;  arguments without "~" are taken as cmdPrefixes.  The
    pipelines weaves [lassign], [apply] and [lreverse] to unpack arguments
    quasi-recursively.
}

namespace eval tip288 {

    # creates pipelines of commands from lists
    # this is also known by names such as [pipe] and [cmdpipe]
    proc ~> args {
        set anonvar ~
        set args [lassign $args body]
        foreach cmd $args {
            if {[string first $anonvar $cmd] >= 0} {
                set body [string map [list $anonvar "\[$body\]"] $cmd]
            } else {
                set body "$cmd \[$body\]"
            }
        }
        set body
    }

    proc ParseArgspec {argspec} {
        set rules {
            req_l   {$a ne "args" && [llength $a] == 1}
            opt_l   {[llength $a] == 2}
            args    {$a eq "args"}
            opt_r   {[llength $a] == 2}
            req_r   {$a ne "args" && [llength $a] == 1}
        }
        foreach {set _} $rules {set $set ""}
        set i 0
        foreach {set expr} $rules {
            while 1 {
                set a [lindex $argspec $i]
                if $expr {
                    lappend $set $a
                    incr i
                } else {
                    break
                }
            }
        }
        if {[llength $args] > 1} {
            throw {TCL BAD ARGSPEC} "args can only occur once!"
        }
        if {$i != [llength $argspec]} {
            throw {TCL BAD ARGSPEC} "did not consume whole argspec!"
        }
        foreach name [concat $req_l $opt_l $args $opt_r $req_r] {
            if {[incr used($name)] > 1} {
                throw {TCL BAD ARGSPEC} "repeated name in argspec: $name {$used}"
            }
        }

        list $req_l $opt_l $args $opt_r $req_r
    }

    # stub of a version using [options::arguments]
    # UNUSED
    proc 0GenArgParser {rl ol as or rr} {
        set or [lreverse $or]       ;# we consume these reversed
        set rr [lreverse $rr]
        set script ""
        if {$rl ne ""} {
            lappend script [list    arguments [concat $rl args] ]
        }
        if {$rr ne ""} {
            lappend script {        set args [lreverse $args] }
            lappend script [list    arguments [concat $rr args] ]
            if {$ol ne ""} {
                lappend script {    set args [lreverse $args] }
            }
        }
        if {$ol ne ""} {
            lappend script [list    arguments [concat $ol args] ]
        }
        if {$or ne ""} {
            if {$ol ne ""} {
                lappend script {    set args [lreverse $args] }
            }
            lappend script [list    arguments [concat $ol args] ]
            if {$as ne ""} {
                lappend script  {   set args [lreverse $args] }
            }
        }
        if {$as eq ""} {
            lappend script  {       if {$args ne ""} {throw {TIP#288 WRONGARGS ""}} }
            lappend script  {       unset args }
        }
        return "$precheck;[join $script ;]"
    }

    # we name things differently here:
    #   {required left} {optional left} {args} {optional right} {required right}
    proc GenArgParser {rl ol as or rr} {
        set or [lreverse $or]       ;# we consume these reversed
        set rr [lreverse $rr]

        set olnames [lmap x $ol      {lindex $x 0}]             ;# arg names
        set ollist  [lmap x $olnames {string cat \$ [list $x]}] ;# list of values
        set ollist  [join $ollist \ ]   ;# as a script (fragment)

        set ornames [lmap x $or      {lindex $x 0}]             ;# arg names
        set orlist  [lmap x $ornames {string cat \$ [list $x]}] ;# list of values
        set orlist  [join $orlist \ ]   ;# as a script (fragment)

        set minlen [expr {[llength $rl] + [llength $rr]}]       ;# precheck for sufficient args
        if {$ol eq "" && $or eq "" && $as eq ""} {
            set op !=
        } else {
            set op <
        }
        set precheck [subst -noc        {if {[llength \$args] $op $minlen} {throw {TIP#288 WRONGARGS} ""}}]
        if {$as eq ""} {
            set maxlen [expr {$minlen + [llength $ol] + [llength $or]}]
            append precheck [subst -noc {;if {[llength \$args] > $maxlen} {throw {TIP#288 WRONGARGS} ""}}]
        }

        set script {}
        lappend script  [subst          {set args}                          ]

        if {$rl ne ""} {
            lappend script  [subst      {lassign ~ $rl}                     ]
        }

        if {$rr ne ""} {
            lappend script  [subst      {lreverse}                          ]
            lappend script  [subst      {lassign ~ $rr}                     ]
            lappend script  [subst      {lreverse}                          ]
        }

        if {$ol ne ""} {
            if {$or eq "" && $as eq ""} {
                lappend script [subst   {apply {{$ol} {list $ollist}} {*}~} ]
            } else {
                lappend script [subst   {apply {{$ol args}\
                                            {list $ollist {*}\$args}} {*}~} ]
            }
            lappend script  [subst      {lassign ~ $olnames}                ]
        }

        if {$or ne ""} {
            lappend script  [subst      {lreverse}                          ]
            if {$as eq ""} {
                lappend script [subst   {apply {{$or} {list $orlist}} {*}~} ]
            } else {
                lappend script [subst   {apply {{$or args}\
                                            {list $orlist {*}\$args}} {*}~} ]
            }
            lappend script  [subst      {lassign ~ $ornames}                ]
            lappend script  [subst      {lreverse}                          ]
        }

        if {$as ne ""} {
            lappend script  [subst  {set args}                          ]
        } else {
            lappend script  [subst  {if {~ ne ""} {throw {TIP#288 WRONGARGS} ""} {unset args}}]
        }
        return "$precheck;[~> {*}$script]"
    }

    proc argscript {argspec} {
        set parser [GenArgParser {*}[ParseArgspec $argspec]]
        list try $parser trap {TIP#288 WRONGARGS} {} [format {
            return -code error -errorcode {TCL WRONGARGS} %s
        } [list "wrong # args: should be \"[formatArgspec $argspec]\""]]
    }
    proc arguments {argspec} {
        set parser [GenArgParser {*}[ParseArgspec $argspec]]
        tailcall try $parser trap {TIP#288 WRONGARGS} {} [format {
            set me [lindex [info level 0] 0]
            return -code error -errorcode {TCL WRONGARGS} [string cat %s $me \  %s]
        } [list "wrong # args: should be \""]  [list [formatArgspec $argspec]\"]]
    }

    proc formatArgspec {argspec} {
        join [lmap arg $argspec {
            if {[llength $arg]>1} {
                string cat "?[lindex $arg 0]?"
            } elseif {$arg eq "args"} {
                string cat "?arg ...?"
            } else {
                string cat $arg
            }
        }] " "
    }

    proc locals {} {
        set res {}
        foreach var [uplevel 1 {info locals}] {
            upvar 1 $var upvar
            dict set res $var $upvar
        }
        return $res
    }

    proc argdict {argspec formalargs} {
        apply [list args "[list arguments $argspec];locals" [namespace current]] {*}$formalargs
    }

    namespace export arguments argscript argdict
}

if {[info exists ::argv0] && [info script] == $::argv0} {
    proc assert {expr} {
        if {![uplevel 1 [list expr $expr]]} {
            return -code error "ASSERT FAILURE: [uplevel 1 [list subst -noc $expr]]"
        }
    }
    proc dict_eq {a b} {
        expr {[lsort -stride 2 $a] eq [lsort -stride 2 $b]}
    }
    package require tcltest
    namespace import -force ::tcltest::test
 
    proc dotest_args {argspec arglist expected} {
        try {
            set result [tip288::argdict $argspec $arglist]
            if {![dict_eq $result $expected]} {
                puts "Expected: $expected"
                puts "Actual:   $result"
            }
        } trap {TCL WRONGARGS} {} {
            set result ERROR
            if {$result ne $expected} {
                puts "Got ERROR when expecting:  $expected"
            }
        }
    }
    proc mktest_args {name title argspec tests} {
        foreach {arglist expected} $tests {
            test $name-[incr i] "$title ($i): [list $arglist]" -body [
                list dotest_args $argspec $arglist $expected
            ] -output ""
        }
    }
    mktest_args argparser-0 "Pathological arglist" {a b {c _c} {d _d} args {e _e} {f _f} g h} {
            {1 2 3}                 ERROR
            {1 2 3 4}               {a 1 b 2 c _c d _d e _e f _f g 3  h 4  args {}}
            {1 2 3 4 5}             {a 1 b 2 c 3  d _d e _e f _f g 4  h 5  args {}}
            {1 2 3 4 5 6}           {a 1 b 2 c 3  d 4  e _e f _f g 5  h 6  args {}}
            {1 2 3 4 5 6 7}         {a 1 b 2 c 3  d 4  e _e f 5  g 6  h 7  args {}}
            {1 2 3 4 5 6 7 8}       {a 1 b 2 c 3  d 4  e 5  f 6  g 7  h 8  args {}}
            {1 2 3 4 5 6 7 8 9}     {a 1 b 2 c 3  d 4  e 6  f 7  g 8  h 9  args 5}
            {1 2 3 4 5 6 7 8 9 0}   {a 1 b 2 c 3  d 4  e 7  f 8  g 9  h 0  args {5 6}}
    }

    if 0 {
        proc lgurka args {
            options {-apa 1 -bepa "" -cepa 0}
            arguments {list item}
        }
    }
    test argparser-tip288-1 "examples from TIP#288" -body {
        # we deviate from TIP#288 in one respect:  {args} is formatted
        # in error messages as "?arg ...?" (consistent with proc)
        # rather than "?args?" or "..." as the TIP examples show
        proc x args {
            tip288::arguments {a args b}
            return "a=$a, args=$args, b=$b"
        }
        proc y args {
            tip288::arguments {a {b x} args c}
            return "a=$a, b=$b, args=$args, c=$c"
        }
        proc z args {
            tip288::arguments {a {b x} c args}
        }
        foreach {test output} {
            {x 1 2}     {a=1, args=, b=2}
            {x 1 2 3}   {a=1, args=2, b=3}
            {x 1}       {wrong # args: should be "x a ?arg ...? b"}
            {y 1 2 3}   {a=1, b=2, args=, c=3}
            {z}         {did not consume whole argspec!}
        } {
            catch $test res
            assert {$res eq $output}
        }
    }

    mktest_args argparser-noargs "No arguments" {} {
        {}      {}
        1       ERROR
        {1 2}   ERROR
    }

    test argparser-left-2 "left only" -body {
        proc stup args {tip288::arguments {{chan stdout} line}; tip288::locals}
        lsort -stride 2 [stup foo bar]
    } -result {chan foo line bar}

    test argparser-left-1 "left only" -body {
        lsort -stride 2 [stup foo]
    } -result {chan stdout line foo}
    test argparser-left-0 "left only" -body {
        catch {lsort -stride 2 [stup]}
    } -result 1

    mktest_args argparser-left-9 "left only" {{chan stdout} text} {
        {}  ERROR
        {foo} {chan stdout text foo}
        {foo bar} {chan foo text bar}
        {foo bar baz} ERROR
    }

    test argparser-error-1 "not enough args" -body {
        proc t args {
            tip288::arguments {foo}
        }
        list [catch t r o] $r [dict get $o -errorcode]
    } -result {1 {wrong # args: should be "t foo"} {TCL WRONGARGS}}
    test argparser-error-2 "too many args" -body {
        list [catch {t a b} r o] $r [dict get $o -errorcode]
    } -result {1 {wrong # args: should be "t foo"} {TCL WRONGARGS}}
    test argparser-error-same "same error as proc" -body {
        proc t foo {}
        set r0 [list [catch t r o] $r [dict get $o -errorcode]]
        proc t args { tip288::arguments {foo} }
        set r1 [list [catch t r o] $r [dict get $o -errorcode]]
        expr {$r0 eq $r1}
    } -result 1
    puts "tests finished"
}
