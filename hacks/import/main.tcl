proc import {basename} {
    set ns [string map {/ ::} $basename]
    set filename $basename.tcl
    uplevel 1 [list namespace eval $ns [list source $filename]]
}

import foo

foo::foo

import bar

bar::foo

import a/foo

a::foo::foo
