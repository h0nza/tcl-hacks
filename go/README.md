Shamelessly stolen from https://securitykiss.com/resources/tutorials/csp_project/
which is a lovely little demo of go-like Communicating Sequential Processes.  
Seriously, check it out.  The examples are wonderful.  I love everything about it
.. so much so that I had to rewrite it myself, in order to understand it.

I don't claim that this implementation is better, just different.  It:

  - passes the same tests
  - uses TclOO, encapsulating most of the smarts in a [gochan] object
  - issues only as many [after] callbacks as are required
  - probably satisfies my standards for cleanup and error reporting/handling
  - definitely helped me understand the paradigm better

The securitykiss version is likely to be better maintained and is definitely
better documented.  This is mine, but *all* creative credit goes to the
original.


go cmd ?args ...?       - starts a coroutine, returning its name
channel varName ?bufsz? - creates a channel, storing its name
<- channel              - receives asychronously
$chan <- msg            - sends a message to a channel
$chan close
-> varName              - constructor for a one-shot channel, result is write command
        -- obj + write command lifetimes need to be tied

A channel has three basic methods:  get, put and close.

    get takes the first item from the buffer
        blocks if the buffer is empty
        dies and errors if the buffer is empty and closed
    put appends an item to the buffer
        blocks if the buffer is full
        dies and errors if the buffer is closed
    close closes the buffer
        and notifies that both reader and writer should unblock

"polite" versions <-? are provided for use in loops:  they return -code break instead of throwing on
closure of the channel.  "imperative" <-! versions are for use outside coroutines, and only with care
as they rely on [vwait].

Commands compatible with the csp package (sufficient to pass tests) are provided in the second 
[namespace eval].  I'm not entirely happy with all of these, so I might rename them and relegate
the aliases to ::go::csp.


There is a notifier pattern hidden in here:

    subscribe pattern ?cmd? ?arg ...?
    proc waiton {args} { subscribe $args [info coroutine] }
    notify event
    delete event

unrelated margin note: [yieldto _ [info coroutine]] ~= (call/cc)
