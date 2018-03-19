#! /usr/bin/env tclsh

package require fileutil

proc file-structure file {
    set nl 1
    set result {}
    foreach line [split [::fileutil::cat $file] \n] {
        if {[regexp {^\s*([a-z-]*?proc|namespace)} $line]
            && ![regexp {namespace\
                         (ensemble|export|children|current|parent|path)} \
                        $line]} {
            lappend result [format %4d:%s $nl \
                                          [regsub {\{[^\{]*?$} $line {}]]
        }
        incr nl
    }
    return $result
}

proc main path {
    set files [lsort [::fileutil::findByPattern $path -regexp -- \.tcl$]]
    foreach file $files {
        if {[file tail $file] eq {pkgIndex.tcl}} continue

        set fs [file-structure $file]
        if {$fs eq {}} continue

        puts "==== $file ===="
        puts [join $fs \n]\n
    }
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    lassign $argv arg
    main [expr {$arg eq {} ? {lib/} : $arg}]
}
