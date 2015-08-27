# This is a CSV parser with a much more pleasant interface (and code!) than the tcllib csv module
# but test-compatible through the csv namespace aliases below
#
# This is within half the speed of tcllib csv in the common configuration
# (quote=escape, no special map, rfcquotes on or off).  It is slightly faster than tcllib with -alternate,
# and about an order of magnitude slower for exotic cases that csv might not be able to handle anyway
#
#tcl::tm::path add [pwd]
package require options
package require tests
package require escape
package require debug   ;# for assert

catch {namespace delete tsv}
namespace eval tsv {
    oo::class create TextSplitter {

        variable separator
        variable quote
        variable quote_re
        variable escape
        variable rfcquotes
        variable newline        ;# how embedded newlines should look - yes, this is for excel
                                ;# not used for reading!
        variable special

        variable CanQuickSplit

        constructor args {

            options {-separator ,} {-quote \"} {-escape {}} {-rfcquotes} {-newline \n} {-special {}}

            if {$escape eq ""} {set escape $quote}

            set quote_re [quote_regex $quote]

            set CanQuickSplit [expr {$escape eq $quote && $special eq ""}]

            if {$rfcquotes} {
                dict set special $quote$quote $quote
            }

            # error-message compatibility with tcllib csv:
            switch -glob $separator {
                "" {
                    return -code error "illegal separator character \"$separator\", is empty"
                }
                "??*" {
                    return -code error "illegal separator character \"$separator\", is a string"
                }
            }
        }

        method QuickSplit {input nq} {
            # a split that is specialised for $escape == $quote, which runs a heck of a lot faster
            # than the big-regexp version.  Still about 4x slower than tcllib though.
            #
            # tokens are:
            #   $separator
            #   $quote
            #   $quote$quote

            set parts [split $input $separator]

            if {!$nq} {
                return $parts   ;# fast path with no quotes in the line
            }

            set sm [list $quote$quote $quote]
            set dqre "^${quote_re}(.*)${quote_re}$"

            set res {}
            set n [llength $parts]
            for {set i 0} {$i < $n} {incr i} {
                set part [lindex $parts $i]
                if {$part ne ""} {
                    while {[set q [regexp -all $quote_re $part]] && ($q % 2)} {
                        set next [lindex $parts [incr i]]
                        append part $separator$next
                    }
                    if {$q} {
                        if {!$rfcquotes && $part eq {""}} {
                            set part {}
                        } else {
                            set part [string map $sm $part]
                            if {[regexp $dqre $part -> inner]} {
                                set part $inner
                            }
                        }
                    }
                }
                lappend res $part
            }
            return $res
        }

        # public interface
        method split {input} {
            # This is incredibly slow next to tcllib tsv:  like >2 orders of magnitude on a Very Wide file.
            # so QuickSplit is specialised for the common case
            set parts {}
            if {[regexp "^[quote_regex $separator]" $input]} {
                lappend parts ""
            }
            #debug show {[my Regexp]}
            lappend parts {*}[lmap {match word bare quoted} [regexp -all -inline [my Regexp] $input] {
                debug assert {$bare eq "" || $quoted eq ""}
                #debug show {[list $bare $quoted $word $match]}
                if {[dict exists $special $word]} {
                    dict get $special $word
                } else {
                    if {$bare eq ""} {
                        set word $quoted
                    } else {
                        set word $bare
                    }
                    my UnArmour $word
                }
            }]
            return $parts
        }
        method next {chan} {
            set input ""
            while {$input eq ""} {
                if {[eof $chan]} {
                    return -code break
                }
                append input [gets $chan]
            }
            if {$escape eq $quote} {
                while {[set nq [regexp -all $quote_re $input]] % 2} {
                    append input \n[gets $chan]
                    if {[eof $chan]} {
                        throw {TSV ERROR} "Unexpected EOF after [list $input]"
                    }
                }
                if {$CanQuickSplit} {
                    return [my QuickSplit $input $nq]
                }
            } else {
                while {![my IsComplete $input]} {
                    append input \n[gets $chan]
                    if {[eof $chan]} {
                        throw {TSV ERROR} "Unexpected EOF after [list $input]"
                    }
                }
            }
            return [my split $input]
        }

        method join args {
            options -quotealways
            arguments {list}
            set chars [quote_regex $quote][quote_regex $separator][quote_regex $escape]
            set re "\[\\r\\n$chars\]"
            join [lmap word $list {
                if {$quotealways || [regexp $re $word]} {
                    string cat $quote [my Armour $word] $quote
                } {
                    string cat $word
                }
            }] $separator
        }

        method writer {chan} {
            coroutine [uplevel 1 gensym tsvwriter] my Write $chan
        }
        method Write {chan} {
            set head [yield [info coroutine]]
            set nf [llength $head]
            my Puts $chan [my join $head]
            while {"" ne [set row [yield]]} {
                debug assert {[llength $row] == $nf}
                my Puts $chan [my join $row]
            }
        }

        method Puts {chan line} {
            if {$newline eq ""} {
                puts $chan $line
            } else {
                set crlf [fconfigure $chan -translation]
                fconfigure $chan -translation lf
                puts -nonewline $chan $line
                fconfigure $chan -translation $crlf
                puts $chan ""
            }
        }

        # private
        method IsComplete {input} {
            regexp "^([my Regexp])*$" $input
        }
        method Regexp {} {
            set map {< ( > ) ( (?: ) )}
            lappend map  , [quote_regex $separator]
            lappend map  e [quote_regex $escape]
            lappend map  q [quote_regex $quote]

            set bare {<[^,q]*>} ;# should this include q?
            if {$escape eq $quote} {
                set quoted {q<(qq|[^q])*>q}
            } else {
                set quoted {q<(e.|[^qe])*>q}
            }
            set field "(${bare}|${quoted})"
            #set re "<${field}>"
            #set re [string map $map $re]
            #set re "${re}(,|$)"

            set re "(^|,)<${field}>"
            set re [string map $map $re]

            #set re "^($field)(,$field)*$"
        }

        method UnArmour {word} {
            if {$escape eq $quote} {
                string map [list $quote$quote $quote] $word
            } else {
                regsub -inline -all "[quote_regex $escape](.)" $word {\1}
            }
        }
        method Armour {word} {
            if {$newline ne ""} {
                set word [regsub -all {\r|\r\n|\n} $word $newline]  ;# Wat the fuck excel
            }
            if {$escape eq $quote} {
                string map [list $quote $quote$quote] $word
            } else {
                string map [list $quote $escape$quote $escape $escape$escape] $word
            }
        }
    }

    # now the interface
    TextSplitter create mscsv -newline \n    ;# HACK
    TextSplitter create tsv -separator \t
    TextSplitter create rfcsv -rfcquotes

    namespace export {[a-z]*}
}
namespace import tsv::*

# for test-compatibility with tcllib's csv
#
# this shim allows all of tcllib csv's tests to run with the exception of:
#  3.1 3.2:         malformed input
#  7.3 7.4 7.5 7.6: argument error syntax from report
#  8.0 8.1:         argument error syntax from split

return
namespace eval csv {
    proc split args {
        options -alternate
        arguments {line {sepChar ,} {delChar \"}}
        if {$alternate} {
            set x [::tsv::TextSplitter new -separator $sepChar -quote $delChar]
        } else {
            set x [::tsv::TextSplitter new -separator $sepChar -quote $delChar -rfcquotes]
        }
        try {
            $x split $line
        } finally {
            $x destroy
        }
    }
    proc join args {
        arguments {values {sepChar ,} {delChar \"} {delMode ""}}
        set x [::tsv::TextSplitter new -separator $sepChar -quote $delChar]
        try {
            if {$delMode ne ""} {
                $x join -quotealways $values
            } else {
                $x join $values
            }
        } finally {
            $x destroy
        }
    }
    proc joinlist {values args} {
        return [::join [lmap list $values {
            ::csv::join $list {*}$args
        }] \n]\n
    }

    # this could use split2matrix / read2matrix / read2queue in order to get the full benefit
    # of the test harness
    # ::csv::split2queue ?-alternate? q line {sepChar ,}
    proc split2queue args {
        options -alternate
        arguments {q line {sepChar ,}}
        set q [uplevel 1 [list namespace which $q]]
        if {$alternate} {
            set row [split -alternate $line $sepChar]
        } else {
            set row [split $line $sepChar]
        }
        $q put $row
    }
    # ::csv::split2matrix ?-alternate? m line {sepChar ,} {expand none}
    proc split2matrix args {
        options {-alternate}
        arguments {m line {sepChar ,} {expand none}}
        set m [uplevel 1 [list namespace which $m]]
        set alternate [expr {$alternate ? "-alternate" : ""}]
        set row [split {*}$alternate $line $sepChar]
        Split2matrix $m $row $expand
    }
    proc Split2matrix {m row expand} {
        switch -exact -- $expand {
            none {}
            empty {
                if {[$m columns] == 0} {
                    $m add columns [llength $row]
                }
            }
            auto {
                if {[$m columns] < [llength $row]} {
                    $m add columns [expr {[llength $row] - [$m columns]}]
                }
            }
        }
        $m add row $row
    }

    # ::csv::read2queue ?-alternate? chan q {sepChar ,}
    proc read2queue args {
        options -alternate
        arguments {chan q {sepChar ,}}
        set q [uplevel 1 [list namespace which $q]]
        if {$alternate} {
            set x [::tsv::TextSplitter new -separator $sepChar]
        } else {
            set x [::tsv::TextSplitter new -separator $sepChar -rfcquotes]
        }
        while {![eof $chan]} {
            set r [$x next $chan]
            $q put $r
        }
    }
    # ::csv::read2matrix ?-alternate? chan m {sepChar ,} {expand none}
    proc read2matrix args {
        options -alternate
        arguments {chan m {sepChar ,} {expand none}}
        set m [uplevel 1 [list namespace which $m]]
        if {$alternate} {
            set x [::tsv::TextSplitter new -separator $sepChar]
        } else {
            set x [::tsv::TextSplitter new -separator $sepChar -rfcquotes]
        }
        while {![eof $chan]} {
            set row [$x next $chan]
            Split2matrix $m $row $expand
        }
    }
    # ::csv::writematrix m chan ?sepChar? ?delChar?
    proc writematrix {m chan {sepChar ,} {delChar \"}} {
        set m [uplevel 1 [list namespace which $m]]
        set n [$m rows]
        for {set r 0} {$r < $n} {incr r} {
            puts $chan [join [$m get row $r] $sepChar $delChar]     ;# FIXME: embedded newlines :(
        }
    }
    # ::csv::writequeue q chan ?sepChar? ?delChar?
    proc writequeue {q chan {sepChar ,} {delChar \"}} {
        set q [uplevel 1 [list namespace which $q]]
        while {[$q size] > 0} {
            puts $chan [join [$q get] $sepChar $delChar]            ;# FIXME: embedded newlines :(
        }
    }
    # ::csv::report cmd matrix ?chan?
    oo::object create report
    oo::objdefine report {
        method printmatrix {matrix} {
            ::csv::joinlist [$matrix get rect 0 0 end end]
        }
        method printmatrix2channel {matrix chan} {
            ::csv::writematrix $matrix $chan
        }
    }
}


tests {
package require debug
package require struct::queue
package require struct::matrix
# -------------------------------------------------------------------------

set str1 {"123","""a""",,hello}
set str2 {1," o, ""a"" ,b ", 3}
set str3 {"1"," o, "","" ,b ", 3}
set str4 {1," foo,bar,baz", 3}
set str5 {1,"""""a""""",b}
set str6 {123,"123,521.2","Mary says ""Hello, I am Mary"""}

set str1a {123,"""a""",,hello}
set str3a {1," o, "","" ,b ", 3}

# Custom delimiter, =

set str1_ {=123=,===a===,,hello}
set str2_ {1,= o, ==a== ,b =, 3}
set str3_ {=1=,= o, ==,== ,b =, 3}
set str4_ {1,= foo,bar,baz=, 3}
set str5_ {1,=====a=====,b}
set str6_ {123,=123,521.2=,=Mary says "Hello, I am Mary"=}

set str1a_ {123,===a===,,hello}
set str3a_ {1,= o, ==,== ,b =, 3}

set str7 {=1=,=====a=====,=b=}

# -------------------------------------------------------------------------

test csv-1.1 {split} {
    csv::split $str1
} {123 {"a"} {} hello}

test csv-1.2 {split} {
    csv::split $str2
} {1 { o, "a" ,b } { 3}}

test csv-1.3 {split} {
    csv::split $str3
} {1 { o, "," ,b } { 3}}

test csv-1.4 {split} {
    csv::split $str4
} {1 { foo,bar,baz} { 3}}

test csv-1.5 {split} {
    csv::split $str5
} {1 {""a""} b}

test csv-1.6 {split} {
    csv::split $str6
} {123 123,521.2 {Mary says "Hello, I am Mary"}}

test csv-1.7 {split on join} {
    # csv 0.1 was exposed to the RE \A matching problem with regsub -all
    set x [list "\"hello, you\"" a b c]
    ::csv::split [::csv::join $x]
} [list "\"hello, you\"" a b c]


test csv-1.8-1 {split empty fields} {
    csv::split {1 2 "" ""} { }
} {1 2 {"} {"}}

test csv-1.9-1 {split empty fields} {
    csv::split {1 2 3 ""} { }
} {1 2 3 {"}}

test csv-1.10-1 {split empty fields} {
    csv::split {"" "" 1 2} { }
} {{"} {"} 1 2}

test csv-1.11-1 {split empty fields} {
    csv::split {"" 0 1 2} { }
} {{"} 0 1 2}

test csv-1.12-1 {split empty fields} {
    csv::split {"" ""} { }
} {{"} {"}}

test csv-1.13-1 {split empty fields} {
    csv::split {"" "" ""} { }
} {{"} {"} {"}}

test csv-1.14-1 {split empty fields} {
    csv::split {"" 0 "" 2} { }
} {{"} 0 {"} 2}

test csv-1.15-1 {split empty fields} {
    csv::split {1 "" 3 ""} { }
} {1 {"} 3 {"}}

test csv-1.8-2 {split empty fields} {
    csv::split "1,2,,"
} {1 2 {} {}}

test csv-1.9-2 {split empty fields} {
    csv::split "1,2,3,"
} {1 2 3 {}}

test csv-1.10-2 {split empty fields} {
    csv::split ",,1,2"
} {{} {} 1 2}

test csv-1.11-2 {split empty fields} {
    csv::split ",0,1,2"
} {{} 0 1 2}

test csv-1.12-2 {split empty fields} {
    csv::split ","
} {{} {}}

test csv-1.13-2 {split empty fields} {
    csv::split ",,"
} {{} {} {}}

test csv-1.14-2 {split empty fields} {
    csv::split ",0,,2"
} {{} 0 {} 2}

test csv-1.15-2 {split empty fields} {
    csv::split "1,,3,"
} {1 {} 3 {}}

test csv-1.8-3 {split empty fields} {
    csv::split {1 2  } { }
} {1 2 {} {}}

test csv-1.9-3 {split empty fields} {
    csv::split {1 2 3 } { }
} {1 2 3 {}}

test csv-1.10-3 {split empty fields} {
    csv::split {  1 2} { }
} {{} {} 1 2}

test csv-1.11-3 {split empty fields} {
    csv::split { 0 1 2} { }
} {{} 0 1 2}

test csv-1.12-3 {split empty fields} {
    csv::split { } { }
} {{} {}}

test csv-1.13-3 {split empty fields} {
    csv::split {  } { }
} {{} {} {}}

test csv-1.14-3 {split empty fields} {
    csv::split { 0  2} { }
} {{} 0 {} 2}

test csv-1.15-3 {split empty fields} {
    csv::split {1  3 } { }
} {1 {} 3 {}}


test csv-1.8-4 {split empty fields} {
    csv::split {1,2,"",""}
} {1 2 {"} {"}}

test csv-1.9-4 {split empty fields} {
    csv::split {1,2,3,""}
} {1 2 3 {"}}

test csv-1.10-4 {split empty fields} {
    csv::split {"","",1,2}
} {{"} {"} 1 2}

test csv-1.11-4 {split empty fields} {
    csv::split {"",0,1,2}
} {{"} 0 1 2}

test csv-1.12-4 {split empty fields} {
    csv::split {"",""}
} {{"} {"}}

test csv-1.13-4 {split empty fields} {
    csv::split {"","",""}
} {{"} {"} {"}}

test csv-1.14-4 {split empty fields} {
    csv::split {"",0,"",2}
} {{"} 0 {"} 2}

test csv-1.15-4 {split empty fields} {
    csv::split {1,"",3,""}
} {1 {"} 3 {"}}

# Try various separator characters

foreach {n sep} {
    0  |    1  +    2  *
    3  /    4  \    5  [
    6  ]    7  (    8  )
    9  ?    10 ,    11 ;
    12 .    13 -    14 =
    15 :
} {
    test csv-1.16-$n "split on $sep" {
        ::csv::split [join [list REC DPI AD1 AD2 AD3] $sep] $sep
    } {REC DPI AD1 AD2 AD3}
}

test csv-2.1 {join} {
    csv::join {123 {"a"} {} hello}
} $str1a

test csv-2.2 {join} {
    csv::join {1 { o, "a" ,b } { 3}}
} $str2

test csv-2.3 {join} {
    csv::join {1 { o, "," ,b } { 3}}
} $str3a

test csv-2.4 {join} {
    csv::join {1 { foo,bar,baz} { 3}}
} $str4

test csv-2.5 {join} {
    csv::join {1 {""a""} b}
} $str5

test csv-2.6 {join} {
    csv::join {123 123,521.2 {Mary says "Hello, I am Mary"}}
} $str6

test csv-2.7 {join, custom delimiter} {
    csv::join {123 =a= {} hello} , =
} $str1a_

test csv-2.8 {join, custom delimiter} {
    csv::join {1 { o, =a= ,b } { 3}} , =
} $str2_

test csv-2.9 {join, custom delimiter} {
    csv::join {1 { o, =,= ,b } { 3}} , =
} $str3a_

test csv-2.10 {join, custom delimiter} {
    csv::join {1 { foo,bar,baz} { 3}} , =
} $str4_

test csv-2.11 {join, custom delimiter} {
    csv::join {1 ==a== b} , =
} $str5_

test csv-2.12 {join, custom delimiter} {
    csv::join {123 123,521.2 {Mary says "Hello, I am Mary"}} , =
} $str6_

test csv-2.13-sf-1724818 {join, newlines in string, sf bug 1724818} {
    csv::join {123 {John Doe} "123 Main St.\nSmalltown, OH 44444"}
} "123,John Doe,\"123 Main St.\nSmalltown, OH 44444\""

test csv-2.14 {join, custom delimiter, always} {
    csv::join {1 ==a== b} , = always
} $str7

# Malformed inputs

# WTF?
#test csv-3.1 {split} {
#    csv::split {abcd,abc",abc} ; # "
#} {abcd abc abc}
#
#test csv-3.2 {split} {
#    csv::split {abcd,abc"",abc}
#} {abcd abc\" abc}


test csv-4.1 {joinlist} {
    csv::joinlist [list \
	    {123 {"a"} {} hello} 	\
	    {1 { o, "a" ,b } { 3}}	\
	    {1 { o, "," ,b } { 3}}	\
	    {1 { foo,bar,baz} { 3}}	\
	    {1 {""a""} b}		\
	    {123 123,521.2 {Mary says "Hello, I am Mary"}}]
} "$str1a\n$str2\n$str3a\n$str4\n$str5\n$str6\n"

test csv-4.2 {joinlist, sepChar} {
    csv::joinlist [list [list a b c] [list d e f]] @
} "a@b@c\nd@e@f\n"

test csv-4.3 {joinlist, custom delimiter} {
    csv::joinlist [list \
	    {123 =a= {} hello} 	\
	    {1 { o, =a= ,b } { 3}}	\
	    {1 { o, =,= ,b } { 3}}	\
	    {1 { foo,bar,baz} { 3}}	\
	    {1 ==a== b}		\
	    {123 123,521.2 {Mary says "Hello, I am Mary"}}] , =
} "$str1a_\n$str2_\n$str3a_\n$str4_\n$str5_\n$str6_\n"

test csv-4.4 {joinlist, sepChar, custom delimiter} {
    csv::joinlist [list [list a b c] [list d e f]] @ =
} "a@b@c\nd@e@f\n"

test csv-5.0.0 {reading csv files, bad separator, empty} {
    ::struct::queue q
    catch {::csv::read2queue dummy q {}} result
    q destroy
    set result
} {illegal separator character "", is empty}

test csv-5.0.1 {reading csv files, bad separator, string} {
    ::struct::queue q
    catch {::csv::read2queue dummy q foo} result
    q destroy
    set result
} {illegal separator character "foo", is a string}

test csv-5.0.2 {reading csv files, bad separator, empty} {
    ::struct::matrix m
    catch {::csv::read2matrix dummy m {}} result
    m destroy
    set result
} {illegal separator character "", is empty}

test csv-5.0.3 {reading csv files, bad separator, string} {
    ::struct::matrix m
    catch {::csv::read2matrix dummy m foo} result
    m destroy
    set result
} {illegal separator character "foo", is a string}

set ::tcltest::testsDirectory /home/tcl/src/tcllib/modules/csv/
test csv-5.1 {reading csv files} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench.csv] r]
    ::struct::queue q
    ::csv::read2queue $f q
    close $f
    set result [list [q size] [q get 2]]
    q destroy
    set result
} {251 {{000 VERSIONS: 2:8.4a3 1:8.4a3 1:8.4a3%} {001 {CATCH return ok} 7 13 53.85}}}

test csv-5.2 {reading csv files} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench_a.csv] r]
    ::struct::queue q
    ::csv::read2queue $f q
    close $f
    set result [list [q size] [q get 2]]
    q destroy
    set result
} {251 {{000 VERSIONS: 2:8.4a3 1:8.4a3 1:8.4a3%} {001 {CATCH return ok} 7 13 53.85}}}

test csv-5.3 {reading csv files} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench.csv] r]
    ::struct::matrix m
    m add columns 5
    ::csv::read2matrix $f m
    close $f
    set result [m get rect 0 227 end 231]
    m destroy
    set result
} {{227 {STR append (1MB + 1MB * 3)} 125505 327765 38.29} {228 {STR append (1MB + 1MB * 5)} 158507 855295 18.53} {229 {STR append (1MB + (1b + 1K + 1b) * 100)} 33101 174031 19.02} {230 {STR info locals match} 946 1521 62.20} {231 {TRACE no trace set} 34 121 28.10}}

test csv-5.4 {reading csv files} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench_a.csv] r]
    ::struct::matrix m
    m add columns 5
    ::csv::read2matrix $f m
    close $f
    set result [m get rect 0 227 end 231]
    m destroy
    set result
} {{227 {STR append (1MB + 1MB * 3)} 125505 327765 38.29} {228 {STR append (1MB + 1MB * 5)} 158507 855295 18.53} {229 {STR append (1MB + (1b + 1K + 1b) * 100)} 33101 174031 19.02} {230 {STR info locals match} 946 1521 62.20} {231 {TRACE no trace set} 34 121 28.10}}

test csv-5.5 {reading csv files} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench.csv] r]
    ::struct::matrix m
    m add columns 5
    ::csv::read2matrix $f m
    close $f

    set result [list]
    foreach c {0 1 2 3 4} {
	lappend result [m columnwidth $c]
    }
    m destroy
    set result
} {3 39 7 7 8}

test csv-5.6 {reading csv files, linking} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench.csv] r]
    ::struct::matrix m
    m add columns 5
    ::csv::read2matrix $f m
    close $f
    unset -nocomplain a
    m link a
    set result [array size a]
    m destroy
    set result
} {1255}


test csv-5.7 {reading csv files, empty expansion mode} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench.csv] r]
    ::struct::matrix m
    ::csv::read2matrix $f m , empty
    close $f
    set result [m get rect 0 227 end 231]
    m destroy
    set result
} {{227 {STR append (1MB + 1MB * 3)} 125505 327765 38.29} {228 {STR append (1MB + 1MB * 5)} 158507 855295 18.53} {229 {STR append (1MB + (1b + 1K + 1b) * 100)} 33101 174031 19.02} {230 {STR info locals match} 946 1521 62.20} {231 {TRACE no trace set} 34 121 28.10}}

