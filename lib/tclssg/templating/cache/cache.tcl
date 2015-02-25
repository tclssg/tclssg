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
    proc fresh? {filename} {
        variable cachedFile
        variable data

        ::set result [expr {
            [file dirname $cachedFile] eq [file dirname $filename]
        }]
        return $result
    }

    proc filename {} {
        variable cachedFile
        return $cachedFile
    }

    # Update cache item $key. If the rest of the cache is no longer
    # fresh discard it.
    proc set {filename key value} {
        variable cachedFile
        variable data

        if {![fresh? $filename]} {
            ::set data {}
            ::set cachedFile $filename
        }
        dict set data $key $value
    }

    proc get {filename key} {
        variable cachedFile
        variable data

        if {[fresh? $filename]} {
            return [dict get $data $key]
        } else {
            error "trying to retrieve stale cache"
        }
    }

    proc exists {filename key} {
        variable data

        return [expr {
            [fresh? $filename] && [dict exists $data $key]
        }]
    }
 } ;# namespace cache
