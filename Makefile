all: build

init:
	./ssg.tcl init data/input data/output

build:
	./ssg.tcl build data/input data/output

clean:
	rm -r data/output

upload:
	./ssg.tcl upload-ftp data/input data/output

open:
	xdg-open data/output/index.html
