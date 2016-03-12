# leaves reads teapot descriptions
#
package require sqlite3
package require vfs::mk4
package require vfs::tar
package require vfs::zip

proc db_init {} {
    sqlite3 db ""
    db collate  vcompare    {package vcompare}
    db function vsatisfies  {{package vsatisfies}}
    db_setup
}

proc db_setup {} {
    db eval {drop table if exists teainfo; drop table if exists teameta}
    set exists [db onecolumn {
        select count(*) from sqlite_master
        where type = 'table' and name = 'teameta';
    }]
    if {$exists} {
        puts "pkgmeta already exists"
        return
    }
    puts "create table pkgmeta"
    db eval {
        create table teainfo (
            name text,
            version text collate vcompare,
            platform text,
            path text,
            primary key (path),
            -- index teainfo_i_nvp (name, version, platform),
            unique (path)
        );
        create table teameta (
            path text,
            field text,
            value text,
            foreign key (path)
              references pkg_meta (path)
                on delete cascade
        );
    }
}
#subject description require platform summary recommend category license

proc db_insert {args} {
    set keys {key name version platform path}
    set d [dict filter $args {*}$keys]
    dict with d {
        db eval {
            insert into teainfo ( name,  version,  platform,  path)
                         values (:name, :version, :platform, :path);

        }
    }
    foreach {field value} $args {
        if {$field in $keys} continue
        db eval {
            insert into teameta ( path,  field,  value)
                         values (:path, :field, :value);
        }
    }
}

proc db_scan {topdir args} {
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
    set n [db onecolumn {select count(1) from teainfo}]
    set m [db onecolumn {select count(1) from teameta}]
    puts "Scanned $n packages, learned $m things"
}


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
    # ?ver ...?
    set i -1
    foreach v $args {
        if {[string match -* $v]} break
        incr i
    }
    set versions [lrange $args 0 $i]
    set opts [lrange $args $i+1 end]

    # defaults:
    set o(-pkg)     $name
    set o(-exact)   false
    set o(-is)      package

    # ?-opt val ...?
    foreach {key val} $opts {
        if {$key ni {-archglob -is -platform -require  -version -exact}} {
            error "Invalid entity reference in \"$name\": $key"
        }
        if {$key eq "-require"} {
            lappend versions $val
        } else {
            set o($key) $val
        }
    }
    # backward-compatibility:
    if {[info exists o(-version)]} {
        if {$versions ne ""} {
            error "Cannot use -version with versions or -require"
        }
        lappend versions $o(-version)
        unset o(-version)
    }
    set versions [lmap ver $versions {join $ver -}]  ;# in vase of legacy list syntax
    if {$o(-exact)} {
        if {[string match {*[- ]*} $versions]} {
            error "Can only use -exact with a single version! \"$name $versions\""
        }
        set v0 [lindex $versions 0]
        set v1 [split $v0 .]
        lset v1 end [expr {1+[lindex $v1 end]}]
        set v1 [join $v1 .]
        lset versions 0 $v0-$v1
    }
    unset o(-exact)

    # normalise versions into vcompare strings
    set versions [lmap v0 $versions {
        if {![string match *-* $v0]} {
            set v1 [split $v0 .]
            set v1 [lindex $v1 0]
            incr v1
            set v0 $v0-$v1
        }
        set v0
    }]
    if {[info exists o(-platform)]} {
        if {$o(-platform) ni {unix windows macosx}} {
            error "Invalid -platform $o(-platform) ($name)"
        }
    }
    if {$versions ne ""} {set o(-versions) $versions}
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


db_init
db_scan {*}$argv
db eval {select path, field, value from teameta where field in ('require', 'recommend')} {
    puts "-- $path: $field: $value"
    foreach req $value {
        puts  " + [parse_req {*}$req]"
    }
}
#dict for {name desc} [parse_teapot {*}$argv] {
#    array set $name $desc
#    parray $name
#    puts ----
#}
