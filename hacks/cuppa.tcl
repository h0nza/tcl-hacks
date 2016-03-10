package require sqlite3
package require geturl

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
        sparc64     sun4u sun4v
        universal   %
        powerpc     ppc
    }

    proc init_db {{filename ""}} {

        sqlite3 db $filename
        db collate vcompare {package vcompare}

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

    proc init_maps {} {
        puts "setting up CPU/OS mappings"

        variable map_os
        variable map_cpu

        db eval {delete from map_os; delete from map_cpu;}

        foreach {teapot local} $map_os {
            foreach t $teapot l $local {
                db eval {
                    insert into map_os (teapot, local) values (:t, :l)
                }
            }
        }

        foreach {teapot local} $map_cpu {
            foreach t $teapot l $local {
                db eval {
                    insert into map_cpu (teapot, local) values (:t, :l)
                }
            }
        }
    }

    proc server_uri {server path} {
        set base [db onecolumn {select uri from servers where server = :server}]
        string cat [string trimright $base /] / [string trimleft $path /]
    }
    proc update_cache {{limit 38400}} {
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

    proc find_pkg {name os cpu args} {
        db eval {
            with t as (
                select distinct name, ver, arch, os, cpu, server, uri 
                from packages p
                inner join servers s using (server)
                where name like :name
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
        } {*}$args
    }

    proc pkg_urls {name {os %} {cpu %}} {
        find_pkg $name $os $cpu {
            puts "$uri/package/name/$name/ver/$ver/arch/$arch/file"
        }
    }

    proc main {} {
        init_db cuppa.db
        update_cache
        puts [pkg_urls {*}$::argv]
    }
}


::cuppa::main
