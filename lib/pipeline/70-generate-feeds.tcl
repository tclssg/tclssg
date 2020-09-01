# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::70-generate-feeds {
    proc transform {} {
        namespace path {
            ::tclssg
            ::tclssg::pipeline::50-generate-pages
            ::tclssg::pipeline::60-generate-tag-pages
        }

        if {![db config get {rss enable} false]
            && {rss} ni [db config get {feeds formats} {}]} return

        set interp 70-generate-feeds
        interpreter create $interp

        lassign [templates blog-index] blogIndexInput
        lassign [tag-index] tagIndexInput

        if {$blogIndexInput ne {%NULL%}} {
            set lastFeedPost [expr {
                [rss-setting posts 10] - 1
            }]
            set posts [lrange [db settings inputs-with-true-setting \
                                           blogPost \
                                           $blogIndexInput] \
                              0 \
                              $lastFeedPost]

            gen -interp $interp \
                -template ::rss-feed::render \
                -input $blogIndexInput \
                -output blog/rss.xml \
                -extraArticles $posts \
                -paginate 0 \
                -logScript {apply {{input output} {
                    ::tclssg::log::info "generating blog RSS feed\
                                         [list $output]"
                }}}
        }

        if {[rss-setting tagFeeds false]} {
            foreach tagPage [db::input::list tag-page] {
                set tag [db::settings::raw-mget [list $tagPage] \
                                                tagPageTag]

                set tagPageOutput [db::output::get-by-input $tagPage file]
                set rssOutput [interp eval $interp \
                                           [list ::rss-feed::rss-feed-path \
                                                 $tagPage \
                                                 {}]]
                set pages [db::tags::inputs-with-tag $tag]

                gen -interp $interp \
                    -template ::rss-feed::render \
                    -input $tagIndexInput \
                    -output $rssOutput \
                    -extraArticles $pages \
                    -paginate 0 \
                    -logScript {apply {{input output} {
                        ::tclssg::log::info "generating tag RSS feed\
                                             [list $output]"
                    }}}
            }
        }

        interp delete $interp
    }

    proc rss-setting {key default} {
        return [db config get \
            [list rss $key] \
            [db config get [list feeds $key] \
                           $default]]
    }
}
