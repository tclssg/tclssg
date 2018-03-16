# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Generate HTML output from every input in the DB with the "type:markdown" tag.
namespace eval ::tclssg::pipeline::5-generate-pages {
    namespace path ::tclssg

    proc transform {} {
        set inputDir [db settings get config inputDir]
        set outputDir [db settings get config outputDir]

        set interp 5-generate-pages
        interpreter create $interp

        set blogIndexOutput [templates input-to-output-path blog/index.md]

        db eval {
            SELECT input.file, input.cooked FROM input
            JOIN tags ON tags.file = input.file
            WHERE tags.tag = 'type:markdown'
            ORDER BY input.timestamp DESC;
        } row {
            set output [templates input-to-output-path $row(file)]
            if {$output eq $blogIndexOutput} {
                # Collect (normally abbreviated) content from all blog posts in
                # the timeline.
                set blogIndexInput $row(file)
                set posts [db eval {
                    SELECT input.file FROM input
                    JOIN settings ON settings.file = input.file
                    WHERE settings.key = 'blogPost' AND
                          settings.value = '1' AND
                          input.file <> :blogIndexInput
                    ORDER BY input.timestamp DESC;
                }]
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
                gen $interp $blogIndexOutput $blogIndexInput $filtered
            } else {
                gen $interp $output $row(file) {}
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

    proc gen {interp baseOutput input extraArticles} {
        set output $baseOutput
        set root [root-path $output]

        set blogPostsPerFile [db settings get config blogPostsPerFile 0xFFFF]
        set grouped [utils::group-by $blogPostsPerFile $extraArticles]
        lset grouped 0 [concat $input [lindex $grouped 0]]

        set groupCount [llength $grouped]
        set i 0
        interpreter inject $interp [dict create \
            collection [expr {[llength $extraArticles] > 0}] \
            collectionTop 1 \
        ]
        foreach group $grouped {
            set nextOutput [add-page-number $baseOutput [expr {$i + 2}]]
            set nextRoot [root-path $nextOutput]

            set prevPage [expr {
                $i > 0 ? $prevOutput : {}
            }]
            set nextPage [expr {
                $i == $groupCount - 1 ? {} : $nextOutput
            }]

            interpreter inject $interp [dict create \
                articles $group \
                prevPage $prevPage \
                nextPage $nextPage \
                output $output \
                input $input \
                root $root \
            ]
            db output add $output \
                          $input \
                          [interp eval $interp ::document::render]
            incr i

            set prevOutput $output
            set output $nextOutput
            set root $nextRoot
        }
    }

    proc root-path output {
        return [::fileutil::relative [file dirname $output] .]
    }
}
