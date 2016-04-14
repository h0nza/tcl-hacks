# records:
#  A record is a dictionary with a defined set of keys, a convenient constructor (${name}::create)
#  and collection constructor (${name}::table).  These get their sugar from [dictargs] and [llsub].
#  The values are just dicts.
#
#  Use [record::declare] to declare a record kind and create these two special methods.
#
#  % record::declare some id {-foo} {-bar $::tcl_version -baz ""} {
#    if {$baz eq ""} {
#      set baz [string reverse $bar]
#    }
#  }
#  ::some
#
#  % some::create one -foo frop
#  {-id one -foo frop -bar 8.6 -baz 6.8}
#
#  % some::table {
#    one -foo frop
#    two -foo twine -bar hello
#    tre -foo food -baz 23
#  }
#  {one {-id one -foo frop -bar 8.6 -baz 6.8}
#   two {-id two -foo twine -bar hello -baz hello}
#   tre {-id tre -foo food -bar 8.6 -baz 23}}
#
#  [record::method] is a convenience wrapper for procs which see all the record's fields as local variables.
#  Simply, it inserts an argument _ and wraps the body in [dict with _]:
#
#   % record::method some::foo {a b} {list $foo $bar $a $b}
#
#  is equivalent to:
#
#   % proc some::foo {_ a b} {dict with _ {list $foo $bar $a $b}}
#
#  and in fact I recommend making procedures alongside methods in this way.
#
#  Records are designed for immutable (create-once) use - mutator methods will need some care.
#
#
#  [${name}::create]: returns a dictionary
#   % ..::create id -field1 val1 -field2 val2
#   {id id field default field1 val1 field2 val2}
#
#  [${name}::table] returns a dictionary whose keys are ids and values are full dicts as above
#   % ..::table {
#       id1 -field value
#       id2 -field2 value2 -field3 [expr 40+2]
#   }
#   {id1 {id id1 field value field1 {} field2 {}}
#    id2 {id id2 field1 default field2 value2 field3 42}}
#
namespace eval record {
    # name  - the namespace in which to create the new record
    # id    - the key that acts as an identifier
    # req   - required arguments, as a list
    # opt   - optional arguments, as a {name default} dictionary
    # body  - an (optional) constructor script, which sees all fields as locals
    proc declare {name id req opt {body ""}} {
        if {![string match ::* $name]} {
            set ns [string trimright [uplevel 1 {namespace current}] :]::$name
        }
        set req [lmap k $req {regsub ^- $k {}}]
        set opt [lmap k $opt {regsub ^- $k {}}]
        set map [dict create @REQ [list $req] @OPT [list $opt] @BODY $body]
        namespace eval $ns {}
        proc ${ns}::create [list $id args] [string map $map {
            set args [dict map {_k _v} $args {
                if {![regsub ^- $_k {} _k]} {
                    throw {BAD ARGUMENT} "Invalid argument \"$_k\""
                }
                set _v
            }]
            unset _k; unset _v
            set _ $args; unset args
            ::record::dictargs _ @REQ @OPT
            unset _
            @BODY
            return [::record::localenv]
        }]
        alias ${ns}::table table ${ns}
    }

    proc method {name args body} {
        tailcall proc $name [list _ {*}$args] [list dict with _ $body]
    }

    proc table {name table} {
        set result {}
        foreach arglist [updo [namespace which llsub] $table] {
            dict set result [lindex $arglist 0] [${name}::create {*}$arglist]
        }
        return $result
    }

# essentials:
    # compare:
    #   interp alias {} [namespace current]::the_alias {} [namespace which -command target] arg
    #   alias the_alias target arg
    proc alias {alias cmd args} {
        set alias   [upns 1 $alias]
        set cmd     [upns 1 $cmd]
        interp alias    {} $alias   {} $cmd {*}$args
    }
    # compare:
    #   set x [uplevel 1 [list namespace which $command]]
    #   set x [updo 1 namespace which $cmd]
    #   set x [updo {namespace which} $cmd]   ;# lvl can be elided when safe; first word will be expanded
    proc updo {{lvl 1} args} {
        tailcall uplevel $lvl $args
    }
    # [upns]            - get namespace of caller
    # [upns 2]          - get namespace of caller's caller
    # [upns 1 cmd]      - qualify cmd with caller's namespace
    # [upns 1 cmd 1 2]  - create a callback with two arguments
    #  level can only be elided in the argless case
    proc upns {{lvl 1} args} {  ;# doubles as resolve-cmdname-in-caller
        if {$args eq ""} {
            tailcall uplevel $lvl {namespace current}
        } else {
            set cargs [lassign $args cmd]
            if {[string match :* $cmd]} {
                return $args
            }
            set ns [uplevel [expr {$lvl+1}] {namespace current}]
            set ns [string trimright $ns :]
            return [list ${ns}::$cmd {*}$cargs]
        }
    }

