---
title: Porting BRouter to Dart, and proving it routes the same
description: How Velorki runs the BRouter bike router on the phone and in the browser, and the 224 recorded routes that check every result against the original.
date: 2026-11-14
author: steffen
category: engineering
image: cover.png
imageAlt: 'Diagram: BRouter 1.7.10 in Java and the Dart port both route the same 224 recorded requests, compared at three levels: tile decoding byte-identical, profile evaluation bit-identical, and routes as GeoJSON byte for byte.'
---

Velorki computes bike routes on the phone, without a server. The router is my port of [BRouter](https://github.com/abrensch/brouter) from Java to Dart. BRouter is the open-source router behind many OpenStreetMap bike apps. In this post I describe how I did the port and how I check that it gives the same answers as the original.

## Why port it at all

A route planner that needs a signal is not much use in the mountains, or abroad without roaming. So the routing had to run on the device. BRouter was my first choice for the engine. Its profiles for trekking, road, gravel and mountain bikes have years of tuning behind them, and one of its `.rd5` tiles holds everything the router needs for a 5 × 5 degree area in a few dozen megabytes.

BRouter is written in Java. That runs on Android but not on iOS, and Velorki is a Flutter app that needs the same router on both, and later in the browser as well. I saw three ways to get there.

I could have run BRouter on a server. That needs a connection, costs money for every request, and every route a rider plans would pass through my server, which I wanted to avoid. Writing my own router would have taken years to get anywhere near BRouter's profiles. Porting BRouter to Dart gave me one code base for iOS, Android and the web, and the profiles keep working unchanged. I went with the port.

## A transliteration, on purpose

The port is mechanical by design. Each Java class has its own Dart file with the same name, the methods come in the same order, and even upstream's typos are still there. I don't change anything inside a ported file. Whatever is specific to Velorki lives in wrappers around them.

I do this because it keeps the port maintainable. When BRouter releases a new version, its Java diff maps onto the Dart files one to one. I look up the changed class in the mapping table and make the same change in the same method. Once a ported file starts to drift from the original, that stops working.

The port is about 23,700 lines of Dart in 106 files and covers BRouter's `util`, `codec`, `mapaccess`, `expressions` and `core` modules.

## Making Dart behave like the JVM

The algorithms were straightforward to port. Most of the work went into the many small ways Java and Dart treat numbers differently. In a router those differences decide which of two nearly equal paths wins.

Integers were the first. Dart's `int` has 64 bits, while Java's `int` overflows at 32, and BRouter's hashing, CRCs and bit coders depend on that overflow. The port wraps values explicitly wherever they can overflow or get shifted, and masks shift distances the way the JVM does.

Floats came next. BRouter does its cost arithmetic in 32-bit `float`, a type Dart doesn't have. Every float operation in the port rounds through a `Float32List`, which happens 57 times per way section in the hottest function.

Then the smaller cases. Dart's `%` never returns a negative number, while Java's takes the sign of the dividend. Java's `(int)` cast of a double saturates and turns NaN into 0. `Math.round(0.49999999999999994)` is 0 in Java. Each of these got its own helper.

One part of the search walks a `java.util.HashMap`, and how many nodes it creates depends on the order of that walk. So the port has a small hash map with Java's bucket order and resize behaviour.

Sine and cosine took the longest. On HotSpot, `Math.sin` and `Math.cos` are compiled to Intel's math library, which doesn't agree bit for bit with Java's own reference implementation or with the C library the Dart VM uses. In BRouter's table of 1,800 precomputed distance factors, 60 came out different. I transcribed the main path of the JVM's version and checked it against 2,000,000 values sampled from the JVM, all bit-identical. `Math.exp` got the same treatment.

## The oracle

For a router, matching most of the time isn't enough, because a difference of one bit in a cost can flip a route. The repository therefore has an oracle. It runs the real BRouter 1.7.10 against two committed tiles, Madeira and the area around Reykjavík, and records every result.

The port is held to it at three levels:

| Level | What has to match |
|---|---|
| L1 | Byte-identical encoding and decoding of the tile format, including two real micro-caches from the tiles |
| L2 | Bit-identical evaluation of the routing profiles over a corpus of real way tags |
| L3 | 224 routing requests (point to point, via points, avoided areas, round trips, voice hints) across six profiles, with the produced GeoJSON compared byte for byte |

The first complete run of the routing core matched all 200 cases the corpus had at the time, down to each coordinate, message row and travel time.

Recording the corpus also turned up a few oddities in BRouter itself. Some encoder calls, for example, never finish for `Integer.MAX_VALUE`. Those values don't occur in real tile data, and the port reproduces the behaviour anyway, because parity comes first.

## How fast is it

On my laptop the port runs at about half the speed of a warmed-up JVM. A 67 km trekking route across Madeira takes 0.74 seconds when compiled ahead of time, which is how the release app runs. A later performance pass made long routes 10 to 20 % faster, and I only kept a change if every corpus case stayed identical. Memory peaks at about 76 MB for the whole run, including the worker isolate the app routes in.

![Bar chart of routing times on a laptop: a 3.6 km route takes 72 ms in the Dart port and 33 ms on the JVM, a 5.9 km route with an avoided area 74 ms and 37 ms, a 9.9 km round trip 410 ms and 204 ms.](speed.png)

## The same engine in the browser

The web planner at [app.velorki.com](https://app.velorki.com) runs the same router, compiled to WebAssembly. This works because Dart's `int` has 64 bits in WebAssembly, as it does on the phone. When I compiled it to plain JavaScript, where integers are doubles, it produced wrong routes, so the web build is WebAssembly only.

## Keeping up with upstream

Once a week a job checks for a new BRouter release, replays the corpus against it and opens an issue with any differences. It never moves the pinned version on its own. To move it, I port the release as a patch, record the corpus again and get every case passing.

## Thanks

All of the routing knowledge in Velorki comes from BRouter, by Arndt Brenschede and its contributors. The port is in [`app/packages/brouter_dart`](https://github.com/orkitec/velorki/tree/main/app/packages/brouter_dart), with a README that maps every Java class to its Dart file. The oracle is in [`tools/brouter-oracle`](https://github.com/orkitec/velorki/tree/main/tools/brouter-oracle).
