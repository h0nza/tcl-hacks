source ebnf-1.tm

if 0 {
proc echeck {s} {
    try {
        set r [ebnf- $s]
    } trap {PARSE FAIL} {e o} {
        set r "PARSE ERROR: $e"
    }
    puts [format "%20s -> %-40s" $s $r]
}

    echeck {{}}
    echeck { { } }
    echeck { { a = b; } }
    echeck { { a = 'b'; } }
    echeck { { a = "b"; } }
    echeck { { a = (b); } }
    echeck { { a = { b }; } }
    echeck { { a = [ b ]; } }
    echeck { { a = b c; } }
    echeck { { a = b c b; } }
    echeck { { a = b|c; } }
    echeck { { a = b|c|b; } }
    echeck { { a = 'b'|'c'; } }
    echeck { { a = b c; c = d; } }
    echeck { { a = 'b' ( 'c' | 'd' ) 'a'; } }
    return
}

proc G {parser string} {
    set script "$parser; end"
    set result [apply [list {s {i 0} {0 ""}} $parser ebnf] $string]
    puts [format "G %-10s %30s %30s" [list $string] [list $parser] [list $result]]
}

#    puts [info body ebnf::ifactor]
#    G identifier { d }
#    G literal { 'd' }
#    G literal {"foo"}
#    G factor { [ d ] }
#    G factor { ( d ) }
#    G factor {foo}

    G {token! foo} foo
    G {tok a; tok b} ab
    G {tok a; many {tok b}} a
    G {tok a; many {tok b}} ab
    G {tok a; many {tok b}} abbb
    G {any {tok a} {tok b}} a
    G {any {tok a} {tok b}} b
    G {many {any {tok a} {tok b}}} baabbab
    G {any {tok f; tok f} {tok 0; tok 0}} ff
    G {many {any {tok f; tok f} {tok 0; tok 0}}} ffff00ff00
    return
    G {any {identifier} {literal}} {bar}
    G {any {literal} {identifier}} {bar}
    G {any {literal} {identifier}} {"bar"}
    G {any {identifier} {literal}} {"ar"}
    #G {identifier} {"xx"}
    G {opt identifier; literal} {"xx"}
    G factor {"foo"}

        G identifier "foo"
        G identifier "foo  "
        G identifier "  foo"
        G identifier "  foo  "
        G {opt identifier} "foo"
        G {opt identifier} ""
        G {opt identifier} " foo"
        G {identifier; identifier} "foo bar"
        G {many identifier} ""
        G {many identifier} "foo "
        G {many identifier} "foo bar"
        G {opt identifier; identifier} "foo bar"
        G {opt {identifier; identifier}} "foo bar"
        G {many {any {identifier; identifier} identifier}} "foo bar baz"
        G {any {identifier; identifier} identifier} "bar baz"
        G {any {identifier; identifier} identifier} "baaz"
        puts >>>+&[apply {{s {i 0} {0 ""}} {opt {identifier; identifier}} ebnf} $s]
        puts >>>**[apply {{s {i 0} {0 ""}} {many {identifier}} ebnf} $s]
        set s "{a=b;}"
        puts >>>[apply {{s {i 0} {0 ""}} {tok \{; identifier; tok =; identifier; tok \;; tok \};end} ebnf} $s]
        puts >>>[apply {{s {i 0} {0 ""}} {
            tok \{
            many {
             identifier
             tok =
             identifier
             lit \;
            }
            tok \}
            end
        } ebnf} $s]
}
