The idea here is to make friendly DSL utilities for general tasks.  cli.tcl supports
being invoked as:

Interactive REPL with error display and so on:

    $ cli                               -- interactive REPL
    $ cli script.ext                    -- runs the script
    $ cli script.ext arg ... argN       -- extra args come in $::argv
    $ cli -someoptions ?script.ext?     -- -* options can be defined in main

The DSL itself comes from a Tcl object command (TclOO, ensemble, whatever), whose
subcommands will be available as top-level commands to the user's script.

This is achieved by:
 - aliasing all the object's commands into a namespace
 - running the user's script(s) in a coroutine inside that namespace

The coroutine provides a frame for local vars.
We add `_ ! $ %` special vars for extra fun and convenience.

TODO:
 - format errorInfo with a nice command
 - line editing some how
 - get towards tksh

## Interactive helpers:

 - [unknown] that execs.  We like this.
 - special vars:  _ ! $ %
 - error info [??]
 - history
 - tab-completion


## A simplified model of evaluation

    proc chain {initialValue args} {
        while 1 {
            foreach script $args {
                uplevel 1 $script [list $initialValue]
            }
        }
    }

    namespace eval app {
        proc Eval {} {
            chain [info coroutine] yield try
        }
        coroutine eval Eval
    }
