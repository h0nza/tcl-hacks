
namespace eval Parser {

    namespace export *

;# utility:
    proc debug {args} {
        set i [string repeat "  " [info level]]
        set msg [lmap s $args {uplevel 1 [list subst $s]}]
        set w [lindex [info level -1] 0]
        puts "D:$i$w = $msg"
    }
    proc debug args {}
    proc _quote_regex {str} { regsub -all {[][$^?+*()|\\.]} $str {\\\0} }
    proc alias {alias cmd args} {
        if {![string match ::* $alias]} {
            set alias [uplevel 1 {namespace current}]::$alias
        }
        if {![string match ::* $cmd]} {
            set c [uplevel 1 [list namespace which $cmd]]
            if {$c eq ""} {
                return -code error "Could not resolve $cmd!"
            }
            set cmd $c
        }
        tailcall interp alias {} $alias {} $cmd {*}$args
    }

;# fancy result threading:
    alias return tailcall lappend 0
    proc --return args {
        debug log {[string repeat "  " [info level]][info level -1]: [uplevel 1 {list $i $s}] -> $args}
        tailcall tailcall lappend 0 {*}$args
    }
;# commands to define parsers:
    proc space {} {}    ;# default space is a noop
    proc space {} { ;# for RC we want a better space
        upvar 1 s s i i
        incr i [string length [lindex [regexp -inline -start $i {\s*} $s] 0]]
        return
    }
    proc %space {re} {
        set re \\A(?:$re)
        tailcall proc space {} [format {
            upvar 1 s s i i
            incr i [string length [lindex [regexp -inline -start $i %s $s] 0]]
            return
        } [list $re]]
    }

    proc %token {name re {result "set 0"}} {
        set re \\A(?:$re)
        tailcall proc $name {} [format {
            upvar 1 s s i i
            space
            debug log {entering: $i "[string index $s $i]"}
            if {[regexp -start $i %s $s 0 1 2 3 4 5 6 7 8 9]} {
                incr i [string length $0]
                debug log {success: $i -> "$0"}
                return [%s]
            } else fail
        } [list $re] $result]
                #return [list %s]
    }

    alias %result variable %result
    #proc %rule {name script {result "return $0"}} {}
    proc %rule {name script args} {
        if {[llength $args] > 1} {return -code error "wrong # args: expected \"%rule name script ?return?\""}
        if {$args eq ""} {
            namespace upvar [uplevel 1 {namespace current}] %result %result
            if {[info exists %result]} {
                set result ${%result}
            } else {
                set result "list [list $name] \$0"
            }
        } else {
            set result [lindex $args 0]
        }
        if {"" eq [uplevel 1 {namespace which __Start}]} {
            uplevel 1 %start $name
        }
        tailcall proc $name {} [format {
            upvar 1 s s i i; lappend 0
            space
            debug log {entering: $i "[string index $s $i]"}
            %s
            lassign $0 1 2 3 4 5 6 7 8 9
            debug log {success: $i -> [list $0]}
            return [%s]
        } $script $result]
            #return [list %s]
    }
    proc %start {rule} {
        tailcall proc __Start {s {i 0} {0 ""}} [format {
                %s; end
        } [list $rule]]
    }
;# commands for use within parsers -- subcommand capture

;# commands for use within parsers -- control structures
    #alias fail throw {PARSER FAIL} "failed to parse"
    alias fail try {throw {PARSER FAIL} "Failed to parse at $i \"[string range $s $i $i+10]\""}
    proc any {args} {
        upvar 1 s s i i 0 0; lappend 0
        set i0 $i; set o0 $0
        foreach script $args {
            try {
                uplevel 1 $script
                return
            } trap {PARSER FAIL} {e o} {
                set i $i0; set 0 $o0
                continue
            }
        }
        fail
    }
    proc seq {args} {
        upvar 1 s s i i 0 0; lappend 0
        set i0 $i; set o0 $0
        try {
            return {*}[lmap script $args {
                uplevel 1 $script
            }]
        } trap {PARSER FAIL} {} {
            set i $i0; set 0 $o0
            fail
        }
    }
    proc opt {script} {
        upvar 1 s s i i 0 0; lappend 0
        set i0 $i; set o0 $0
        try {
            uplevel 1 $script
        } trap {PARSER FAIL} {} {
            set i $i0; set 0 $o0
            return ""   ;# empty result for failure
        }
    }
    proc many {script} {
        upvar 1 s s i i 0 0; lappend 0
        set res {}
        set o0 $0; set 0 {}
        while 1 {
            set i0 $i
            try {
                #set res [uplevel 1 $script]
                set 0 {}
                uplevel 1 $script
                lappend res {*}$0
            } trap {PARSER FAIL} {} {
                set i $i0
                break
            }
        }
        set 0 $o0
        return $res
    }
    proc many1 {script} {
        tailcall seq $script [list many $script]
    }
;# actual matchers -- returning nothing
    proc end {} {
        upvar 1 s s i i
        if {$i != [string length $s]} fail
        return
    }
    proc drop {n} {
        upvar 1 s s i i
        if {$i + $n > [string length $s]} fail
        incr i $n
        return
    }
    proc lit {v} {
        upvar 1 s s i i
        set len [string length $v]
        if {[string equal -length $len $v  [string range $s $i end] ]} {
            incr i $len
            return
        } else fail
    }
    alias ws if {[regexp {^\s+} $s match]} {
        incr i [string length $match]
    }
;# actual matchers -- returning literal results
    proc take {n} {
        upvar 1 s s i i
        set j [expr {$i + $n}]
        if {$j > [string length $s]} fail
        return [string range $s $i [expr {[set i $j]-1}]]
    }
    proc tok {v} {
        upvar 1 s s i i
        set len [string length $v]
        if {[string equal -length $len $v  [string range $s $i end] ]} {
            incr i $len
            return $v
        } else fail
    }
    proc re {re} {
        upvar 1 s s i i
        set re \\A(?:$re)
        if {[regexp -start $i $re $s match]} {
            incr i [string length $match]
            return $match
        } else fail
    }

;# constructor:  create a namespace, set its path and alias to __start
    proc Parser {name script} {
        set ns [uplevel 1 namespace current]
        if {$ns eq "::"} {set ns ""}
        set name ${ns}::$name
        namespace eval $name [list namespace path [namespace current]]
        proc ${name}::end {} {
            upvar 1 s s i i
            space
            if {$i != [string length $s]} fail
            return
        }
        #alias end if {$i != [string length $s]} fail else {set 0}
        proc ${name}::token {v} {
            upvar 1 s s i i
            space; tailcall lit $v
        }
        proc ${name}::token! {v} {
            upvar 1 s s i i
            space; tailcall tok $v
        }
        namespace eval $name $script
        alias $name ${name}::__Start
    }

}

namespace import Parser::Parser