test csv-5.8 {reading csv files, auto expansion mode} {
    set f [open [file join $::tcltest::testsDirectory mem_debug_bench.csv] r]
    ::struct::matrix m
    m add columns 1
    ::csv::read2matrix $f m , auto
    close $f
    set result [m get rect 0 227 end 231]
    m destroy
    set result
} {{227 {STR append (1MB + 1MB * 3)} 125505 327765 38.29} {228 {STR append (1MB + 1MB * 5)} 158507 855295 18.53} {229 {STR append (1MB + (1b + 1K + 1b) * 100)} 33101 174031 19.02} {230 {STR info locals match} 946 1521 62.20} {231 {TRACE no trace set} 34 121 28.10}}


# =========================================================================
# Bug 2926387

test csv-5.9.0 {reading csv files, inner field newline processing, bug 2926387} {
    set m [struct::matrix]
    set f [open [file join $::tcltest::testsDirectory 2926387.csv] r]
    csv::read2matrix $f $m , auto
    close $f
    set result [$m serialize]
    $m destroy
    set result
} {2 3 {{a b c} {d {e,
e} f}}}

test csv-5.9.1 {reading csv files, inner field newline processing, bug 2926387} {
    set q [struct::queue]
    set f [open [file join $::tcltest::testsDirectory 2926387.csv] r]
    csv::read2queue $f $q
    close $f
    set result [$q get [$q size]]
    $q destroy
    set result
} {{a b c} {d {e,
e} f}}

