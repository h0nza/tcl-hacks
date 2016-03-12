proc putl args {puts $args}
package require sqlite3
package require geturl
package require vfs::zip

package require platform

namespace eval cuppa {
    variable map_os {
        tcl         %
        linux-%     linux
        win32       windows
        solaris%    {solaris sunos}
        freebsd     freebsd_%
        irix        irix_%
        macosx%     darwin
    }
    variable map_cpu {
        ix86        {x86 intel i?86 i86pc}
        sparc       sun4%
        sparc64     {sun4u sun4v}
        universal   %
        %           ""
        powerpc     ppc
    }

    proc {package vsatisfies} args {
        set r [package vsatisfies {*}$args]
        if {$r} {puts vsat($r):$args?}
        return $r
    }

    proc init_db {{filename ""}} {

        sqlite3 db $filename
        db collate  vcompare    {package vcompare}
        db function vsatisfies  {{package vsatisfies}}

        set exists [db onecolumn {
            select count(*) from sqlite_master 
            where type = 'table' and name = 'servers';
        }]
        if {$exists} {
            puts "Using existing db"
            return
        }

        puts "Initialising new db"
        db eval {
            create table servers (
                server text not null, uri text not null,
                last_checked integer default 0,
                primary key (server),
                unique (uri)
            );
            insert into servers (server, uri) values (
                'activestate', 'http://teapot.activestate.com'
            ), (
                'rkeene',   'http://teapot.rkeene.org'
            );
            create table packages (
                name text,
                ver text collate vcompare,
                arch text, os text, cpu text,
                server text,
                primary key (name, ver, arch, os, cpu, server),
                foreign key (server) references servers (server)
            );

            create table map_os ( teapot text, local text );
            create table map_cpu ( teapot text, local text );
        }
        init_maps
    }

    proc stat_db {} {
        db eval {select name from sqlite_master where type = 'table'} {
            db eval "select count(1) count from \"$name\"" {
                puts "$name: $count records"
            }
        }
    }

    proc init_maps {} {
        puts "setting up CPU/OS mappings"

        variable map_os
        variable map_cpu

        db eval {delete from map_os; delete from map_cpu;}

        foreach {teapot local} $map_os {
            foreach t $teapot {
                foreach l $local {
                    db eval {
                        insert into map_os (teapot, local) values (:t, :l)
                    }
                }
            }
        }

        foreach {teapot local} $map_cpu {
            foreach t $teapot {
                foreach l $local {
                    db eval {
                        insert into map_cpu (teapot, local) values (:t, :l)
                    }
                }
            }
        }
    }

    proc server_uri {server path} {
        set base [db onecolumn {select uri from servers where server = :server}]
        string cat [string trimright $base /] / [string trimleft $path /]
    }
    proc update_cache {{limit 604800}} {
        set now [clock seconds]
        set last [expr {[clock seconds]-$limit}]
        db eval {select server, uri from servers where last_checked < :last} {
            cache_server $server
        }
        puts "Caches updated"
    }

    proc cache_server {server} {
        puts "Updating cache for $server"
        set data [geturl [server_uri $server /package/list]]
        set now [clock seconds]
        db eval {delete from packages where server = :server}
        regexp {\[\[TPM\[\[(.*)\]\]MPT\]\]} $data -> data
        foreach record $data {
            lassign $record type pkg ver arch
            if {$type ne "package"} continue
            if {$arch eq "source"} continue
            if {$arch eq "tcl"} {
                lassign {% %} os cpu
            } elseif {![regexp {^(.*)-([^-]*)} $arch -> os cpu]} {
                error "Can't match arch [list $arch]"
            }
            db eval {
                insert or replace
                into packages (name, ver, arch, os, cpu, server)
                values (:pkg, :ver, :arch, :os, :cpu, :server);
            }
        }
        db eval {
            update servers set last_checked = :now where server = :server;
        }
    }

    variable pkgquery {
            with t as (
                select distinct name, ver, arch, os, cpu, server, 
                    (uri || '/package/name/' || name 
                         || '/ver/'          || ver 
                         || '/arch/'         || arch 
                         || '/file'     
                    ) as uri
                from packages p
                inner join servers s using (server)
                where name like :name
                  and vsatisfies(ver, :ver)
                  and (cpu like :cpu
                   or exists (
                    select * from map_cpu
                    where (p.cpu like map_cpu.teapot or map_cpu.teapot like p.cpu)
                      and (:cpu like map_cpu.local or map_cpu.local like :cpu)
                  ))
                  and (os like :os
                   or exists (
                    select * from map_os
                    where (p.os like map_os.teapot or map_os.teapot like p.os)
                      and (:os like map_os.local or map_os.local like :os)
                  ))
            ) 
            select * from t where ver = (select max(ver) from t)
    }

    proc pkg_select {fields where} {
        variable pkgquery
        set where [uplevel 1 {dict create} $where]
        set where [dict merge {
            name % arch % os % cpu %
            ver 0-
        } $where]
        dict with where {
            db eval [string map [list * [join $fields ,]] $pkgquery]
        }
    }

    proc pkg_foreach {fields where body} {
        set script {
            foreach $fields [pkg_select $fields $where] $body
        }
        dict set map \$fields [list $fields]
        dict set map \$where  [list $where]
        dict set map \$body   [list $body]
        tailcall try [string map $map $script]
    }

    proc find_pkg {name os cpu args} {
        variable pkgquery
        tailcall db eval $pkgquery {*}$args
        ;#{} row {puts >>$row(*)} ;#{*}$args
    }

    proc pkg_urls {name {os %} {cpu %}} {
        init_maps
        pkg_select {uri} {name $name os $os cpu $cpu}
    }

    proc platform {} {
        split [platform::generic] -
    }

    proc download {path uri} {
        set data [geturl $uri]
        set fd [open $path w]
        fconfigure $fd -encoding binary
        puts -nonewline $fd $data[unset data]
        close $fd
        puts "Wrote $path"
    }

    proc pkg_install {dir pkg args} {
        lassign [platform] os cpu
        set ver 0-
        dict with args {}
        if {$os eq "tcl"} {
            set cpu %
        }
        pkg_foreach {name ver uri} {name $pkg ver $ver os $os cpu $cpu} {
            set path [file join $dir "$name-$ver.tm"]
            puts "Trying $uri -> $path"
            try {
                download $path $uri
            } on error {e o} {
                puts "geturl $uri -- $e"
                continue
            } on ok {} {
                break
            }
        }
        if {![info exists path]} {
            throw {INSTALL FAILED NOTFOUND} "No candidate $pkg for $os-$cpu"
        }
        if {![file exists $path]} {
            throw {INSTALL FAILED ERROR} "Failed to install $path"
        }
        try {
            set vfsd [vfs::zip::Mount $path $path]
        } on error {} {
            puts "$path is a tcl module: finished!"
            return $path
        }
        try {
            set dest [file rootname $path]
            if {[file exists $dest]} {
                error "Destination path exists: [list $dest]"
            }
            file copy $path [file rootname $path]
        } finally {
            vfs::zip::Unmount $vfsd $path
        }
        file delete $path
        set path [file rootname $path]
        puts "$path is a tcl package: finished"
        return $path
    }

    proc main {pkg args} {
        puts "Running on [platform::identify] ([platform::generic])"
        init_db cuppa.db
        init_maps
        update_cache
        stat_db
        #puts [join [pkg_urls $pkg {*}[platform]] \n]
        #puts :$args:
        #puts [join [pkg_urls $pkg {*}$args] \n]
        #puts ----
        pkg_install lib $pkg {*}$args
    }
}


::cuppa::main {*}$argv