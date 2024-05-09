# Tclssg, a static website generator.
# Copyright (c) 2013-2019
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::60-generate-tag-pages {
    namespace path {::tclssg ::tclssg::pipeline::50-generate-pages}

    proc transform {} {
        if {![db config get tagPages 1]} return

        set inputDir [db config get inputDir]
        set outputDir [db config get outputDir]

        set interp 60-generate-tag-pages
        interpreter create $interp

        lassign [tag-index] tagIndexInput

        set tags [db::tags::list]

        foreach tag $tags {
            set input [tag-page-input-path $tag][file ext $tagIndexInput]

            db input copy $tagIndexInput $input
            db input set $input type tag-page
            db input set $input timestamp [db config get buildTimestamp]
            db settings set $input tagPageTag $tag

            set pages [db::tags::inputs-with-tag $tag]

            set output [templates input-to-output-path $input]

            gen \
                -interp $interp \
                -template ::document::render \
                -input $input \
                -output $output \
                -extraArticles $pages \
                -logScript {apply {{input output} {
                    ::tclssg::log::info "generating tag page\
                                         [list $output]"
                }}}

        }

        interp delete $interp
    }

    proc tag-page-input-path tag {
        return blog/tags/[utils::slugify $tag]
    }

    proc tag-index {} {
        set tagIndexOutput [templates input-to-output-path blog/tags/tag.foo]
        return [templates output-to-input-path $tagIndexOutput]
    }
}
