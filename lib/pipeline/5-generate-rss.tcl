# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

namespace eval ::tclssg::pipeline::5-generate-rss {
    proc transform {} {
        namespace path {::tclssg ::tclssg::pipeline::5-generate-pages}

        set interp 5-generate-rss
        interpreter create $interp

        lassign [blog-index] blogIndexInput

        if {$blogIndexInput ne {%NULL%}} {
            set lastFeedPost [expr {
                [db settings get config {rss posts} 10] - 1
            }]
            set posts [lrange [collection $blogIndexInput blogPost] \
                              0 \
                              $lastFeedPost]

            gen -interp $interp \
                -template ::rss-feed::render \
                -input $blogIndexInput \
                -output blog/rss.xml \
                -extraArticles [collection $blogIndexInput blogPost] \
                -paginate 0
        }

        interp delete $interp
    }
}
