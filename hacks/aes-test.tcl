#!/bin/sh
#
# AES sampler
#
package require aes

proc randbytes {n} {
    set r {}
    while {$n > 0} {
        lappend r [expr {int(rand()*256)}]
        incr n -1
    }
    binary format c* $r
}

# PKCS-style padding
proc pad {data {mul 16}} {
    set len [string length $data]
    set n [expr {$mul - ($len % $mul)}]
    append data [binary format c* [lrepeat $n $n]]
}

proc unpad {data {mul 16}} {
    binary scan [string index $data end] c n
    set pad [string replace $data 0 end-$n]
    set expect [binary format c* [lrepeat $n $n]]
    if {$pad ne $expect} {
        error "Bad padding! [list [binary encode hex $pad] != [binary encode hex $expect]]"
    }
    string range $data 0 end-$n
}

proc encrypt {key data} {
    set fd [file tempfile fn]
    try {
        chan configure $fd -translation binary
        aes::aes -mode cbc -dir encrypt -key $key -out $fd [pad $data]
        return $fn
    } finally {
        close $fd
    }
}

proc decrypt {key filename} {
    set fd [open $filename r]
    try {
        chan configure $fd -translation binary
        unpad [aes::aes -mode cbc -dir decrypt -key $key -in $fd]
    } finally {
        close $fd
    }
}

proc readbinary {filename} {
    set fd [open $filename r]
    try {
        chan configure $fd -translation binary
        read $fd
    } finally {
        close $fd
    }
}

namespace eval main {
    proc enc {key filename} {
        puts -nonewline [encrypt [binary decode base64 $key] [readbinary $filename]]
    }
    proc dec {key filename} {
        puts -nonewline [decrypt [binary decode base64 $key] $filename]
    }

    proc test {filename} {
        puts "Generating key"
        set key [randbytes 32]
        puts "Reading file"
        set data [readbinary $filename]
        puts "Encrypting"
        set file [encrypt $key $data]
        puts "Decrypting"
        set data2 [decrypt $key $file]
        puts "Encrypted file: $file"
        puts "Key (base64): [binary encode base64 $key]"
        puts --
        puts -nonewline "Verifying: "
        if {$data eq $data2} {
            puts "OK!"
        } else {
            puts "Error!"
            puts "data = [binary encode hex $data]"
            puts "data2 = [binary encode hex $data2]"
        }
    }
    namespace export *
    namespace ensemble create
}

main {*}$argv
