# actions:
# [x] index update ?server ...?
# [x] index info
# [x] index add /url/
# [x] index del /pattern/
# [x] cache info
# [x] cache drop ?pkginfo to match?
# [x] find ?pkginfo?
# [x] get /pkginfo/
# [x] cat /pkginfo/
# [x] meta /pkginfo/
# [x] deps /pkginfo/
# [x] mkenv directory
# [x] install directory name ?entityinfo?
# [ ] windows: tclsh.bat
# [ ] consider fixing shebang for applications
# [ ] serve .. or produce static teapot tree
#   - nanoweb: GET only, no keepalive, minimal header handling
# [ ] help and error handling
#   - put commands into a namespace with docs
# [ ] modularise and use appdirs
# [ ] parse tclenv.txt -> uninstall
#   - empty interp
# [ ] assemble & distribute
# [ ] isatty() ?
#
# teaparty synthesises a pkgIndex.tcl for tm's.  I don't wanna do that, so
# install needs to know about libpath + tmpath.
#
# different path for native libs?  hm?  good for xplat starkits.
#
# Teapot deficiencies:  by understanding and consuming these, I can define & serve something better
#   * metadata (requires) is only available embedded - in text, zip or vfs-in-exe (!)
#   * text/binary only known from http response
#   * extension must be inferred (particularly windows applications!)
#   * no incremental index updates
# Some of these could be read from HTML data, but not reliably

package require http
package require platform
package require sqlite3

source zip.tcl

proc finally {args} {
    tailcall trace add variable :#finally#: unset [list apply [list args $args]]
}

proc dictargs {defaults} {
    upvar 1 args args
    set keys [dict keys $defaults]
    if {[catch {dict size $args}]} {
        tailcall tailcall throw {TPM BAD_ARGS} "Expected dictionary argument with keys in [list $keys]"
    }
    dict for {k v} $args {
        if {$k ni $keys} {
            tailcall tailcall throw {TPM WRONG_ARGS} "Incorrect dictionary argument \"$k\", must be one of [list $keys]"
        }
    }
    set args [dict merge $defaults $args]
    tailcall dict with args {}
}

proc createfile {path data args} {
    set mode "w"
    if {[dict exists $args -binary]} {
        if {[dict get $args -binary]} {
            set mode "wb"
        }
        dict unset args -binary
    }
    if {[file exists $path]} {
        return -code error "File already exists! \"$path\""
    }
    log "Creating file \"$path\""
    set fd [open $path $mode]
    try {
        puts -nonewline $fd $data
    } finally {
        close $fd
    }
    if {$args ne ""} {
        file attributes $path {*}$args
    }
}

proc dedent {text} {
    set text [string trimleft $text \n]
    set text [string trimright $text \ ]
    regexp -line {^ +} $text space
    regsub -line -all ^$space $text ""
}


proc log {text} {
    puts stderr "# $text"
}

proc isatty {} {
    # unix:
    expr {![catch {exec sh -c {stty <&1} <@stdin >@stdout}]}
}

