# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Website page database. Provides procs to interact with SQLite tables that
# hold the input and intermediate data.

namespace eval ::tclssg::pages {
    namespace export *
    namespace ensemble create

    # Create tables necessary for various procs called by Tclssg's build
    # command.
    #
    # What follows is a very short description of the each table's
    # respective contents in the format of "<table name> -- <contents>":
    #
    # pages -- page data for every page. Page data is the information about
    # the page that is *not* set by the user directly in preamble
    # (settings) section of the page file.
    # links -- relative hyperlink HREFs to link from page $id to page
    # $targetId.
    # settings -- page settings for every page.
    # websiteConfig -- website-wide settings.
    # tags -- blog post tags for every blog post.
    # tagPages -- a list of tag pages for every tag. See add-tag-pages.
    proc init {} {
        sqlite3 tclssg-db :memory:
        # Do not store settings values as columns to allow pages to set
        # custom settings. These settings can then be parsed by templates
        # without changes to the static site generator source itself.
        tclssg-db eval {
            CREATE TABLE pages(
                id INTEGER PRIMARY KEY,
                inputFile TEXT,
                outputFile TEXT,
                rawContent TEXT,
                cookedContent TEXT,
                pageLinks TEXT,
                rootDirPath TEXT,
                articlesToAppend TEXT,
                sortingDate INTEGER
            );
            CREATE TABLE links(
                id INTEGER,
                targetId INTEGER,
                link TEXT,
                PRIMARY KEY (id, targetId)
            );
            CREATE TABLE settings(
                id INTEGER,
                name TEXT,
                value TEXT,
                PRIMARY KEY (id, name)
            );
            CREATE TABLE websiteConfig(
                name TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE TABLE tags(
                id INTEGER,
                tag TEXT
            );
            CREATE TABLE tagPages(
                tag TEXT,
                pageNumber INTEGER,
                id INTEGER,
                PRIMARY KEY (tag, pageNumber)
            );
        }
    }


    # Procs for working with the table "pages".


    proc add {inputFile outputFile rawContent cookedContent sortingDate} {
        if {![string is integer -strict $sortingDate]} {
            set sortingDate 0
        }
        tclssg-db eval {
            INSERT INTO pages(
                inputFile,
                outputFile,
                rawContent,
                cookedContent,
                sortingDate)
            VALUES (
                $inputFile,
                $outputFile,
                $rawContent,
                $cookedContent,
                $sortingDate);
        }
        return [tclssg-db last_insert_rowid]
    }
    # Make a copy of page $id in table pages return the id of the copy.
    proc copy {id copySettings} {
        tclssg-db eval {
            INSERT INTO pages(
                inputFile,
                outputFile,
                rawContent,
                cookedContent,
                rootDirPath,
                articlesToAppend,
                sortingDate)
            SELECT
                inputFile,
                outputFile,
                rawContent,
                cookedContent,
                rootDirPath,
                articlesToAppend,
                sortingDate
            FROM pages WHERE id = $id;
        }
        set newPageId [tclssg-db last_insert_rowid]
        tclssg-db eval {
            INSERT INTO links(
                id,
                targetId,
                link)
            SELECT
                $newPageId,
                targetId,
                link
            FROM links WHERE id = $id;
        }
        if {$copySettings} {
            tclssg-db eval {
                INSERT INTO settings(
                    id,
                    name,
                    value)
                SELECT
                    $newPageId,
                    name,
                    value
                FROM settings WHERE id = $id;
            }
        }
        return $newPageId
    }
    proc delete {id} {
        tclssg-db transaction {
            tclssg-db eval {
                 DELETE FROM pages WHERE id = $id;
            }
            tclssg-db eval {
                DELETE FROM links WHERE id = $id;
            }
            tclssg-db eval {
                DELETE FROM settings WHERE id = $id;
            }
        }
    }
    proc set-data {id field value} {
        # TODO: get rid of format?
        if {![regexp {^[a-zA-Z0-9]+$} $field]} {
            # A very simple failsafe.
            error "wrong field name: $field"
        }
        tclssg-db eval [format {
            UPDATE pages SET %s=$value WHERE id = $id;
        } $field]
    }
    proc get-data {id field {default ""}} {
        tclssg-db eval {
            SELECT * FROM pages WHERE id = $id;
        } arr {}
        if {[info exists arr($field)]} {
            return $arr($field)
        } else {
            return $default
        }
    }
    # Returns the list of ids of all pages sorted by their sortingDate, if
    # any.
    proc sorted-by-date {} {
        set result [tclssg-db eval {
            SELECT id FROM pages ORDER BY sortingDate DESC;
        }]
        return $result
    }
    proc input-file-to-id {filename} {
        set result [tclssg-db eval {
            SELECT id FROM pages WHERE inputFile = $filename LIMIT 1;
        }]
        return $result
    }
    proc output-file-to-id {filename} {
        set result [tclssg-db eval {
            SELECT id FROM pages WHERE outputFile = $filename LIMIT 1;
        }]
        return $result
    }

    # Procs for working with the table "links".


    proc add-link {sourceId targetId link} {
        tclssg-db eval {
            INSERT INTO links(id, targetId, link)
            VALUES ($sourceId, $targetId, $link);
        }
    }
    proc get-link {sourceId targetId} {
        set result [lindex [tclssg-db eval {
            SELECT link FROM links
            WHERE id = $sourceId AND targetId = $targetId;
        }] 0]
        return $result
    }
    proc copy-links {oldId newId} {
        set result [tclssg-db eval {
            INSERT INTO links(id, targetId, link)
            SELECT $newId, targetId, link FROM links
            WHERE id = $oldId;
        }]
        return $result
    }
    proc delete-links-to {targetId} {
        tclssg-db eval {
            DELETE FROM links
            WHERE targetId = $targetId;
        }
    }

    # Procs for working with the table "settings".


    proc set-setting {id name value} {
        tclssg-db eval {
            INSERT OR REPLACE INTO settings(id, name, value)
            VALUES ($id, $name, $value);
        }
    }
    proc get-setting {id name default {pageSettingsFailover 1}} {
        if {$pageSettingsFailover} {
            set default [::tclssg::utils::dict-default-get \
                    $default \
                    [get-website-config-setting pageSettings {}] \
                    $name]
            # Avoid an infinite loop when recursing by disabling failover.
            set isBlogPost [get-setting $id blogPost 0 0]
            if {$isBlogPost} {
                set default [::tclssg::utils::dict-default-get \
                        $default \
                        [get-website-config-setting blogPostSettings {}] \
                        $name]
            }
        }

        set result [lindex [tclssg-db eval {
            SELECT ifnull(max(value), $default) FROM settings
            WHERE id = $id AND name = $name;
        }] 0]
        return $result
    }


    # Procs for working with the table "websiteConfig".


    proc set-website-config-setting {name value} {
        tclssg-db eval {
            INSERT OR REPLACE INTO websiteConfig(name, value)
            VALUES ($name, $value);
        }
    }
    proc get-website-config-setting {name default} {
        set result [lindex [tclssg-db eval {
            SELECT ifnull(max(value), $default) FROM websiteConfig
            WHERE name = $name;
        }] 0]
        return $result
    }


    # Procs for working with the tables "tags" and "tagPages".


    proc add-tags {id tagList} {
        foreach tag $tagList {
            tclssg-db eval {
                INSERT INTO tags(id, tag)
                VALUES ($id, $tag);
            }
        }
    }
    proc get-tags {id} {
        set result [tclssg-db eval {
            SELECT tag FROM tags WHERE id = $id;
        }]
        return $result
    }
    proc get-tag-page {tag pageNumber} {
        set result [tclssg-db eval {
            SELECT id FROM tagPages
            WHERE tag = $tag AND pageNumber = $pageNumber;
        }]
        return $result
    }
    proc add-tag-page {id tag pageNumber} {
        tclssg-db eval {
            INSERT INTO tagPages(tag, pageNumber, id)
            VALUES ($tag, $pageNumber, $id);
        }
    }
    # Return pages with tag $tag.
    proc with-tag {tag} {
        set result [tclssg-db eval {
            SELECT pages.id FROM pages
            JOIN tags ON tags.id = pages.id
            WHERE tag = $tag
            ORDER BY sortingDate DESC;
        }]
        return $result
    }
    # Return a list of all tags sorted by name or frequency.
    proc get-tag-list {{sortBy "name"} {limit -1}} {
        switch -exact -- $sortBy {
            frequency {
                set result [tclssg-db eval {
                    SELECT DISTINCT tag FROM tags
                    GROUP BY tag ORDER BY count(id) DESC
                    LIMIT $limit;
                }]
            }
            name {
                set result [tclssg-db eval {
                    SELECT DISTINCT tag FROM tags ORDER BY tag LIMIT $limit;
                }]
            }
            default {
                error "unknown tag sorting option: $sortBy"
            }
        }
        return $result
    }
} ;# namespace pages
