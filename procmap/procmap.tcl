#
# The core of this is [procmap::whatnext $cmdPrefix]
# which returns a dictionary of info useful for completion.
# and [procmap::mapprocs], which parses argument errors.
# [procmap::procmap] obtains a starting point by chasing ensembles.
# But it really should come from {info commands}+{namespace children}
# 
# As a "generalised [info args]", it knows about:
#  * aliases
#  * ensembles
#  * objects (methods and forwards)
#  * widgets
#  * command prefixes
#
# A surprising wealth of information is available in an arghelp string:
#
#   * repeated sequences "?foo bar ...?"
#   * -option positions "?-option value ...?"
#   * script arguments {script body command}
#
# Repeated sequences suggest another extension to formalargs:
#  {foo {*}{bar baz} qux}
# bar and baz are populated like $args, but in pairs.  They are constructed 
# as lists, suitable for 
#  foreach r $bar z $baz { ... }
# This can not be permitted alongside args.
# Alongside that "literal" would be nice too ... or maybe $literal? is an inversion too cute?
#
namespace eval procmap {
    proc DecodeUnknownArgs {err cmd} {
        set re [string map {` \"} {(?:bad|unknown(?: or ambiguous))? (?:(?:sub)?command|method|option|argument) `([^`]*)`: must be(?: one of)?:? +(.*) or (.*)}]
        if {[regexp $re $err -> subcmd alts altz]} {
            set alts [string trimright $alts { ,}]
            set alts [split $alts ,]
            set alts [lmap x $alts {string trim $x}]
            lappend alts $altz
        } else {
            throw {PROCMAP DECODE} "Failed to decode Unknown message \"$err\""
        }
        return [dict create subcommands $alts]
    }
    proc DecodeWrongArgs {err cmd} {
        set re [string map {` \"} {^wrong # args: should be(.*)$}]
        set qre [string map {` \"} { +`([^`]*)`}]
        if {[regexp $re $err -> match]} {
            set argspecs [lmap {_ match} [regexp -inline -all $qre $match] {
                if {[string match $cmd* $match]} {
                    string range $match [string length $cmd]+1 end
                } else {
                    string range $match [string first " " $match]+1 end
                }
            }]
        } else {
            throw {PROCMAP DECODE} "Failed to decode Wrong message \"$err\""
        }
        return [dict create arghelps $argspecs]
    }
    proc is_ensemble cmd {
        expr {![catch {namespace ensemble configure $cmd}]}
    }
    proc is_object cmd {
        expr {![catch {info object $cmd}]}
    }
    proc ens_map ens {  ;# see also fun::subcommands
        # FIXME:? parameters?
        # FIXME: if both -map and -subcommands are populated, -map is "slave" to -subcommands (thanks pyk 2015-11-23)
        # FIXME: the values of $map can include arguments.  Handling that will make things quite a bit more complicated (thanks pyk 2015-22-23)
        if {[set map [namespace ensemble configure $ens -map]] ne ""} {
            return $map
        }
        set ns [namespace ensemble configure $ens -namespace]
        if {[set map [namespace ensemble configure $ens -subcommands]] ne ""} {
            foreach cmd $map[set map {}] {
                dict set map $cmd ${ns}::$cmd
            }
            return $map
        }
        if {[set map [namespace eval $ns {namespace export}]] ne ""} {
            foreach pat $map[set map {}] {
                foreach cmd [info commands ${ns}::$pat] {
                    dict set map [namespace tail $cmd] $cmd
                }
            }
            return $map
        }
        return -code error "Not an ensemble!"
    }
    proc obj_map obj {  ;# this should try to deal with forwards as well
        lmap {m} [info object methods -all $obj] {
            list $m [list $obj $m]
        }
    }

    proc Procmap {{pfx {}} {cmd {}}} {
        set procs {}
        lappend procs $pfx $cmd
        if {[is_ensemble $cmd]} {
            foreach {sub t} [ens_map $cmd] {
                lappend procs {*}[Procmap [list {*}$pfx $sub] $t]
            }
        } elseif {[is_object $cmd]} {
            foreach {sub t} [obj_map $cmd] {
                lappend procs {*}[Procmap [list {*}$pfx $sub] $t]
            }
        }
        return $procs
    }

    variable procs {}
    proc procmap {{ns {}}} {
        variable procs
        foreach cmd [info commands ${ns}::*] {
            if {$cmd in [dict values $procs]} continue
            lappend procs {*}[Procmap $cmd $cmd]
        }
#        if {$ns eq ""} {set ns "::"}
#        foreach ns [namespace children $ns] {
#            puts "Exploring $ns"; after 200
#            procmap $ns
#        }
        return $procs
    }

    proc What {cmd} {
        if {$cmd in [interp aliases]} {
            return "alias"
        } elseif {[string trimleft $cmd :] in [interp aliases]} {
            return "alias"
        } elseif {$cmd in [info procs $cmd]} {
            return "proc"
        } elseif {[info object isa object $cmd]} {
            if {[info object isa metaclass $cmd]} {
                return "metaclass"
            } elseif {[info object isa class $cmd]} {
                return "class"
            } else {
                return "object"
            }
        } elseif {[llength [info commands winfo]] && [winfo exists $cmd]} {
            return "widget"
        } elseif {![catch {namespace ensemble configure $cmd}]} {
            return "ensemble"
        } else {
            return "command"
        }
    }

    proc map {cmdPrefix ls} {
        lmap 0 $ls {
            uplevel 1 $cmdPrefix [list $0]
        }
    }

    proc hint {cmd} {
        # FIXME: the cmd actually comes in as a script!
        # so that should be parsed into words, and the last word identified, and so on
        try {
            set what [whatnext {*}$cmd]
            foreach key {error arginfo arghelp subcommands cmdtype} {
                if {[dict exists $what $key]} {
                    return [dict get $what $key]
                }
            }
        } on error {e o} {
            return "$e"
        }
    }

    # whatnext cmd ?arg ...?
    # returns a dict:
    # has key "cmdtype" or key "error"
    # if "cmdtype", probably has key "arginfo" or "arghelp" or "subcommands"
    proc whatnext {cmd args} {
        set cmd [uplevel 1 [list namespace which -command $cmd]]
        set cmdtype [What $cmd]
        #puts "Dispatching for $cmdtype $cmd"
        switch $cmdtype {
            alias {
                # recurse
                tailcall whatnext [interp alias {} $cmd]
            }
            proc {
                if {$args ne ""} {
                    # FIXME: attempt to match args
                    return [map subst {
                        error   "no subcommands"
                        at      $args
                    }]
                }
                return [map subst {
                    cmdtype      $cmdtype
                    arginfo     {[info args $cmd]}
                }]
            }
            command {
                if {$args ne ""} {
                    # FIXME: attempt to match args
                    return [map subst {
                        error   "no subcommands"
                        at      $args
                    }]
                }
                # FIXME: subcommands may still be present! (zlib)
                # consult magic book
                variable arghelp
                if {[info exists arghelp] && [dict exists $arghelp [list $cmd {*}$args]]} {
                    return [map subst {
                        cmdtype  $cmdtype
                        arghelp $arghelp
                    }]
                } else {
                    # no arghelp!
                    return [map subst {
                        cmdtype  $cmdtype
                    }]
                }
            }
            widget {
                if {$args ne ""} {
                    throw {PROCMAP UNIMPLEMENTED} "Not yet implemented: widget introspection"
                }
                return [map subst {
                    cmdtype  $cmdtype
                }]
            }
            ensemble {
                set map [namespace ensemble configure $cmd -map]    ;# FIXME: subcommands or exports
                set rest [lassign $args subcmd]
                if {$args eq ""} {
                    set subcommands [concat [dict keys $map] $rest]
                    return [map subst {
                        cmdtype      $cmdtype
                        subcommands $subcommands
                    }]
                }
                # recurse
                tailcall whatnext [dict get $map $subcmd] {*}$rest
            }
            metaclass - class - object {
                if {$args eq ""} {
                    set methods [info object methods $cmd -all]
                    return [map subst {
                        cmdtype      $cmdtype
                        subcommands $methods
                    }]
                }
                set rest [lassign $args subcmd]
                set callchain [info object call $cmd $subcmd]
                #puts "callchain = {\n\t[join $callchain \n\t]}"
                lassign [lindex $callchain 0] calltype methodname locus methodtype
                # calltype in {method filter unknown}
                if {$methodtype eq "forward"} {
                    if {$locus eq "object"} {
                        set target [info object forward $cmd $methodname]
                    } else {
                        set target [info class forward $locus $methodname]
                    }
                    # recurse
                    tailcall whatnext {*}$target
                } elseif {$methodtype in {"method" "unknown"}} {
                    if {$locus eq "object"} {
                        set lambda [info object definition $cmd $methodname]
                    } else {
                        set lambda [info class definition $locus $methodname]
                    }
                    return [map subst {
                        cmdtype  $cmdtype
                        arginfo     {[lindex $lambda 0]}
                    }]
                } else {
                    throw {PROCMAP WHAT UNKNOWN} "I don't know how to inspect [list $cmd $subcmd], a $methodtype!"
                }
            }
            default {
                throw {PROCMAP WHAT UNKNOWN} "I don't know how to inspect [list $cmd], a $cmdtype!"
            }
        }
    }

    proc examine cmd {
        try {
            uplevel 1 $cmd
            uplevel 1 $cmd XXXXXXXXXXXXXXX [lrepeat 100 100]
        } trap {TCL LOOKUP} {e o} {
            # bad option "-e": must be -directory, -join, -nocomplain, -path, -tails, -types, or --
            tailcall DecodeUnknownArgs $e $cmd
        } trap {TCL WRONGARGS} {e o} {
            tailcall DecodeWrongArgs $e $cmd
        } trap {TCL OO MONKEY_BUSINESS} {e o} {
            puts "SKIP: $e"
            # moving right along ..
        } on error {e o} {
            set code [list [dict get $o -errorcode]]
            puts "Unexpected error $code: $e"
            try {
                try {
                    DecodeWrongArgs $e $cmd
                } trap {PROCMAP DECODE} {} {
                    DecodeUnknownArgs $e $cmd
                }
            } on error {} {
                puts "Unable to parse {$e}: $cmd"
            }
        } on ok {} {
            return -code error "$cmd didn't squeal!"
        }
    }
    proc mapprocs {} {
        variable arghelp
        set maxfirst {
            break continue
            exit cd
        }
        set avoid {
            return
            tailcall yield yieldto
            unknown
            concat
            {dict merge}
            {file delete}
            {file mkdir}
            glob
            global
            if
            list
            {namespace delete}
            {namespace export}
            {namespace forget}
            {namespace import}
            {string cat}
            unset
            variable
            msgcat::mcmax
            oo::Helpers::next
            oo::Helpers::nextto
            oo::Helpers::self
        }   ;# some are {args}, some are dangerous, some (if) just don't play nice
        set doms {
            zlib
        }   ;# some of these are recognisable by "subcommand ?...?"
        set maxfirst [map {string cat ::} $maxfirst]
        set avoid [map {string cat ::} $avoid]
        set doms [map {string cat ::} $doms]
        ;# FIXME: need to examine namespaces other than root to catch
        ;#  ::oo::define, ::tcl::mathfunc::* etc.  But I should take some care
        ;#  to not double-count (or worse: double-examine) ensemble subcommands
        set procs [lsort [dict keys [procmap::procmap]]]
        set Procs $procs

        while {$procs ne ""} {
            set procs [lassign $procs cmd]
            if {[string match ::procmap* $cmd]} continue
            if {$cmd in $avoid} continue
            puts "Examining $cmd ..."
            after 10    ;# delay for good luck .. raise this if you're squeamish!
            if {$cmd in $maxfirst} {
                set res [procmap::examine [list {*}$cmd XXXXXXXX {*}[lrepeat 100 100]]]
            } else {
                set res [procmap::examine $cmd]
            }
            if {$cmd in $doms || -1 != [lsearch -glob [dict get $res arghelps] "subcommand*"]} {
                set res [dict merge $res [procmap::examine [list {*}$cmd NOSUCHSUBCOMMANDEVEREVERISAYEVER]]]
            }
            if {[dict exists $res subcommands]} {
                lappend procs {*}[lmap sub [dict get $res subcommands] {list {*}$cmd $sub}]
            }
            puts ">> $res"
            dict set arghelp $cmd $res
        }
    }
}

if 0 {
    oo::class create foo {method foo {bah hum bug} {}; forward bar puts -nonewline stderr}
    foo create fu
    oo::objdefine fu method fa {lala la} {}
    oo::objdefine fu forward baa puts
    interp alias {} putn {} puts -nonewline
    foreach cmd {
        puts putn procmap::procmap 
        info oo::class oo::object 
        oo::objdefine {info class}
    } {
        puts $cmd\t[procmap::whatnext {*}$cmd]
    }
    foreach cmd {
        {fu bar} {fu foo}
        {fu fa} {fu baa}
    } {
        puts $cmd\t[procmap::whatnext {*}$cmd]
    }
    foreach cmd {puts socket switch procmap::examine {namespace ensemble configure} {namespace HAHA} {fu LOL} {fu fa} {fu baa} {fu bar TOO MANY ARGS}} {
        puts EXAMINE\t$cmd\t[procmap::examine $cmd]
    }
}

apply {{} {
    puts "Are you sure?  This could be dangerous."
    gets stdin
    set outf [open [file join [file dirname [info script]] procmap_lib.tcl] w]
    puts $outf "# Tcl [info patchlevel] from [info nameofexe] at ([clock seconds]) [clock format [clock seconds]]"
    foreach {k v} [array get ::tcl_platform] {
        puts $outf [format "#\ttcl_platform(%-15s = %s" $k) [list $v]]
    }
    puts $outf
    procmap::mapprocs
    foreach var {procs arghelp} {
        set s [lmap {a b} [set ::procmap::$var] {list $a $b}]
        set s [join $s \n\t]
        puts $outf "set ::procmap::$var {\n\t$s\n}\n"
    }
    close $outf
}}
