# Non-standard extensions to core commands
# based on DKF's version from http://wiki.tcl.tk/15566
#
# Putting procs in the namespace is a bit unpleasant, with generic/reused names
#  (eg [array foreach])
#
package require fun
package require adebug

# helper to make quoting less odious
if {[info commands Uplevel] eq ""} {
    proc Uplevel {n args} {tailcall uplevel $n $args}
}

proc extend {ens script} {
    namespace eval $ens [concat {
        proc _unknown {ens cmd args} {
            if {$cmd in [::namespace eval ::${ens} {::info commands}]} {
                ::set map [::namespace ensemble configure $ens -map]
                ::dict set map $cmd ::${ens}::$cmd
                ::namespace ensemble configure $ens -map $map
            }
            ::return "" ;# back to namespace ensemble dispatch
        }
    }   \; $script]
    namespace ensemble configure $ens -unknown ${ens}::_unknown
}

extend dict {

    proc print {d args} {
        # get what $d looks like in our invocation:
        #set _ [lindex [cmd::wordSplit [dict get [info frame -1] cmd]] 2]
        #::array set _ $d
        #::parray _
        # copied from fun.tcl, pdict
        set maxl [::tcl::mathfunc::max {*}[map {string length} [dict keys $d]]]
        ;# [dict for] doesn't see duplicate elements, which I want to:
        foreach {key value} $d {
            puts stdout [format "%-*s = %s" $maxl $key $value]
        }
    }
    # returns "" if the path doesn't exist
    # note: this doesn't error if the 1st arg is not a dict
    proc get? {d args} {
        if {$args eq ""} {return $d}
        if {[dict exists $d {*}$args]} {dict get $d {*}$args}
    }

    # like dict get, but matches with glob patterns in the dict
    # *not* similar to [dict filter keys]
    proc glob {dict key args} {
        dict for {k v} $dict {
            if {[string match $k $key]} {
                if {$args eq ""} {
                    return $v
                } else {
                    tailcall [glob $dict {*}$args]
                }
            }
        }
    }

    # will only set if the kye doesn't already exist
    # .. I'm unsure if I want an [info exists d] check
    proc set! {_d args} {
        upvar 1 $_d d
        set v [lindex $args end]
        set args [lrange $args 0 end-1]
        if {(1 || [info exists d]) && [dict exists $d {*}$args]} {
            throw {ASSERT DICT KEY EXISTS} "Key $args exists in $_d!"
        }
        dict set d {*}$args $v
    }

    # if {[dict grab foo $d key]} {puts "foo = $foo"}
    proc grab {_varName args} {
        if {[dict exists {*}$args]} {
            upvar 1 [lindex $args end] var
            set var [dict get {*}$args]
            return 1
        } else {
            return 0
        }
    }

    # turns:  if {[dict exists $d {*}$k]} {set v [dict get $d {*}$k]; # do something with $v }
    # into:   dict use v $d {*}$k { # do something with $v }
    proc use {_name d args} {
        set script [lindex $args end]
        set args [lrange $args 0 end-1]
        if {[dict exists $d {*}$args]} {
            upvar 1 $_name var
            set var [dict get $d {*}$args]
            tailcall try $script
        }
    }

    proc search {d args} {  ;# returns a list of the numeric position of each key, -1 for not found
        debug what
        switch [llength $args] {
            0 {
                error "Incorrect arguments"
            }
            1 {
                lassign $args idx
                dict for {name _} $d [counting n {
                    if {$name eq $idx} {
                        return $n
                    }
                }]
                return -1
            }
            default {
                set args [lassign $args idx]
                dict for {name value} $d [counting n {
                    if {$name eq $idx} {
                        return [concat $n [::dict search $value {*}$args]]
                    }
                }]
                return -1
            }
        }
    }

    # [dict sort {*}{lsort args} $dict] -> creates a new dict with sorted keys
    proc sort {args} {
        set d [lindex $args end]
        set args [lrange $args 0 end-1]
        set r {}
        ::foreach {k} [lsort {*}$args [dict keys $d]] {
            dict set r $k [dict get $d $k]
        }
        return $r
    }

    # there is room for some sort of [dict apply] as well.  Colin's version is more like [dict with] + [apply] 
    # (https://code.google.com/p/wub/source/browse/Utilities/Dict.tcl)
    # than the idea I had of mapping keys to a command's named arguments.  Perhaps another name is needed.

    # dict lambda can create a lambdaexpr with the dict keys as params, defaulted to their values
    proc lambda {dict script} {
        tailcall ::lambda [lmap {k v} $dict {list $k $v}] $script
    }

    # from kap:
    # Beginnings of a [dict assign] like command
    # Updates a a dictionary and returns the remainder key value pairs
    # dictVarName - Dictionary to assign key value pairs to
    # args - ?key value ...?
    proc assign {dictVarName args} {
        upvar $dictVarName dictVar
        # Get the keys are not in dictVar
        set notin [dict remove $args {*}[dict keys $dictVar]]
        # Get the keys that are in dictVar
        set in [dict remove $args {*}[dict keys $notin]]
        # Merge the values for the keys that are in dictVar
        set dictVar [dict merge $dictVar $in]
        # Returns the keys that aren't in dictVar
        return $notin
    }

    # st {[dict keymap {a A b B} {a 1 b 2 c 3}] eq {A 1 B 2 C 3}}
    proc keymap {map d} {
        dict map {k v} $d {
            catch {
                set k [dict get $map $k]
            }
            set v
        }
    }

    # "safe" version of [dict with]:  FIXME untested
    # alternative:  [dict withonly {arglist} $dict ?key ...? { script }]
    proc with! {_dict args} {
        upvar 1 $_dict dict
        set script [lindex $args end]
        set keys [lrange $args 0 end-1]
        set names [dict keys [dict get $dict {*}$keys]]
        tailcall try [format {
            debug assert {![any {info exists} {%2$s}]}
            try {
                dict with %1$s
            } finally {
                unset %3%s
            }
        } [list $_dict {*}$args] [list $keys] $keys]
    }
}