proc localPath fn {file join $::tcltest::testsDirectory $fn}
test csv-6.1 {writing csv files} {
    set f [open [localPath eval.csv] r]
    ::struct::matrix m
    m add columns 5
    ::csv::read2matrix $f m
    close $f

    set f [open [makeFile {} eval-out1.csv] w]
    ::csv::writematrix m $f
    close $f

    set result [viewFile eval-out1.csv]
    m destroy
    removeFile eval-out1.csv
    set result
} {023,EVAL cmd eval in list obj var,26,45,57.78
024,EVAL cmd eval as list,23,42,54.76
025,EVAL cmd eval as string,53,92,57.61
026,EVAL cmd and mixed lists,3805,11276,33.74
027,EVAL list cmd and mixed lists,3812,11325,33.66
028,EVAL list cmd and pure lists,592,1598,37.05}

test csv-6.2 {writing csv files} {
    set f [open [localPath eval.csv] r]
    ::struct::queue q
    ::csv::read2queue $f q
    close $f

    set f [open [makeFile {} eval-out2.csv] w]
    ::csv::writequeue q $f
    close $f

    set result [viewFile eval-out2.csv]
    q destroy
    removeFile eval-out2.csv
    set result
} {023,EVAL cmd eval in list obj var,26,45,57.78
024,EVAL cmd eval as list,23,42,54.76
025,EVAL cmd eval as string,53,92,57.61
026,EVAL cmd and mixed lists,3805,11276,33.74
027,EVAL list cmd and mixed lists,3812,11325,33.66
028,EVAL list cmd and pure lists,592,1598,37.05}

