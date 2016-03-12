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
        ix86        {x86 intel i?86 i86pc}
        sparc       sun4%
        sparc64     {sun4u sun4v}
        universal   %
        %           ""
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
        puts "Setting up cuppa"
        db eval {
            create table if not exists servers (
                server text not null, uri text not null,
                last_checked integer default 0,
                primary key (server),
                unique (uri)
            );
            insert or replace
                into servers    (server,    uri)
                values  ( 'activestate',    'http://teapot.activestate.com'
                ),      ( 'rkeene',         'http://teapot.rkeene.org'
                );
            create table if not exists packages (
                name text,
                ver text collate vcompare,
                arch text, os text, cpu text,
                server text,
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
        dict with where {}
        db eval [string map [list * [join $fields ,]] $pkgquery]
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

    proc pkg_urls {name {os %} {cpu %}} {
        #init_maps
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

    proc check_exists {dir name ver} {
        foreach cmd [info commands [namespace current]::path:*] {
            set path [$cmd $dir $name $ver]
            if {[file exists $path]} {return $path}
        }
    }

    proc path:dl {dir name ver} {
        set name [string trimleft $name ::]
        file join $dir [string map {:: _ _ __} "$name-$ver.zip"]
    }
    proc path:tm {dir name ver} {
        set name [string trimleft $name ::]
        file join $dir [string map {:: /} "$name-$ver.tm"]
    }
    proc path:dir {dir name ver} {
        set name [string trimleft $name ::]
        file join $dir [string map {:: _ _ __} "$name-$ver"]
    }

    proc pkg_install {dir pkg args} {
        lassign [platform] os cpu
        set ver 0-
        dict with args {}
        if {$os eq "tcl"} {
            set cpu %
        }
        pkg_foreach {name ver uri} {name $pkg ver $ver os $os cpu $cpu} {
            set loc [check_exists $dir $name $ver]
            if {$loc ne ""} {
                throw [list CUPPA EXISTS $loc] "Package (might?) exist at \"$loc\""
            }
            set path [path:dl $dir $name $ver]
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
            set dest [path:tm $dir $name $ver]
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
            set dest [path:dir $dir $name $ver]
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
        find    pkg_urls
        install pkg_install
    }

    proc test {pkg args} {
        puts "Running on [platform::identify] ([platform::generic])"
        db::init cuppa.db
        init_maps
        update_cache
        db::stat
        #puts [join [pkg_urls $pkg {*}[platform]] \n]
        #puts :$args:
        #puts [join [pkg_urls $pkg {*}$args] \n]
        #puts ----
        pkg_install lib $pkg {*}$args
    }
}


#::cuppa::main {*}$argv
lib::main args {
    db::init cuppa.db
    puts [cuppa {*}$args]
}
