package require pkg
package require debug

pkg tdbcplus {
    oo::class create tdbcplus {

        # these work around http://core.tcl.tk/tdbc/tktview?name=fbcd8d40f1
        method primarykeys {table} {
            # FIXME: [string cat next] is an artifact of http://core.tcl.tk/tcl/tktview?name=0f42ff7871
            set res [[string cat next] $table]
            set key tableSchema
            set schema [my configure -database]
            lmap d $res {
                if {[dict get $d $key] ne $schema} continue
                set d
            }
        }
        method foreignkeys {o table} {
            # FIXME: [string cat next] is an artifact of http://core.tcl.tk/tcl/tktview?name=0f42ff7871
            set res [[string cat next] $o $table]
            set key [string range $o 1 end]Schema
            set schema [my configure -database]
            lmap d $res {
                if {[dict get $d $key] ne $schema} continue
                set d
            }
        }

        # this is just so handy I don't know why you'd not have it
        method scalar args {
            debug assert {[llength $args] in {1 2}}
            set res [uplevel 1 [list [namespace current]::my allrows -as lists {*}$args]]
            debug assert {[llength $res] eq 1}
            debug assert {[llength [lindex $res 0]] eq 1}
            lindex $res 0 0
        }

        # sqlite (mostly) shim.
        # for proper sqlite compatibility, this should speak NULL
        method eval args {
            if {[llength $args] eq 1} {
                tailcall my allrows -as lists {*}$args
            }
            set script [lindex $args end]
            set args [lrange $args 0 end-1]
            my foreach -as lists -columnsvariable cols row {*}$args {
                uplevel 1 "
                    lassign [list $row] $cols
                    $script
                "
            }
        }

        method changes {} {
            return -1234    ;# don't know how to count changes on mysql :-(
        }

    }

    proc upgrade_obj {obj} {
        set mixin [namespace which -command tdbcplus]
        if {$mixin ni [info object mixins $obj]} {
            oo::objdefine $obj mixin -append $mixin
        }
    }
    proc upgrade_class {class} {
        set mixin [namespace which -command tdbcplus]
        if {$mixin ni [info class mixins $class]} {
            oo::define $class mixin -append $mixin
        }
    }
}

if 0 {

    #rename tailcall _tailcall
    #proc tailcall args { _tailcall try "return \[uplevel 1 [list $args]\]" }

    lappend auto_path /home/tcl/ActiveTcl-8.6.3/lib/teapot/package/linux-glibc2.3-x86_64/lib
    package require tdbc::mysql
    oo::define tdbc::connection mixin tdbconn2
    #upgrade_connection0 {}
    set ::USER retest
    set ::PASSWORD retestz0r
    set ::DB re_testmigrate
        ::tdbc::mysql::connection create db -host localhost -port 3306 \
            -db $::DB \
            -user $::USER \
            -passwd $::PASSWORD
    puts [lmap x [db foreignkeys -primary records] {dict get $x foreignConstraintSchema}]
    puts [db scalar "select count(1) from records"]
    db eval {select first_name, last_name from records where first_name is not null limit 10} {
        puts "$first_name $last_name"
    }

}
