namespace eval keymap {

    variable default_keymap {
        ^A  home
        ^B  back
        ^C  sigint
        ^D  sigpipe
        ^E  end
        ^F  forth
        ^G  softbreak
        ^H  backspace
        ^I  tab
        ^J  newline
        ^K  yank-after
        ^L  redraw
        ^M  newline
        ^N  history-next
        ^O  stash
        ^P  history-prev
        ^Q  scroll-unlock
        ^R  history-search
        ^S  scroll-lock
        ^T  transpose
        ^U  yank-before
        ^V  quote
        ^W  yank-word-before
        ^Y  paste
        ^Z  suspend

        ^?  backspace
        ^_  undo

        ^X^E    editor
        ^X^U    undo
        ^X^X    swap-mark

        ^[^[[A    history-prev-starting
        ^[^[[B    history-next-starting

        ^[[A    up
        ^[[B    down
        ^[[C    forth
        ^[[D    back

        ^[[3~   delete
        ^[[5~   page-up
        ^[[6~   page-down
        ^[[7~   home
        ^[[8~   end

        ^[^?    yank-word-before
        ^[^[^?  yank-word-after
        ^[d     yank-word-after
        ^[^[[3~ yank-word-after
        ^[^[[C  forth-word
        ^[^[[D  back-word

        ^[b     back-word
        ^[f     forth-word
        ^[u     uppercase-word
        ^[l     lowercase-word
        ^[t     transpose-words
        ^[g     complete-filename
        ^[d     yank-after
        ^[p     ??
        ^[n     ??
    }

    # convert a string rep from keymap into a string of binary codes
    proc keycode {str} {
        set controls {
            ^A  0x01  ^B  0x02  ^C  0x03  ^D  0x04  ^E  0x05  ^F  0x06  ^G  0x07
            ^H  0x08  ^I  0x09  ^J  0x0a  ^K  0x0b  ^L  0x0c  ^M  0x0d  ^N  0x0e
            ^O  0x0f  ^P  0x10  ^Q  0x11  ^R  0x12  ^S  0x13  ^T  0x14  ^U  0x15
            ^V  0x16  ^W  0x17  ^X  0x18  ^Y  0x19  ^Z  0x1a

            ^3  0x1b  ^4  0x1c  ^5  0x1d  ^6  0x1e  ^7  0x1f
            ^[  0x1b  ^\\ 0x1c  ^]  0x1d  ^^  0x1e  ^_  0x1f

            ^2  0x00  ^8  0x7f
            ^@  0x00  ^?  0x7f
        }
        set controls [dict map {_ v} $controls {format %c $v}]
        set res {}
        set s $str
        while {$s ne ""} {
            if {[regexp {^(\^.)(.*)} $s -> code rest]} {
                append res [dict get $controls $code]
                set s $rest
            } elseif {[regexp {^(.[^^]*)(.*)} $s -> part rest]} {
                append res $part
                set s $rest
            }
        }
        return $res
    }

    # turn a list of lists into a trie, realised as a recursive dict
    # with leaves holding {}
    proc mktrie {items} {
        set res [dict create]
        foreach ks $items {
            if {![dict exists $res {*}$ks]} {
                dict set res {*}$ks {}
            }
        }
        return $res
    }

    oo::class create KeyMapper {
        variable Chan
        variable KeyTrie
        variable Map
        constructor {chan {map .}} {
            set ns [namespace qualifiers [self class]]
            namespace path [list $ns {*}[namespace path]]
            try {
                dict size $map
            } on error {} {
                set map [set ${ns}::default_keymap]
            }
            set Chan $chan

            # turn keycodes into lists of bytes
            set Map [dict map {k v} $map {
                set k [split [keycode $k] ""]
                set v
            }]

            # make a trie for gettok
            set KeyTrie [mktrie [dict keys $Map]]
        }

        method getch {} {
            yield
            read $Chan 1
        }

        method gettok {{chars ""}} {
            set state [dict get $KeyTrie {*}$chars]
            while 1 {
                if {$state eq ""} {
                    set tok [dict get $Map $chars]
                    if {$tok eq "quote"} {
                        return [list LITERAL "" [list [my getch]]]
                    } else {
                        return [list TOKEN $tok $chars]
                    }
                }
                lappend chars [set c [my getch]]
                if {![dict exists $state $c]} {
                    return [list LITERAL "" $chars]
                }
                set state [dict get $state $c]
            }
        }
    }
}
