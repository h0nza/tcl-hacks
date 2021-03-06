#!/usr/bin/env tclsh
#
# Generate a tags file by tracing a package at load time.
#
# The goal is some compatibility with editor support for tagfiles, eg tagbar.vim
#

#puts [read [open out r]]; return
#ctags -f - --format=2 --excmd=pattern --extra= --fields=nksaSmt myfile

tcl::tm::path add ~/tcl/modules


clock format [clock seconds]    ;# don't let this spam our trace!

namespace eval tcltags {

    variable TOP

    oo::class create Tagger {

        variable TOP
        variable KINDS
        variable EMIT
        forward db db   ;# we store intermediate data in sqlite, because why not

        constructor {{topdir ""}} {
            namespace path [list {*}[namespace path] ::tcltags]
            set KINDS {
                namespace   n
                proc        p
                class       c
                method      m
                variable    v
            }
            set EMIT {
                qualified   1
                scoped      1
                subcommand  1
            }
            if {$topdir eq ""} {set topdir [pwd]}
            set TOP $topdir

            package require sqlite3     ;# deferred so safe interps don't miss it

            sqlite3 db {}
            db eval {
                create table if not exists tags (
                    kind, name, file, line, addr, fields
                );  -- no keys.  The only update that makes sense is to purge/retag a file.
            }
        }

        method emit {args} {
            if {$args eq ""} {
                return [lmap {k p} $EMIT {
                    string cat [expr {$p ? "" : "-"}] $k
                }]
            }
            foreach a $args {
                if {[regexp -- -(.*) $a -> a]} {
                    dict set EMIT [tcl::prefix match [dict keys $EMIT] $a] 0
                } else {
                    dict set EMIT [tcl::prefix match [dict keys $EMIT] $a] 1
                }
            }
        }

        method relpath {path} {
            set len [string length $TOP]
            if {[string equal -length $len $TOP $path]} {
                file join . [string range $path $len+1 end]
            } else {
                return [file join $TOP $path]     ;# ???
            }
        }

        # tag format is "variant 3" from vim doc:
        #   <name> \t <file> \t <addr> ;# ?\t <field> ...?
        # Where the first field is a single-char "kind"
        #  <file>  can be abs or rel, may contain env vars and wildcards
        #  <addr>  is an ex command eg 42 /^foo/  (POSIX only allows line numbers and search commands)
        # kinds and further fields are derived from exuberant-ctags examples
        #
        # "scoped" tags have limited support in some tools (notably: tagbar.vim).
        # To get the best of both worlds, we emit two tags per item:
        #   * a fully-qualified simple tag starting with ::
        #   * a fully-marked-up "naked" with no qualifiers but full scope info in {field}s
        #
        # It might also be worthy to emit different tags for exported names?
        method tagfile {{chan stdout}} {

            set enc [chan configure $chan -encoding]
            puts $chan "!_TAG_FILE_ENCODING\t$enc\tgenerated by $::argv0 $::argv at [clock format [clock seconds]] ~"
            puts $chan "!_TAG_FILE_SORTED\t2\tCOLLATE NOCASE ~"
            
            db eval {select kind, name, file, line, addr, fields 
                        from tags
                        order by name collate nocase} {

                if {$addr eq ""} {set addr $line}       ;# default if no regexp provided
                dict set fields line $line              ;# add values to comment

                unset -nocomplain tail
                if {[regexp {^::(?:(.*)::)?(.*)$} $name -> ns tail]} {
                    if {$ns ne ""} {
                        dict set fields namespace ::$ns
                    }
                }
                if {[dict get $EMIT qualified]} {
                    puts $chan "${name}\t${file}\t${addr};\"\t${kind}\t[my Fields $fields]"
                }

                if {[dict get $EMIT scoped] && [info exists tail]} {
                    puts $chan "${tail}\t${file}\t${addr};\"\t${kind}\t[my Fields $fields]"
                }
                if {[dict get $EMIT subcommand] && [dict exists $fields class]} {
                    ;# this should attempt some introspection on namespaces
                    ;# to see if they are ensembles and emit tags for their subcommands
                    ;# FIXME: introduce [subcommands] from fun-0.tm
                    set class [dict get $fields class]
                    #set class [namespace tail $class]
                    puts $chan "${class} ${name}\t${file}\t${addr};\"\t${kind}\t[my Fields $fields]"
                }
            }
        }
        method Fields {fields} {
            join [lmap {k v} $fields {   ;# format comment
                string cat $k:[list $v]
            }] \t
        }

        method add {frame kind name args} {
            set kind [dict get $KINDS $kind]
            set line [dict get $frame line]
            set file [dict get $frame file]
            set file [my relpath $file]
            db eval {
                insert or replace
                      into tags (  kind,  name,  file,  line, fields )
                        values  ( $kind, $name, $file, $line, $args );
            }
        }

        method vimrc {} {
            puts "\tlet g:tagbar_type_tcl = \{"
            puts "\t\t\\ 'ctagstype' : 'Tcl',"
            puts "\t\t\\ 'ctagsbin' : '[file normalize [info script]]',"
            puts "\t\t\\ 'sro' : '::',"
            puts "\t\t\\ 'kinds' : \["
            dict for {kind k} $KINDS {
                set fold [expr {$kind ni {proc variable}}]
                set stl  [expr {$kind ni {proc variable method}}]
                puts "\t\t\t\\ '$k:$kind:$fold:$stl',"
            }
            puts "\t\t\\ \],"
            puts "\t\t\\ 'kind2scope' : \{"
            dict for {kind k} $KINDS {
                puts "\t\t\t\\ '$k' : '$kind',"
            }
            puts "\t\t\\ \},"
            puts "\t\t\\ 'scope2kind' : \{"
            dict for {kind k} $KINDS {
                puts "\t\t\t\\ '$kind' : '$k',"
            }
            puts "\t\t\\ \},"
            puts "\t\\ \}"
        }

    }



;# utilities:
    proc find_frame {args} {
        for {set f -2} {1} {incr f -1} {
            set d [info frame $f]
            if {[dict_match $args $d]} {
                return $d
            }
        }
    }

