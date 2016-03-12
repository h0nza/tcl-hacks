# leaves reads teapot descriptions
#
# SYNOPSIS:
#
#  $ leaves.tcl scan lib/
#  $ leaves.tcl find path lib/%
#  $ leaves.tcl deps lib/snit-2.3.2
#
::tcl::tm::path add [pwd]
package require db
package require lib
package require vfs::mk4
package require vfs::tar
package require vfs::zip

namespace eval leaves {
    db::reset {
        db eval {
            drop table if exists teapkgs;
            drop table if exists teameta;
        }
    }
    db::setup {
        if {[db::exists teapkgs]} return
        puts "Setting up leaves"
        db eval {
            create table if not exists teapkgs (
                name text,
                ver text collate vcompare,
                arch text,
                path text,
                primary key (path),
                -- index teapkgs_i_nvp (name, ver, arch),
                unique (path)
            );
            create table if not exists teameta (
                path text,
                field text,
                value text,
                primary key (path, field),
                foreign key (path)
                  references pkg_meta (path)
                    on delete cascade
            );
        }
        #subject description require platform summary recommend category license
    }

    proc db_insert {args} {
        set keys {key name version platform path}
        set d [dict filter $args {*}$keys]
        dict with d {
            db eval {
                insert or replace 
                    into teapkgs ( name,  ver,      arch,      path)
                          values (:name, :version, :platform, :path);
            }
        }
        foreach {field value} $args {
            if {$field in $keys} continue
            db eval {
                insert or replace
                    into teameta ( path,  field,  value)
                          values (:path, :field, :value);
            }
        }
    }

