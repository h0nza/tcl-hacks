This module provides an DSL for defining recursive-descent parsers in an EBNF-like syntax.

A single command is exported:  [Parser name script], which creates a new command (and namespace)
called "name", with parsing commands populated from the script.

In the script, the following commands may be used:

    %start ruleName     - defines the top production rule.  By default, the first defined %rule is used.
    %space regex        - define a regexp for "whitespace" which will be silently consumed as a prefix
                            of each token and of "end" "token" and "token!"
    %result script      - set default result script for following rules
    %token name regexp ?resultscript?
    %rule  name lexscript ?resultscript?

%token and %rule define parsing commands in the namespace.
%token defines a regular expression to consume input.
In %token's resultscript, $0 is bound to the full regexp match, and $1 through $9 to any capturing groups.
The default token resultscript is {string cat $0}.

%rules lexscript can call other parsing commands without arguments, or any of the inbuilt lexers.
It can also use arbitrary Tcl commands, with care.
The result argument is optional and has a sensible default.

** Lexer scripts

The lexscript context is a bit special:

  * $s is the full input string
  * $i is our current position in the input string  (aka: the index of the next character to consume)
  * $0 is the parse result of this script so far

A rule normally doesn't have to interact with these variables directly -- lexers do that for you.  It can - just as it can invoke arbitrary Tcl code - but must be careful to preserve invariants.  See the definitions of [any], [opt], [many] for example.


** Lexer results

resultscript is evaluated immediately following:

    % lassign $0 1 2 3 4 5 6 7 8 9

There is an extra bit of special to how results are handled in order to keep $0 maintained.  Essentially,
we alias [return] to [tailcall lappend 0], which has a few side effects:

  * the simple return value from a procedure is no longer useful
  * multiple arguments can be returned, which will be spliced into the list!

The default resultscript is [list <rulename> {*}$0], which is pretty good as a generic option.  You
might also want to try [list <rulename> $1 {*}$2] for right-recursive repeating rules, [return] for
a silent return-only grammar.  %result can be used to change the default for any rules defined after it.

Be very careful about the multiple return feature - it's easy to make things unpredictable.  If you're
considering this, you may want different semantics for some control constructs, like [many].


** Inbuilt lexers

    [token]      - consume (space then) a literal without reporting (doesn't appear in $0)
    [token!]     - consume (space then) a literal and push its value onto $0
    [opt script] - attempt script.  If it fails, push a single empty result onto $0.
    [any s0 ...] - attempt each script until one succeeds.  The successful script's results will appear on $0.
    [many script]- try script repeatedly until it fails.  Results are collected into a list and pushed.


** References

http://www.garshol.priv.no/download/text/bnf.html
