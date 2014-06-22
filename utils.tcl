# ssg-tcl, a static website generator in Tcl.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Returns the content of file fname.
proc read-file {fname {binary 0}} {
    set fpvar [open $fname r]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    set content [read $fpvar]
    close $fpvar
    return $content
}

# Save content to file fname.
proc write-file {fname content {binary 0}} {
    set fpvar [open $fname w]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    puts -nonewline $fpvar $content
    close $fpvar
}

# Transform a path relative to fromDir into the same path relative to toDir.
proc replace-path-root {path fromDir toDir} {
    # string map here is a hack to fix /./ making printed logs ugly.
    string map {/./ /} [
        file join $toDir [
            ::fileutil::relative $fromDir [file dirname $path]
        ] [
            file tail $path
        ]
    ]
}

# Return a value from dictionary like dict get would if it is there.
# Otherwise return the default value.
proc dict-default-get {default dictionary args} {
    if {[dict exists $dictionary {*}$args]} {
        dict get $dictionary {*}$args
    } else {
        return $default
    }
}

# Trim indentation in multiline quoted text. Unlike textutil::undent this
# removes lines at the beginning and the end of the text that were turned blank
# by the unindentation.
proc trim-indentation {msg {whitespaceChars " "}} {
    set msgLines [split $msg "\n"]
    set maxLength [string length $msg]

    set regExp [subst -nocommands {([$whitespaceChars]*)[^$whitespaceChars]}]

    set indent [
        tcl::mathfunc::min {*}[
            struct::list mapfor x $msgLines {
                if {[regexp $regExp $x match whitespace]} {
                    string length $whitespace
                } else {
                    lindex $maxLength
                }
            }
        ]
    ]

    return [
        join [
            ltrim [
                struct::list mapfor x $msgLines {string range $x $indent end}
            ]
        ] "\n"
    ]
}

# Remove empty items at the beginning and the end of a list.
proc ltrim {list {emptyRegExp "^$"}} {
    set first [lsearch -not -regexp $list $emptyRegExp]
    set last [lsearch -not -regexp [lreverse $list] $emptyRegExp]
    return [
        if {$first == -1} {
            list
        } else {
            lrange $list $first end-$last
        }
    ]
}

# Format text for URL slug. E.g., "Hello, World!" becomes "hello-world".
proc slugify {text} {
    string trim [
        regsub -all {[^[:alnum:]]+} [string tolower $text] "-"
    ] "-"
}

# Return dictionary with values replaced with stars for every key with
# "password" in its name.
proc obscure-password-values {dictionary} {
    set result {}
    dict for {key value} $dictionary {
        dict set result $key [
            if {[string match -nocase *password* $key]} {
                lindex {***}
            } else {
                lindex $value
            }
        ]
    }
    return $result
}

# Format dictionary for printing.
proc dict-format {dictionary {formatString "%s %s\n"}} {
    set result {}
    dict for {key value} $dictionary {
        append result [format $formatString $key $value]
    }
    return $result
}