test csv-7.1 {reporting} {
    set f [open [localPath eval.csv] r]
    ::struct::matrix m
    m add columns 5
    ::csv::read2matrix $f m
    close $f

    set result [m format 2string csv::report]
    m destroy
    set result
} {023,EVAL cmd eval in list obj var,26,45,57.78
024,EVAL cmd eval as list,23,42,54.76
025,EVAL cmd eval as string,53,92,57.61
026,EVAL cmd and mixed lists,3805,11276,33.74
027,EVAL list cmd and mixed lists,3812,11325,33.66
028,EVAL list cmd and pure lists,592,1598,37.05
}

test csv-7.2 {reporting} {
    set f [open [localPath eval.csv] r]
    ::struct::matrix m
    m add columns 5
    ::csv::read2matrix $f m
    close $f

    set f [open [makeFile {} eval-out3.csv] w]
    m format 2chan csv::report $f
    close $f

    set result [viewFile eval-out3.csv]
    m destroy
    removeFile eval-out3.csv
    set result
} {023,EVAL cmd eval in list obj var,26,45,57.78
024,EVAL cmd eval as list,23,42,54.76
025,EVAL cmd eval as string,53,92,57.61
026,EVAL cmd and mixed lists,3805,11276,33.74
027,EVAL list cmd and mixed lists,3812,11325,33.66
028,EVAL list cmd and pure lists,592,1598,37.05}


