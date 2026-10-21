SHELL := /bin/bash

# Path to the goose compiler, e.g.  make GOOSE=~/goose/build/goose
GOOSE ?= ~/dev/3rd/goose/build/goose

.PHONY: all bench-small bench-large clean

all: mandelbrot

mandelbrot: mandelbrot.goose
	$(GOOSE) build mandelbrot.goose

bench-small: mandelbrot
	time ./mandelbrot png=1 width=1000 height=750 > image.dat

bench-large: mandelbrot
	time ./mandelbrot png=1 width=5000 height=5000 > image.dat

clean:
	rm -f mandelbrot image.dat
