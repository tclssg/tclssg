# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Provides a cache for data that doesn't vary between files in one
# directory.
namespace eval ::tclssg::templating::cache {
    namespace export *
    namespace ensemble create

    variable cachedFile {}
    variable data {}

    # Check if the cache is fresh for file newFile. Fresh in our case
    # means it is either the same file or a file located in the same
    # directory (because relative link paths for the sidebar and the tag
    # cloud are the same for such files, and that is what the cache is
    # used for).
    proc fresh? {newFile} {
        variable cachedFile
        variable data

        set result [expr {
            [file dirname $cachedFile] eq [file dirname $newFile]
        }]
        return $result
    }

    proc filename {} {
        variable cachedFile
        return $cachedFile
    }

    # Update cache item $key. If the rest of the cache is no longer
    # fresh discard it.
    proc update-key {newFile key varName} {
        variable cachedFile
        variable data

        upvar 1 $varName var

        if {![fresh? $newFile]} {
            set data {}
            set cachedFile $newFile
        }
        dict set data $key $var
    }

    # Use varName as the key in update-key.
    proc update {newFile varName} {
        upvar 1 $varName localVar
        update-key $newFile $varName localVar
    }

    # If fresh for newFile retrieve the cached value under key and put
    # it in variable varName.
    proc retrieve-key! {newFile key varName} {
        upvar 1 $varName var

        variable data

        if {![fresh? $newFile] || ![dict exists $data $key]} {
            return 0
        }
        set var [dict get $data $key]
        return 1
    }

    # Use varName as key for retrieve-key!.
    proc retrieve! {newFile varName} {
        upvar 1 $varName localVar
        retrieve-key! $newFile $varName localVar
    }
 } ;# namespace cache
