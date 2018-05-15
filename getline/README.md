## STATUS:

 - state-management bugs have been introduced, causing too many overdraws and multi-line to go wiggy
   - fixable, specifically by examining the Getlines/Getline inheritance relationship
 - still needs a little bit of factoring to make a loadable module
 - most of core functionality is there and "tested" - see top of getline.tcl for details

!IMPORTANT!: call [getline] from inside a coroutine, so it can yield to the event loop.  If you prefer a callback style, it's just a few lines of code:

    proc getline_cb {cmd args} {
        while 1 {$cmd {*}$args [getline]}
    }
    coroutine getline#[info cmdcount] getline_cb mycallbackproc


## SUMMARY

This is a simple-as-I-could-make it line-editing mode for terminals.  Call [getline] instead of [gets] to read input from a user who can use line-editing control- and meta- keystrokes to craft their input.  Basic history is provided.  Completion is coming.  Colour is under consideration.

It knows how to present a prompt, navigate about an editing area, arbitrarily insert and delete, represent non-printable characters (with multi-char output sequences, which navigate correctly) and wrap at EOL.  Multi-line editing (more ipython than readline) is coming.

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

