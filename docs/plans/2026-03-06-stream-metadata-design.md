# Stream Metadata Fallback Design

**Context**

`mpv-youtube-queue.lua` currently imports externally opened playlist items by calling `sync_with_playlist()`. For non-YouTube streams such as Jellyfin or custom extractor URLs, `yt-dlp --dump-single-json` can fail. The current listener flow also retries that import path on `playback-restart`, which fires during seeks, causing repeated metadata fetch attempts and repeated failures.

**Goal**

Keep externally opened streams in the queue while preventing seek-triggered metadata retries. When extractor metadata is unavailable, use mpv metadata, preferring `media-title`.

**Chosen Approach**

1. Stop using `playback-restart` as the trigger for queue import.
2. Import external items on real file loads and startup sync only.
3. Add a metadata fallback path for playlist items:
   - use cached metadata first
   - try `yt-dlp` once
   - if that fails, build queue metadata from mpv properties, preferring `media-title`
4. Cache fallback metadata too so later syncs do not retry `yt-dlp` for the same URL.

**Why This Approach**

- Fixes root cause instead of hiding repeated failures behind a negative cache alone.
- Preserves current rich metadata for URLs that `yt-dlp` understands.
- Keeps Jellyfin/custom extractor streams visible in the queue with a usable title.

**Metadata Resolution**

For a playlist URL, resolve metadata in this order:

1. Existing cached metadata entry
2. `yt-dlp` metadata
3. mpv fallback metadata using:
   - `media-title`
   - then filename/path-derived title
   - placeholder values for channel/category fields

Fallback entries should be marked so the script can distinguish rich extractor metadata from mpv-derived metadata if needed later.

**Listener Changes**

- Keep startup `on_load` sync.
- Keep `file-loaded` handling.
- Remove external queue bootstrap from `playback-restart`, because seeks trigger it.
- Keep existing index-tracking listeners that do not rebuild queue state.

**Error Handling**

- Failing extractor metadata should no longer drop the playlist item.
- Missing uploader/channel data should not be treated as fatal for fallback entries.
- Queue sync should remain best-effort per item: one bad URL should not abort the whole playlist import.

**Regression Coverage**

- Non-extractor stream gets queued with `media-title` fallback.
- Repeated sync for the same URL reuses cached fallback metadata instead of calling extractor again.
- Standard supported URLs still keep extractor metadata.

**Risks**

- mpv properties available during playlist sync may differ by source; fallback builder must handle missing values safely.
- The repo currently has no obvious test harness, so regression coverage may require a small isolated Lua test scaffold.
