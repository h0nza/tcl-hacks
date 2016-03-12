package require sqlite3

namespace eval db {
    namespace export *

    proc db {args} { init; tailcall db {*}$args }

    proc glob {s} {
        string map {* % ? _} $s
    }
    proc qn {s} {
        return \"[string map {\" ""} $s]\"
    }
    proc qs {s} {
        return '[string map {' ''} $s]'
    }

    proc init {{filename ""}} {
        if {[running]} {
            puts "already running"
            return
        }
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
            db eval "select count(1) count from [qn $name]" {
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

    variable Setup_scripts {}
    proc Setup {} {
        variable Setup_scripts
        foreach {namespace script} $Setup_scripts {
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

    variable Reset_scripts
    proc reset script {
        variable Reset_scripts
        set ns [uplevel 1 {namespace current}]
        dict set Reset_scripts $ns $script
    }

}