extend array {  

    # like [dict with], but for an array
    # and without leaking.  So it needs a namespace argument
    proc with {_array script {ns ""}} {
        upvar 1 $_array a
        set prelude [lmap name [array names a] {
            list upvar 1 a($name) $name
        }]
        set prelude [join $prelude \n]
        set script $prelude\n$script
        if {$ns ne ""} {set ns [list $ns]}
        apply [list {} $script {*}$ns]
    }

    # returning the above's lambda could be interesting
    # .. troublesome if _array is a local though.

if 0 {
    proc for {vars _array script} {
        set names [expr {[llength $vars]==2 ? "get" : "names"}]
        tailcall ::foreach $vars [
            uplevel 1 array $names $_array
        ] $script
    }
}

    # this is just asking for trouble in an ensemble:
    #proc foreach args {tailcall for {*}$args}

    proc values {_array} {
        upvar 1 $_array a
        ::lmap k [array names a] {
            set a($k)
        }
    }

    # returns a list of keys whose values match any of the glob patterns in args
    proc find {_array args} {
        upvar 1 $_array array
        dict keys [dict filter [array get array] value  {*}$args]
    }

}

proc array_for {vars _array script} {
    set names [expr {[llength $vars]==2 ? "get" : "names"}]
    uplevel 1 [list ::foreach $vars [
        uplevel 1 array $names $_array
    ] $script]
}
namespace ensemble configure ::array -map [list for array_for {*}[
        namespace ensemble configure ::array -map
]]


if {[catch {string cat}]} {
    extend string {
        proc cat {args} {   ;# TIP 429
            join $args ""
        }
    }
}

extend string {
    proc insert {s i ins} { ;# like [linsert]   -- NEEDS TESTING
        if {![string is integer $i]} {
            regexp {^end(.*)$} $i -> ofs
            if {$ofs eq ""} {set ofs 0}
            incr ofs
            set i_ $i
            set i end+$ofs
        } else {
            set i_ [expr {$i-1}]
        }
        string cat [
            string range $s 0 $i_
        ] $ins [
            string range $s $i end
        ]
    }
}

extend info {
    proc formalargs {name} {    ;# TIP 65
        set procname [uplevel 1 namespace which -command [list $name]]
        if {$procname eq ""} {
            throw {TCL LOOKUP proc} "$name is not a procedure"
        }
        lmap argname [info args $procname] {
            if {[info default $procname $argname default]} {
                list $argname $default
            } else {
                list $argname
            }
        }
    }

    proc cmdexists {name} {
        expr {[Uplevel 1 namespace which -command $name] ne ""}
    }
}

extend namespace {
    # this should take an optional $ns argument, but I'm not sure on which side
    # nicely it doesn't need to distinguish between vars and commands
    proc qualify {name} {
        if {[string match ::* $name]} {
            debug log {WARNING: set name [namespace qualify $name] is a noop}
            return $name
        }
        set ns [uplevel 1 namespace current]
        if {$ns eq "::"} {set ns ""}
        string cat $ns :: $name
    } 

    proc join {prefix name} {
        if {[string match ::* $name]} {
            return $name
        }
        if {$prefix eq "::"} {
            return ::$name
        }
        return ${prefix}::$name
    }
    # the true complement of [namespace tail], in the sense that it returns ::
    # and [DUP prefix tail join] == [I]
    proc prefix {name} {
        string range $name 0 end-[string length [namespace tail $name]]
    }

    -- proc inheritpath args {
        switch [llength $args] {
            0 {set ns [namespace qualifiers [uplevel 1 {namespace current}]]}
            1 {set ns [lindex $args 0]}
            default {error "Incorrect arguments"}
        }
        if {$ns eq ""} {
            debug log {WARNING: inheriting path from :: in [info level -1]}
            set ns "::"
        }
        set p [namespace eval $ns {namespace path}]
        set p [linsert $p 0 $ns]
        set p [linsert $p 0 {*}[uplevel 1 {namespace path}]]
        debug log {Inheriting path $p <--- [uplevel 1 namespace current]}
        tailcall namespace path $p
    }

    proc pathinsert {pos ns args} {
        set args [list $ns {*}$args]    ;# it is an error to specify no namespaces
        uplevel 1 [format {
            namespace path [linsert [namespace path] %1$s %2$s]
        } [list $pos] $args]
    }
    proc pathdelete {args} {
#        uplevel 1 [pipe {
#                namespace path
#        } {*}[lmap n $args {string cat {
#                lsearch -exact -inline -all -not ~ $n
#           }}]]
        uplevel 1 [format {
            namespace path [ldiff [namespace path] %1$s]
        } [list $args]]
    }

    proc exportto {namespace cmd} {
        uplevel 1 [list namespace export $cmd]
        namespace eval $namespace [list namespace import [uplevel 1 {namespace current}]::$cmd]
    }
}

# this breaks tcltags. !!??!!?
extend ::oo::InfoObject {
    proc commands {o args} {
        map {::namespace tail} [info commands [info object namespace $o]::*]
    }
}
