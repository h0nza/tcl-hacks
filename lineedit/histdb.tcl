namespace eval histdb {
    proc init {sqliteconn} {
        variable lastid ""
        interp alias {} [namespace current]::db {} $sqliteconn
        db eval {
            create table if not exists "history" (
                rowid integer primary key autoincrement,
                timestamp int,
                entry text
            );
        }
    }

    proc add {entry} {
        variable lastid
        if {[regexp {^[[:space:]]} $entry]} {
            set rec 0
        } elseif {[db exists {select 1 from "history" where rowid=$lastid and entry=$entry}]} {
            set rec 0
        } else {
            set rec 1
        }
        if {$rec} {
            set now [clock seconds]
            db eval {
                insert into "history" (timestamp, entry) values ($now, $entry);
            }
            set lastid [db last_insert_rowid]
        }
        return $lastid  ;# yes, even if it's not true!
    }

    proc get {id} {
        variable lastid
        db onecolumn {
            select entry from "history" where rowid = $id limit 1
        }
    }
    proc next {id} {
        db onecolumn {
            select rowid from "history" where rowid > $id order by rowid limit 1
        }
    }
    proc prev {id} {
        if {$id eq ""} {
            db onecolumn {
                select rowid from "history" order by rowid desc limit 1
            }
        } else {
            db onecolumn {
                select rowid from "history" where rowid < $id order by rowid desc limit 1
            }
        }
    }
    proc lastid {} {
        variable lastid
        return $lastid
    }
    proc curr {} {
        variable lastid
        lindex [db onecolumn {select entry from history where rowid = $lastid}]
    }
}


