# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Load Markdown files into the database. Expand Markdown -> Markdown macros in
# them if macros are enabled.
namespace eval ::tclssg::pipeline::1-load-markdown {
    namespace path ::tclssg

    proc load files {
        set interp 1-load-markdown
        interpreter create $interp
        foreach file $files {
            if {[string tolower [file extension $file]] in {.md .markdown}} {
                log::info "reading Markdown file [list $file]"
                load-page $file
            }
        }
        interp delete $interp
    }

    # Load the content of the file $file into the input database.
    proc load-page file {
        lassign [utils::separate-frontmatter \
                    [utils::read-file -translation binary $file]] \
                frontmatter \
                raw
        set inputDir [db settings get config inputDir]
        set id [utils::replace-path-root $file $inputDir {}]

        # Skip pages marked as drafts.
        if {[utils::dict-default-get 0 $frontmatter draft]} {
            return
        }

        debugger save-intermediate $file \
                                   frontmatter-0-raw.tcl \
                                   $frontmatter
        debugger save-intermediate $file \
                                   content-0-raw \
                                   $raw

        db transaction {
            # Parse date and modified into a Unix timestamp plus a format
            # string.
            set clockOptions {}
            set timezone [db settings get config timezone {}]
            if {$timezone ne {}} {
                set clockOptions [list -timezone $timezone]
            }

            set timestamp [utils::incremental-clock-scan \
                              [dict-default-get {} $frontmatter date] \
                              $clockOptions]
            if {$timestamp ne {{} {}}} {
                dict set frontmatter timestamp $timestamp
            }

            set modified [utils::incremental-clock-scan \
                             [dict-default-get {} $frontmatter modified] \
                             $clockOptions]
            if {$modified ne {{} {}}} {
                dict set frontmatter modifiedTimestamp $modified
            }

            set macros [db settings get config enableMacros 0]
            set cooked [prepare-content $file \
                                        $frontmatter \
                                        $raw \
                                        $macros \
                                        1-load-markdown \
                                        [list input $id]]

            db input add $id \
                         $raw \
                         $cooked \
                         [lindex $timestamp 0]
            db tags add $id \
                        [dict-default-get {} $frontmatter tags]
            dict unset frontmatter tags
            db tags add $id type:markdown

            tclssg debugger save-intermediate $file \
                                              frontmatter-1-final.tcl \
                                              $frontmatter
            foreach {key value} $frontmatter {
                db settings set $id $key $value
            }
        }
    }

    proc prepare-content {file frontmatter content macros interp
                          extraVariables} {
        if {$macros} {
            set content [dict-default-get {} \
                                          $frontmatter \
                                          prelude]\n$content
            debugger save-intermediate $file \
                                       content-1-toexpand \
                                       $content
            set template [templates parse $content]
            interpreter inject $interp $extraVariables
            set content [interp eval $interp $template]
        }

        debugger save-intermediate $file \
                                          content-2-markdown \
                                          $content
        set content [converters markdown markdown-to-html $content]

        debugger save-intermediate $file \
                                          content-3-html \
                                          $content
        return $content
    }
}
