#
# The tricky bit here is to support something like [<token> -until )] for array indexing,
# without the extra pain of having the -until parameter infect every. single. rule.
# Worse is [<token> -until \]] for command substitutions, since it must go through script
Parser tclScript {
    %start script

    # extra whitespace around commands is a mild pain
    %rule script    { many {any {comment; token \n} {command; cmdSep}} }
    %token cmdSep       {[\n;]}
    %rule comment       { token \#; restOfLine }
    %token restOfLine   {(\\.|[^\\\n])*}
    %token noBrace      {[^{}]+}
    %token noWs         {\S+}

    %rule command   { many {word; wordSep} }
    %token wordSep      {(\s|\\\n)+}

#   %rule word {{-until ""}}        { any bword qword {bareword -until $until}}
#   %rule bareword {{-until ""}}    { many { any varSub cmdSub bSlash noWs } }
#   %rule noWs {{-until ""}}    {
#       if {$until eq ""} {
#           re {\S+}
#       } else {
#           re "\[^\\s\\$until\]+"
#       }
#   }
    %rule word      { any bword qword bareword }
    %rule bword     { token \x7b; balanced; token \x7d }
    %rule balanced  { many { any noBrace balanced } }

    %rule qword     { token \"; many { any varSub cmdSub bSlash literal }; token \" }
    %rule bareword  { many { any varSub cmdSub bSlash noWs } }

    %rule bSlash    { any bsChar bsNewline bsOctal bsHex bsUni4 bsUni8 }
    %token bsChar       {\\[abfnrt\\]}
    %token bsNewline    {\\\n\s*}
    %token bsOctal      {\\[0-7]{1,3}}
    %token bsHex        {\\x[0-9a-fA-F]{1,2}}
    %token bsUni4       {\\u[0-9a-fA-F]{1,4}}
    %token bsUni8       {\\U[0-9a-fA-F]{1,8}}

    %rule varSub    { any { plainVarSub; optarrayIndex }; bracedVarSub }
    %token plainVarSub  {\$([a-zA-Z0-9_]+|::+)*}
    %token arrayIndex   { token \(; word; token \) }
#    %token arrayIndex   { token \(; word -until |); token \) }
    %token bracedVarSub {\$\{[^\x7d]*\}}

    %rule cmdSub    { token \[; script; token \] }
#    %rule cmdSub    { token \[; script -until \]; token \] }
}