## ============================================================
## Test new restrictions on argument syntax of split.

test csv-8.2 {csv argument error} {
    catch {::csv::split -alternate b {}} msg
    set msg
} {illegal separator character "", is empty}

test csv-8.3 {csv argument error} {
    catch {::csv::split -alternate b foo} msg
    set msg
} {illegal separator character "foo", is a string}

test csv-8.4 {csv argument error} {
    catch {::csv::split b {}} msg
    set msg
} {illegal separator character "", is empty}

test csv-8.5 {csv argument error} {
    catch {::csv::split b foo} msg
    set msg
} {illegal separator character "foo", is a string}


## ============================================================
## Tests for alternate syntax.


test csv-91.1 {split} {
    csv::split -alternate $str1
} {123 {"a"} {} hello}

test csv-91.2 {split} {
    csv::split -alternate $str2
} {1 { o, "a" ,b } { 3}}

test csv-91.3 {split} {
    csv::split -alternate $str3
} {1 { o, "," ,b } { 3}}

test csv-91.4 {split} {
    csv::split -alternate $str4
} {1 { foo,bar,baz} { 3}}

test csv-91.5 {split} {
    csv::split -alternate $str5
} {1 {""a""} b}

test csv-91.6 {split} {
    csv::split -alternate $str6
} {123 123,521.2 {Mary says "Hello, I am Mary"}}

