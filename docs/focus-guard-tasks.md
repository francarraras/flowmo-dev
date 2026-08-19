# Flowmo — Focus Guard (tasks)

From [`focus-guard-design.md`](focus-guard-design.md). Done means [`focus-guard.md`](focus-guard.md) holds.

Signed by the captain on 2026-08-19. Implementation of this list is allowed.

Do not start a second store. Do not add a menu bar, living TUI, Pause-during-focus, or a focus progress ring.

---

1. **Spike**  
   Disposable proof of activation + `hide()`, Open-once without a loop, hidden window still guards, `swift run` and Dock app, no Accessibility. If it fails, stop.

2. **Core config**  
   Additive `FocusGuardConfiguration` on `Config`. Legacy `world.json` loads disabled. Normalize IDs. Engine event + Store only. Checks for decode, normalize, demand matrix, failed persist does not activate.

3. **Adapter + controller**  
   Injectable observer. Reconcile from persisted World. Open-once by process id. Fail open. Fake-adapter checks.

4. **Compact UI**  
   Idle config in the same frame. Focus status + intercept Stay focused / Open once. Clock remains the hero.

5. **Prove live**  
   Native, Electron, multi-window, full-screen. Hide Flowmo. Stop / Skip / quit-Continue. CLI while the window runs.

Anything not listed is a later slice.
