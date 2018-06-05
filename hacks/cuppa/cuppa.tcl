package require sqlite3
package require geturl
package require vfs::zip
::tcl::tm::path add [pwd]
package require db
package require lib

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
        ix86        {x86 intel i_86 i86pc}
        sparc       sun4%
        sparc64     {sun4u sun4v}
        universal   %
        {""}        %
        powerpc     ppc
    }

    db::reset {
        db eval {
            drop table if exists servers;
            drop table if exists packages;
            drop table if exists map_os;
            drop table if exists map_cpu;
        }
    }
    db::setup {
        if {[db::exists servers]} return
        log::info {setting up cuppa}
        db eval {
            create table if not exists servers (
                server text not null, uri text not null,
                last_checked integer default 0,
                pri integer default 100,
                primary key (server),
                unique (uri)
            );
            insert or replace
                into servers (pri, server,    uri)
                values  ( 1, 'activestate',  'http://teapot.activestate.com'
                ),      ( 2, 'rkeene',       'http://teapot.rkeene.org'
                );
            create table if not exists packages (
                name    text,
                ver     text collate vcompare,
                arch    text, os text, cpu text,
                server  text,
                pkgurl  text,
                primary key (name, ver, arch, os, cpu, server),
                foreign key (server) references servers (server)
            );

            create table if not exists map_os ( teapot text, local text );
            create table if not exists map_cpu ( teapot text, local text );
        }
        init_maps
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

    proc join_url {args} {
        set url [join $args /\0/]
        regsub -all {/*\0/*} $url / url
        return $url
    }

    proc server_uri {server args} {
        db eval {select uri from servers where server = :server} {
            return [join_uri $uri {*}$args]
        }
    }
    proc update_cache {{limit 604800}} {
        set now [clock seconds]
        set last [expr {[clock seconds]-$limit}]
        log::info {updating servers since $last}
        db eval {select server, uri, last_checked from servers where last_checked < :last} {
            set when [clock format $last_checked]
            log::info {Updating cache for $server (last: $when)}
            cache_server $server $uri
        }
    }

    proc cache_server {server uri} {
        set data [geturl [join_url $uri /package/list]]
        set now [clock seconds]
        if { ![regexp {\[\[TPM\[\[(.*)\]\]MPT\]\]} $data -> data]} {
            throw {CUPPA BADTPM} "No TPM data at $uri"
        }
        if {  [catch {llength $data}] } {
            throw {CUPPA BADTPM} "TPM data not a list at $uri"
        }
        db eval {
            delete from packages where server = :server
        }
        foreach record $data {
            lassign $record type pkg ver arch
            if {$type ne "package"} continue
            if {$arch eq "source"}  continue
            regexp {^(.*)(?:-(.*))?$} $arch -> os cpu
            try {
                package vsatisfies $ver 0-
            } on error {e o} {
                log::warn {Bad version: ignoring! $pkg $ver @ $server}
                continue
            }
            set pkgurl [join_url $uri package name $pkg ver $ver arch $arch file]
            db eval {
                insert or replace
                into packages (name, ver, arch, os, cpu, server, pkgurl)
                values (:pkg, :ver, :arch, :os, :cpu, :server, :pkgurl);
            }
        }
        db eval {
            update servers set last_checked = :now where server = :server;
        }
    }

    db::qproc Find {
        name %  ver 0-  arch %  os %  cpu %
    } {
            with t as (
                select distinct name, ver, arch, os, cpu, server, pkgurl, pri
                from packages
                 inner join servers using (server)
                   -- inner join map_cpu on ( cpu like teapot and :cpu like local )
                where name like :name
                  and vsatisfies(ver, :ver)
                  and (cpu like :cpu
                    or exists (select * from map_cpu where cpu like teapot and :cpu like local))
                  and (os like :os
                    or exists (select * from map_os  where os  like teapot and :os  like local))
            )
            select * from t
            -- where ver = (select max(ver) from t)
            order by ver desc, pri;
    }

    proc find {args} {
        Find {pkgurl} $args {
            puts "Found at $pkgurl"
        }
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

    proc check_exists {dir name ver} {
        foreach cmd [info commands [namespace current]::Path:*] {
            set path [$cmd $dir $name $ver]
            if {[file exists $path]} {return $path}
        }
    }

    proc Path:dl {dir name ver} {
        set name [string trimleft $name ::]
        file join $dir [string map {:: _ _ __} "$name-$ver.zip"]
    }
    proc Path:tm {dir name ver} {
        set name [string trimleft $name ::]
        file join $dir [string map {:: /} "$name-$ver.tm"]
    }
    proc Path:dir {dir name ver} {
        set name [string trimleft $name ::]
        file join $dir [string map {:: _ _ __} "$name-$ver"]
    }

    proc install {dir pkg args} {
        lassign [platform] os cpu
        lib::dictargs args {
            os  $os
            cpu $cpu
            ver 0-
        }
        if {$os eq "tcl"} {
            set cpu %
        }
        Find {name ver uri} {name $pkg ver $ver os $os cpu $cpu} {
            set loc [check_exists $dir $name $ver]
            if {$loc ne ""} {
                throw [list CUPPA EXISTS $loc] "Package (maybe?) exists at \"$loc\""
            }
            set path [Path:dl $dir $name $ver]
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
            throw {CUPPA NOTFOUND} "No candidate $pkg for $os-$cpu"
        }
        if {![file exists $path]} {
            throw {CUPPA ERROR} "Failed to install $path"
        }
        try {
            set vfsd [vfs::zip::Mount $path $path]
        } on error {} {
            set dest [Path:tm $dir $name $ver]
            file rename $path $dest
            set path $dest
            puts "$path is a tcl module: finished!"
            return $path
        }
        try {
            set dest [file rootname $path]
            if {[file exists $dest]} {
                error "Destination path exists: [list $dest]"
            }
            set dest [Path:dir $dir $name $ver]
            file copy $path $dest
        } finally {
            vfs::zip::Unmount $vfsd $path
        }
        file delete $path
        set path $dest
        puts "$path is a tcl package: finished"
        return $path
    }

    namespace ensemble create -map {
        update  update_cache
        check   check_exists
        find    find
        install install
    }

}


#::cuppa::main {*}$argv
lib::main args {
    db::init cuppa.db
    puts [cuppa {*}$args]
}
