# Tclssg, a static website generator.
# Copyright (c) 2013-2019, 2024
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::utils {
    namespace export *
    namespace ensemble create
    namespace path ::tclssg

    proc read-file args {
        if {[llength $args] == 0} {
            error "wrong # args: should be \"[info level 0] ?options? path\""
        }
        set path [lindex $args end]
        set options [lrange $args 0 end-1]
        set ch [open $path r]
        fconfigure $ch {*}$options
        set data [read $ch]
        close $ch
        return $data
    }
    interp alias {} ::tclssg::utils::write-file {} ::fileutil::writeFile

    proc normalize-relative-path path {
        # TODO: Normalize $relPrefix as well.
        regexp {^(\.[/\.]+\/)(.*)} $path _ relPrefix path
        set path [::fileutil::lexnormalize $path]
        if {[info exists relPrefix]} {
            set path ${relPrefix}$path
        }
        return $path
    }

    # Transform a path relative to fromDir into the same path relative to toDir.
    proc replace-path-root {path fromDir toDir} {
        normalize-relative-path [
            file join $toDir \
                      [::fileutil::relative $fromDir [file dirname $path]] \
                      [file tail $path] \
        ]
    }

    # A version of the above that conforms to the Tcl 8.7 [dict getdef] syntax.
    proc dict-getdef args {
        if {[llength $args] < 3} {
            error "wrong # args: should be \"[info level 0] dictionary\
                   ?key ...? key default\""
        }

        set dictionary [lindex $args 0]
        set default [lindex $args end]
        set keys [lrange $args 1 end-1]

        set error [catch {
            dict get $dictionary {*}$keys
        } result opts]

        if {!$error} {
            return $result
        }

        return $default
    }

    # Trim indentation in multiline quoted text. Unlike [textutil::undent],
    # this proc removes a leading and a trailing blank line. If
    # $ignoreIndentOnlyLines is true, it does not count indentation-only lines
    # in $text and removes an indentation-only trailing line if it is present.
    proc trim-indentation {
        text
        {chars { }}
        {ignoreIndentOnlyLines true}
        {max inf}
    } {
        regsub ^\n $text {} text
        if {$ignoreIndentOnlyLines} {
            regsub \n\[$chars\]*?$ $text {} text
        } else {
            regsub \n$ $text {} text
        }

        set rLeading ^\[$chars\]*
        set rBlankLine $rLeading$

        foreach line [split $text \n] {
            if {$line eq {}
                || ($ignoreIndentOnlyLines
                    && [regexp $rBlankLine $line])} continue

            regexp -indices $rLeading $line idc
            set count [expr {[lindex $idc 1] + 1}]

            set max [expr {min($max,$count)}]
        }

        set start [expr { $max == inf ? {end+1} : $max }]

        join [struct::list mapfor line [split $text \n] {
            string range $line $start end
        }] \n
    }

    # Format text for URL slug. E.g., "Hello, World!" becomes "hello-world".
    proc slugify {text} {
        string trim [regsub -all {[^[:alnum:]]+} [string tolower $text] "-"] "-"
    }

    # Return dictionary with values or every key with "password" in its name
    # recursively replaced with stars.
    proc obscure-password-values {dictionary} {
        set result {}
        dict for {key value} $dictionary {
            dict set result $key [
                if {[string match -nocase *password* $key]} {
                    lindex {***}
                } elseif {([llength $value] > 1) &&
                        ([llength $value] % 2 == 0)} {
                    obscure-password-values $value
                } else {
                    lindex $value
                }
            ]
        }
        return $result
    }

    # Format dictionary for printing.
    proc dict-format {dictionary {formatString "%s %s\n"} {doNotRecurKeys {}}} {
        set lengthLimit 50
        set result {}

        dict for {key value} $dictionary {
            set wrappedValue 0
            if {([llength $value] > 1) &&
                    ($key ni $doNotRecurKeys) &&
                    ([llength $value] % 2 == 0)} {
                # Assume the value is a nested dictionary.
                set value [dict-format $value $formatString $doNotRecurKeys]
                set value "{\n[::textutil::indent $value {    }]\n}"
                set wrappedValue 1
            } elseif {$value eq ""} {
                set value "{}"
            }
            if {!$wrappedValue} {
                if {[string length $value] > $lengthLimit} {
                    set value "{\n[::textutil::indent $value {    }]\n}"
                } elseif {[llength $value] > 1} {
                    set value "{$value}"
                }
            }
            append result [format $formatString $key $value]
        }

        return $result
    }

    # Remove first n elements from varName and return them.
    proc unqueue! {varName {n 1}} {
        upvar 1 $varName var
        if {$n eq {inf}} {
            set result $var
            set var {}
        } else {
            if {$n == 1} {
                set result [lindex $var 0]
            } else {
                set result [lrange $var 0 [expr $n - 1]]
            }
            set var [lrange $var $n end]
        }
        return $result
    }


    # Copy all files form fromDir to toDir displaying feedback to the user. All
    # files matching skipRegExp are ignored. If overwrite is "?" prompt
    # user whether to overwrite each file.
    proc copy-files {fromDir toDir {overwrite never} {skipRegExp ""}} {
        if {$overwrite ni {never always ask}} {
            error "unknown overwrite value \"$overwrite\";\
                   must be \"never\", \"always\" or \"ask\""
        }
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
                if {$overwrite eq "ask"} {
                    if {$input ni {all none}} {
                        set input {}
                        while {$input ni {y n all none}} {
                            puts "overwrite $destFile with $file?\
                                  (y/n/all/none)"
                            set input [string tolower [gets stdin]]
                        }
                    }
                }

                if {$overwrite eq "always" ||
                    ($overwrite eq "ask" && $input in {y all})} {
                    log::info "copying [list $file] over [list $destFile]"
                    file copy -force $file $destFile
                } else {
                    log::info "skipped copying [list $file] to\
                               [list $destFile]: file exists"
                }
            } else {
                log::info "copying [list $file] to [list $destFile]"
                if {![file isdir [file dirname $destFile]]} {
                    file mkdir [file dirname $destFile]
                }
                file copy $file $destFile
            }
        }
    }

    # Try several formats for clock scan.
    proc incremental-clock-scan {dateOrig {options {}} {debug 0}} {
        set date [regsub {([+-])(\d\d):(\d\d)$} $dateOrig {\1\2\3}]
        set date [regsub -all {[ :.T/]+} $date -]

        set result(timeVal) {}
        set result(format) {}

        foreach {format(test) format(standard) format(padding) format(scan)} {
            %Y
            %Y
            -01-01-00-00-00
            %Y-%m-%d-%H-%M-%S

            %Y-%m
            %Y-%m
            -01-00-00-00
            %Y-%m-%d-%H-%M-%S

            %Y-%m-%d
            %Y-%m-%d
            -00-00-00
            %Y-%m-%d-%H-%M-%S

            %Y-%m-%d-%H-%M
            %Y-%m-%dT%H:%M
            -00
            %Y-%m-%d-%H-%M-%S

            %Y-%m-%d-%H-%M-%S
            %Y-%m-%dT%H:%M:%S
            {}
            %Y-%m-%d-%H-%M-%S

            %Y-%m-%d-%H-%M-%S%z
            %Y-%m-%dT%H:%M:%S%z
            {}
            %Y-%m-%d-%H-%M-%S%z
        } {
            if {$debug} {
                log::debug [list $format(test) $date]
            }
            try {
                clock scan $date -format $format(test) {*}$options
            } on ok scan {
                # Work around unexpected treatment of %Y and %Y-%m dates;
                # see http://wiki.tcl-lang.org/2525.
                set result(timeVal) [clock scan $date$format(padding) \
                                                -format $format(scan) \
                                                {*}$options]
                set result(format) $format(standard)
                if {$debug} {
                    log::debug match
                    log::debug [clock format $scan {*}$options]
                }
                break
            } on error {} {}
        }

        if {$result(timeVal) eq {}} {
            return -code error \
                   -errorcode [list INCR_CLOCK_SCAN BAD_DATE_TIME] \
                   [list no known format matches date-time string $dateOrig]
        }

        return [list $result(timeVal) $result(format)]
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

    # A wrapper for ::sha2::sha256 for safe interps.
    proc sha256 args {
        if {[llength $args] ni {1 2}} {
            error "wrong # args: should be \"[info level 0] ?-bin|-hex?\
                   string\""
        }
        if {[llength $args] == 2} {
            lassign $args format string
            if {$format ni {-bin -hex}} {
                error "unexpected format argument \"$format\";\
                       must be \"-bin\" or \"-hex\""
            }
        } else {
            set format -hex
            lassign $args string
        }
        return [::sha2::sha256 $format -- $string]
    }

    # Return fileName with the number n inserted before its extension.
    proc add-number-before-extension {fileName n {numberFormat {-%d}}
            {numberToSkip 0}} {
        if {$n == $numberToSkip} {
            set s ""
        } else {
            set s [format $numberFormat $n]
        }
        return [format \
                "[file rootname $fileName]%s[file extension $fileName]" $s]
    }

    # Get variables set in page using Tcl list syntax at the beginning of the
    # post.
    proc separate-frontmatter {rawContent} {
        if {![regexp ^\{ $rawContent]} {
            return [list {} $rawContent]
        }

        # Find the longest substring of rawContent that is a list.
        set maxListLength [expr {[string length $rawContent] + 1}]
        string is list -failindex maxListLength $rawContent
        set maxList \
            [string trimleft \
                [string range \
                    $rawContent \
                    0 \
                    [expr {$maxListLength - 1}]]]

        set vars [lindex $maxList 0]

        # Trim newlines before markup. The "+2" is for the list delimiters.
        set markup \
            [string trimleft \
                [string range \
                    $rawContent \
                    [string length $vars]+2 \
                    end]]

        return [list $vars $markup]
    }

    # Take {column1 width1 column2 width2 ...} and return text formatted in
    # columns of the specified width.
    proc text-columns args {
        set result {}

        # Remove a substring from variable stringVarName without break words and
        # return that fragment.
        proc getFragment {stringVarName length} {
            upvar 1 $stringVarName stringVar

            # Longest substring of length <= $length that can be taken from
            # stringVarName breaking on non-blank characters.
            set lst [::textutil::splitx $stringVar]
            set result [lindex $lst 0]
            set i 1
            while {([string length "$result"] < $length) &&
                    ($i < [llength $lst])} {
                append result " [lindex $lst $i]"
                incr i
            }

            # Remove fragment from string.
            set stringVar [string range $stringVar [string length $result] end]

            set result [string trim $result]
            # Pad result to length $length.
            if {[string length $result] < $length} {
                append result [::textutil::blank \
                        [expr {$length - [string length $result]}]]
            }
            return $result
        }

        try {
            set content [dict keys $args]
            set widths [dict values $args]
        } on error {} {
            return -code error \
                   "wrong # args: should be \"[lindex [info level 0] 0]\
                    {content width ...}\""
        }

        # For all columns...
        while 1 {
            set allEmpty 1
            for {set i 0} {$i < [llength $content]} {incr i} {
                set s [lindex $content $i]
                append result [getFragment s [lindex $widths $i]]
                lset content $i $s
                set allEmpty [expr {$allEmpty && ($s eq "")}]
            }
            append result \n
            if {$allEmpty} {
                break
            }
        }
        return $result
    }

    proc inspect args {
        set data {}
        set maxLength 0
        foreach varName $args {
            upvar 1 $varName v
            dict set data $varName $v
            set maxLength [expr {max($maxLength, [string length $varName])}]
        }
        incr maxLength
        set indented [::textutil::indent [dict-format $data \
                                                      "%-${maxLength}s %s\n"] \
                                         {    }]
        puts stderr \{\n$indented\n\}
    }

    proc group-by {n list} {
        if {$n <= 0} {
            error "expected an integer >= 1 but got \"$n\""
        }
        set lol {} ;# A list of lists.
        set total [llength $list]
        set current {}
        set i 0

        foreach el $list {
            lappend current $el
            incr i
            if {$i % $n == 0} {
                lappend lol $current
                set current {}
            }
        }
        if {$current ne {}} {
            lappend lol $current
        }

        return $lol
    }

    proc named-args {mapping {strict true}} {
        upvar 1 args args
        set argsVarName {}

        dict for {key dest} $mapping {
            catch {unset default}

            switch -exact -- [llength $dest] {
                1 { set varName $dest }
                2 { lassign $dest varName default }
                default { error "expected \"varName ?default?\",\
                                 but got \"$dest\"" }
            }

            if {$key eq {args}} {
                set argsVarName $varName
                continue
            }

            upvar 1 $varName v
            if {[dict exists $args $key]} {
                set v [dict get $args $key]
            } elseif {[info exists default]} {
                set v $default
            } else {
                error "missing required argument $key"
            }
            dict unset args $key
        }

        if {$args ne {}} {
            if {$argsVarName eq {}} {
                if {$strict} {
                    error "unknown extra arguments: \"$args\""
                } else {
                    return
                }
            }

            upvar 1 $argsVarName upArgs
            set upArgs $args
        }

        return
    }

    proc remove-comments data {
        set lines [split $data \n]
        set filtered [::struct::list filterfor x $lines {![regexp {^\s*#} $x]}]
        return [join  $filtered \n]
    }

    proc longest-common-list-prefix {xs ys} {
        set common {}
        foreach x $xs y $ys {
            if {$x ne $y} {
                break
            }
            lappend common $x
        }
        return $common
    }

    proc dict-expand-shorthand dict {
        set result {}

        dict for {key value} $dict {
            if {![dict exists $result {*}$key]} {
                dict set result {*}$key $value
                continue
            }

            set oldValue [dict get $result {*}$key]

            if {$oldValue eq $value} continue

            if {[llength $oldValue] % 2 == 1} {
                error "can't merge [list $oldValue] with [list $value] under\
                       key [list $key]"
            }

            set merged [dict merge [dict get $result {*}$key] $value]
            dict set result {*}$key $merged
        }

        return $result
    }

    proc proc-source proc {
        set params {}
        foreach param [info args $proc] {
            if {[info default $proc $param default]} {
                lappend params [list $param $default]
            } else {
                lappend params $param
            }
        }

        list proc $proc $params [info body $proc]
    }
}

package provide tclssg::utils 0
