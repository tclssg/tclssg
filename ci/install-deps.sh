#! /bin/sh
set -e

if [ "$(uname)" = Linux ]; then
    apt-get install -y cmark libsqlite3-tcl tcl tcllib
fi

if [ "$(uname)" = FreeBSD ]; then
    pkg install -y cmark tcl-sqlite3 tcl86 tcllib
    ln -s /usr/local/bin/tclsh8.6 /usr/local/bin/tclsh
fi

if [ "$(uname)" = NetBSD ]; then
    pkgin -y install cmark tcl tcllib
fi

if [ "$(uname)" = OpenBSD ]; then
    pkg_add -I cmark sqlite3-tcl tcl%8.6 tcllib
    ln -s /usr/local/bin/tclsh8.6 /usr/local/bin/tclsh
fi
