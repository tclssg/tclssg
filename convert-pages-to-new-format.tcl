#!/usr/bin/env tclsh

package require fileutil

# Get variables set in page using the "! variable value" syntax.
proc get-page-variables {rawContent} {
    global errorInfo
    set variables {}
    set markup {}
    foreach line [split $rawContent \n] {
        if {[string index $line 0] == "!"} {
            if {[catch {dict set variables [lindex $line 1] [lindex $line 2]}]} {
                puts "error: syntax error when setting page variable: '$line'"
                puts "$errorInfo"
                exit 1
            }
            if {[llength $line] > 3} {
                puts "warning: trailing data after variable value: '$line'"
            }
        } else {
            lappend markup $line
        }
    }
    return [list $variables [join $markup \n]]
}

proc format-settings {lst} {
    set result "{\n"
    foreach {var val} $lst {
        append result "    [list $var $val]\n"
    }
    append result "}\n"
    return $result
}

if {[llength $argv] == 0} {
    puts "usage: $argv0 file ?file ...?"
}
foreach file $argv {
    puts "converting $file"
    file copy $file $file.backup
    lassign [get-page-variables [fileutil::cat $file]] varList markup
    fileutil::writeFile $file [format-settings $varList]$markup
}
