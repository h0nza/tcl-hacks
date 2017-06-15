source parser-1.tm

Parser ebnf0 {
    %start  syntax
    %space            {\s*}   ;# tokens (and end) implicitly eat preceding whitespace
    %token literal    {(?:'([^']*)')|(?:"([^"]*)")}
    %token identifier {[[:alnum:]_]+}

    %rule syntax      { opt title; token \{; many production; token \}; opt comment }
    %rule production  { identifier; token =; expression; any {token .} {token \;} }
    %rule expression  { term; many { token |; term} }
    %rule term        { factor; many factor }
    %rule factor      { any identifier literal ofactor mfactor ifactor }
    %rule ofactor     { token \[; expression; token \] }
    %rule mfactor     { token \{; expression; token \} }
    %rule ifactor     { token \(; expression; token \) }
    %rule title       { literal }
    %rule comment     { literal }
}


Parser ebnf- {
    %start  syntax
    %space            {\s*}   ;# tokens (and end) implicitly eat preceding whitespace
    %token literal    {(?:'([^']*)')|(?:"([^"]*)")}                 {list token! $1$2}
    %token identifier {[[:alnum:]_]+}                               ;# default result = value

    %rule syntax      { opt title; token \{; many production; token \}; opt comment }   {list Parser $1 $2}
    %rule production  { identifier; token =; expression; any {token .} {token \;} }   {list %rule $1 $2}
    %rule expression  { term; many { token |; term} }               {list any $1 {*}$2}
    %rule term        { factor; many factor }                       {list seq $1 {*}$2}
    %rule factor      { any identifier literal ofactor mfactor ifactor }    {return $1}
    %rule ofactor     { token \[; expression; token \] }                    {list opt $1}
    %rule mfactor     { token \{; expression; token \} }                    {list many $1}
    %rule ifactor     { token \(; expression; token \) }                    {return $1}
    %rule title       { literal }                                           {return $1}
    %rule comment     { literal }                                           {return $1}
}

#        identifier  { character; many character }
#        literal     { any { lit '; character; many character; lit '}
#                          { lit "; character; many character; lit "} } ;# -> {"$2[join $3]"}
#        character   { re {[a-zA-Z0-9_]} } ;# -> $1

Parser ebnf {
    %start  syntax
    %space            {\s*}   ;# tokens (and end) implicitly eat preceding whitespace
    %token literal    {(?:'([^']*)')|(?:"([^"]*)")}                 {list token! $1$2}   ;#" - for vim
    %token identifier {[[:alnum:]_]+}                               ;# default result = value

    #%rule syntax      { opt title; token \{; many production; token \}; opt comment }   {list ebnf $1 $2}
    %rule syntax      { opt title; token \{; many production; token \}; opt comment }   {list Parser $1 \n\t[join $2 \n\t]\n}
    %rule production  { identifier; token =; expression; any {token .} {token \;} }   {list %rule $1 $2}
    %rule expression  { term; many { token |; term} }               {list any $1 {*}$2}
    %rule expression  { term; many { token |; term} }               {
        if {$2 eq ""} {return $1} else {return [list any $1 {*}$2]}
    }
    %rule term        { factor; many factor }                       {list seq $1 {*}$2}
    %rule term        { factor; many factor }                       {join [list $1 {*}$2] "; "}
    %rule factor      { any identifier literal ofactor mfactor ifactor }    {return $1}
    %rule ofactor     { token \[; expression; token \] }                    {list opt $1}
    %rule mfactor     { token \{; expression; token \} }                    {list many $1}
    %rule ifactor     { token \(; expression; token \) }                    {return $1}
    %rule title       { literal }                                           {return [lindex $1 1]}
    %rule comment     { literal }                                           {return [lindex $1 1]}
}

