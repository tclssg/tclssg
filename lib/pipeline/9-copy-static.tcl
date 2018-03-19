# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::9-copy-static {
    namespace path ::tclssg

    proc transform {} {
        set inputDir [db settings get config inputDir]
        set outputDir [db settings get config outputDir]

        ::tclssg::utils::copy-files [file join $inputDir static] \
                                    $outputDir \
                                    always

    }
}
