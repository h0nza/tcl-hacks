source parser-1.tm

Parser gbx {
    %start gerber
    %space          {\s*}   ;# tokens (and end) implicitly eat preceding whitespace

    # names beginning with a dot are reserved
    %token rname    {[.][a-zA-Z_.0-9]+}
    %token uname    {[a-zA-Z_$][a-zA-Z_.0-9]+}

    # All but \r\n%*
    # Note there is no escape char.  \ is literal. \u{hex4} is unicode.
    %token String   {(\\u[0-9a-fA-F]{4}|[a-zA-Z0-9_+-/!?<>\"'(){}.|&@# ,;$:=])+}   ;# "

    %token digits    {[0-9]+}
    %token fixnum   {[+-]?[0-9]+}
    %token flonum   {[+-]?[0-9]+.[0-9]+}

    %token aptype   {[CROP]}
    %token cmdltr   {[DGM]}
    %token letter   {[A-Z]}

    %token anybut*  {[^*]*}
    %token anybut%  {[^%]*}

    %rule function {
        letter; fixnum
    } { return $1$2 }

    %rule basic {
        # G04 comment doesn't fit here :(
        many function; token *
    } { return * {*}$1 }

    %rule excommand {
        any {
            tok MO; any { tok IN } { tok MM }
        } {
            tok FSLA
            tok X; digits
            tok Y; digits
        } {
            tok ADD; digits; aptype; tok ,; anybut*
        } {
            tok LN; anybut*
        }
        token *
    } { return {*}$0 }

    %rule extended {
        token %; excommand; token %
    } { return % {*}$0 }

    %rule command {
        any basic extended
    } { return $0 }

    %rule gerber {
        many command
    } { return {*}$0 }
}

puts [gbx {
    %MOIN*%
    %FSLAX25Y25*%
    %LNOUTLINE*%
    %ADD22C,0.0100*%
    G54D22*X0Y36000D02*G75*G03X0Y36000I36000J0D01*G01*
    M02*
}]