    # get current (local) environment as a dict
    # arrays are ignored (bluntly, by [catch])
    proc localenv args {
        if {$args eq ""} {
            set args [uplevel 1 {info locals}]
        }
        set result {}
        foreach arg $args {
            catch { ;# ignore arrays
                dict set result $arg [uplevel 1 [list set $arg]]
            }
        }
        return $result
    }

    # [lsub] sits conceptually between [list] and [subst]:
    #  its argument is tokenised into words according to Tcl command syntax,
    #  and each word is substituted in the caller's environment.
    #
    # Example:
    #   % apply {{{greeting "Hello, %s!\n"} {who world}} {
    #     lsub { $greeting $who  ;# comments are allowed
    #            # and so are newlines
    #            [string toupper $who] }}}
    #   {{Hello, %s!\n} world WORLD}
    #
    proc lsub script {              ;# [sl] from the wiki
        # FIXME: this breaks badly on semicolons
        set res {}
        set parts {}
        foreach part [split $script \n] {
            lappend parts $part
            set part [join $parts \n]
            #add the newline that was stripped because it can make a difference
            if {[info complete $part\n]} {
                set parts {}
                set part [string trim $part]
                if {$part eq {}} {
                    continue
                }
                if {[string index $part 0] eq {#}} {
                    continue
                }
                #Here, the double-substitution via uplevel is intended!
                lappend res {*}[uplevel list $part]
            }
        }
        if {$parts ne {}} {
            error [list {incomplete parts} [join $parts]]
        }
        return $res
    }

    # llsub is lsub's simpler big brother.  It tokenises its argument according to
    # Tcl *script* syntax and returns a list of list, where each inner list is a
    # (substituted) command from the input.  Unlike lsub, newlines and semicolons
    # between elements are significant.
    #
    # This proc is a one-token change from lsub, but provided in full for
    # easy bytecoding.
    proc llsub script {              ;# tiny derivation from [lsub]
        # FIXME: this breaks badly on semicolons
        set res {}
        set parts {}
        foreach part [split $script \n] {
            lappend parts $part
            set part [join $parts \n]
            #add the newline that was stripped because it can make a difference
            if {[info complete $part\n]} {
                set parts {}
                set part [string trim $part]
                if {$part eq {}} {
                    continue
                }
                if {[string index $part 0] eq {#}} {
                    continue
                }
                #Here, the double-substitution via uplevel is intended!
                lappend res [uplevel list $part]    ;# the difference!  (no {*})
            }
        }
        if {$parts ne {}} {
            error [list {incomplete parts} [join $parts]]
        }
        return $res
    }

    # The named _args variable must have all requireds, and all keys must be in requireds OR defaults.
    # _args is updated with defaults, and all req+opt are created in the calling environment.
    #   * requireds is an ordinary list
    #   * defaults is an lsub dict.
    proc dictargs {_args requireds defaults} {
        upvar 1 $_args args
        set defaults [uplevel 1 [list [namespace which lsub] $defaults]]
        # FIXME: handle unambiguous prefixes
        set missing [lmap arg $requireds {
            if {[dict exists $args $arg]} continue
            set arg
        }]
        if {$missing ne ""} {
            tailcall tailcall throw {TCL BADARGS} "Missing required arguments \"[join $missing {", "}]\""
        }
        set bad [dict filter $args script {k _} {
            expr {($k ni $requireds) && ![dict exists $defaults $k]}
        }]
        if {$bad ne ""} {
            tailcall tailcall throw {TCL BADARGS} "Unexpect arguments \"$bad\"\naccepted arguments are ([dict keys $defaults])"
        }
        set args [dict merge $defaults $args]
        tailcall dict with $_args {}
    }

}


if 1 {
    record::declare option switch { } {
        -studly     {}
        -default    {}
        -verifier   {}
        -configuremethod {}
        -cgetmethod {}

        -delegate   {}
    } {
        if {$studly eq "" && $delegate eq ""} {
            error "Must provide either -studly or -delegate!"
        }
        set resname     [string tolower $studly 0 0]
        set resclass    $studly
        unset studly
    }

    #proc option::resource {_ value}
    record::method option::resource {value} {
        list $switch $resname $resclass $default $value
    }


    proc putl args {puts $args}
    putl ok
    #putl proc option::create [info args option::create] [info body option::create]
    #putl --

    set win .CONSOLE
    set options [option::table {
         -readonly   -studly ReadOnly -default false -verifier {string is boolean}
         -background -delegate $win.output
         -ibg        -delegate [list $win.input -background]
    }]
    array set {} $options; parray {}
    putl ok

    array set v {-readonly TRYE -background FREEN -ibg YELLOF}
    puts [join [lmap {o d} $options {option::resource $d $v($o)}] \n]
}