test csv-91.7 {split on join} {
    # csv 0.1 was exposed to the RE \A matching problem with regsub -all
    set x [list "\"hello, you\"" a b c]
    ::csv::split -alternate [::csv::join $x]
} [list "\"hello, you\"" a b c]

test csv-91.8-1 {split empty fields} {
    csv::split -alternate {1 2 "" ""} { }
} {1 2 {} {}}

test csv-91.9-1 {split empty fields} {
    csv::split -alternate {1 2 3 ""} { }
} {1 2 3 {}}

test csv-91.10-1 {split empty fields} {
    csv::split -alternate {"" "" 1 2} { }
} {{} {} 1 2}

test csv-91.11-1 {split empty fields} {
    csv::split -alternate {"" 0 1 2} { }
} {{} 0 1 2}

test csv-91.12-1 {split empty fields} {
    csv::split -alternate {"" ""} { }
} {{} {}}

test csv-91.13-1 {split empty fields} {
    csv::split -alternate {"" "" ""} { }
} {{} {} {}}

test csv-91.14-1 {split empty fields} {
    csv::split -alternate {"" 0 "" 2} { }
} {{} 0 {} 2}

test csv-91.15-1 {split empty fields} {
    csv::split -alternate {1 "" 3 ""} { }
} {1 {} 3 {}}

