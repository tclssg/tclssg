# Tclssg, a static website generator.
# Copyright (c) 2013-2019
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Website page database. Provides procs to interact with SQLite tables that
# hold the input and intermediate data.

namespace eval ::tclssg::db {
    namespace export *
    namespace ensemble create

    proc init {} {
        sqlite3 tclssg-db :memory:

        tclssg-db collate SLUG ::tclssg::utils::slug-compare
        tclssg-db nullvalue %NULL%

        # Do not store page settings as columns to allow pages to set
        # custom settings. These settings can then be parsed by templates
        # without changes to the static site generator source itself.
        tclssg-db eval {
            PRAGMA foreign_keys = ON;
            CREATE TABLE input(
                file TEXT PRIMARY KEY,
                type TEXT,
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
            CREATE TABLE config(
                key TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE TABLE settings(
                file TEXT,
                key TEXT,
                value TEXT,
                PRIMARY KEY (file, key),
                FOREIGN KEY(file) REFERENCES input(file)
            );
            CREATE TABLE tags(
                file TEXT,
                tag TEXT COLLATE SLUG,
                PRIMARY KEY (file, tag),
                FOREIGN KEY(file) REFERENCES input(file)
            );
        }

        foreach {name script} {
            dict_path_exists  ::tclssg::db::dict-path-exists
            dict_path_get     ::tclssg::db::dict-path-get
            lindex            ::lindex
            llength           ::llength
            lrange            ::lrange
            regexp            ::regexp
        } {
            # Compatibility.
            try {
                tclssg-db function $name -deterministic $script
            } on error {} {
                tclssg-db function $name $script
            }
        }
    }

    proc eval args {
        uplevel 1 [list tclssg-db eval {*}$args]
    }

    proc transaction script {
        uplevel 1 [list tclssg-db transaction $script]
    }

    proc valid-field-name field {
        return [regexp {^[a-zA-Z0-9]+$} $field]
    }

    # Helper procs to use as functions in SQLite.
    proc dict-path-exists {dict path} {
        return [dict exists $dict {*}$path]
    }

    proc dict-path-get {dict path} {
        return [dict get $dict {*}$path]
    }
}

namespace eval ::tclssg::db::input {
    namespace export *
    namespace ensemble create

    proc add args {
        tclssg::utils::named-args {
            -file       file
            -type       type
            -raw        {raw {}}
            -cooked     {cooked {}}
            -timestamp  timestamp
        }
        if {![string is integer -strict $timestamp]} {
            ::set timestamp 0
        }
        tclssg-db eval {
            INSERT INTO input(file, type, raw, cooked, timestamp)
            VALUES (:file, :type, :raw, :cooked, :timestamp);
        }
        return $file
    }

    proc copy {file1 file2} {
        tclssg-db eval {
            INSERT INTO input(file, type, raw, cooked, timestamp)
            SELECT :file2, type, raw, cooked, timestamp FROM input
            WHERE file = :file1;

            INSERT INTO settings(file, key, value)
            SELECT :file2, key, value FROM settings
            WHERE file = :file1;

            INSERT INTO tags(file, tag)
            SELECT :file2, tag FROM tags
            WHERE file = :file1;
        }

        return $file2
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
        if {![::tclssg::db::valid-field-name $field]} {
            # A very simple failsafe.
            error "bad field name: \"$field\""
        }
        tclssg-db eval [format {
            UPDATE input SET %s = :value WHERE file = :file;
        } $field]
    }

    proc get {file field} {
        if {![::tclssg::db::valid-field-name $field]} {
            error "bad field name: \"$field\""
        }
        lassign [tclssg-db eval [format {
            SELECT %s FROM input WHERE file = :file;
        } $field]] result
        return $result
    }

    proc list type {
        tclssg-db eval {
            SELECT file FROM input
            WHERE type = :type;
        }
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
        }
    }

    proc set {file field value} {
        if {![::tclssg::db::valid-field-name $field]} {
            error "bad field name: \"$field\""
        }
        tclssg-db eval [format {
            UPDATE output SET %s = :value WHERE file = :file;
        } $field]
    }

    proc get {file field} {
        if {![::tclssg::db::valid-field-name $field]} {
            error "bad field name: \"$field\""
        }

        tclssg-db eval [format {
            SELECT %s FROM output WHERE file = :file;
        } $field]
    }

    proc get-by-input {input field} {
        if {![::tclssg::db::valid-field-name $field]} {
            error "bad field name: \"$field\""
        }

        tclssg-db eval [format {
            SELECT %s FROM output WHERE input = :input;
        } $field]
    }
}

namespace eval ::tclssg::db::config {
    namespace export *
    namespace ensemble create

    proc set {key value} {
        tclssg-db eval {
            INSERT OR REPLACE INTO config
            VALUES (:key, :value);
        }
    }

    proc get {key {default %NULL%}} {
        lassign [tclssg-db eval {
            SELECT ifnull(max(value), :default) FROM config
            WHERE key = :key;
        }] result
        return $result
    }
}

namespace eval ::tclssg::db::settings {
    namespace export *
    namespace ensemble create

    # We store values verbatim instead of flattening dictionaries into
    # multiple rows of (path, value) pairs. We can't transform nested keys
    # into paths because we cannot differentiate between a dictionary and a
    # string that wasn't intended as one.
    proc set {file key value} {
        if {[llength $key] > 1} {
            error "expected a key of list length one, but got [list $key]"
        }
        tclssg-db transaction {
            tclssg-db eval {
                INSERT OR REPLACE INTO settings(file, key, value)
                VALUES (:file, :key, :value);
            }
        }
    }

    proc raw-mget {files key {default %NULL%}} {
        ::set i 0
        ::set vars {}
        foreach file $files {
            ::set fileArr($i) $file
            lappend vars :fileArr($i)
            incr i
        }
        ::set fileValues [join $vars {, }]
        ::set ordering "file = [join $vars { DESC, file = }] DESC"

        tclssg-db eval [format {
            SELECT ifnull(
                (SELECT
                    CASE
                        WHEN llength(:key) = 1 THEN value
                        ELSE dict_path_get(value, lrange(:key, 1, 'end'))
                    END
                 FROM settings
                 WHERE file IN (%1$s) AND
                       key = lindex(:key, 0) AND
                       value IS NOT NULL AND
                       (llength(:key) = 1 OR
                        dict_path_exists(value, lrange(:key, 1, 'end')))
                 ORDER BY %2$s
                 LIMIT 1),
                :default
            ) AS result
        } $fileValues $ordering] row {
            return $row(result)
        }
    }

    proc preset-get {file key {default %NULL%}} {
        tclssg-db transaction {
            ::set files [list $file]
            foreach preset [raw-mget [list $file] presets {}] {
                lappend files presets/$preset
            }
            lappend files presets/default

            ::set value [raw-mget $files $key $default]
            return $value
        }
    }

    proc inputs-with-true-setting {setting {dropList {}} {filter 1}}  {
        ::set posts {}
        tclssg-db eval {
            SELECT input.file FROM input
            WHERE input.type = 'page'
            ORDER BY input.timestamp DESC;
        } row {
            if {[preset-get $row(file) $setting 0]} {
                lappend posts $row(file)
            }
        }

        ::set filtered {}
        foreach post $posts {
            if {$post ni $dropList &&
                (!$filter || [preset-get $post {visibleIn collections} 1])} {
                lappend filtered $post
            }
        }
        return $filtered
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
            SELECT tag FROM tags
            WHERE file = :file;
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
