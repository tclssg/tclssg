# Tclssg, a static website generator.
# Copyright (c) 2013-2020, 2024
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Load Markdown files into the database. Expand Markdown -> Markdown macros in
# them if macros are enabled.
namespace eval ::tclssg::pipeline::20-load-markdown {
    namespace path ::tclssg

    proc load files {
        set interp 20-load-markdown
        interpreter create $interp

        set inputDir [db config get inputDir]
        foreach file $files {
            set id [utils::replace-path-root $file $inputDir {}]
            if {[lindex [file split $id] 0] in {data debug}} continue

            if {[string tolower [file extension $file]] in {.md .markdown}} {
                log::info "reading Markdown file [list $file]"
                load-page $file
            }
        }
        interp delete $interp
    }

    # Load the content of the file $file into the input database.
    proc load-page file {
        set bin [utils::read-file -translation binary $file]
        lassign [utils::separate-frontmatter $bin] \
                frontmatterWithComments \
                raw
        set frontmatterWithShorthand \
            [utils::remove-comments $frontmatterWithComments]
        set frontmatter \
            [utils::dict-expand-shorthand $frontmatterWithShorthand]

        set inputDir [db config get inputDir]
        set id [utils::replace-path-root $file $inputDir {}]

        # Skip pages marked as drafts.
        if {[utils::dict-getdef $frontmatter draft 0]} {
            return
        }

        debugger save-intermediate $file \
                                   frontmatter-0-raw.tcl \
                                   $frontmatter
        debugger save-intermediate $file \
                                   content-0-raw.md \
                                   $raw

        db transaction {
            # Parse date and modified into a Unix timestamp plus a format
            # string.
            set presetTimezone [db settings preset-get $file {timezone date} {}]
            set timezone [dict-getdef \
                $frontmatter \
                timezone date \
                $presetTimezone \
            ]
            set clockOptions [expr {
                $timezone eq {} ? {} : [list -timezone $timezone]
            }]

            set timestamp {{} {}}
            if {[dict exists $frontmatter date]} {
                try {
                    utils::incremental-clock-scan \
                        [dict get $frontmatter date] \
                        $clockOptions
                } on ok timestamp {
                    dict set frontmatter timestamp $timestamp
                }
            }

            if {[dict exists $frontmatter modified]} {
                try {
                    utils::incremental-clock-scan \
                        [dict get $frontmatter modified] \
                        $clockOptions
                } on ok modified {
                    dict set frontmatter modifiedTimestamp $modified
                }
            }

            db input add \
                -type page-dummy \
                -file $id \
                -raw $raw \
                -cooked {} \
                -timestamp [lindex $timestamp 0]

            db tags add $id [dict-getdef $frontmatter tags {}]
            dict unset frontmatter tags

            foreach {key value} $frontmatter {
                db settings set $id $key $value
            }

            set macros [db config get macros 0]
            set cooked [prepare-content $file \
                                        $frontmatter \
                                        $raw \
                                        $macros \
                                        20-load-markdown \
                                        [dict create input $id]]

            db input set $id type page
            db input set $id cooked $cooked

            tclssg debugger save-intermediate $file \
                                              frontmatter-1-final.tcl \
                                              $frontmatter
        }
    }

    proc prepare-content {file frontmatter content macros interp
                          extraVariables} {
        if {$macros} {
            set content [dict-getdef $frontmatter prelude {}]\n$content
            debugger save-intermediate $file \
                                       content-1-with-prelude.md \
                                       $content
            set template [templates parse $content]
            interpreter inject $interp $extraVariables
            set content [interp eval $interp $template]
        }

        debugger save-intermediate $file content-2-macroexpanded.md \
                                         $content
        set content [converters markdown markdown-to-html $content]

        debugger save-intermediate $file content-3-cooked.html \
                                         $content
        return $content
    }
}
