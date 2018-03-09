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
                set shownPosts [::struct::list filterfor post $posts {
                    [templates file-setting $post showInCollections 1]
                }]
                gen $interp $blogIndexOutput $blogIndexInput $shownPosts
            } else {
                gen $interp $output $row(file)
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

    proc gen {interp baseOutput topInput {extraInputs {}}} {
        set output $baseOutput
        set extraInputsCount [expr {[llength $extraInputs]}]
        set root [root-path $output]

        set vars [vars-for-input $topInput 1]
        interpreter inject $interp $vars
        set topInputContent [interp eval $interp article]
        set documentContent $topInputContent
        set inputsProcessed 0
        set outputsCreated 0
        set blogPostsPerFile [db settings get config blogPostsPerFile 0xFFFF]

        if {$extraInputs eq {}} {
            add-document $topInput
            return
        }

        foreach input $extraInputs {
            set vars [vars-for-input $input 0]
            interpreter inject $interp $vars

            append documentContent [interp eval $interp article]
            incr inputsProcessed

            # Pagination.
            if {$inputsProcessed % $blogPostsPerFile == 0 ||
                $inputsProcessed == $extraInputsCount} {
                set vars [vars-for-input $topInput 1]
                add-document $topInput
            }
        }
    }

    proc root-path output {
        return [::fileutil::relative [file dirname $output] .]
    }

    proc vars-for-input {input top} {
        upvar 1 extraInputsCount extraInputsCount \
                output output \
                root root
        set abbreviate [db settings get config abbreviate 1]
        lassign [db eval {
            SELECT cooked FROM input WHERE input.file = :input
        }] content
        return [dict create abbreviate [expr {!$top && $abbreviate}] \
                            collection [expr {$extraInputsCount > 0}] \
                            collectionTop $top \
                            content $content \
                            input $input \
                            output $output \
                            root $root \
        ]
    }

    proc add-document input {
        # Ugly. To say that this code was "factored out" of [gen] is an
        # overstatement.
        foreach varName {
            baseOutput
            blogPostsPerFile 
            documentContent 
            extraInputsCount 
            inputsProcessed 
            interp 
            nextOutput 
            output 
            outputsCreated 
            prettyURLs
            prevOutput 
            nextOutput 
            nextRoot 
            root
            topInput
            topInputContent
            vars 
        } {
            upvar 1 $varName $varName
        }

        set nextOutput [add-page-number $baseOutput \
                                        [expr {$outputsCreated + 2}]]
        set nextRoot [root-path $nextOutput]

        set prevPage [expr {
            $outputsCreated > 0 ?
            $prevOutput : {}
        }]
        set nextPage [expr {
            $extraInputsCount - $inputsProcessed >= 1 ?
            $nextOutput : {}
        }]

        set vars [dict replace $vars content $documentContent \
                                     collectionTop 1 \
                                     prevPage $prevPage \
                                     nextPage $nextPage \
                                     output $output \
                                     root $root]
        interpreter inject $interp $vars
        db output add $output $input [interp eval $interp document]
        set documentContent $topInputContent
        incr outputsCreated

        set prevOutput $output
        set output $nextOutput
        set root $nextRoot
    }
}
