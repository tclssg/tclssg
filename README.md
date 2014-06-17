ssg-tcl
=======

A static website generator written in Tcl for danyilbohdan.com.

To use `ssg-tcl` you'll need Tcl 8.5 and Tcllib.

Generates blogs. All blog entries have a sidebar.

Usage
-----

    ./ssg.tcl (init|build|upload-copy|upload-ftp) sourceDir destDir

    make init

    make build (or just make)

    make upload

Website settings
----------------
websiteTitle {Danyil Bohdan}
url {http://danyilbohdan.com/}
uploadDestCopy {/tmp/dest}
uploadDestFTP {ftp://ftp.univ.kiev.ua/incoming/upload/dotcomtest}
expandMacrosInPages 0
charset utf-8

Per-page variables
------------------
pageTitle
hideTitle
blogEntry
hideFromList
date
tags
