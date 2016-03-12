::tcl::tm::path add [pwd]
package require db

namespace eval billy {

    db::setup {
        db eval {
            create table if not exists packages (
                name text,
                ver text collate vcompare,
                arch text,
                filedata blob,
                primary key (name, ver, arch)
            );
        }
    }

    proc add_tms {path} {
        set re {([_[:alpha:]][:_[:alnum:]]*)-([[:digit:]].*)\.tm}
        foreach file [glob -tails -dir $path *.tm] {
            if {[regexp $re $file -> pkg ver]} {
                set fd [open [file join $path $file] r]
                fconfigure $fd -encoding binary -translation binary
                set filedata [read $fd]
                close $fd
                db eval {
                    insert into packages (name, ver, arch, filedata)
                    values (:pkg, :ver, 'tcl', @filedata);
                }
            }
        }
    }

    proc gen_tpm {} {
        set result {}
        db eval {
            select name, ver, arch from packages
        } {
            lappend result [list package $name $ver $arch 0]
        }
        return $result
    }

    proc serve {req} {
        if {[regexp {^/package/list/?$} $req]} {
            set tpm [gen_tpm]
            return [subst -noc {<!--[[TPM[[$tpm]]MPT]] -->}]
        }
        if {[regexp {^/package/name/(.*)/ver/(.*)/arch/(.*)/file$} $req -> name ver arch]} {
            db eval {
                select filedata from packages where
                    name = :name and ver = :ver and arch = :arch
                ;
            } {
                return $filedata
            }
        }
    }

    proc test {args} {
        ::db::init billy.db
        add_tms {*}$args
        puts [serve /package/name/mainscript/ver/1/arch/tcl/file]
        puts [serve /package/list]
    }
}

billy::test {*}$argv
