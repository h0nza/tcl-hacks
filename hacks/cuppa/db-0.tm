package require sqlite3

namespace eval db {
    namespace export *

    proc db {args} { init; tailcall db {*}$args }

    proc init {{filename ""}} {
        sqlite3 [namespace current]::db $filename
        db collate  vcompare    {package vcompare}
        db function vsatisfies  {package vsatisfies}
        Setup
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

    proc tables {{pattern}} {
        db eval {select name from sqlite_master where type = 'table' and name like :pattern}
    }

    proc exists {table} {
        db exists {select 1 from sqlite_master where type = 'table' and name = :table}
    }

    proc running {} {
        expr {[info procs [namespace current]::db] eq {}}
    }

    variable setup_scripts {}
    proc Setup {} {
        variable setup_scripts
        foreach {namespace script} $setup_scripts {
            puts "db setup $namespace"
            apply [list {} $script $namespace]
        }
    }
    proc setup {script} {
        variable setup_scripts
        set ns [uplevel 1 {namespace current}]
        dict set setup_scripts $ns $script              ;# register a setup script
        if {[running]} {
            apply [list {} $script $ns]                 ;# apply immediately
        }
        tailcall namespace import [namespace which db]  ;# make db accessible
    }

    proc reset script {
        variable reset_scripts
        set ns [uplevel 1 {namespace current}]
        dict set reset_scripts $ns $script
    }

}