test csv-91.8-2 {split empty fields} {
    csv::split -alternate "1,2,,"
} {1 2 {} {}}

test csv-91.9-2 {split empty fields} {
    csv::split -alternate "1,2,3,"
} {1 2 3 {}}

test csv-91.10-2 {split empty fields} {
    csv::split -alternate ",,1,2"
} {{} {} 1 2}

test csv-91.11-2 {split empty fields} {
    csv::split -alternate ",0,1,2"
} {{} 0 1 2}

test csv-91.12-2 {split empty fields} {
    csv::split -alternate ","
} {{} {}}

test csv-91.13-2 {split empty fields} {
    csv::split -alternate ",,"
} {{} {} {}}

test csv-91.14-2 {split empty fields} {
    csv::split -alternate ",0,,2"
} {{} 0 {} 2}

test csv-91.15-2 {split empty fields} {
    csv::split -alternate "1,,3,"
} {1 {} 3 {}}

test csv-91.8-3 {split empty fields} {
    csv::split -alternate {1 2  } { }
} {1 2 {} {}}

test csv-91.9-3 {split empty fields} {
    csv::split -alternate {1 2 3 } { }
} {1 2 3 {}}

test csv-91.10-3 {split empty fields} {
    csv::split -alternate {  1 2} { }
} {{} {} 1 2}

test csv-91.11-3 {split empty fields} {
    csv::split -alternate { 0 1 2} { }
} {{} 0 1 2}

test csv-91.12-3 {split empty fields} {
    csv::split -alternate { } { }
} {{} {}}

test csv-91.13-3 {split empty fields} {
    csv::split -alternate {  } { }
} {{} {} {}}

test csv-91.14-3 {split empty fields} {
    csv::split -alternate { 0  2} { }
} {{} 0 {} 2}

test csv-91.15-3 {split empty fields} {
    csv::split -alternate {1  3 } { }
} {1 {} 3 {}}


test csv-91.8-4 {split empty fields} {
    csv::split -alternate {1,2,"",""}
} {1 2 {} {}}

test csv-91.9-4 {split empty fields} {
    csv::split -alternate {1,2,3,""}
} {1 2 3 {}}

test csv-91.10-4 {split empty fields} {
    csv::split -alternate {"","",1,2}
} {{} {} 1 2}

test csv-91.11-4 {split empty fields} {
    csv::split -alternate {"",0,1,2}
} {{} 0 1 2}

test csv-91.12-4 {split empty fields} {
    csv::split -alternate {"",""}
} {{} {}}

test csv-91.13-4 {split empty fields} {
    csv::split -alternate {"","",""}
} {{} {} {}}

test csv-91.14-4 {split empty fields} {
    csv::split -alternate {"",0,"",2}
} {{} 0 {} 2}

test csv-91.15-4 {split empty fields} {
    csv::split -alternate {1,"",3,""}
} {1 {} 3 {}}


test csv-92.0.1 {split} {
    csv::split {"xxx",yyy}
} {xxx yyy}

test csv-92.0.2 {split} {
    csv::split -alternate {"xxx",yyy}
} {xxx yyy}

