## What is it?

Getline is a simple-as-I-could-make it line-editing mode for terminals, implemented in pure Tcl.

It's not quite cross-platform, as it relies on:

 - the terminal supporting (without asking) common VT100 escape sequences
 - `exec stty`, to un-cook input and query the terminal geometry

It's an object, so you use it something like:

    package require getline
    Getline create getline      ;# -options go here!
    coroutine go while 1 {
        set line [getline]
        puts "You said: \"$line\""
    }

Remember to do this in a coroutine!  Getline is non-blocking, so it needs to yield to the event loop.
It supports various ?options? at creation time so you can specify the channel, prompt, a history object etc.
Call it in a loop:  `^C` (interrupt) will invoke `continue` and `^D` (eof) will invoke `break`.


## The Example

`tclish` is a Tcl Interactive SHell.  It's just `tclsh` with affordances.
Use it from your `.tclshrc`, or to provide a debug/admin port to your application.

This is probably the main way most people will enjoy Getline, but remember!  It doesn't have to feed the result to `eval`, nor does the input need to be Tcl code!  Just provide a suitable predicate to `-iscomplete` and send the result to `sqlite` .. or wherever you like!


## Why Getline?

Because ergonomy is important.  Terminal interfaces for humans need to have affordances, and so does the code needed to provide them.
I'm sick of using and providing shells without basic cursor navigation, and the trade-offs in using existing libraries pretty much all suck.

Getline does all of (items in __ are incomplete):

 - non-blocking operation with `chan event` and `yield`
 - multi-byte input and output
 - representing an input char by multiple output chars (try `^V^A` and then cursor around it)
 - multi-key maps (I love `^X^E`)
 - handles wrapping properly (terminals suck, so this is harder than it sounds)
 - multi-line input with continuation prompts and inter-line navigation (modelled a bit after `ipython`, but better)
 - multiple instances can exist serving different channels
 - lots of convenient keymaps, easy to add more
 - a simple yank buffer with __ cumulative yank "where you expect it"
 - __ completion callback support
 - around 1kloc of pure Tcl, crafted with readability and hackability in mind.  Go on, read it.
 - well-behaved __ package which doesn't pollute the root namespace

.. all in a nice Tcl'ish package, which in truth gets most of the above goodness from Tcl itself.

I didn't find all of these in any alternatives.  `tclreadline` requires the GPL, doesn't disable `!` and has only the most basic of programmer interfaces.  `editline` and `linenoise` are either blocking, limited to stdin/out or do poorly with multi-byte input.  `Pure-Tcl Readline` is too much crufty code (some of it my fault), and requires `expect` (which is awesome, but not always available) or `TclX` (which pollutes `::` and has some questionable designs).  I've used each of these for a period in the past, but abandoned them for one or another of these reasons.  Finally, I made this.


## Key maps

Lots of key maps are supported.  You can call [getline add-maps] with a dictionary to .. add more.
The defaults include a fairly broad selection of default readline maps.
My hope is that the ones in your muscle memory are there, and work properly (ie, like `readline` except for some sensible variations for multi-line input).
If you feel it's missing (or wrong about!) an important keymap, please file a bug.  Ergonomy is what it's all about.

See `keymap.tcl` for the default maps, which use `^` syntax for control characters (remember many terminals transmit `Alt-X` as `Esc, X` so this would be written `^[X`.
The "actions" performed by maps are just the name of methods on the `Getline` object.  Look them up in there, override them or add more with a mixin.


## STATUS:

 - wrapping + multi-line in conjunction has some bugs now
 - redraws too much.  This can be seen to go wrong in wrapped lines
 - yeah it's slow, have you tried taking out the [after 10] in tty::emit?
 - still needs a little bit of factoring to make a well-behaved loadable module
 - most of core functionality is there and "tested" - see top of getline.tcl for details
 - I might want to specially name the exposable commands - eg :forth ?
 - a call graph would be pretty neat to see

!IMPORTANT!: call [getline] from inside a coroutine, so it can yield to the event loop.  If you prefer a callback style, it's just a few lines of code:

    proc getline_cb {cmd args} {
        while 1 {$cmd {*}$args [getline]}
    }
    coroutine getline#[info cmdcount] getline_cb mycallbackproc


## SUMMARY

This is a simple-as-I-could-make it line-editing mode for terminals.  Call [getline] instead of [gets] to read input from a user who can use line-editing control- and meta- keystrokes to craft their input.  Basic history is provided.  Completion is coming.  Colour is under consideration.

It knows how to present a prompt, navigate about an editing area, arbitrarily insert and delete, represent non-printable characters (with multi-char output sequences, which navigate correctly) and wrap at EOL.  Multi-line editing works and history is supported.

Key sequences are mapped to editing commands with a simple syntax (^C, ^[) so you can easily extend.

The public interface is [getline], which should be called in a coroutine so it can [yield] to the event loop and only wake up when input is received .. and only return when there is a complete line, or the user presses ^C (yieldto continue) or ^D (which should yieldto break).

The project is structured:

                      getline.tcl

    input.tcl   output.tcl  keymap.tcl  histdb.tcl

                  tty.tcl

input manages the input string, output manages the display.  They have some matching primitives:

    back ?n?        forth ?n?
    backspace ?n?   delete ?n?
    insert          reset
    get     pos     rpos

[rep] ties them together:  rep creates the output-rep of a given input token, which may be several characters long.  Wrapper primitives (insert/delete/back/forth/backspace) in the getline namespace handle this.  Out of these are built more complex editing commands, like kill-word-before.

tty.tcl just knows basic vt100 escapes.  Some smarts are built into output to handle EOL and wrapping correctly, which terminals' historical ambiguity makes obnoxiously awkward.

we use [exec stty] to put the tty in raw mode and turn ^C/^D into normal characters we can catch.  [exec stty size] obtains the tty geometry so we can track when to wrap.  This is both obnoxiously simple and quite portable.

Signal handling would be nice for sigwinch.  For now, the redraw command calls [stty size] so just hit ^L if your window size changes.

keymap compiles the given key map into a trie, which is traversed as input tokens come in.  If a sequence is completed, it emits {TOKEN xxx} which getline uses to dispatch to command ::getline::xxx.  If a sequence is broken, it is reported to getline as {LITERAL} and gets inserted as actually typed.

