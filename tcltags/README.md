** HIGHLY EXPERIMENTAL **

While this works as far as it goes, the interface needs a lot of work and should
not be considered stable.  Feedback from testers and would-be users will help :-).


This project generates a ctags-like tags file for Tcl modules by loading them
with instrumentation on proc, oo::define::method et al and identifying creation
sites by examining [info frame].

Default mode is to attempt to source the files specified on the command line,
one by one, in a slave interp and output all captured tags.

It takes some options:

    -path           -- add to the access path
    -unsafe         -- run in main interp
    -tk             -- load Tk in the slave
    -snit           -- load and instrument snit.  Only captures widgets and types
    -emit           -- what sort of tags to output, see below
    -vimrc          -- emit a snippet for tagbar.vim

emit variants:  specify a list of the options below, preceded with "-" to turn
them off.  Unique prefixes are okay.

    scope           -- emit bare identifiers with scope fields attached
    qualified       -- emit fully-qualified identifiers (with ::namespace prefix)
    ensemble        -- emit multi-word identifiers for ensembles, like ("dict map")  (**)

eg:  -emit "sco qua -en"

-emit "scope -qualified -ensemble" is the default and the most useful for navigating tags
or displaying them as a hierarchy.

-emit "scope qualified -ensemble" is a good choice for a searchable tag database, as it
will include both "procname" and "::namespace::procname".

"qualified" output might need to be tuned.
"ensemble" output is not yet implemented.

** TODO

  * fix sorting
  * -only filename-or-pathname (multiple)  -- restrict output to entities defined in these files
  * bring in the good bits of procmap to map ensembles to commands and emit tags for them
  * signatures: can we get arghelp messages to display?


** Vim

    :set iskeyword+=:

The jump-to-tag action (C-]) can be launched with a gesture (eg: visual mode) to look for multi-word tags.

