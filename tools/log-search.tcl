#! /usr/bin/env tclsh
# A tool for searching logs in Tclssg's indentation-based format.
# Copyright (c) 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

package require try 1

namespace eval ::log-search {
    proc usage {} {
        puts stderr "usage: [file tail [info script]] regexp \[file\
                     \[--no-color\]\]"
    }

    # Find occurrences of $regexp in lines read from $channelId -- with prefix
    # retention. "Prefix retention" means that the initial whitespace in the
    # current line is replaced with the content of the previous line.
    proc search {regexp channelId {colorMode none}} {
        set timestamp {}
        set timestampShown 1
        set retained {}
        set retain 1
        set matched 0

        while {[gets $channelId line] != -1} {
            if {[regexp -- ^---- $line]} {
                set timestamp $line
                set timestampShown 0
                continue
            }

            if {[regexp {^(?:[^\s].*?|)\{$} $line]} {
                set retain 0
            } elseif {[regexp ^\}$ $line]} {
                set retain 1
            }
            if {!$retain} {
                set retained {}
            }

            set prevRetained $retained
            set retained [join [retain-line $retained $line] {}]

            if {[regexp -- $regexp $retained]} {
                set matched 1

                if {!$timestampShown} {
                    cprint $colorMode \
                           [list {%color yellow} $timestamp {%color default}]
                    set timestampShown 1
                }

                lassign [retain-line $prevRetained $line] prefix unique
                # Retained text is dim. New text is normal or bold. Matching
                # text is red and non-matching is the default color.
                set output [list \
                    {%color default dim} \
                    {*}[delimit $regexp \
                                {%color red dim} \
                                {%color default dim} \
                                $prefix] \
                    {%color default nobold} \
                    {*}[delimit $regexp \
                                {%color red bold} \
                                {%color default nobold} \
                                $unique] \
                    {%color default nobold} \
                ]
                cprint $colorMode $output
            }
        }

        return $matched
    }

    # Prefix retention. See the comment for [search].
    proc retain-line {line1 line2} {
        set result {}
        set ws -1
        if {[regexp -indices -- {^\s+} $line2 match]} {
            lassign $match _ ws
        }
        set len [string length $line1]
        if {$ws >= $len} {
            append line1 [string repeat { } [expr {$ws + 1 - $len}]]
        }
        list [string range $line1 0 $ws] [string range $line2 $ws+1 end]
    }

    # Split $text into a list of fragments. Insert $startInsert before and
    # $endInsert after each fragment matching $regexp.
    proc delimit {regexp startInsert endInsert text} {
        set result {}
        set offset -1
        foreach match [regexp -all -indices -inline -- $regexp $text] {
            lassign $match start end
            lappend result [string range $text $offset $start-1]
            lappend result $startInsert
            lappend result [string range $text $start $end]
            lappend result $endInsert
            set offset [expr {$end + 1}]
        }
        lappend result [string range $text $offset end]
        return $result
    }

    # Print a list of strings while interpreting color commands. This is not a
    # [puts].
    proc cprint args {
        set channelId stdout
        set newline 1

        switch -exact -- [llength $args] {
            2 {
                lassign $args colorMode list
            }
            3 {
                lassign $args channelId colorMode list
            }
            4 {
                lassign $args flag channelId colorMode list
                if {$flag eq {-nonewline}} {
                    set newline 0
                } else {
                    error "expected \"-nonewline\", but got [list $flag]"
                }
            }
            default {
                error {wrong # args: should be\
                       "cprint ?-nonewline? ?channelId? colorMode list"}
            }
        }
        foreach fragment $list {
            if {[regexp ^%\s*?color $fragment]} {
                puts -nonewline $channelId \
                                [color $channelId \
                                       $colorMode \
                                       {*}[lrange $fragment 1 end]]
            } else {
                puts -nonewline $channelId $fragment
            }
            flush $channelId
        }
        if {$newline} {
            puts $channelId {}
            flush $channelId
        }
    }

    # Depending on the $colorMode,
    # * return the color- and text attribute-setting codes that correspond to
    #   $color and $attr;
    # * set the current text attributes for $channelId directly.
    proc color {channelId colorMode color {attr {}}} {
        if {$attr ni {bold nobold dim {}}} {
            error "unknown attribute: [list $attr]"
        }
        switch -exact -- $colorMode {
            ansi {
                set seq {}
                if {$color ne {}} {
                    append seq [sda_fg$color]
                }
                if {$attr ne {}} {
                    append seq [sda_$attr]
                }
                return $seq
            }
            twapi {
                set arguments {}

                if {$color eq {default}} {
                    set color gray
                }

                if {$color eq {black} ||
                    ($color eq {gray} && $attr eq {dim})} {
                    ::twapi::set_console_default_attr $channelId \
                        -fgred 1
                    ::twapi::set_console_default_attr $channelId \
                        -fgred 0 \
                        -fgbright [expr {$attr eq {dim}}]
                    return
                }
                
                if {$color ne {}} {
                    lappend arguments -fg$color 1
                }
                if {$attr ne {}} {
                    lappend arguments -fgbright [expr {$attr eq {bold}}]
                }
                if {$arguments ne {}} {
                    ::twapi::set_console_default_attr $channelId {*}$arguments
                }
            }
            none {
                return {}
            }
            default {
                error "unknown color mode: [list $mode]"
            }
        }
    }

    # Return the best color mode to use based on the platform and the available
    # packages.
    proc detect-color-mode {} {
        switch -exact -- $::tcl_platform(platform) {
            unix {
                try {
                    package require term::ansi::code::ctrl 0-2
                    namespace path ::term::ansi::code::ctrl
                } on error {} {
                    return none
                }
                return ansi
            }
            windows {
                try {
                    package require twapi 4
                } on error {} {
                    return none
                }
                return twapi
            }
            default {
                return none
            }
        }
    }

    proc main {argv} {
        if {$argv in {-h -help --help}} {
            usage
            exit 0
        }

        switch -exact -- [llength $argv] {
            1 {
                lassign $argv regexp
                set file -
            }
            2 {
                lassign $argv regexp file
            }
            3 {
                lassign $argv regexp file noColor
                if {$noColor ne {--no-color}} {
                    puts stderr "error: expected \"--no-color\",\
                                 but got \"$noColor\""
                    usage
                    exit 1
                }
            }
            default {
                usage
                exit 1
            }
        }
        if {[file isdir $file]} {
            puts stderr "error: path [list $file] is a directory"
            exit 1
        }

        if {$file eq {-}} {
            set ch stdin
        } else {
            try {
                open $file r
            } on error result {
                regexp {^.*?: (.*)$} $result _ result
                puts stderr "error: couldn't open [list $file]: $result"
                exit 1
            }
        }

        set colorMode [expr {
            [info exists noColor] ? {none} : [detect-color-mode]
        }]

        set matched [search $regexp $ch $colorMode]

        exit [expr {!$matched}]
    }
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::log-search::main $argv
}
