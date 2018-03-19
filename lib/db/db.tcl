# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Website page database. Provides procs to interact with SQLite tables that
# hold the input and intermediate data.

namespace eval ::tclssg::db {
    namespace export *
    namespace ensemble create

    proc init {} {
        sqlite3 tclssg-db :memory:
        # Do not store page settings as columns to allow pages to set
        # custom settings. These settings can then be parsed by templates
        # without changes to the static site generator source itself.
        tclssg-db eval {
            PRAGMA foreign_keys = ON;
            CREATE TABLE input(
                file TEXT PRIMARY KEY,
                raw BLOB,
                cooked BLOB,
                timestamp INTEGER
            );
            CREATE TABLE output(
                file TEXT PRIMARY KEY,
                input TEXT,
                content TEXT,
                FOREIGN KEY(input) REFERENCES input(file)
            );
            CREATE TABLE settings(
                file TEXT,
                key TEXT,
                value TEXT,
                PRIMARY KEY (file, key)
            );
            CREATE TABLE tags(
                file TEXT,
                tag TEXT,
                PRIMARY KEY (file, tag),
                FOREIGN KEY(file) REFERENCES input(file)
            );
        }
        # Compatibility.
        if {[catch {
            tclssg-db function lindex -deterministic ::lindex
        }]} {
            tclssg-db function lindex ::lindex
        }
        tclssg-db nullvalue %NULL%
    }

    proc eval args {
        uplevel 1 [list tclssg-db eval {*}$args]
    }

    proc transaction script {
        uplevel 1 [list tclssg-db transaction $script]
    }
}

namespace eval ::tclssg::db::input {
    namespace export *
    namespace ensemble create

    proc add {file raw cooked timestamp} {
        if {![string is integer -strict $timestamp]} {
            ::set timestamp 0
        }
        tclssg-db eval {
            INSERT INTO input(file, raw, cooked, timestamp)
            VALUES (:file, :raw, :cooked, :timestamp);
        }
        return $file
    }

    proc delete file {
        tclssg-db eval {
            DELETE FROM input WHERE file = $file;
            DELETE FROM settings WHERE file = $file;
            DELETE FROM tags WHERE file = $file;
        }
    }

    proc set {file field value} {
        # TODO: get rid of format?
        if {![regexp {^[a-zA-Z0-9]+$} $field]} {
            # A very simple failsafe.
            error "wrong field name: \"$field\""
        }
        tclssg-db eval [format {
            UPDATE input SET %s = :value WHERE file = :file;
        } $field]
    }

    proc get {file field} {
        if {![regexp {^[a-zA-Z0-9]+$} $field]} {
            error "wrong field name: \"$field\""
        }
        lassign [tclssg-db eval [format {
            SELECT %s FROM input WHERE file = :file;
        } $field]] result
        return $result
    }
}

namespace eval ::tclssg::db::output {
    namespace export *
    namespace ensemble create

    proc add {file input content} {
        tclssg-db eval {
            INSERT INTO output(file, input, content)
            VALUES (:file, :input, :content);
        }
        return $file
    }

    proc delete file {
        tclssg-db eval {
            DELETE FROM output WHERE file = $file;
            DELETE FROM settings WHERE file = $file;
        }
    }

    proc set {file field value} {
        if {![regexp {^[a-zA-Z0-9]+$} $field]} {
            error "wrong field name: \"$field\""
        }
        tclssg-db eval [format {
            UPDATE output SET %s = :value WHERE file = :file;
        } $field]
    }

    proc get {file field} {
        tclssg-db eval {
            SELECT :field FROM output WHERE file = :file;
        }
    }
}

namespace eval ::tclssg::db::settings {
    namespace export *
    namespace ensemble create

    proc split-key key {
        return [list [lindex $key 0] [lrange $key 1 end]]
    }

    # We store values verbatim instead of flattening dictionaries into
    # multiple rows of (path, value) pairs. We can't transform nested keys
    # into paths because we cannot differentiate between a dictionary and a
    # string that wasn't intended as one.
    proc set {file key value} {
        tclssg-db transaction {
            lassign [split-key $key] tableKey dictKey
            ::set wrapped $value
            if {$dictKey ne {}} {
                ::set wrapped [get $file $tableKey {}]
                dict set wrapped {*}$dictKey $value
            }
            tclssg-db eval {
                INSERT OR REPLACE INTO settings(file, key, value)
                VALUES (:file, :tableKey, :wrapped);
            }            
        }
    }

    proc get {file key {default %NULL%}} {
        lassign [split-key $key] tableKey dictKey
        lassign [tclssg-db eval {
            SELECT ifnull(max(value), NULL) FROM settings
            WHERE file = :file AND key = :tableKey;
        }] result
        if {$result eq {%NULL%}} {
            ::set result $default
        } elseif {$dictKey ne {}} {
            ::set result [::tclssg::utils::dict-default-get $default \
                                                            $result \
                                                            {*}$dictKey]
        }
        return $result
    }
}

namespace eval ::tclssg::db::tags {
    namespace export *
    namespace ensemble create

    proc add {file tags} {
        tclssg-db transaction {
            foreach tag $tags {
                tclssg-db eval {
                    INSERT OR REPLACE INTO tags(file, tag)
                    VALUES (:file, :tag);
                }
            }
        }
    }

    proc get file {
        tclssg-db eval {
            SELECT tag FROM tags WHERE file = :file;
        }
    }

    proc list {{sortBy {name}} {limit -1}} {
        switch -exact -- $sortBy {
            frequency {
                set result [tclssg-db eval {
                    SELECT DISTINCT tag FROM tags
                    GROUP BY tag ORDER BY count(file) DESC
                    LIMIT :limit;
                }]
            }
            name {
                set result [tclssg-db eval {
                    SELECT DISTINCT tag FROM tags
                    ORDER BY tag
                    LIMIT :limit;
                }]
            }
            default {
                error "unknown tag sorting option: $sortBy"
            }
        }
        return $result
    }

    proc inputs-with-tag tag {
        tclssg-db eval {
            SELECT input.file FROM input
            JOIN tags ON input.file = tags.file
            WHERE tag = :tag
            ORDER BY timestamp DESC;
        }
    }
}

package provide tclssg::db 0
