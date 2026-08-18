# Flowmo v1 — plan

Architecture derived from [`PROJECT.md`](PROJECT.md) and [`acceptance.md`](acceptance.md). Throw this away and rewrite if those change.

Signed off by the captain on 2026-08-18 as **constraints** (SwiftPM, JSON, CLI side door). Not the engineering design — see [`design.md`](design.md).

## Goal

A compact Mac window that runs the locked loop. Same live session for the window and any CLI/agent. The Xcode `.app` must not mean rewriting the loop.

## Approach

Three pieces:

1. **FlowmoCore** (evolve the existing library in this folder). Timestamped session reducer + JSON store. Elapsed time is `now - startedAt`. One live session. File lock around load/save. Path: `~/.flowmo/world.json` (atomic replace, already how `Sources/FlowmoCore/Store.swift` works). Pause exists only as quit/sleep recovery; **Continue** is resume. Do not expose Pause during focus.
2. **FlowmoWindow**. SwiftUI views for Idle, Prime, Focus, Break, Recall, close beat, and paused+Continue. Layout follows the state table. Plain compact chrome; no brand. Pin-on-top: one control, default off.
3. **Launchers** (thin). A SwiftPM executable (`swift run`) and an Xcode app target (`Apps/Flowmo.xcodeproj`) both host the same `FlowmoWindow`. Neither launcher owns the clock or the store.

CLI (`flowmo`) stays a **side door** to Core. Do not grow it into the daily UI. Reuse Core; throw away command-tennis as the product.

Sound and notifications are adapters on phase changes, not part of Core.

## Layout (not look)

One compact frame. Insides change. No Home, tabs, or menu bar. Focus: big count-up + earned strip + **+**. Timed phases: determinate ring. Paused: frozen clock + Continue.

## Risks

- `swift build` / `swift run` remain the SwiftPM path. The Dock `.app` is an Xcode wrap of the same window, not a fork.
- Sketch `Engine` still has a pause *event*. Keep it for recovery; never as a focus button. Close-beat / today-total / Continue must match `acceptance.md` even if the sketch is incomplete — change Core, do not invent a second store.
- Two clocks is a bug. Window and CLI must share `world.json`.

## Not this plan

Brand, iPhone, menu-bar glance, SQLite, history browser.
