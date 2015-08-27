source ebnf-1.tm

proc check {name s {tests {}}} {
    puts "*** $name:"
    try {
        set r [ebnf $s]
    } trap {PARSER FAIL} {e o} {
        set r "PARSE ERROR: $e"
    }
    puts [format "%20s -> %-40s" $s $r]
    if {[info exists e]} return
    lset r 0 1 $name
    try [lindex $r 0]
    namespace eval $name {
        %space {\s*}            ;# hack so rules can space
        %token character {\w}   ;# for ebnf
    }
    foreach s $tests {
        try {
            set r [$name $s]
        } trap {PARSER FAIL} {e o} {
            set r "PARSE ERROR: $e"
        }
        puts [format "%20s -> %-40s" $s $r]
    }
}
proc -- args {}

check "ebnf-mini" {
       "EBNF defined in itself" {
          syntax     = [ title ] "{" { production } "}" [ comment ].
          production = identifier "=" expression ( "." | ";" ) .
          expression = term { "|" term } .
          term       = factor { factor } .
          factor     = identifier
                     | literal
                     | "[" expression "]"
                     | "(" expression ")"
                     | "{" expression "}" .
          identifier = character { character } .
          title      = literal .
          comment    = literal .
          literal    = "'" character { character } "'"
                     | '"' character { character } '"' .
       }
} { 
    {   "a" { a = "a" { a }; }      } 
}

check "one-liner" { 
    "a" { a = "a1" ( "a2" | "a3" ) { "a4" } [ "a5" ] "a6" ; } "z" 
} {
        "a1a3a4a4a5a6"
        "a1 a2a6"
        "a1 a3 a4 a6 "

        "a1 a4 a5 a6"
        "a1 a2 a4 a5 a5 a6"
        "a1 a2 a4 a5 a6 a7"
        "your ad here"
}

check "arithmetic" {
    "arithmetic" {
        expr = term { plus term } .
        term = factor { times factor } .
        factor = number | '(' expr ')' .
     
        plus = "+" | "-" .
        times = "*" | "/" .
     
        number = digit { digit } .
        digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" .
    }
} {  
        "2" "2*3 + 4/23 - 7" "(3 + 4) * 6-2+(4*(4))"
        "-2" "3 +" "(4 + 3 "
}

check "bad1" {       a = "1";
}
check "bad2" {       \{ a = 1;
}
check "bad?3" {      { hello world = 1; }
}
check "bad?4" {      { foo = bar .; }
}