proc geturl {url} {
    set redirs 2
    while {1} {
        set tok [http::geturl $url]
        try {
            upvar 1 $tok state
            if {[set status [::http::status $tok]] ne "ok"} {
                throw {HTTP BAD_STATUS} "HTTP call returned \"$status\""
            }
            set headers [dict map {key val} [::http::meta $tok] {
                set key [string tolower $key]
                set val
            }]
            if {[dict exists $headers location]} {
                if {[incr redirs -1] <= 0} {
                    throw {HTTP TOO_MANY_REDIRECTS} "Too many redirections"
                }
                if {[regexp {^\w+://} $location]} {
                    set base ""
                } elseif {[regexp {^//} $location]} {
                    regexp {^(\w+:)//} $url -> base
                } elseif {[regexp {^/} $location]} {
                    regexp {^(\w+://[^/?]+)} $url -> base
                } else {
                    regexp {^(\w+://.+/)[^/]*} $url -> base
                }
                set location $base$location
                continue
            }
            return [::http::data $tok]
        } finally {
            ::http::cleanup $tok
        }
    }
}

proc join_url {args} {
    set url [join $args /\0/]
    regsub -all {/*\0/*} $url / url
    return $url
}

proc get_tpm {url} {
    set data [geturl $url]
    if {![regexp {\[\[TPM\[\[(.*)\]\]MPT\]\]} $data -> tpm]} {
        throw {TPM MISSING} "No TPM data at \"$url\""
    }
    return $tpm
}

# for mapping Teapot arch to requested arch
proc expand_arch {arch} {
    if {$arch eq "%"} {
        set arch "*"
    } elseif {$arch eq ""} {
        set arch [platform::patterns [platform::identify]]
    } else {
        set arch [platform::patterns $arch]
    }
    return $arch
}

proc lmatch {item list} {
    expr {$list eq "*" || $item in $list}
}

proc init_db {} {
    db eval {
        drop table if exists servers;
        drop table if exists pkgindex;
        drop table if exists packages;

        create table servers (
            rowid integer primary key asc,
            baseurl text not null,
            last_checked integer not null default 0,
            priority integer not null default 100,
            unique (baseurl)
        );

        create table pkgindex (
            rowid integer primary key,
            type text not null,
            name text not null,
            ver  text not null collate vcompare,
            arch text not null,
            os text not null,
            cpu text not null,
            url text not null,
            server_id integer not null,
            ts text default current_timestamp,
            unique (type, name, ver, arch, os, cpu, server_id),
            foreign key (server_id) references servers (rowid) on delete cascade
        );

        create table packages (
            rowid integer primary key asc,
            data blob not null,
            format text not null,
            pkgindex_id integer,
            ts text default current_timestamp,
            unique (pkgindex_id),
            foreign key (pkgindex_id) references pkgindex (rowid) on delete cascade
        );

        create table meta (
            package_id integer not null,
            key text not null,
            value text not null,
            primary key (package_id, key),
            foreign key (package_id) references packages (rowid) on delete cascade
        );
    }
}

proc index:del {baseurl} {
    db eval {
        select baseurl from servers where baseurl like :baseurl
    } row {
        lappend result [row_as_dict row]
    }
    db eval {
        delete from servers where baseurl like :baseurl
    }
    log "Deleted [db total_changes] total items"
    return -type dicts [lappend result]
}

proc index:refresh {{baseurl %}} {
    set baseurls [db onecolumn {select baseurl from servers where baseurl like :baseurl}]
    foreach baseurl $baseurls {
        index:add $baseurl
    }
}

proc index:add {baseurl} {

    log "Indexing $baseurl ..."

    try {
        set data [get_tpm [join_url $baseurl list]]
    } on error {} {
        set data [get_tpm [join_url $baseurl package list]]
    }

    log "$baseurl: [llength $data] entities"

    db eval {insert or ignore into servers (baseurl) values (:baseurl)}
    set server_id [db eval {select rowid from servers where baseurl = :baseurl}]

    db eval { update servers set last_checked = datetime('now', 'localtime') }
    db eval { delete from pkgindex where server_id = $server_id }

    db transaction {
        foreach ent $data {

            lassign $ent type name ver arch

            if {$type eq "profile"} continue    ;# used for collections - these just return metadata
            if {$type eq "redirect"} continue   ;# used for non-freely licensed pkgs @ activestate

            set os [lindex [split $arch -] 0]
            set cpu [lindex [split $arch -] end]

            if {[catch {package vsatisfies $ver 0-}]} {
                log "Ignoring bad version [list $name $ver]"
                continue
            }

            set url [join_url $baseurl $type name $name ver $ver arch $arch file]

            db eval {
                insert or replace
                into pkgindex (type, name, ver, arch, os, cpu, server_id, url)
                values (:type, :name, :ver, :arch, :os, :cpu, :server_id, :url);
            }
        }
    }

    log "$baseurl: [db total_changes] entities indexed"
}

proc index:info {args} {
    if {$args eq ""} {
        set args [db eval {select baseurl from servers}]
    }
    foreach baseurl $args {
        db eval {
            select
                baseurl, priority, last_checked,
                count(pkgindex.rowid) as items
            from servers
            left join pkgindex on (server_id = servers.rowid)
            where baseurl = :baseurl
            group by baseurl, priority, last_checked
        } row {
            lappend result [row_as_dict row]
        }
    }
    return -type dicts $result
}

proc cache:drop {args} {
    # FIXME: also support older than X
    dictargs {
        type %
        name %
        ver 0-
        arch %
        server %
    }
    set arch [expand_arch $arch]
    set rowids [db eval {
        select
            packages.rowid as rowid
        from packages
        inner join pkgindex on packages.pkgindex_id = pkgindex.rowid
        inner join servers on pkgindex.server_id = servers.rowid
        where 1
          and type like :type
          and name like :name
          and vsatisfies(ver, :ver)
          and lmatch(arch, :arch)
          and baseurl like :server
    }]
    log "Deleting [llength $rowids] records"
    db transaction {
        foreach rowid $rowids {
            db eval {
                delete from packages where rowid = :rowid
            }
        }
    }
    return ""
}

proc cache:info {args} {
    dictargs {
        type %
        name %
        ver 0-
        arch %
        server %
    }
    set arch [expand_arch $arch]
    db eval {
        select
            type, name, ver, arch
            format,
            length(data) as size,
            baseurl
        from packages
        inner join pkgindex on packages.pkgindex_id = pkgindex.rowid
        inner join servers on pkgindex.server_id = servers.rowid
        where 1
          and type like :type
          and name like :name
          and vsatisfies(ver, :ver)
          and lmatch(arch, :arch)
          and baseurl like :server
        order by type, name, ver desc, arch
    } row {
        lappend result [row_as_dict row]
    }
    lappend result
    return -type dicts $result
}

proc find {name args} {
    dictargs {
        type %
        ver 0-
        arch ""
        server %
        limit 99999999
    }
    set arch [expand_arch $arch]
    lassign [split [platform::generic] -] os_ cpu_
    db eval {
        select distinct
            pkgindex.rowid as rowid, type, name, ver, arch, url
        from pkgindex
        inner join servers on (server_id = servers.rowid)
        where 1
          and type like :type
          and name like :name
          and baseurl like :server
          and vsatisfies (ver, :ver)
          and lmatch(arch, :arch)
        order by name, ver desc, priority desc
        limit :limit
    } row {
        lappend result [row_as_dict row]
    }
    lappend result
    return -type dicts $result
}

proc row_as_dict {_row} {
    upvar 1 $_row row
    foreach k $row(*) {
        lappend res $k $row($k)
    }
    lappend res
}

proc download {name args} {
    foreach _ [find $name limit 1 {*}$args] {
        dict with _ {}
        log "Downloading $type $name from $url"
        return -type data [geturl $url]
    }
}

proc is_zipdata {data} {
    string match "PK\3\4*" $data
}

proc show {name args} {
    set _ [get $name {*}$args]
    dict with _ {
        set size [string length $data]
        unset data
    }
    return -type dicts [list $_]
}

proc get {name args} {
    foreach _ [find $name limit 1 {*}$args] {
        dict with _ {}
        db eval {
            select format, data from packages where pkgindex_id = :rowid
        } row {
            log "Already have $name $args"
            return -type ignore [dict merge $_ [row_as_dict row]]
        }
        set data [download $name {*}$args]
        if {[is_zipdata $data]} {               ;# FIXME: must use http content-type, as there are executables too
            set format "zip"
        } else {
            set format "tm"
        }
        db eval {
            insert into packages (data, format, pkgindex_id) values (:data, :format, :rowid);
        }
        log "Downloaded [string length $data] bytes"
        db eval {
            select format, data from packages where pkgindex_id = :rowid
        } row {
            return -type ignore [dict merge $_ [row_as_dict row]]
        }
    }
    throw {TPM NOT_FOUND} "No package found matching $name $args"
}

proc cat {name args} {
    set _ [get $name {*}$args]
    dict with _ {}
    if {$format eq "zip"} {
        return -type binary $data
    } else {
        return -type text $data
    }
}

# it would be nice if specific meta fields could be requested: require, depend, description ..
proc meta {name args} {
    try {
        cat $name {*}$args
    } on ok {data opts} {
        set format [dict get $opts -type]
    }
    if {$format eq "text"} {
        if {![regexp {@@ Meta Begin\s*(.*)\n.*@@ Meta End} $data -> meta]} {
            throw {TPM NO_METADATA} "No metadata in $name $args!"
        }
    } else {
        set zip [Zip new $data]
        set meta [$zip comment]
        if {[regexp {\mMeta\M} $meta]} {
            log "Found metadata in zip comment"
        } else {
            set meta [$zip contents teapot.txt]
            log "Found metadata in zip teapot.txt"
        }
        $zip destroy
    }
    # FIXME: should check first line for eg {Package name version}
    if {$meta eq ""} {
        throw {TPM NO_META} "Metadata not found!"
    }
    # fill in required keys first:
    set res {
        require ""
    }
    set meta [regexp -line -inline -all {^(?:\s*#)?\s*Meta (\S+)\s+(.*)} $meta]
    foreach {_ key val} $meta {
        dict lappend res $key {*}$val
    }
    return -type dict $res
}

proc deps {name args} {
    set meta [meta $name {*}$args]
    foreach req [dict get $meta require] {
        if {[llength $req] > 2} {
            # FIXME: parse properly
            #   <name> <ver> -is application
            #throw {TPM UNIMPLEMENTED} "Unsupported requirement format: $req"
            log "Ignoring unknown extra fields in requirement: $req"
        }
        lassign $req name version
        #if {$name in {Tcl Tk}} continue
        lappend res [list name $name ver $version]
    }
    lappend res
    return -type dicts $res
}

proc mkenv {dir} {
    if {[file isdirectory $dir]} {
        throw {TPM EXISTS} "Directory \"$dir\" already exists!"
    }

    set tclexe [info nameofexe]
    set tclver [info patch]
    regexp {^(\d+).(\d+)} $tclver -> majver minver

    log "Creating Tcl environment in $dir for $tclexe ($tclver)"
    file mkdir $dir
    file mkdir $dir/bin $dir/lib $dir/modules

    set dir [file normalize $dir]

    createfile $dir/bin/activate [dedent [subst -noc {
        # source this file to initialize your env:
        PATH="$dir/bin:\$PATH"
        # FIXME: what if these are already set?
        TCLLIBPATH="$dir/lib"
        TCL${majver}_${minver}_TM_PATH="$dir/modules"
        export PATH TCLLIBPATH TCL${majver}_${minver}_TM_PATH
    }]]

    createfile $dir/bin/tclsh [dedent [subst -noc {
        #!/bin/sh
        . "$dir/bin/activate"
        exec "$tclexe" "\$@"
    }]] -permissions 0755

    createfile $dir/tclenv.txt [dedent [subst {
        # Tcl environment initialised at [clock format [clock seconds]]
        tcl_version $tclver
        platform    [platform::identify]

        bindir      [list bin]
        libdir      [list lib]
        tmdir       [list modules]

    }]]
}

proc install {dir name args} {
    set fd [open $dir/tclenv.txt r+]
    finally close $fd

    # FIXME: read params from this file, so we know what's already installed
    seek $fd 0 end

    # collect dependencies ..
    set deps {}
    lappend deps [dict create name $name {*}$args]

    for {set i 0} {$i < [llength $deps]} {incr i} {
        set dep [lindex $deps $i]
        log "# depends: $dep"

        set dep_name [dict get $dep name]
        dict unset dep name
        set dep_args $dep

        foreach rdep [deps $dep_name {*}$dep_args] {
            if {[dict get $rdep name] in {Tcl Tk}} continue     ;# FIXME ...
            if {[dict exists $rdep ver] && [dict get $rdep ver] eq ""} {           ;# FIXME: dicts-everywhere would simplify this
                dict unset rdep ver
            }
            if {$rdep ni $deps} {
                lappend deps $rdep
            }
        }
    }

    foreach pkgdesc $deps {
        set name [dict get $pkgdesc name]
        dict unset pkgdesc name
        set args $pkgdesc
        log "Installing $name $args"
        set _ [get $name {*}$args]
        dict with _ {}

        switch $type {
            "profile" {
                log "$name is a profile, nothing to install"
            }
            "application" {
                # FIXME: think of extension
                createfile [set loc $dir/bin/$name] $data -permissions 0755
            }
            "package" {
                switch $format {
                    "tm" {
                        createfile [set loc $dir/modules/$name-$ver.tm] $data
                    }
                    "zip" {
                        file mkdir [set loc $dir/lib/$name$ver]
                        set z [Zip new $data]
                        foreach ent [$z names] {
                            if {[string match */ $ent]} {
                                file mkdir $loc/$ent
                            } else {
                                createfile $loc/$ent [$z contents $ent] -binary 1
                            }
                        }
                    }
                    default {
                        throw {TPM UNIMPLEMENTED} "Unsupported entity format \"$format\""
                    }
                }
            }
            default {
                throw {TPM UNIMPLEMENTED} "Unsupported entity type \"$type\""
            }
        }
        puts $fd [list installed $name $ver $loc]
    }


    close $fd
}

proc main {args} {
    chan configure stdout -buffering none
    set ex [file exists tpc.db]
    sqlite3 db tpc.db
    db eval {
        pragma foreign_keys = on
    }
    db collate  vcompare    {package vcompare}
    db function vsatisfies  {package vsatisfies}
    db function lmatch      lmatch

    if {!$ex} {
        init_db
        index:add http://teapot.rkeene.org/
        index:add http://teapot.activestate.com/
    }

    try {
        set r [{*}$args]
    } trap {TPM} {err opt} {
        log "Error: $err"
        return 1
    } on ok {res opt} {
        if {![dict exists $opt -type]} {
            dict set opt -type text
        }
        switch [dict get $opt -type] {
            ignore {}
            dict {
                array set {} $res
                parray {}
            }
            dicts {
                set row [lindex $res 0]
                dict unset row rowid
                set keys [dict keys $row]
                puts \x1b\[1m[join $keys \t]\x1b\[0m
                foreach row $res {
                    dict unset row rowid
                    puts [join [dict values $row] \t]
                }
            }
            table {
                foreach row $res {
                    puts [join $row \t]
                }
            }
            text {
                puts -nonewline $res
            }
            binary {
                set trans [chan configure stdout -translation]
                chan configure stdout -translation binary
                puts -nonewline stdout $res
                chan configure stdout -translation $trans
            }
            default {
                if {$res ne ""} {puts $res}
            }
        }
    }
    return 0
}

exit [main {*}$::argv]
