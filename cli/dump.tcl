# dump "arbitrary" Tcl things.
# Currently supports:
#  - variables (set name $val)
#  - arrays
#  - procs
#  - aliases
#  - ensembles
#  - namespaces
#  - widgets (just configure)
# TODO:
#  - tcloo objects/classes
#  - intrep-sensitive variables
#  - generally improve formatting and add comments
#  - window geometry?
# Later:
#  - some sort of async support (persistent rel. with editor?)
#  - don't just throw away files (?)
#  - source tracking (ctags/tcltags sensibility?)
namespace eval ::dumper {
    proc upcall {cmd args} {
        set cmd [uplevel 1 [list namespace which -command $cmd]]
        tailcall uplevel 1 [list $cmd {*}$args]
    }
    proc Error {msg} {
        tailcall return -code error $msg
    }

    proc FindNS {name} {
        tailcall namespace eval $name {namespace current}
    }

    proc edit {args} {
        set editor vi
        catch {set editor $::env(EDITOR)}
        set defn [upcall dump {*}$args]
        file tempfile tempfile editor_[pid].tcl
        set fd [open $tempfile w]
        puts -nonewline $fd $defn
        close $fd
        while 1 {
            try {
                exec $editor $tempfile <@ stdin >@ stdout 2>@ stderr
            } on ok {} {
                set fd [open $tempfile r]
                set newdefn [read $fd]
                close $fd
                if {$newdefn eq $defn} {
                    puts "No change."
                    break
                }
                set rc [catch {uplevel 1 $newdefn} e o]
                if {$rc == 0} break
                puts "\[$rc $editor\]: $e"      ;# trace errorinfo for more specific location?
                puts -nonewline --:;flush stdout;gets stdin
                continue
            }
        }
        file delete $tempfile
    }

    proc dump {args} {
        # tip288::args {{types ""} name}
        set args [lreverse [lassign [lreverse $args] name]]
        set varname [uplevel 1 [list namespace which -variable $name]]
        set cmdname [uplevel 1 [list namespace which -command $name]]

        # this should be full options processing, but hey
        set types $args
        if {$types == ""} {
            if {$cmdname != ""} {
                lappend types proc alias ensemble widget    ;# object
            }
            if {$varname != ""} {
                lappend types var array
            }
        }
        lappend types namespace
        foreach type $types {
            if {![catch {upcall dump_${type} $name} result]} {
                return $result
            } else {
            }
        }
        Error "Unable to find a dumper for \"$name\""
    }

    proc dump_alias {name} {
        set alias [upcall interp alias $name]
        if {$alias eq ""} {Error "No such alias \"$name\""}
        list interp alias {} {*}$alias
    }

    proc dump_proc {name} {
        set argspec [lmap arg [upcall info args $name] {
            if {[upcall info default $name $arg default]} {
                list $arg $default
            } else {
                list $arg
            }
        }]
        set body [upcall info body $name]
        list proc $name $argspec $body
    }

    proc dump_widget {name} {
        if {![upcall winfo exists $name]} {
            Error "No such widget: \"$name\""
        }
        append result "\n# [winfo class $name] $name"
        set opts {}
        foreach opt [$name configure] {
            if {[llength $opt] == 2} continue
            lassign $opt opt - - def val
            if {$val ne $def} {
                lappend opts $opt $val
            }
        }
        set opts [join [lmap {o v} $opts {string cat $o \t [list $v]}] \ \\\n\t]
        append result "\nlist $name configure \\\n\t$opts"
    }
    # see tkcon, tksec for dump_text, dump_canvas

    proc dump_oo_object {name} {
        set name  [upcall namespace which -command $name]
        set class        [info object class $name]
        set mixins       [info object mixins $name]
        set methods      [info object methods $name]
        set private      [info object methods $name -private]
        set private      [lmap p $private {if {$p in $methods} continue; set p}]
        # methodtype .. definition, forward
        Error "Not implemented!"
    }
    proc dump_oo_class {name} {
        set name  [upcall namespace which -command $name]
        set superclasses [info class superclasses $name]
        set mixins       [info class mixins $name]
        set methods      [info class methods $name]
        set private      [info class methods $name -private]
        set private      [lmap p $private {if {$p in $methods} continue; set p}]
        # methodtype .. definition, forward
        # self is on the object stuff
        Error "Not implemented!"
    }

    proc dump_array {name} {
        join [lmap {key value} [upcall array get $name] {
            list set ${name}(${key}) $value
        }] \n
    }
    proc dump_var {name} {
        if {[upcall array exists $name]} {
            tailcall dump_array $name
        }
        set rep [uplevel 1 "::tcl::unsupported::representation \[[list set $name]\]"]
        append result "# ${name}: $rep" \n
        append result [list set $name [upcall set $name]] \n
    }

    proc dump_ensemble {name} {
        try {
            set conf [namespace ensemble configure $name]
        } on error {} {
            Error "No an ensemble: $name"
        }
        set conf [join [lmap {o v} $conf {string cat $o \t [list $v]}] \ \\\n\t]
        return "\nnamespace ensemble configure $name \\\n\t$conf"
    }

    proc dump_namespace {name} {
        if {![upcall namespace exists $name]} {
            Error "No such namespace: \"$name\""
        }
        set name [upcall FindNS $name]
        set result "## generated dump"

        # variables
        foreach var [info vars ${name}::*] {
            append result \n[dump_var $var]
        }

        # procs
        foreach proc [info procs ${name}::*] {  ;# try more aggressively with [info commands] ?
            append result \n[dump_proc $proc]
        }

        # imports
        foreach import [namespace eval $name {namespace import}] {
            set origin [namespace origin ${name}::${import}]
            append result \n[list namespace import -force $origin]      ;# check if -force needed?
        }

        # path, export
        set path [namespace eval $name {namespace path}]
        if {$path ne ""} {
            append result \n[list namespace path $path]
        }
        set export [namespace eval $name {namespace export}]
        if {$export ne ""} {
            append result \n[list namespace export $export]
        }

        set result \n$result\n
        return "namespace eval [list $name] [list $result]"
    }

    namespace export dump edit
}
