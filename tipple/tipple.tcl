#!/usr/bin/env tclsh
#

proc createfile {path data args} {
    if {[file exists $path]} {
        return -code error "File already exists! \"$path\""
    }
    set fd [open $path w]
    try {
        puts -nonewline $fd [dedent $data]
    } finally {
        close $fd
    }
    if {$args ne ""} {
        file attributes $path {*}$args
    }
}

proc dedent {lines} {
    regexp {\n( +)} $lines -> indent
    regsub -all \n$indent   $lines  \n  lines
    regsub      { +$}       $lines  ""  lines
    regexp {\n(.*)} $lines -> lines
    return $lines
}

namespace eval tipple {
    namespace ensemble create
    namespace export {[a-z]*}

    proc help {} {
        puts "Subcommands: [lmap c [info commands [namespace current]::\[a-z\]*] {namespace tail $c}]"
    }

    proc init {topdir} {

        set topdir [file normalize $topdir]

        if {[file exists $topdir]} {
            if {[file exists $topdir/tipple.txt]} {
                return -code error "Error: $topdir/tipple.txt already exists!"
            }
            puts "Setting up in existing directory: $topdir"
        } else {
            puts "Setting up new directory: $topdir"
        }

        set tclver [info tclversion]
        regexp {^(\d+).(\d+)} $tclver -> majver minver

        set bindir $topdir/[set relbindir bin]
        set libdir $topdir/[set rellibdir lib/tcl$tclver]
        set moddir $topdir/[set relmoddir lib/tcl${majver}/site-tcl]

        puts "mkdir -p $topdir $bindir $libdir $moddir"
        file mkdir $topdir $bindir $libdir $moddir

        createfile $bindir/activate [subst -noc {
            # source this file to initialize your env:
            PATH="$bindir:\$PATH"
            TCLLIBPATH="$libdir"
            TCL${majver}_${minver}_TM_PATH="$moddir"
            export PATH TCLLIBPATH TCL${majver}_${minver}_TM_PATH
        }]

        if {[file exists $bindir/tclsh]} {

            puts "Not modifying existing $bindir/tclsh"

        } else {

            set tclexe [info nameofexecutable]

            puts "Creating wrapper script $bindir/tclsh -> $tclexe"

            createfile $bindir/tclsh [subst -noc {
                #!/bin/sh
                . "$bindir/activate"
                exec "$tclexe" "\$@"
            }] -permissions 0755

        }

        createfile $topdir/tclenv.txt [subst {
            # Tcl environment initialised at [clock format [clock seconds]]
            tcl_version $tclver
            lib_dir [list $rellibdir]
            tm_dir  [list $relmoddir]

        }]
    }
}

proc main {args} {
    if {$args eq ""} {set args "help"}
    try {
        tipple {*}$args
    } on error {err opts} {
        puts stderr "Error: $err"
        return 1
    }
    return 0
}

exit [main {*}$::argv]
