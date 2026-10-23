SHELL := /bin/bash

# Path to the goose compiler, e.g.  make GOOSE=~/goose/build/goose
GOOSE ?= goose

.PHONY: all bench-small bench-large bench-threads-small bench-threads-large clean

all: mandelbrot mandelbrot_threads

mandelbrot: mandelbrot.goose
	$(GOOSE) build mandelbrot.goose

mandelbrot_threads: mandelbrot_threads.goose
	$(GOOSE) build mandelbrot_threads.goose

bench-small: mandelbrot
	time ./mandelbrot png=1 width=1000 height=750 > image.dat

bench-large: mandelbrot
	time ./mandelbrot png=1 width=5000 height=5000 > image.dat

bench-threads-small: mandelbrot_threads
	time ./mandelbrot_threads png=1 width=1000 height=750 > image.dat

bench-threads-large: mandelbrot_threads
	time ./mandelbrot_threads png=1 width=5000 height=5000 > image.dat

clean:
	rm -f mandelbrot mandelbrot_threads image.dat
