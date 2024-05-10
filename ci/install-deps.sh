#! /bin/sh
set -e

if [ "$(uname)" = Linux ]; then
    sudo apt-get install -y cmark libsqlite3-tcl tcl tcllib
fi

if [ "$(uname)" = FreeBSD ]; then
    sudo pkg install -y cmark tcl-sqlite3 tcl86 tcllib
    sudo ln -s /usr/local/bin/tclsh8.6 /usr/local/bin/tclsh
fi

if [ "$(uname)" = NetBSD ]; then
    sudo pkgin -y install cmark tcl tcllib
fi

if [ "$(uname)" = OpenBSD ]; then
    # doas(1) isn't configured.
    # See https://github.com/cross-platform-actions/action/issues/75
    sudo pkg_add -I cmark sqlite3-tcl tcl%8.6 tcllib
    sudo ln -s /usr/local/bin/tclsh8.6 /usr/local/bin/tclsh
fi