    proc scan {topdir args} {
        foreach path [glob $topdir/*] {
            try {
                parse_teapot $path
            } on ok {teameta} {
                puts "Found teapot.txt in $path"
                foreach {key meta} $teameta {
                    puts "Inserting metadata for $key"
                    db_insert path $path {*}$args {*}$meta
                }
            } on error {e o} {
                if {[file isdirectory $path]} {
                    db_scan $path {*}$args
                }
            }
        }
        set n [db onecolumn {select count(1) from teapkgs}]
        set m [db onecolumn {select count(1) from teameta}]
        puts "Scanned $n packages, learned $m things"
    }

    # simplifies a set of version bounds into a single bound
    proc vsimplify {vers} {
        set vers [lassign $vers first]
        set first [split $first -]
        lassign $first A B
        foreach ver $vers {
            lassign [split $ver -] a b
            if {[package vcompare $A $a] < 0} { set A $a }
            if {$B eq ""} {set B $b}
            if {$b eq ""} continue
            if {[package vcompare $b $B] < 0} { set B $b }
        }
        return $A-$B
    }
    #puts [vsimplify {8 8.4- 7.2-8.7.9 8.7.5-8.8}]; exit

    # parses a {Meta require} argument into a dictionary
    #
    # result can contain:
    #   {
    #       is       package 
    #       pkg      name 
    #       versions {a- b-c d} 
    #       platform windows|linux|macosx
    #       archglob *
    #   }
    proc parse_req {name args} {

        # ?ver ...? ?-opt val ...?
        set i -1
        foreach v $args {
            if {[string match -* $v]} break
            incr i
        }
        set vers [lrange $args 0 $i]
        set opts [lrange $args $i+1 end]

        # defaults:
        set o(-pkg)     $name
        set o(-exact)   false
        set o(-is)      package

        foreach {key val} $opts {
            if {$key ni {-archglob -is -platform -require  -version -exact}} {
                error "Invalid entity reference in \"$name\": $key"
            }
            if {$key eq "-require"} {
                lappend vers $val
            } else {
                set o($key) $val
            }
        }

        # backward-compatibility:
        if {[info exists o(-version)]} {
            if {$vers ne ""} {
                error "Cannot use -version with versions or -require"
            }
            lappend vers $o(-version)
            unset o(-version)
        }

        set vers [lmap v $vers {join $v -}]  ;# legacy list notation

        if {$o(-exact)} {
            if {[string match {*[- ]*} $vers]} {
                error "Can only use -exact with a single version! \"$name $vers\""
            }
            set v [lindex $vers 0]
            set v1 [split $v .]
            # FIXME: behaviour on a.b versions may be dodgy
            lset v1 end [expr {1+[lindex $v1 end]}]
            set v1 [join $v1 .]
            lset vers 0 $v-$v1
        }
        unset o(-exact)

        # normalise versions into vcompare strings
        set vers [lmap v0 $vers {
            if {[string match *-* $v0]} {
                string cat $v0
            } else {    ;# synthesise upper bound
                set v1 [split $v0 .]
                set v1 [lindex $v1 0]
                incr v1
                string cat $v0-$v1
            }
        }]

        if {[info exists o(-platform)]} {
            if {$o(-platform) ni {unix windows macosx}} {
                error "Invalid -platform $o(-platform) ($name)"
            }
        }

        if {$vers ne ""} {
            set o(-versions) [vsimplify $vers]
        }

        # result:
        dict map {k v} [array get o] {
            set k [string trimleft $k -]
            set v
        }
    }

    proc parse_teapot {path} {
        set meta [get_meta $path]
        set meta [string trim $meta]
        foreach line [split $meta \n] {
            set line [string trimleft $line #]
            set line [string trim $line]
            if {$line eq ""} {continue}
            try {
                set args [lassign $line cmd]
            } on error {} {
                error "Malformed teapot"
            }
            set cmd [string tolower $cmd]
            if {$cmd in {package profile application}} {
                lassign $args name version
                set pkgInfo($name-$version) [dict create name $name version $version]
                continue
            } elseif {$cmd ni {meta}} {
                error "Unknown TEAPOT.txt cmd: $cmd $args"
            }
            set args [lassign $args field]
            set field [string tolower $field]
            dict lappend pkgInfo($name-$version) $field {*}$args
        }
        array get pkgInfo
    }

    proc get_meta {path} {
        if {[file isdirectory $path]} {
            set fd [open $path/teapot.txt r]
            set meta [read $fd]
            close $fd
            return $meta
        }
        set fd [open $path r]
        if {[get_meta_text $fd meta]} {
            return $meta
        }
        seek $fd 0
        if {[get_meta_bin $fd meta]} {
            return $meta
        }
        close $fd
        set unmount [try_mount $path]
        if {$unmount ne ""} {
            try {
                return [get_meta $path]
            } finally {
                {*}$unmount
            }
        }
    }
    proc get_meta_text {fd _meta} {
        upvar 1 $_meta meta
        gets $fd line0
        if {![catch {llength $line0} r] && $r == 3} {
            gets $fd line1
            if {![catch {lindex $line1 0} r] && $r eq "Meta"} {
                set meta $line0\n$line1\n[read $fd]
                return true
            }
        }
        return false
    }
    proc get_meta_bin {fd _meta} {
        upvar 1 $_meta meta
        fconfigure $fd -encoding binary
        set block [read $fd 16384]
        return [regexp {# @@ Meta Begin(.*)# @@ Meta End} $block -> meta]
    }

    proc try_mount {path} {
        foreach ext {zip mk4 tar} {
            try {
                set fd [::vfs::${ext}::Mount $path $path]
            } on error {e o} {
                puts "Failed to mount ${ext}://$path"
                continue
            } on ok {fd} {
                puts "Mounted ${ext}://$path"
                return [list ::vfs::${ext}::Unmount $fd $path]
            }
        }
        return ""   ;# failed to mount
    }

    proc find {args} {
        set where [dict merge {
            pkg     %
            ver     0-
            path    %
        } $args]
        dict with where {}
        db eval {
            select path
            from teapkgs
            where name like :pkg
            and vsatisfies(ver, :ver)
            and path like :path || '%'
        }
    }

    proc deps {args} {
        set where [dict merge {
            pkg     %
            ver     0-
            path    %
        } $args]
        dict with where {}
        set reqs [db eval { 
            select value as reqs 
            from            teameta
              natural join  teapkgs
            where name like :pkg
              and vsatisfies(ver, :ver)
              and path like :path || '%'
               and field = ('require')
        }]
        set reqs [concat {*}$reqs]
        return [lmap r $reqs {parse_req {*}$r}]
    }

    namespace ensemble create -subcommands {scan deps find}
}

lib::main args {
    db::init leaves.db
    puts [leaves {*}$args]
}
