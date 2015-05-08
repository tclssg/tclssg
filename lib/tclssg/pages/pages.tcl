# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Website page database. Provides procs to interact with SQLite tables that
# hold the input and intermediate data.

namespace eval ::tclssg::pages {
    namespace export *
    namespace ensemble create

    variable outputFileCallback
    variable rssFileCallback

    # Create tables necessary for various procs called by Tclssg's build
    # command.
    #
    # What follows is a very short description of the each table's
    # respective contents in the format of "<table name> -- <contents>":
    #
    # pages -- page data for every page. Page data is the information about
    # the page that is *not* set by the user directly in preamble
    # (settings) section of the page file.
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
                rootDirPath TEXT,
                articlesToAppend TEXT,
                sortingDate INTEGER
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
    # Make a copy of page $id in table pages and return the id of the copy.
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
                DELETE FROM settings WHERE id = $id;
            }
            tclssg-db eval {
                DELETE FROM tags WHERE id = $id;
            }
            tclssg-db eval {
                DELETE FROM tagPages WHERE id = $id;
            }
            # Remove $id from articleToAppend. This part of page deletion could
            # be simplified through normalization of the DB but storing a list
            # is more convenient everywhere. Note that the query below will
            # overselect. E.g., it will select a page with articlesToAppend
            # containing the value "180" for $id "18". This is, however,
            # harmless because such a page's articlesToAppend value will be left
            # unchanged by the lsearch command below.
            set idPattern "%$id%"
            set collections [tclssg-db eval {
                SELECT id, articlesToAppend FROM pages
                WHERE articlesToAppend LIKE $idPattern
            }]
            foreach {topPageId articlesToAppend} $collections {
                set articlesToAppendUpdated \
                        [lsearch -all -inline -not -exact \
                                $articlesToAppend $id]
                tclssg-db eval {
                    UPDATE pages SET articlesToAppend=$articlesToAppendUpdated
                    WHERE id = $topPageId;
                }
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
    proc get-output-file {id} {
        tclssg-db eval {
            SELECT
                outputFile as outputFileStored,
                inputFile
            FROM pages WHERE id = $id;
        } arr {}
        if {$arr(outputFileStored) eq ""} {
            if {$arr(inputFile) eq ""} {
                set result ""
            } else {
                variable outputFileCallback
                set result [$outputFileCallback $arr(inputFile)]
                # Cache outputFile value.
                set-data $id outputFile $result
            }
        } else {
            # Retrieve stored value for outputFile.
            set result $arr(outputFileStored)
        }
        return $result
    }
    # Returns a relative links from page $sourceId to page $targetId.
    proc get-link {sourceId targetId} {
        set sourceFile [get-output-file $sourceId]
        set targetFile [get-output-file $targetId]
        set result [::fileutil::relative [file dirname $sourceFile] $targetFile]
        return $result
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

    # Procs for working with the table "settings".

    # Set website page setting $name for page $id to $value. See get-setting
    # for the semantics of $name when it is a list.
    proc set-setting {id name value} {
        set nameInTable [lindex $name 0]
        set dictKey [lrange $name 1 end]

        if {[llength $dictKey] > 0} {
            set dictionary [get-setting $nameInTable ""]
            dict set dictionary {*}$dictKey $value
            set-setting $nameInTable $dictionary
        } else {
            tclssg-db eval {
                INSERT OR REPLACE INTO settings(id, name, value)
                VALUES ($id, $name, $value);
            }
        }

        tclssg-db eval {
            INSERT OR REPLACE INTO settings(id, name, value)
            VALUES ($id, $name, $value);
        }
    }

    # Get page setting $name for page $id. If $name is a list the
    # first item is is used as the name of the value to retrieve from the
    # table settings. The rest of is then treated as a list of keys in
    # the dict that the value represents.
    proc get-setting {id name default {pageSettingsFailover 1}} {

        if {$pageSettingsFailover} {
            set default [get-website-config-setting \
                    [concat pageSettings $name] $default]
            set isBlogPost [tclssg-db eval {
                SELECT ifnull(max(value), 0) FROM settings
                WHERE id = $id AND name = "blogPost";
            }]
            if {$isBlogPost} {
                set default [get-website-config-setting \
                        [concat blogPostSettings $name] $default]
            }
        }

        set nameInTable [lindex $name 0]
        set dictKey [lrange $name 1 end]

        set exists [lindex [tclssg-db eval {
            SELECT exists(
                SELECT 1 FROM settings
                WHERE id = $id AND name = $nameInTable
            );
        }] 0]

        if {$exists} {
            set databaseResult [lindex [tclssg-db eval {
                SELECT value FROM settings
                WHERE id = $id AND name = $nameInTable;
            }] 0]
            if {[llength $dictKey] > 0} {
                if {[dict exists $databaseResult {*}$dictKey]} {
                    set result [dict get $databaseResult {*}$dictKey]
                } else {
                    set result $default
                }
            } else {
                set result $databaseResult
            }
        } else {
            set result $default
        }

        return $result
    }


    # Procs for working with the table "websiteConfig".

    # Set website config setting $name to $value. Like with set-setting $name
    # can be a list.
    proc set-website-config-setting {name value} {
        set nameInTable [lindex $name 0]
        set dictKey [lrange $name 1 end]

        if {[llength $dictKey] > 0} {
            set dictionary [get-website-config-setting $nameInTable ""]
            dict set dictionary {*}$dictKey $value
            set-website-config-setting $nameInTable $dictionary
        } else {
            tclssg-db eval {
                INSERT OR REPLACE INTO websiteConfig(name, value)
                VALUES ($name, $value);
            }
        }

    }
    # Get website config setting $name. Like with get-setting $name can be a
    # list.
    proc get-website-config-setting {name default} {
        set nameInTable [lindex $name 0]
        set dictKey [lrange $name 1 end]

        set exists [lindex [tclssg-db eval {
            SELECT exists(
                SELECT 1 FROM websiteConfig
                WHERE name = $nameInTable
            );
        }] 0]

        if {$exists} {
            set databaseResult [lindex [tclssg-db eval {
                SELECT value FROM websiteConfig
                WHERE name = $nameInTable;
            }] 0]
            if {[llength $dictKey] > 0} {
                if {[dict exists $databaseResult {*}$dictKey]} {
                    set result [dict get $databaseResult {*}$dictKey]
                } else {
                    set result $default
                }
            } else {
                set result $databaseResult
            }
        } else {
            set result $default
        }

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
    proc get-tag-pages {pageNumber} {
        set result [tclssg-db eval {
            SELECT id FROM tagPages
            WHERE pageNumber = $pageNumber;
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