    proc dict_match {patterns dict} {
        dict for {k p} $patterns {
            if {[dict exists $dict $k]} {
                set v [dict get $dict $k]
                if {[string match $p $v]} {
                    continue
                }
            }
            return false
        }
        return true
    }

;# a container for many execution leave traces.
    oo::class create MultiTrace {
        variable Traces
        constructor {} {set Traces ""}
        method apply {arglist body args} { ;# eval-like helper
            tailcall apply [list $arglist $body [namespace current]] {*}$args
        }
        method add {cmd argspec body} {
            set cmd [uplevel 1 [list namespace which $cmd]]
            oo::objdefine [self] method $cmd $argspec $body
        }
        method fwd {fwd method args} {
            oo::objdefine [self] forward $fwd my $method {*}$args
        }

        method install {tagger} {
            interp alias {} [namespace current]::tagger {} [uplevel 1 [list namespace which $tagger]]
            set Traces [lmap cmd [info object methods [self] -private] {
                if {![string match ::* $cmd]} continue
                set cmd
            }]
            foreach {cmd} $Traces {
                my InstallTrace $cmd
            }
        }
        method InstallTrace {cmd args} {
            if {[namespace which $cmd] eq ""} {
                #puts stderr "Dummy traceproc on $cmd -- this won't work"
                namespace eval [namespace qualifiers $cmd] {}
                proc $cmd {} {error "dummy proc for trace"}
            }
            trace add execution $cmd leave [
                list [namespace which my] Trace $cmd
            ]
            trace add command $cmd delete [
                list [namespace which my] InstallTrace $cmd
            ]
        }
        method Trace {cmd cmdline args} {
            #puts stderr "Trace fired on $cmd"
            tailcall my $cmd {*}$cmdline
        }
        destructor {
            foreach {cmd t} $traces {
                trace remove execution $cmd leave $t
            }
        }
    }

;# probes:
    MultiTrace create tracer
    tracer apply {ns} {
        namespace path [list {*}[namespace path] $ns]
    } [namespace current]

    tracer add ::oo::define::method {method name argspec args} {
        set frame [find_frame file *]
        set class [uplevel 1 [list ::namespace which [lindex [info level -1] 1]]]
        tagger add $frame method $name class $class tcl [list $name $argspec]
    }
    tracer fwd ::oo::define::forward  ::oo::define::method

    tracer add ::oo::define::variable {variable name args} {
        set frame [find_frame file *]
        set class [uplevel 1 [list ::namespace which [lindex [info level -1] 1]]]
        foreach name $args {
            tagger add $frame variable $name class $class 
        }
    }

    tracer add ::proc {proc name args body} {
        set frame [find_frame file *]
        set name [uplevel 1 [list namespace which $name]]
        tagger add $frame proc $name tcl [list $name $args]
    }

    tracer add ::variable {variable args} {
        set frame [find_frame file *]
        foreach {name value} $args {
            set name [uplevel 1 [list namespace which -variable $name]]
            tagger add $frame variable $name
        }
    }

    tracer add ::tcl::namespace::eval {eval name args} {
        if {![string match ::* $name]} {
            set ns [uplevel 1 {namespace current}]
            if {$ns eq "::"} {set ns ""}
            set name ${ns}::${name}
        }
        tagger add [find_frame file *] namespace $name
    }

