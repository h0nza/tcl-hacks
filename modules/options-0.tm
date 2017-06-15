#!/usr/bin/tclsh

# neat little options/arguments parser I apparently wrote.
# commented sections are questionable support for validation of arguments (not opts - conflicts with multi-value form).
#
# Crazy ideas:
#   composition of interfaces:  {-quickly -with alacrity} make it tricky and benefiting from [prefix match] requires a model

package require fun

namespace eval options {

    proc chuck args {   ;# copied from fun-0.tm to decouple dependency
        set args [lreverse [lassign [lreverse $args] msg code]]
        tailcall return {*}$args -code error -errorcode $code $msg
    }

    proc ?- {option} {          ;# [?- quickly ] == $quickly ? "-quickly" : ""
        upvar 1 $option opt
        if {$opt} {
            return [list -$opt]
        } else {
            return ""
        }
    }

    proc lshift {varName} {     ;# removes & returns first element of $varName, or throws {LSHIFT EMPTY}
        upvar 1 $varName list
        if {$list eq ""} {
            throw {LSHIFT EMPTY} "Attempted to shift empty list!"
        }
        set list [lassign $list result]
        return $result
    }


    # taking each optspec as an argument is {convenient}, but options really wants .. options!
    #  options ?-args args? ?-exact|-error x|-message y? optspec
    #
    # An optspec is a list of lists describing options.
    #
    #   eatopts {
    #     {-quickly} 
    #     {-with ease} 
    #     {-by road tram walk}
    #   }
    #
    # declares three options and their corresponding variables, "quickly", "with" and "by".
    # $quickly will be 1 if "-quickly" is provided, else 0.
    # "-with" takes an extra argument, and has default value "ease".
    # "-by" takes an argument that must be one of {road tram walk}.  If not provided, $by eq "road".
    #
    # An optspec list can contain "--", indicating that if "--" is seen options processing should stop 
    # and remaining arguments be left in "argsvar".
    #
    proc eatopts {args} {
        set optspec [lindex $args end]
        set argv [lrange $args 0 end-1]

        # parse our own options, first-principles style
        set _opts {args args message "option" error {-errorcode {TCL WRONGARGS}} exact 0 script 0}
        set keys [lsort -dictionary [lmap o [dict keys $_opts] {string cat - $o}]]
        dict with _opts {
            while {$argv ne ""} {
                set arg [lshift argv]
                switch -exact [::tcl::prefix::match -error {-errorcode {TCL WRONGARGS}} -message option $keys $arg] {
                    -args       { set args      [lshift argv] }
                    -message    { set message   [lshift argv] }
                    -error      { set error     [lshift argv] }
                    -script     { set script    1 }
                    -exact      { set exact     1 }
                }
            }
        }
        unset _opts

        # our version:
        #   eatopts {  {-args args}  {-message option}  {-error {-errorcode TCL WRONGARGS}}  -exact  }

        # We will fill in this template to match, with care to create no named temporaries.
        # Using [subst -noc] should keep us honest.
        set MACRO {
            $DEFAULTS
            while {\$args ne ""} {
                switch -exact [::tcl::prefix::match -error $ERROR -message $MESSAGE $KEYS [::options::lshift args]] {
                    $SWITCH
                    -- break
                }
            }
        }

        foreach spec $optspec {
            set spec [lassign $spec opt]
            lappend KEYS $opt
            if {$opt eq "--"} continue          ;# special-cased in macro.
            set name [string range $opt 1 end]
            switch -exact [llength $spec] {
                0 {             ;#  {-flag}: consumes no args, boolean $flag
                    append DEFAULTS [list set $name 0]\;
                    lappend SWITCH $opt [format {
                                incr %s 1
                    } [list $name]]
                }
                1 {             ;# {-option default}: consumes an arg
                    set default [lindex $spec 0]
                    append DEFAULTS [list set $name $default]\;
                    lappend SWITCH $opt [format {
                            set %s [::options::lshift args]
                    } [list $name]]
                }
                default {       ;# {-enum red green blue}: default first
                    set default [lindex $spec 0]
                    set values [lsort -dictionary $spec]
                    append DEFAULTS [list set $name $default]\;
                    lappend SWITCH $opt [format {
                            set %s [::tcl::prefix match \
                                    -error {-errorcode {TCL WRONGARGS}} \
                                    -message %s \
                                    %s [::options::lshift args]]
                    } [list $name] [list [format {value for "%s"} $opt]] [list $values]]
                }
            }
        }

        set KEYS        [list   [lsort -dictionary $KEYS]]
        set MESSAGE     [list   $message]
        set ERROR       [list   $error]
        set SCRIPT [subst -nocommands $MACRO]
        if {$script} {
            return $SCRIPT
        }
        tailcall try $SCRIPT
    }

