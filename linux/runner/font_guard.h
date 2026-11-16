#ifndef RUNNER_FONT_GUARD_H_
#define RUNNER_FONT_GUARD_H_

// Keeps the engine from hanging on a font that fontconfig lists with no family
// name. Call once, first thing in main(), before any other thread exists and
// before anything has initialised fontconfig. See font_guard.cc.
void ninja_guard_fonts();

#endif  // RUNNER_FONT_GUARD_H_
