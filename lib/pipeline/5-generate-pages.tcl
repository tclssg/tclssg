# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Generate HTML output from every input in the DB with the "type:markdown" tag.
namespace eval ::tclssg::pipeline::5-generate-pages {
    namespace path ::tclssg

    proc transform {} {
        set inputDir [db settings get config inputDir]
        set outputDir [db settings get config outputDir]

        set interp 5-generate-pages
        interpreter create $interp

        lassign [blog-index] blogIndexInput blogIndexOutput

        db eval {
            SELECT input.file FROM input
            JOIN tags ON tags.file = input.file
            WHERE tags.tag = 'type:markdown'
            ORDER BY input.timestamp DESC;
        } row {
            if {$row(file) eq $blogIndexInput} {
                gen -interp $interp \
                    -template ::document::render \
                    -input $blogIndexInput \
                    -output $blogIndexOutput \
                    -extraArticles [collection $blogIndexInput blogPost]
            } else {
                gen -interp $interp \
                    -template ::document::render \
                    -input $row(file) \
                    -output [templates input-to-output-path $row(file)]
            }
        }

        interp delete $interp
    }

    proc add-page-number {output n} {
        if {[db settings get config prettyURLs 0]} {
            regexp {(.*?)(?:/page/[0-9]+)?/index.html$} $output _ output
            if {$n > 1} {
                append output /page/$n
            }
            append output /index.html
        } else {
            regexp {(.*?)(?:-[0-9]+)?.html$} $output _ output
            if {$n > 1} {
                append output -$n
            }
            append output .html
        }
        return $output
    }

    proc blog-index {} {
        # Find the blog index by the output rather than the input to account for
        # the possible differences in the file extension and to allow the index
        # to be generated at an earlier stage of the pipeline.
        set blogIndexInput %NULL%
        set blogIndexOutput [templates input-to-output-path blog/index.foo]
        db eval {
            SELECT input.file FROM input
        } row {
            set output [templates input-to-output-path $row(file)]
            if {$output eq $blogIndexOutput} {
                set blogIndexInput $row(file)
                break
            }
        }
        if {$blogIndexInput eq {%NULL%}} {
            set blogIndexOutput %NULL%
        }
        return [list $blogIndexInput $blogIndexOutput]
    }

    proc collection {index setting {filter 1}}  {
        set posts [db eval {
            SELECT input.file FROM input
            JOIN settings ON settings.file = input.file
            WHERE settings.key = :setting AND
                  settings.value = '1' AND
                  input.file <> :index
            ORDER BY input.timestamp DESC;
        }]
        if {!$filter} {
            return $posts
        }

        # Rather than filter for showInCollections in the query, we
        # use [templates file-setting] to read the showInCollections
        # setting. This ensures fallback to the appropriate default
        # values.
        set filtered {}
        foreach post $posts {
            if {[templates file-setting $post showInCollections 1]} {
                lappend filtered $post
            }
        }
        return $filtered
    }

    proc gen args {
        utils::named-args {
            -interp         interp
            -input          input
            -output         baseOutput
            -template       templateProc
            -extraArticles  {extraArticles {}}
            -paginate       {paginate 1}
        }

        set output $baseOutput
        set root [root-path $output]

        if {$paginate} {
            set blogPostsPerFile [db settings get config \
                                                  blogPostsPerFile \
                                                  0xFFFF]
            set grouped [utils::group-by $blogPostsPerFile $extraArticles]
            set topGroup [list $input {*}[lindex $grouped 0]]
            if {$grouped eq {}} {
                set grouped [list $topGroup]
            } else {
                lset grouped 0 $topGroup
            }
        } else {
            set grouped [list [list $input {*}$extraArticles]]
        }
        set groupCount [llength $grouped]
        set templateArgs [dict create \
            -collection [expr {[llength $extraArticles] > 0}] \
            -collectionTop 1 \
        ]

        set pageNumber 1
        foreach group $grouped {
            set nextOutput [add-page-number $baseOutput \
                                            [expr {$pageNumber + 1}]]
            set nextRoot [root-path $nextOutput]

            set prevPage [expr {
                $pageNumber == 1 ? {} : $prevOutput
            }]
            set nextPage [expr {
                $pageNumber == $groupCount ? {} : $nextOutput
            }]

            set templateArgs [dict merge $templateArgs [dict create \
                -articles $group \
                -input $input \
                -nextPage $nextPage \
                -output $output \
                -pageNumber $pageNumber \
                -prevPage $prevPage \
                -root $root \
            ]]
            db output add $output \
                          $input \
                          [interp eval $interp \
                                       [list $templateProc {*}$templateArgs]]
            incr pageNumber

            set prevOutput $output
            set output $nextOutput
            set root $nextRoot
        }
    }

    proc root-path output {
        return [::fileutil::relative [file dirname $output] .]
    }
}
