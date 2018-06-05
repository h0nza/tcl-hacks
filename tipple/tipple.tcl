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
        puts "Subcommands:"
        foreach pat [namespace export] {
            foreach cmd [info commands [namespace current]::$pat] {
                set args [info args $cmd]
                set cmd [namespace tail $cmd]
                puts "  $cmd $args"
            }
        }
    }

    proc init {topdir} {

        set topdir [file normalize $topdir]

        if {[file exists $topdir]} {
            if {[file exists $topdir/tclenv.txt]} {
                return -code error "Error: $topdir/tclenv.txt already exists!"
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
            platform    [platform::identify]

            lib_dir     [list $rellibdir]
            tm_dir      [list $relmoddir]

        }]
    }

    proc install {pkgname {pkgver ""}} {
        # download: pkgname is one of:
        #  * just a package name - use teapot
        #  * a local path - goto install
        #  * a url - download it
        #   * if it's a zip or tarball, extract it in DIR/src and goto install
        #   * otherwise install as a tm
        #  * fossil+$url or git+$url - clone it in DIR/src
        #
        # install:
        #   * look for tipple.txt
        #   * install files
        #    ? if tipple.txt specified, follow its directions
        #    * lib/ modules/ bin/
        #    ? or if there's /*.tm or /pkgIndex.tcl, the whole shebang
        #   * record package presence in log (+tclenv.txt?)
    }

    proc _read_txt {filename} {
        set fd [open $filename r]
        try {
            set res {}
            while {[gets $fd line]>=0} {
                if {[string match #* $line]} continue
                if {$line eq ""} continue
                set val [lassign $line key]
                dict lappend res $key {*}$val
            }
            return $res
        } finally {
            close $fd
        }
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
