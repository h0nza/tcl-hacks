package require sqlite3
package require log 0

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

    # decodes a list like {a b:bee c}
    # into "a as a, b as bee, c as c"
    proc sargs {fields} {
        join [lmap f $fields {
            lassign [split $f :] name alias
            if {$alias eq ""} {
                string cat "[qn $name]"
            } else {
                string cat "[qn $name] as [qn $alias]"
            }
        }] ,
    }
    proc vargs {fields} {
        lmap f $fields {regsub {^.*:} $f {}}
    }

    # declare an sql-backed procedure
    # a qproc takes arguments: fields where ??varName? script?
    #  - fields is a list of names to select, or name:alias to project [sarg]/[farg]
    #  - where is a [lib::subl] dict of parameters to the query
    # additional args are like the ??row? script? args to sqlite
    proc qproc {name defaults sqlquery} {
        set name [lib::upns 1 $name]

        dict set map @SQL   [list $sqlquery]
        dict set map @DEF   [list $defaults]

        set args {fields where args}
        set body [string map $map {
            set _FIELDS [db::sargs $fields]
            set _VARS   [db::vargs $fields]
            set _SQL    [string map [list * $_FIELDS] @SQL]
            set _ARGS   [lib::updo lib::lsub $where]
            lib::dictargs _ARGS @DEF
            lib::dictable $_VARS [db eval $_SQL {*}$args]
        }]
        proc $name $args $body
    }

    proc init {{filename ""}} {
        if {[running]} {
            return
        }
        log::info {$filename}
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
            log::info {setup $namespace}
            apply [list {} $script $namespace]
        }
    }
    proc setup {script} {
        variable Setup_scripts
        set ns [uplevel 1 {namespace current}]
        dict set Setup_scripts $ns $script              ;# register a setup script
        if {[running]} {
            log::info {late setup $namespace}
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
