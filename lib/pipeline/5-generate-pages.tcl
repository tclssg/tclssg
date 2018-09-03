# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Generate HTML output from every input in the DB with the "type:page" tag.
namespace eval ::tclssg::pipeline::5-generate-pages {
    namespace path ::tclssg

    proc transform {} {
        set inputDir [db config get inputDir]
        set outputDir [db config get outputDir]

        set interp 5-generate-pages
        interpreter create $interp

        lassign [blog-index] blogIndexInput blogIndexOutput

        db eval {
            SELECT input.file FROM input
            JOIN tags ON tags.file = input.file
            WHERE tags.tag = 'type:page'
            ORDER BY input.timestamp DESC;
        } row {
            if {$row(file) eq $blogIndexInput} {
                gen -interp $interp \
                    -template ::document::render \
                    -input $blogIndexInput \
                    -output $blogIndexOutput \
                    -extraArticles [collection $blogIndexInput blogPost] \
                    -logScript {apply {{input output} {
                        ::tclssg::log::info "generating blog index page\
                                             [list $output]"
                    }}}
            } else {
                gen -interp $interp \
                    -template ::document::render \
                    -input $row(file) \
                    -output [templates input-to-output-path $row(file)] \
                    -logScript {apply {{input output} {
                    ::tclssg::log::info "generating [list $output]\
                                         from [list $input]"
                }}}
            }
        }

        interp delete $interp
    }

    proc add-page-number {output n} {
        if {[db config get prettyURLs 0]} {
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
        set posts {}
        db eval {
            SELECT input.file FROM input
            JOIN tags ON tags.file = input.file
            WHERE tags.tag = 'type:page' AND
                  input.file <> :index
            ORDER BY input.timestamp DESC;
        } row {
            if {[db settings preset-get $row(file) $setting 0]} {
                lappend posts $row(file)
            }
        }
        if {!$filter} {
            return $posts
        }

        # Rather than filter for showInCollections in the query, we
        # use [db settings preset-get] to read the showInCollections
        # setting. This ensures fallback to the appropriate default
        # values.
        set filtered {}
        foreach post $posts {
            if {[db settings preset-get $post showInCollections 1]} {
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
            -logScript      {logScript {}}
        }

        set output $baseOutput
        set root [root-path $output]

        if {$paginate && [llength $extraArticles] > 0} {
            set blogPostsPerFile [db config get blogPostsPerFile 0xFFFF]
            if {!([string is integer -strict $blogPostsPerFile] &&
                  $blogPostsPerFile >= 1)} {
                error "blogPostsPerFile must be an integer >= 1;\
                       got \"$blogPostsPerFile\""
            }
            set groupedExtras [utils::group-by $blogPostsPerFile $extraArticles]
            set grouped {}
            foreach extrasGroup $groupedExtras {
                lappend grouped [list $input {*}$extrasGroup]
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

            if {$logScript ne {}} {
                {*}$logScript $input $output
            }
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
