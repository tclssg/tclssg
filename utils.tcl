# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

interp alias {} read-file {} fileutil::cat

# Transform a path relative to fromDir into the same path relative to toDir.
proc replace-path-root {path fromDir toDir} {
    fileutil::lexnormalize [
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
    string trim [regsub -all {[^[:alnum:]]+} [string tolower $text] "-"] "-"
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

# Sort the keys of a dictionary of dictionaries by value index. The index can
# be one or more key names. TODO: sort by value itself if index is {}.
# Optionally set default value for keys that are missing the index, pass
# option to lsort or applying lambda to each value.
proc dict-sort {dictionary \
                index \
                {default 0} \
                {lsortOptions {}} \
                {lambda {x {lindex $x}}}} {
    set lp {}
    dict for {key value} $dictionary {
        lappend lp [
            list $key $value [
                apply $lambda [
                    dict-default-get $default $value {*}$index
                ]
            ]
        ]
    }
    return [
        concat {*}[
            struct::list mapfor x [
                lsort -index 2 {*}$lsortOptions $lp
            ] {
                lrange $x 0 1
            }
        ]
    ]
}

# Remove first n elements from varName and return them.
proc unqueue {varName {n 1}} {
    upvar 1 $varName var
    set result [lrange $var 0 [expr $n - 1]]
    set var [lrange $var $n end]
    return $result
}


# Copy all files form fromDir to toDir displaying feedback to the user. All
# files matching skipRegExp are ignored. If overwrite == 2 prompt
# user whether to overwrite each file.
proc copy-files {fromDir toDir {overwrite 0} {skipRegExp ""}} {
    set files [
        struct::list filterfor x [
            fileutil::find $fromDir {file isfile}
        ] {
            $skipRegExp eq "" || ![regexp -- $skipRegExp $x]
        }
    ]

    set input {}
    foreach file $files {
        set destFile [replace-path-root $file $fromDir $toDir]
        if {[file exists $destFile]} {
            if {$overwrite == 2} {
                if {$input ne "all"} {
                    set input {}
                    while {$input ni {y n all}} {
                        puts "overwrite $destFile with $file? (y/n/all)"
                        set input [string tolower [gets stdin]]
                    }
                }
            }

            if {$overwrite == 1 || \
                ($overwrite == 2 && $input in {y all})} {
                puts "overwriting $destFile with $file"
                file copy -force $file $destFile
            } else {
                puts "skipped copying $file to $destFile: file exists"
            }
        } else {
            puts "copying $file to $destFile"
            if {![file isdir [file dirname $destFile]]} {
                file mkdir [file dirname $destFile]
            }
            file copy $file $destFile
        }
    }
}

# Try several formats for clock scan.
proc incremental-clock-scan {date {debug 0}} {
    set date [regsub -all {[ :.T/]+} $date {-}]

    set result {}
    foreach {format padding} {
        {%Y} {-01-01-00-00-00}
        {%Y-%m} {-01-00-00-00}
        {%Y-%m-%d} {-00-00-00}
        {%Y-%m-%d-%H-%M} {-00}
        {%Y-%m-%d-%H-%M-%S} {}
    } {
        if {$debug} {
            puts "$format $date"
        }
        if {![catch {
                set scan [clock scan $date -format $format]
            }]} {
            # Work around unexpected treatment %Y and %Y-%m dates, see
            # http://wiki.tcl.tk/2525.
            set result [
                clock scan [
                    join [list $date $padding] ""
                ] -format {%Y-%m-%d-%H-%M-%S}
            ]
            if {$debug} {
                puts "match"
                puts [clock format $scan]
            }
        }
    }
    return $result
}

# Find the first directory dir in list dirs in which path exists.
# Return path prefixed with dir.
proc choose-dir {path dirs} {
    foreach dir $dirs {
        set fullPath [file join $dir $path]
        if {[file exists $fullPath]} {
            return $fullPath
        }
    }
    error "$path not found in [join $dirs {, }]"
}

# Return true for a relative path and false otherwise.
proc path-is-relative? {path} {
    return [catch {::fileutil::relative / $path}]
}

# Return fileName with the number n inserted before its extension.
proc add-number-before-extension {fileName n {numberFormat {-%d}}
        {nothingOnZero 1}} {
    if {$n == 0 && $nothingOnZero} {
        set s ""
    } else {
        set s [format $numberFormat $n]
    }
    return [format "[file rootname $fileName]%s[file extension $fileName]" $s]
}

# Get variables set in page using Tcl list syntax at the beginning of the
# post.
proc get-page-variables {rawContent} {
    global errorInfo

    set vars {}
    # Find the longest substring of rawContent that is a list.
    set maxListLength [expr {[string length $rawContent] + 1}]
    string is list -failindex maxListLength $rawContent
    set maxList \
            [string trimleft \
                    [string range $rawContent 0 [expr {$maxListLength - 1}]]]

    #
    if {[string index $maxList 0] == "\{"} {
        set vars [lindex $maxList 0]
    }

    # Trim newlines before markup. The "+2" is for the list delimiters.
    set markup \
            [string trimleft \
                    [string range $rawContent [string length $vars]+2 end]]

    return [list $vars $markup]
}
