#!/usr/bin/tclsh

# neat little options/arguments parser I apparently wrote.
# commented sections are questionable support for validation of arguments (not opts - conflicts with multi-value form).

namespace eval options {

    proc chuck args {   ;# copied from fun-0.tm to decouple dependency
        set args [lreverse [lassign [lreverse $args] msg code]]
        tailcall return {*}$args -code error -errorcode $code $msg
    }

    proc options {args} {
        # parse optspec
        foreach optspec $args {
            set name [lindex $optspec 0]
            switch [llength $optspec] {
                1 {
                    dict set opts $name type 0 ;# flag
                    dict set result [string range $name 1 end] 0
                    #dict set opts $name value 0
                } 
                2 {
                    dict set opts $name type 1 ;# arbitrary value
                    dict set opts $name default [lindex $optspec 1]
                    dict set result [string range $name 1 end] [lindex $optspec 1]
                    #dict set opts $name value [lindex $optspec 1]
                }
                default {
                    dict set opts $name type 2 ;# choice
                    dict set opts $name default [lindex $optspec 1]
                    dict set opts $name values [lrange $optspec 1 end]
                    dict set result [string range $name 1 end] [lindex $optspec 1]
                }
            }
        }
        # get caller's args
        upvar 1 args argv
        for {set i 0} {$i<[llength $argv]} {} {
            set arg [lindex $argv $i]
            if {![string match -* $arg]} {
                break
            }
            incr i
            if {$arg eq "--"} {
                break
            }
            set candidates [dict filter $opts key $arg*]
            switch [dict size $candidates] {
                0 {
                    tailcall chuck {TCL WRONGARGS} "Unknown option $arg: must be one of [dict keys $opts]"
                }
                1 {
                    dict for {name spec} $candidates {break}
                    set name [string range $name 1 end]
                    dict with spec {} ;# look out
                    if {$type==0} {
                        dict set result $name 1
                        #dict set opts $name value 1
                    } else {
                        if {[llength $argv]<($i+1)} {
                            tailcall chuck {TCL WRONGARGS} "Option $name requires a value"
                        }
                        set val [lindex $argv $i]
                        if {$type==2} {
                            # FIXME:?  ::tcl::prefix match -message $name
                            set is [lsearch -all -glob $values $val*]
                            switch [llength $is] {
                                1 {
                                    set val [lindex $values $is]
                                }
                                0 {
                                    tailcall chuck {TCL WRONGARGS} "Bad $name \"$val\": must be one of $values"
                                }
                                default {
                                    tailcall chuck {TCL WRONGARGS} "Ambiguous $name \"$val\": could be any of [lmap i $is {lindex $values $i}]"
                                }
                            }
                        }
                        dict set result $name $val
                        incr i
                    }
                }
                default {
                    tailcall chuck {TCL WRONGARGS} "Ambiguous option $arg: maybe one of [dict keys $candidates]"
                }
            }
        }
        dict set result args [lrange $argv $i end]
        tailcall mset {*}$result
    }

    proc formatArgspec {argspec} {
        join [lmap arg $argspec {
            if {[llength $arg]>1} {
                string cat "?[lindex $arg 0]?"
            } elseif {$arg eq "args"} {
                string cat "?args ...?"
            } else {
                string cat $arg
            }
        }] " "
    }

