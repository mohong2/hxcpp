# hxcpp — SeiunEngine 4.3 fork

[![CI](https://github.com/mohong2/hxcpp/actions/workflows/main.yml/badge.svg?branch=seiunengine-4.3.175)](https://github.com/mohong2/hxcpp/actions/workflows/main.yml)
[![Haxe](https://img.shields.io/badge/Haxe-4.3.7-ff6f00)](https://haxe.org)
[![License](https://img.shields.io/badge/license-BSD-blue)](LICENSE.txt)

> **中文简介**
>
> 这是 SeiunEngine / FNF-PsychEngine 使用的 hxcpp 4.3 分支。它不追 6.0 的 API/ABI，而是把上游、openfl/libhxcpp、FNF 社区和 SeiunEngine 生产环境里验证过的修复挑出来，稳定地放回 4.3.175。
>
> 主要特点：
>
> - 补全 GC 根、寄存器捕获、`cpp.Pointer` 字段、内部指针、GC-free zone 和未注册线程的安全点
> - 修复 FreeLarge、数组排序、finalizer map、VirtualArray、zlib 等可复现的内存破坏和挂死
> - ObjectMap 地址哈希、StringMap 紧凑条目、churn 堆目标，改善对象/字符串密集场景
> - zlib-ng 2.3.90、per-call zip 计数器、中英双语构建进度
> - 构建工具：链接参数变化重链、per-file C/C++ 标准与 PCH、260 字符路径
> - 已用 SeiunEngine/FNF 全量构建和启动冒烟验证，不是只跑微基准

`hxcpp` is the C++ runtime for the Haxe compiler. This repository is the hxcpp used by **SeiunEngine / FNF-PsychEngine**. It stays on the Haxe 4.3 ABI/API line and collects the fixes that matter from several worlds, instead of forcing a 6.0 migration.

## Why this fork? / 集百家之长

hxcpp 6.0 is a large API/ABI jump. A game on 4.3 cannot take it without porting, and a wholesale merge would bring in moving-GC and API-500 work that most 4.3 projects do not use.

This fork takes the opposite approach: **stay on 4.3.175 and selectively backport the fixes that have proved useful**. It is a best-of-breed branch, not a copy of one upstream.

```text
HaxeFoundation/hxcpp 4.3.175
  ├─ upstream fixes: #1357 weak-key Hash ephemerons, #1409 BIG_BLOCKS rows,
  │                  #1465 GC root set lifetime, #1472 Boxed finalisers
  ├─ openfl/libhxcpp 6.0 backports: GC roots/registers, pointer fields,
  │                  finalizer map, VirtualArray, array/string safety, zlib
  ├─ SeiunEngine production patches: zlib-ng, per-call zip counters,
  │                  bilingual build progress, FNF-scale validation
  └─ CI/build-tool hardening: hxcpp.n rebuilt, Node 24 actions, actionlint
        = seiunengine-4.3.175
```

## At a glance

| Item | Value |
|---|---|
| Haxe | 4.3.7 tested; 4.3 API / `binaryversion 48` |
| Primary target | Windows x64 (SeiunEngine/FNF) |
| CI coverage | Windows 32/64, Linux 32/64, macOS x86_64/arm64 |
| GC | stop-the-world Immix, conservative roots; no moving GC |
| Compression | zlib-ng 2.3.90 |
| License | BSD |

## What is inside

### GC roots, registers and safe points

- Capture registers on Windows x64 and copy the paused frame on every capture path
- Keep `cpp.Pointer` fields, interior pointers and block-base pointers alive correctly
- Handle safe points inside a GC-free zone and on threads the collector does not know
- Make Haxe 4 `AtomicInt` a safe point so a spinning thread cannot stall a collection
- Remove finalizer entries before invoking callbacks; rebuild the finalizer map safely
- Mark only what the collector actually owns for default closures and `Boxed` values
- Release early only blocks that are really on the large-allocation list

The practical effect: fewer "object is still reachable but was collected" crashes, fewer finalizer surprises, and fewer GC stalls in mod/script-heavy games.

### Memory safety and runtime correctness

- Array sort for bool/char/small-int/float/Int64, size-overflow guards, negative resize clamp
- `String` surrogate and `fromCharCode` bounds, unsigned `charAt/substr/split`
- `Anon` five-field lookup, `HX_FIELD_EQ` length check, `memset` negative position
- `VirtualArray` empty-store concat/blit, store propagation, memcmp convention, Int64/Float promotion
- `haxe.zip` zlib hazards: geometric growth, `Z_NEED_DICT`, pinned buffers, invalid flush mode
- Empty-array buffer pointers use `Pointer()/data()` instead of `&a[0]`
- SSL empty-digest and buffer handling fixes

These are not style cleanups. Most have a reproducer that crashes, hangs or silently writes out of bounds on the 4.3.175 base.

### Maps and containers

- Hash `ObjectMap` keys by address when objects do not move: no object-id lock or global id table
- Pack the hash beside the value in map entries; `StringMap<Int>` entries shrink from 40 to 32 bytes
- Keep Int64 values in Int64-keyed maps instead of boxing through `Dynamic`
- Bound nested map formatting so a self-referential map prints `...` instead of overflowing the stack
- Keep the heap at its target under churn of objects larger than a cache line

In microbenchmarks this is the largest single win: 1M object-key insert/lookup goes from about **2.6 to 25.9 Mops/s**, with peak memory dropping from **178 MB to 94 MB**.

### zlib-ng and zip streams

- Bundled **zlib-ng 2.3.90** instead of the old zlib
- Per-call `haxe.zip` stream counters, so concurrent compress/uncompress calls do not share state
- Safer pin/unpin and error paths for malformed archives

### Build tool and developer experience

- Relink when a target's link flags, libraries or library paths change
- Per-file `cxx_standard` / `c_standard` with PCH, nvcc groups and NDK 20+
- Warn on MSVC paths approaching 260 characters and shorten long object names
- Bilingual (Chinese/English) compile progress output
- `hxcpp.n` is checked in and rebuilt from the updated `tools/hxcpp` sources

### CI

The GitHub Actions matrix covers:

- Windows 32/64, Linux 32/64, macOS x86_64/arm64
- `haxe`, `cffi`, `native`, `std`, `cppia` (interp/jit), `telemetry`, `debugger`
- build-tool tests (`test/cxx_standard`), regression tests, Haxe unit suite
- Workflow syntax kept `actionlint`-clean; all actions use Node 24 runtimes

## Compatibility

| Area | Status |
|---|---|
| Haxe 4.3.x | Supported; 4.3.7 is the tested version |
| hxcpp API | 430 / `binaryversion 48` |
| Windows x64 | Primary target, full FNF build + smoke tested |
| Windows 32, Linux 32/64, macOS x86_64/arm64 | CI coverage |
| Haxe 5 preview | Not supported; preview legs are excluded |
| Moving GC / nursery | Not a target of this branch |
| Wholesale hxcpp 6.0 API | Not merged; fixes are backported selectively |

If you need the 6.0 API or moving GC, use `openfl/libhxcpp` or upstream hxcpp 6.x. This fork intentionally stays on 4.3 so existing games do not need an API port.

## Install

Use this repository as a development hxcpp:

```sh
haxelib dev hxcpp /absolute/path/to/hxcpp
```

Or install the branch directly:

```sh
haxelib git hxcpp https://github.com/mohong2/hxcpp seiunengine-4.3.175
```

After changing anything under `tools/`, rebuild the checked-in tool binaries:

```sh
cd tools/run
haxe compile.hxml

cd ../hxcpp
haxe compile.hxml
```

The second command writes `hxcpp.n` at the repository root.

## Build a Haxe/C++ application

```sh
haxe -main Main -cpp build
```

For a C++/cppia host:

```sh
cd project
haxe compile-cppia.hxml
```

## Test

The test projects live under `test/`. The GitHub Actions workflows run the full matrix; locally you can start with:

```sh
cd test/haxe
haxe compile.hxml
bin/TestMain
```

Build-tool tests:

```sh
cd test/cxx_standard
for xml in *.xml; do
  haxelib run hxcpp "$xml"
  haxelib run hxcpp "$xml" clean
done
```

## Field validation

This branch is not only unit-tested. It has been used to build **SeiunEngine / FNF-PsychEngine** in release mode:

- 2,929 generated C++ source files, 17 groups
- full rebuild with the checked-in `hxcpp.n`
- startup smoke test: Vulkan renderer committed after 300 frames, clean exit
- the game's 13,846-file `bin` tree kept its path set across rebuilds

That matters because FNF-scale projects exercise mod loading, Lua/HSCRIPT, async assets, zip streams and large object graphs in ways a microbenchmark does not.

## Lineage and credits

This fork would not exist without:

- [HaxeFoundation/hxcpp](https://github.com/HaxeFoundation/hxcpp) — the upstream runtime
- [openfl/libhxcpp](https://github.com/openfl/libhxcpp) — the 6.0 GC/runtime work selectively backported here
- [SeiunEngine](https://github.com/mohong2/FNF-SeiunEngine) — production use, zlib-ng, zip counters and build UI
- FunkinCrew and the wider FNF/Psych Engine hxcpp forks — field reports and cross-compile work
- Upstream PRs [#1357](https://github.com/HaxeFoundation/hxcpp/pull/1357), [#1409](https://github.com/HaxeFoundation/hxcpp/pull/1409), [#1465](https://github.com/HaxeFoundation/hxcpp/pull/1465), [#1472](https://github.com/HaxeFoundation/hxcpp/pull/1472)

This is a community fork, not an official Haxe Foundation release.

## License

BSD. See [LICENSE.txt](LICENSE.txt).