test csv-92.1.1 {split} {
    csv::split {"xx""x",yyy}
} {xx\"x yyy}

test csv-92.1.2 {split} {
    csv::split -alternate {"xx""x",yyy}
} {xx\"x yyy}

# -------------------------------------------------------------------------


test csv-100.1 {custom delimiter, split} {
    csv::split $str1_ , =
} {123 =a= {} hello}

test csv-100.2 {custom delimiter, split} {
    csv::split $str2_ , =
} {1 { o, =a= ,b } { 3}}

test csv-100.3 {custom delimiter, split} {
    csv::split $str3_ , =
} {1 { o, =,= ,b } { 3}}

test csv-100.4 {custom delimiter, split} {
    csv::split $str4_ , =
} {1 { foo,bar,baz} { 3}}

test csv-100.5 {custom delimiter, split} {
    csv::split $str5_ , =
} {1 ==a== b}

test csv-100.6 {custom delimiter, split} {
    csv::split $str6_ , =
} {123 123,521.2 {Mary says "Hello, I am Mary"}}

test csv-100.7 {custom delimiter, split on join} {
    # csv 0.1 was exposed to the RE \A matching problem with regsub -all
    set x [list "\"hello, you\"" a b c]
    ::csv::split [::csv::join $x , =] , =
} [list "\"hello, you\"" a b c]

test csv-100.8-1 {custom delimiter, split empty fields} {
    csv::split {1 2 == ==} { } =
} {1 2 = =}

test csv-100.9-1 {custom delimiter, split empty fields} {
    csv::split {1 2 3 ==} { } =
} {1 2 3 =}

test csv-100.10-1 {custom delimiter, split empty fields} {
    csv::split {== == 1 2} { } =
} {= = 1 2}

test csv-100.11-1 {custom delimiter, split empty fields} {
    csv::split {== 0 1 2} { } =
} {= 0 1 2}

test csv-100.12-1 {custom delimiter, split empty fields} {
    csv::split {== ==} { } =
} {= =}

test csv-100.13-1 {custom delimiter, split empty fields} {
    csv::split {== == ==} { } =
} {= = =}

test csv-100.14-1 {custom delimiter, split empty fields} {
    csv::split {== 0 == 2} { } =
} {= 0 = 2}

test csv-100.15-1 {custom delimiter, split empty fields} {
    csv::split {1 == 3 ==} { } =
} {1 = 3 =}

test csv-100.8-2 {custom delimiter, split empty fields} {
    csv::split "1,2,,"
} {1 2 {} {}}

test csv-100.9-2 {custom delimiter, split empty fields} {
    csv::split "1,2,3,"
} {1 2 3 {}}

test csv-100.10-2 {custom delimiter, split empty fields} {
    csv::split ",,1,2"
} {{} {} 1 2}

test csv-100.11-2 {custom delimiter, split empty fields} {
    csv::split ",0,1,2"
} {{} 0 1 2}

test csv-100.12-2 {custom delimiter, split empty fields} {
    csv::split ","
} {{} {}}

test csv-100.13-2 {custom delimiter, split empty fields} {
    csv::split ",,"
} {{} {} {}}

test csv-100.14-2 {custom delimiter, split empty fields} {
    csv::split ",0,,2"
} {{} 0 {} 2}

test csv-100.15-2 {custom delimiter, split empty fields} {
    csv::split "1,,3,"
} {1 {} 3 {}}

test csv-100.8-3 {custom delimiter, split empty fields} {
    csv::split {1 2  } { } =
} {1 2 {} {}}

test csv-100.9-3 {custom delimiter, split empty fields} {
    csv::split {1 2 3 } { } =
} {1 2 3 {}}

test csv-100.10-3 {custom delimiter, split empty fields} {
    csv::split {  1 2} { } =
} {{} {} 1 2}

test csv-100.11-3 {custom delimiter, split empty fields} {
    csv::split { 0 1 2} { } =
} {{} 0 1 2}

test csv-100.12-3 {custom delimiter, split empty fields} {
    csv::split { } { } =
} {{} {}}

test csv-100.13-3 {custom delimiter, split empty fields} {
    csv::split {  } { } =
} {{} {} {}}

test csv-100.14-3 {custom delimiter, split empty fields} {
    csv::split { 0  2} { } =
} {{} 0 {} 2}

test csv-100.15-3 {custom delimiter, split empty fields} {
    csv::split {1  3 } { } =
} {1 {} 3 {}}

test csv-100.8-4 {custom delimiter, split empty fields} {
    csv::split {1,2,==,==} , =
} {1 2 = =}

test csv-100.9-4 {custom delimiter, split empty fields} {
    csv::split {1,2,3,==} , =
} {1 2 3 =}

test csv-100.10-4 {custom delimiter, split empty fields} {
    csv::split {==,==,1,2} , =
} {= = 1 2}

test csv-100.11-4 {custom delimiter, split empty fields} {
    csv::split {==,0,1,2} , =
} {= 0 1 2}

test csv-100.12-4 {custom delimiter, split empty fields} {
    csv::split {==,==} , =
} {= =}

test csv-100.13-4 {custom delimiter, split empty fields} {
    csv::split {==,==,==} , =
} {= = =}

test csv-100.14-4 {custom delimiter, split empty fields} {
    csv::split {==,0,==,2} , =
} {= 0 = 2}

test csv-100.15-4 {custom delimiter, split empty fields} {
    csv::split {1,==,3,==} , =
} {1 = 3 =}

# Try various separator characters

foreach {n sep} {
    0  |    1  +    2  *
    3  /    4  \    5  [
    6  ]    7  (    8  )
    9  ?    10 ,    11 ;
    12 .    13 -    14 @
    15 :
} {
    test csv-100.16-$n "split on $sep" {
	::csv::split [join [list REC DPI AD1 AD2 AD3] $sep] $sep =
    } {REC DPI AD1 AD2 AD3}
}

test csv-200.0 {splitting to queue, bad separator, empty} {
    ::struct::queue q
    catch {::csv::split2queue q dummy-line {}} result
    q destroy
    set result
} {illegal separator character "", is empty}

test csv-200.1 {splitting to queue, bad separator, string} {
    ::struct::queue q
    catch {::csv::split2queue q dummy-line foo} result
    q destroy
    set result
} {illegal separator character "foo", is a string}

test csv-200.2 {splitting to matrix, bad separator, empty} {
    ::struct::matrix m
    catch {::csv::split2matrix m dummy-line {}} result
    m destroy
    set result
} {illegal separator character "", is empty}

test csv-200.3 {splitting to matrix, bad separator, string} {
    ::struct::matrix m
    catch {::csv::split2matrix m dummy-line foo} result
    m destroy
    set result
} {illegal separator character "foo", is a string}

} ;# tests