    proc arguments {argspec} {
        upvar 1 args argv
        for {set i 0} {$i<[llength $argv]} {incr i} {
            if {$i >= [llength $argspec]} {
                tailcall chuck {TCL WRONGARGS} "wrong # args: should be \"[lindex [info level -1] 0] [formatArgspec $argspec]\""
            }
            set name [lindex $argspec $i 0]
            if {$name eq "args"} {
                dict set result args [lrange $argv $i end]
                tailcall mset {*}$result
            }
            set value [lindex $argv $i]
#            set test [lindex $argspec $i 2]
#            if {$test != ""} {
#                set valid [uplevel 1 $test $value]
#                if {!$value} {
#                    tailcall chuck {TCL WRONGARGS} "Invalid $name \"$value\", must be $test"
#                }
#            }
            dict set result $name $value
        }
        # defaults:
        for {} {$i < [llength $argspec]} {incr i} {
            set as [lindex $argspec $i]
            if {[llength $as]==1} {
                if {$as ne "args"} {
                    tailcall chuck {TCL WRONGARGS} "wrong # args: should be \"[lindex [info level -1] 0] [formatArgspec $argspec]\""
                }
                dict set result args [lrange $argv $i end]
                break
            }
            lassign $as name value
#            set test [lindex $argspec $i 2]
#            if {$test != ""} {
#                set valid [uplevel 1 $test $value]
#                if {!$value} {
#                    tailcall chuck {TCL WRONGARGS} "Invalid $name \"$value\", must be $test"
#                }
#            }
            dict set result $name $value
        }
        unset argv  ;# uplevel 1 unset args
        if {![info exists result]} {return}
        tailcall mset {*}$result
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

    proc multiargs {args} {
        if {[llength $args]==1} {
            set args [lindex $args 0]
        }
        foreach {argspec body} $args {
            try {
                uplevel 1 [list arguments $argspec]
            } on return {e o} {
                ;# ??  if {[dict get $o -errorcode] ne {TCL WRONGARGS}} { return {*}$o $e }
                lappend errs [string range $e [string first \" $e] end]
            } on ok {} {
                tailcall try $body
            }
        }
        tailcall chuck {TCL WRONGARGS} "wrong # args: should be [join $errs " or "]"
    }

    ;# WARNING: not the same mset as in fun-0.tm!  This takes a dict, not a foreach arglist!
    proc mset args {
        #tailcall ::foreach {*}[dict map {k v} $args {set k [list $k]; list $v}] {}
        uplevel 1 ::foreach [dict map {k v} $args {set k [list $k]; list $v}] #
        return $args
    }
    if 0 {
    proc Options {args} {
        tailcall try [format {
            ::options::mset {*}[::options::Options %s]
        } $args]
    }
    proc Arguments {args} {
        tailcall try [format {
            ::options::mset {*}[::options::Arguments %s]
        } $args]
    }
    }

    namespace export options arguments multiargs
}

namespace import options::*

# -- tests only follow:
if {![info exists ::argv0] || $::argv0 ne [info script]} {
    return
}
tcl::tm::path add [pwd]
package provide options 0
package require tests


tests {
    package require textutil

    test options-level "" -body {
        proc a args {
            arguments {b c}
        }
        proc b args {
            try {
                a {*}$args
            } trap {TCL WRONGARGS} {e o} {
                return $e
            }
        }
        b
    } -result {wrong # args: should be "a b c"}

    test options-result "" -body {
        proc t {args} {
            concat [ options {-flag} {-flip {}} {-value 100} {-colour red green blue black}
                ]  [ arguments {rabbit {poo yes} args}
                ]
        }

        t 1 2 3
    } -result {flag 0 flip {} value 100 colour red args {1 2 3} rabbit 1 poo 2 args 3}
    ;# ^^ note the twice-appearing $args!

    test multiargs-error "" -body {
        proc t args {
            multiargs {a b c} {
                list $a $b $c
            } {a b} {
                list $a $b
            }
        }
        list [t b a] [catch {t a} e o] $e
    } -result {{b a} 1 {wrong # args: should be "t a b c" or "t a b"}}

    test multiargs-clearargs "clear args after parsing" -body {
        proc t args {
            arguments {a b}
            lsort [info locals]
        }
        t 1 2
    } -result {a b}

    test options-test "" -body {
        proc t {args} {
            options {-flag} {-flip {}} {-value 100} {-colour red green blue black}
            arguments {rabbit {poo yes} args}
            foreach name [info locals] {
                puts "$name = [set $name]"
            }
            puts {}
        }

        try {
            t hehe
            t -fla hehe
            t -fli lalala hehe
            t -val 230 hehe
            t hjg hgj hj ghjgjh
            t -col gr hg h
            t
        } trap {TCL WRONGARGS} {e o} {
            puts "e = $e"
        }
        string match {*"arguments*} [dict get $o -errorinfo]] ;#"
        #set o
    } -result 0 -output [string trim [textutil::undent {
        args = 
        rabbit = hehe
        colour = red
        value = 100
        poo = yes
        flag = 0
        flip = 

        args = 
        rabbit = hehe
        colour = red
        value = 100
        poo = yes
        flag = 1
        flip = 

        args = 
        rabbit = hehe
        colour = red
        value = 100
        poo = yes
        flag = 0
        flip = lalala

        args = 
        rabbit = hehe
        colour = red
        value = 230
        poo = yes
        flag = 0
        flip = 

        args = hj ghjgjh
        rabbit = hjg
        colour = red
        value = 100
        poo = hgj
        flag = 0
        flip = 

        args = 
        rabbit = hg
        colour = green
        value = 100
        poo = h
        flag = 0
        flip = 

        e = wrong # args: should be "t rabbit ?poo? ?args ...?"
    }]]\n
}
