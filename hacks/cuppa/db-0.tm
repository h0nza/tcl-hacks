package require sqlite3

namespace eval db {
    namespace export *

    proc db {args} { init; tailcall db {*}$args }

    proc init {{filename ""}} {
        sqlite3 [namespace current]::db $filename
        db collate  vcompare    {package vcompare}
        db function vsatisfies  {package vsatisfies}
        setup
    }

    proc stat {} {
        if {![running]} {
            puts "not running"
            return
        }
        db eval {select name from sqlite_master where type = 'table'} {
            db eval "select count(1) count from \"$name\"" {
                puts "$name: $count records"
            }
        }
    }

    proc running {} {
        expr {[info procs [namespace current]::db] eq {}}
    }

    variable setup_scripts {}
    proc setup args {
        variable setup_scripts
        if {$args eq ""} {  ;# run setup
            foreach {namespace script} $setup_scripts {
                apply [list {} $script $namespace]
            }
        } elseif {[llength $args] > 1} {
            error {TCL WRONGARGS} "Expected ::db::setup ?script?"
        }
        set ns [uplevel 1 {namespace current}]
        if {[running]} {
            apply [list {} $script $ns]
        } else {    ;# register a setup script
            dict set setup_scripts $ns [lindex $args 0]
            tailcall namespace import [namespace which db]
        }
    }

}
