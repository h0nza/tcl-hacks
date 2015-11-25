# this also wants a less conflicty name.  For the package, not the object.
#
# I want this:
#
#    [sql {from [qn $table] [qn $t1] inner join [qn $table] [qn $t2]}]
#
# but to get local variables requires much trickery (capture unbound? + namespace unknown)
#
# SYNOPSIS
#
#  Sql select table columns ?sql?
#  Sql select sql columns ?sql?
#  Sql select ::sqlobj columns ?sql?
# 
#  Sql count ( table | sql | ::sqlobj )
#  Sql distinct (..) ?columns?
#  Sql columns ::sqlobj
# 
#  Sql trim sql
#  Sql format sql
# 
#  Sql qstr
#  Sql qname part ?part?
#  Sql qcols
#
# .. this is not ready to use
#

package require pkg
pkg -export Sql sql {
    oo::class create SqlClass {

if 0 {
        method tokenise {sql} {
            # words
            # 'quo''ted'
            # "quot""ed"
            # `quot``ed`
            # /* comment */
            # -- comment
            # , ( ) ;
        }
}
        method trim {sql} {
            # FIXME: get a real tokeniser
            regsub -all -line {^--\s.*$}    $sql {} sql     ;# -- comments
            regsub -all {/\*((?!\*/).)*\*/} $sql {} sql     ;# /* comments */
            string trim $sql "; \n"
        }

        method kind {sql} {
            regexp {^(\w+)} [my trim $sql] -> word
            set word [string tolower $word]
            catch {debug assert {$word in "select insert update create drop delete alter"}}
            if {$word eq "select"} {
                if {[regexp -nocase {^select\s+count\s*\([^\)]*\)\s+from\s+} $sql]} {
                    lappend word "count"
                }
                if {[regexp -nocase {^select\s+distinct\s} $sql]} {
                    lappend word "distinct"
                }
            }
            if {$word in "create drop"} {
                regexp {^\w+\s*(\w+)} $sql -> what
                catch {debug assert {$what in "table index"}}
                lappend word $what
            }
            return $word    ;# this could do with some metadata ...
        }

    # simple query generation:
        method select {table cols {sql "1"}} {
            return "SELECT \
                [my qcols $cols] \
                FROM [my qname $table] \
                WHERE $sql"
        }
        method count {table {sql "1"}} {
            return "SELECT count(1) \
                FROM [my qname $table] \
                WHERE $sql"
        }
        method distinct {columns {sql "1"}} {
            return "SELECT DISTINCT \
                    [my qcols $columns] \
                FROM [my qname $table] \
                WHERE $sql"
        }
        method cdistinct {columns table {sql "1"}} {
            # should be select * ?
            return "SELECT \
                    count(1) [my qname #],
                    [my qcols $columns] \
                FROM [my qname $table] \
                GROUP BY [my qcols $columns \
                HAVING $having"
        }

        forward set   my qdict -join ", "
        #forward where my qdict -join "\n  AND "
        method where args {
            if {[llength $args] == 1} {
                tailcall my qdict -join "\n  AND " {*}$args
            }
            join [lmap arg $args {
                string cat ([my qdict -join " AND " $arg])
            }] "\n   OR "
        }

        method update {table {set {}} {where {}}} {
            append res "UPDATE [my qname $table]"
            if {$set ne ""} {
                append res "\nSET [my set $set]"
            }
            if {$where ne ""} {
                append res "\nWHERE [my where $where]"
            }
            return $res
        }

        method delete {table {args {}}} {
            append res "DELETE FROM [my qname $table]\n"
            if {$args ne ""} {
                append res "WHERE "
                append res [join [lmap where $args {
                    string cat ([my where $where])
                }] "\n  OR "]
            }
            return $res
        }

        # this could take options to make it more generic:
        #   -notnull "*"
        #   -types $dict
        method create_table {tableName colNames} { ;# sqlite specific!
            #set colspec [join [lmap col $colNames {K "[my qname $colName] NOT NULL"}] ", "]
            return "CREATE TABLE [my qname $tableName] ([my qcols $colNames])"
        }
                    
        method insertdicts {tableName dict args} {
            set cols [dict keys $dict]
            append res "INSERT INTO [my qname $tableName] ([my qcols $cols])\n"
            append res " VALUES ([my qlist [dict values $dict]])"
            while {$args ne "" && [dict keys [lindex $args 0]] eq $cols} {
                set args [lassign $args dict]
                append res ",\n ([my qlist [dict values $dict]])"
            }
            append res "\n;"
            if {$args ne ""} {
                append res [insertdicts $tableName {*}$args]
            }
            return $res
        }

        # values are not quoted, so they can be "$var"
        method insert {tableName colNames args} {
            return "INSERT INTO [my qname $tableName] ([my qcols $colNames])\n\
                VALUES [join [lmap vals $args {
                    string cat ( [join $vals ,] )
                }] ,]"
        }

    # quotation:
        method qname {args} {
            foreach a $args {
                set a [string map {` ``} $a]
                lappend res `$a`
            }
            return [join $res .]
        }

        # doesn't add brackets
        method qlist {list} {
            join [map {my qstr} $list] ,
        }
        # quote a (string) value:
        method qstr {value} {
            set value [string map {' ''} $value]
            return '$value'
        }

        ## quote a list of column names:
        # this seems to be a bit overloaded
        method qcols {columns {attr {}} {prepend {}}} {
            set res [join [lmap c $columns {subst {[my qname $c] $attr}}] ,]
            if {($prepend ne {}) && ($res ne {})} {
                set res $prepend$res
            }
            return $res
        }

        method qdict args {
            options {-table {}} {-join " AND "}
            arguments {dict}
            if {$table ne ""} {set table [list $table]}
            join [lmap {col val} $dict {
                string cat [
                    my qname {*}$table $col
                ] " = " [
                    my qstr $val    ;# ?? numbers?
                ]
            }] $join
        }

        method unknown {method args} {
            set match [lsearch -all -inline -glob [info object methods [self] -all] $method*]
            if {[llength $match] eq 1} {
                tailcall my $match {*}$args
            }
            throw {TCL METHOD_UNKNOWN} "Method unknown"
        }
    }
    SqlClass create Sql
}
