// mandelbrot_threads.goose
//
// Multi-threaded Mandelbrot generator (ASCII or gnuplot text).
// Goose port of mandelbrot_pthread.c. Goose workers share no memory, so the
// atomic row counter of the C version becomes a queue of row jobs: a fixed
// pool of workers takes one row at a time, computes it and sends it back as a
// flat value. The main thread stores the rows as they arrive and, once all
// are in, formats and writes the output in a single pass.
// Arguments are given as key=value.
//
// Build:
//   goose build mandelbrot_threads.goose
//
// Usage:
//   ./mandelbrot_threads
//   ./mandelbrot_threads width=120 ll_x=-0.75 ll_y=0.1 ur_x=-0.74 ur_y=0.11
//   ./mandelbrot_threads png=1 width=800 height=600 > mandelbrot.dat

import std;
import os;

struct Config {
    width: i64,
    height: i64,
    png: bool,
    ll_x: f64,
    ll_y: f64,
    ur_x: f64,
    ur_y: f64,
    max_iter: i64,
}

let SYMBOLS = "MW2a_. ";
let FLUSH_AT = 65536;
let NUM_THREADS = 10; // Adjust based on CPU core count

struct Job { y: i64 }                        // y < 0: no more work, exit
struct Row { y: i64, cells: i32[] }          // a flat value: crosses the queue as one copy

// Maps an iteration count in [0, max_iter] to an ASCII character.
fn cnt2char(value: i64, max_iter: i64) -> u8 {
    let idx = (value as f64 / max_iter * (SYMBOLS.len - 1)) as i64;
    return SYMBOLS[idx];
}

// Escape time for the point c = cr + ci*i; returns max_iter - iterations used.
fn escape_time(cr: f64, ci: f64, max_iter: i64) -> i64 {
    var zr = 0.0;
    var zi = 0.0;
    var iter = 0;
    while iter < max_iter {
        let zr2 = zr * zr;
        let zi2 = zi * zi;
        if zr2 + zi2 > 4.0 { break; }
        let tmp = zr2 - zi2 + cr;
        zi = 2.0 * zr * zi + ci;
        zr = tmp;
        iter++;
    }
    return max_iter - iter;
}

// Escape times for one row of the image.
fn render_row(cfg: Config&, y: i64) -> i32[>..] {
    let fwidth = cfg.ur_x - cfg.ll_x;
    let fheight = cfg.ur_y - cfg.ll_y;
    let imag = cfg.ur_y - y * fheight / cfg.height;
    var cells: i32[>..] = [];
    for x in cfg.width {
        let real = cfg.ll_x + x * fwidth / cfg.width;
        cells.push(escape_time(real, imag, cfg.max_iter) as i32);
    }
    return cells;
}

// A worker: take a row job, render it, send the row back; stop on y < 0.
thread_fn worker(cfg: Config) {
    loop {
        let job = qget<Job>();
        guard job.y >= 0 else { break; }
        qput(Row { y: job.y, cells: render_row(cfg, job.y) });
    }
}

// Computes all rows on NUM_THREADS workers; pixels[y * width + x] is the escape time.
fn compute_pixels(cfg: Config&) -> i32[>..] {
    var pixels: i32[>..] = [];
    if cfg.width <= 0 || cfg.height <= 0 { return pixels; }
    pixels.resize(cfg.width * cfg.height, 0);

    // Jobs are queued before the workers start, one quit job per worker after them.
    for y in cfg.height { qput(Job { y: y }); }
    for i in NUM_THREADS { qput(Job { y: -1 }); }
    var ids: i64[>..] = [];
    for i in NUM_THREADS { ids.push(thread_spawn(worker, cfg)); }

    // Rows arrive in whatever order the workers finish them.
    for i in cfg.height {
        let row = qget<Row>();
        for x in cfg.width { pixels[row.y * cfg.width + x] = row.cells[x]; }
    }
    for id in ids { thread_wait(id); }
    return pixels;
}

// Renders the computed pixels as ASCII art to stdout.
fn ascii_output(cfg: Config&, pixels: i32[:]) {
    var buf: u8[>..] = [];

    for y in cfg.height {
        for x in cfg.width {
            buf.push(cnt2char(pixels[y * cfg.width + x], cfg.max_iter));
        }
        buf.push('\n');
        if buf.len >= FLUSH_AT {
            write_stdout(buf);
            buf.clear();
        }
    }
    write_stdout(buf);
    flush_stdout();
}

// Writes comma-separated iteration counts for gnuplot (bottom row first).
fn gptext_output(cfg: Config&, pixels: i32[:]) {
    var buf: u8[>..] = [];

    var y = cfg.height - 1;
    while y >= 0 {
        for x in cfg.width {
            if x > 0 { buf.append(", "); }
            format(buf, pixels[y * cfg.width + x]);
        }
        buf.push('\n');
        if buf.len >= FLUSH_AT {
            write_stdout(buf);
            buf.clear();
        }
        y--;
    }
    write_stdout(buf);
    flush_stdout();
}

fn warn(msg: u8[:], what: u8[:]) {
    var line: u8[>..] = [];
    format(line, "Warning: ", msg, " '", what, "'\n");
    write_stderr(line);
}

fn warn_invalid(key: u8[:], value: u8[:]) {
    var line: u8[>..] = [];
    format(line, "Warning: Invalid value '", value, "' for '", key, "'\n");
    write_stderr(line);
}

// Parses an integer value; warns and returns the fallback if unparseable.
fn int_arg(key: u8[:], value: u8[:], fallback: i64) -> i64 {
    let n, ok = parse_int(value);
    if !ok {
        warn_invalid(key, value);
        return fallback;
    }
    return n;
}

// Parses a floating point value; warns and returns the fallback if unparseable.
fn flt_arg(key: u8[:], value: u8[:], fallback: f64) -> f64 {
    let n, ok = parse_flt(value);
    if !ok {
        warn_invalid(key, value);
        return fallback;
    }
    return n;
}

// Parses a single "key=value" command-line argument into cfg.
fn parse_arg(a: u8[:], cfg: Config&) {
    let eq = find(a, "=");
    if eq < 0 {
        warn("Ignoring invalid argument", a);
        return;
    }
    let key = a[..eq];
    let value = a[eq + 1..];

    if key == "width" { cfg.width = int_arg(key, value, cfg.width); }
    else if key == "height" { cfg.height = int_arg(key, value, cfg.height); }
    else if key == "png" { cfg.png = int_arg(key, value, if cfg.png { 1 } else { 0 }) != 0; }
    else if key == "ll_x" { cfg.ll_x = flt_arg(key, value, cfg.ll_x); }
    else if key == "ll_y" { cfg.ll_y = flt_arg(key, value, cfg.ll_y); }
    else if key == "ur_x" { cfg.ur_x = flt_arg(key, value, cfg.ur_x); }
    else if key == "ur_y" { cfg.ur_y = flt_arg(key, value, cfg.ur_y); }
    else if key == "max_iter" { cfg.max_iter = int_arg(key, value, cfg.max_iter); }
    else { warn("Unknown parameter", key); }
}

fn main() {
    var cfg = Config {
        width: 100,
        height: 75,
        png: false,
        ll_x: -1.2,
        ll_y: 0.2,
        ur_x: -1.0,
        ur_y: 0.35,
        max_iter: 255,
    };

    let argv = args();
    for i in 1..argv.len {
        parse_arg(argv[i], cfg);
    }

    let pixels = compute_pixels(cfg);
    if cfg.png { gptext_output(cfg, pixels); } else { ascii_output(cfg, pixels); }
}
