#!/usr/bin/env tclsh
#
lappend auto_path [file normalize [info script]/../modules]
::tcl::tm::path add [file normalize [info script]/../modules]
source [lindex $argv 0][set argv [lrange $argv 1 end]]
