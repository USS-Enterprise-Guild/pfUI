# Fix: Castbar Color strsplit on Cast Start

## Issue

The castbar module calls `strsplit()` to parse color strings each time a new cast begins, creating temporary tables and strings.

### Current Code (line 113)

```lua
if this.endTime ~= endTime then
  this.bar:SetStatusBarColor(strsplit(",", C.appearance.castbar[(channel and "channelcolor" or "castbarcolor")]))
```

### Impact

- `strsplit()` creates a temporary table and string allocations
- Runs every time a cast starts (frequent during combat)
- While not every-frame, it adds to GC pressure during high activity

## Proposed Fix

Pre-cache the cast and channel colors as arrays at module initialization time, and use `unpack()` to pass to SetStatusBarColor.

### Changes

1. At module init: Parse both castbarcolor and channelcolor into cached arrays
2. In OnUpdate: Use the cached arrays with `unpack()` instead of calling `strsplit()`

### Implementation

```lua
-- At module initialization (after line 5)
local castcolor = {strsplit(",", C.appearance.castbar.castbarcolor)}
local channelcolor = {strsplit(",", C.appearance.castbar.channelcolor)}

-- In OnUpdate (line 113)
this.bar:SetStatusBarColor(unpack(channel and channelcolor or castcolor))
```

## Testing

1. Verify cast bar shows correct color during regular casts
2. Verify cast bar shows correct color during channeled spells
3. Monitor memory allocation during combat
