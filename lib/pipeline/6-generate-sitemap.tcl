# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Add an XML sitemap output listing the outputs of all Markdown inputs that
# don't have showInCollections 0.
namespace eval ::tclssg::pipeline::6-generate-sitemap {
    namespace path ::tclssg

    proc transform {} {
        if {![db settings get config {sitemap enable} 0]} return
        set outputDir [db settings get config outputDir]
        set sitemapFile [file join $outputDir sitemap.xml]
        log::info "writing sitemap to [list $sitemapFile]"
        utils::write-file $sitemapFile [make-sitemap]
    }

    # Generate a sitemap for the static website. This requires the setting
    # "url" to be set in the website config.
    proc make-sitemap {} {
        set outputDir [db settings get config outputDir]
        set header [utils::trim-indentation {
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset
              xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9
                    http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">
        %s</urlset>
        }]

        set entry [utils::trim-indentation {
            <url>
              <loc>%s</loc>%s
            </url>
        }]

        db transaction {
            set result {}
            set url [db settings get config url]
            if {$url eq {%NULL%}} {
                error {can't generate a sitemap without a base URL set\
                       in the config}
            }
            # Exclude from the sitemap pages that are hidden from collections.
            db eval {
                SELECT output.file,
                       ifnull(mtime.value, ctime.value) as t
                FROM output
                JOIN tags ON output.input = tags.file
                LEFT JOIN settings as ctime ON output.input = ctime.file AND
                                               ctime.key = 'timestamp'
                LEFT JOIN settings as mtime ON output.input = mtime.file AND
                                               mtime.key = 'modifiedTimestamp'
                WHERE tags.tag = 'type:markdown'
                ORDER BY output.file ASC;
            } row {
                if {![templates file-setting $row(file) showInCollections 1]} {
                    continue
                }
                set lastmod {}
                if {$row(t) ne {%NULL%}} {
                    lassign $row(t) sec format
                    set lastmod "\n  <lastmod>[clock format $sec \
                                 -format $format]</lastmod>"
                }
                set path [file join $outputDir $row(file)]
                append result [format $entry $url$path $lastmod]\n
            }
        }
        set result [format $header $result]
        return $result
    }
}