    # -eat: boolean
    # -with fire: defaulted free
    # -by tram boat bike: defaulted enum
    proc options {args} {
        set R [dict create]     ;# result goes here
        set specs {}
        foreach optspec $args {
            set spec [lassign $optspec opt]
            set name [string range $opt 1 end]
            switch [llength $spec] {
                0       { set default 0 }
                1       { set default [lindex $spec 0] }
                default {
                    set default [lindex $spec 0]
                    set spec [lsort -dictionary $spec]  ;# only length matters!
                }
            }
            dict set specs $opt $spec
            dict set R $name $default
        }
        set keys [lsort -dictionary [dict keys $specs]]

        # get caller's args
        upvar 1 args argv
        while {$argv ne ""} {
            # FIXME: this is a dramatic flaw in the way I've been using [options]!
            if {![string match -* [lindex $argv 0]]} {
                break
            }
            set arg [lshift argv]
            set opt [::tcl::prefix match \
                        -error {-errorcode {TCL WRONGARGS}} \
                        -message "option" \
                        $keys $arg]
            set spec [dict get $specs $opt]
            set name [string range $opt 1 end]
            switch [llength $spec] {
                0       { set val 1 }
                1       { set val [lshift argv] }
                default { set val [::tcl::prefix match \
                                -error {-errorcode {TCL WRONGARGS}} \
                                -message "value for $opt" \
                                $spec [lshift argv]]
                }
            }
            dict set R $name $val
        }
        dict set R args $argv
        tailcall mset {*}$R
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
#tcl::tm::path add [pwd]
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

    set setup {
        proc t {args} {
            options {-quickly} {-with ease alacrity charm alarm} {-willingly yes}
            list quickly $quickly with $with willingly $willingly
        }
    }
    set cleanup {
        rename t {}
    }
    test options-1.1 {basic options test} -setup $setup -cleanup $cleanup -body {
        t
    } -result {quickly 0 with ease willingly yes}
    test options-1.2 {basic options test} -setup $setup -cleanup $cleanup -body {
        t -with charm
    } -result {quickly 0 with charm willingly yes}
    test options-1.3 {basic options test} -setup $setup -cleanup $cleanup -body {
        t -with alar
    } -result {quickly 0 with alarm willingly yes}

    test options-1.4 {basic options test} -setup $setup -cleanup $cleanup -body {
        list [catch {t -wi} e o] $e [dict get $o -errorcode]
    } -result {1 {ambiguous option "-wi": must be -quickly, -willingly, or -with} {TCL WRONGARGS}}
    # {} -result {1 {ambiguous option "-wi": must be -quickly, -with, or -willingly} {TCL WRONGARGS}}
    test options-1.5 {basic options test} -setup $setup -cleanup $cleanup -body {
        list [catch {t -with a} e o] $e [dict get $o -errorcode]
    } -result {1 {ambiguous value for -with "a": must be alacrity, alarm, charm, or ease} {TCL WRONGARGS}}
}

#puts [options::eatopts -script -exact {{-quickly} {-with ease alacrity charm alarm} {-willingly yes}}]
