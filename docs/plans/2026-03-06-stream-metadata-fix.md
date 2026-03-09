# Stream Metadata Fallback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop seek-triggered repeated metadata lookups for external streams while still queueing Jellyfin/custom-extractor items using mpv `media-title` fallback metadata.

**Architecture:** Remove queue bootstrap work from the seek-sensitive `playback-restart` path. Refactor metadata resolution into helpers that can use cached data, `yt-dlp`, or mpv-derived fallback values, then reuse those helpers during playlist sync and queue insertion.

**Tech Stack:** Lua, mpv scripting API, `yt-dlp`, minimal Lua regression test harness if needed

---

### Task 1: Add regression test scaffold for metadata resolution

**Files:**
- Create: `tests/metadata_resolution_test.lua`
- Test: `tests/metadata_resolution_test.lua`

**Step 1: Write the failing test**

Create a small Lua test file that loads the metadata helper surface and asserts:

```lua
local result = subject.build_fallback_video_info({
  video_url = "https://example.invalid/stream",
  media_title = "Jellyfin Episode 1",
})

assert(result.video_name == "Jellyfin Episode 1")
```

Add a second test that simulates a failed extractor lookup followed by a second resolution for the same URL and asserts the extractor path is not called twice.

**Step 2: Run test to verify it fails**

Run: `lua tests/metadata_resolution_test.lua`
Expected: FAIL because helper surface does not exist yet.

**Step 3: Write minimal implementation**

Extract or add pure helper functions in `mpv-youtube-queue.lua` for:

```lua
build_fallback_video_info(url, props)
resolve_video_info(url, context)
```

Keep the interface small enough that the test can stub extractor results and mpv properties.

**Step 4: Run test to verify it passes**

Run: `lua tests/metadata_resolution_test.lua`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/metadata_resolution_test.lua mpv-youtube-queue.lua
git commit -m "test: add stream metadata fallback regression coverage"
```

### Task 2: Remove seek-triggered queue bootstrap

**Files:**
- Modify: `mpv-youtube-queue.lua`
- Test: `tests/metadata_resolution_test.lua`

**Step 1: Write the failing test**

Add a regression that models the previous bad behavior:

```lua
subject.on_playback_restart()
assert(sync_calls == 0)
```

or equivalent coverage around the listener registration/dispatch split if direct listener export is simpler.

**Step 2: Run test to verify it fails**

Run: `lua tests/metadata_resolution_test.lua`
Expected: FAIL because `playback-restart` still triggers sync/bootstrap behavior.

**Step 3: Write minimal implementation**

Change listener behavior so `playback-restart` no longer calls `sync_with_playlist()` for queue bootstrap. Keep startup and `file-loaded` flows responsible for real import work.

**Step 4: Run test to verify it passes**

Run: `lua tests/metadata_resolution_test.lua`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/metadata_resolution_test.lua mpv-youtube-queue.lua
git commit -m "fix: avoid seek-triggered queue metadata refresh"
```

### Task 3: Use fallback metadata during playlist sync

**Files:**
- Modify: `mpv-youtube-queue.lua`
- Test: `tests/metadata_resolution_test.lua`

**Step 1: Write the failing test**

Add a test that simulates `sync_with_playlist()` for a URL whose extractor metadata fails and asserts the resulting queue entry is still created with:

```lua
assert(video.video_name == "Jellyfin Episode 1")
assert(video.video_url == test_url)
```

**Step 2: Run test to verify it fails**

Run: `lua tests/metadata_resolution_test.lua`
Expected: FAIL because sync currently drops entries when `yt-dlp` fails.

**Step 3: Write minimal implementation**

Refactor playlist import to call the new metadata resolution helper. Cache fallback metadata the same way extractor metadata is cached, and relax the fatal-field check so fallback entries can omit channel URL/uploader.

**Step 4: Run test to verify it passes**

Run: `lua tests/metadata_resolution_test.lua`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/metadata_resolution_test.lua mpv-youtube-queue.lua
git commit -m "fix: fallback to mpv metadata for external streams"
```

### Task 4: Verify end-to-end behavior and docs

**Files:**
- Modify: `README.md`
- Modify: `docs/plans/2026-03-06-stream-metadata-design.md`
- Modify: `docs/plans/2026-03-06-stream-metadata-fix.md`

**Step 1: Write the failing test**

Document the expected behavior change before code handoff:

```text
External streams should stay queued and should not re-fetch metadata on seek.
```

**Step 2: Run test to verify it fails**

Run: `lua tests/metadata_resolution_test.lua`
Expected: Existing coverage should fail if the final behavior regresses.

**Step 3: Write minimal implementation**

Update `README.md` with a short note that unsupported extractor sources fall back to mpv metadata such as `media-title`.

**Step 4: Run test to verify it passes**

Run: `lua tests/metadata_resolution_test.lua`
Expected: PASS

If practical, also run a syntax check:

```bash
lua -e 'assert(loadfile("mpv-youtube-queue.lua"))'
```

**Step 5: Commit**

```bash
git add README.md docs/plans/2026-03-06-stream-metadata-design.md docs/plans/2026-03-06-stream-metadata-fix.md tests/metadata_resolution_test.lua mpv-youtube-queue.lua
git commit -m "docs: document stream metadata fallback behavior"
```
