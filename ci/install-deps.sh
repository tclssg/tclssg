#! /bin/sh
set -e

tcllib_dir=tcllib-tcllib-2-0
tcllib_url=https://github.com/tcltk/tcllib/archive/refs/tags/tcllib-2-0.tar.gz

if [ "$(uname)" = Linux ]; then
    apt-get install -y cmark libsqlite3-tcl make tcl wget

    wget --output-document tcllib.tar.gz --quiet "$tcllib_url"
    tar xzf tcllib.tar.gz

    cd "$tcllib_dir"
    ./configure
    make install
fi

if [ "$(uname)" = FreeBSD ]; then
    pkg install -y cmark tcl-sqlite3 tcl86
    ln -s /usr/local/bin/tclsh8.6 /usr/local/bin/tclsh

    fetch -o tcllib.tar.gz "$tcllib_url"
    tar xzf tcllib.tar.gz

    cd "$tcllib_dir"
    ./configure
    make install
fi

if [ "$(uname)" = NetBSD ]; then
    pkgin -y install cmark tcl

    ftp -o tcllib.tar.gz "$tcllib_url"
    tar xzf tcllib.tar.gz

    cd "$tcllib_dir"
    ./configure
    make install
fi

if [ "$(uname)" = OpenBSD ]; then
    pkg_add -I cmark sqlite3-tcl tcl%8.6
    ln -s /usr/local/bin/tclsh8.6 /usr/local/bin/tclsh

    ftp -o tcllib.tar.gz "$tcllib_url"
    tar xzf tcllib.tar.gz

    cd "$tcllib_dir"
    ./configure
    make install
fi