    tracer add ::interp {interp cmd args} {
        if {$cmd eq "alias"} {
            set args [lassign $args i0 name i1 target]
            if {$i0 eq "" && $i1 eq ""} {
                set frame [find_frame file *]
                set name [uplevel 1 [list namespace which $name]]
                tagger add $frame proc $name tcl [list alias]
            }
        }
    }

    tracer add ::snit::widget {cmd name body} {
        set frame [find_frame file *]
        set name [uplevel 1 [list namespace which $name]]
        tagger add $frame class $name tcl [list $cmd $name]
    }
    tracer fwd ::snit::widgetadaptor ::snit::widget
    tracer fwd ::snit::type ::snit::widget

if 0 {
    ;# unfortunately, due to the way snit compiles types, the same
    ;# method of introspection won't work for discovering their locations.
    tracer add ::snit::method {cmd class name argspec body} {}
    tracer add ::snit::Comp.statement.method {cmd name argspec body} {
        set frame [find_frame file *checkset.tcl]
        set class [lindex [info level -1] 2]
        error [list tagger add $frame method $name class $class tcl [list $name $argspec]]
    }
}

;# mixin for oo::class create
    oo::class create TagMixin {
        constructor {args} {
            namespace path [list {*}[namespace path] ::tcltags]
            lassign [info level 0] metaclass "create" name
            set name [uplevel 1 [list namespace which $name]]
            set metaclass [uplevel 1 [list namespace which $metaclass]] ;# normally "::oo::class"
            set frame [find_frame file *]
            tagger add $frame class $name tcl [list $metaclass $name]
            next {*}$args
        }
    }
    oo::define oo::class mixin TagMixin


;# main
    if {[info exists ::argv0] && $::argv0 eq [info script]} {
        Tagger create tagger

        proc unsafe {args} {
            tracer install tagger
            foreach arg $args {
                source $arg
            }
            tagger tagfile
        }

        proc safe {scripts args} {
            array set o [dict merge {
                -path {}
                -loadtk 0
                -loadsnit 0
            } $args]

            safe::interpCreate slave -accessPath $o(-path)

            if {$o(-loadtk)} {
                safe::loadTk slave
                #slave eval {wm withdraw .} ;# huh?
                wm withdraw {*}[winfo children .]
            }
            if {$o(-loadsnit)} {
                slave eval {package require snit}
            }

            slave invokehidden source [info script]
            interp alias slave ::tcltags::tagger {} [namespace which tagger]
            slave eval {namespace eval ::tcltags {tracer install tagger}}

            foreach script $scripts {
                slave invokehidden source $script
            }
            interp delete slave
            tagger tagfile
        }

        proc runtest {} {
            namespace eval tagstest {
                proc func {name args expr} {
                    tailcall proc $name $args [list expr $expr]
                }
                func square {x} {$x*$x}
                proc foo {a b} {
                    # this is foo
                }
                oo::class create Foo {
                    method frob {a b} {frob body}
                }
                Foo create f
            }
            tagger tagfile
        }

        proc main args {
            set path {}
            set unsafe 0
            set loadtk 0
            set loadsnit 0
            set emit {scoped -qualified -subcommand}
            #set emit {qualified -scoped -subcommand}
            while {$args ne ""} {
                set args [lassign $args o]
                switch $o {
                    -- {break}
                    -path {
                        set args [lassign $args path]
                    }
                    -unsafe {
                        set unsafe 1
                    }
                    -tk {
                        set loadtk 1
                    }
                    -snit {
                        set loadsnit 1
                    }
                    -emit {
                        set args [lassign $args emit]
                    }
                    -vimrc {
                        if {$args ne ""} {
                            error "cannot provide extra args to vimrc!"
                        }
                        tailcall tagger vimrc
                    }
                    -runtest {
                        tailcall runtest
                    }
                    default {
                        set args [linsert $args 0 $o]
                        break
                    }
                }
            }

            tagger emit {*}$emit

            if {$loadtk} {
                package require Tk  ;# need to load this in the master for safe::loadTk
                wm withdraw .
            }

            if {$unsafe} {
                tcl::tm::path add {*}$path
                lappend ::auto_path {*}$path
                if {$loadsnit} {
                    package require snit
                }
                tailcall unsafe {*}$args
            }

            tailcall safe $args -path $path -loadtk $loadtk -loadsnit $loadsnit
        }

        main {*}$::argv
        exit
    }

    # invocations:
    #   ttags <filename> ?...?
    #   ttags -path <list> ...
    #         -unsafe yes
    #         -emit "q -sc -su"
    #         -vimrc
    #

}
