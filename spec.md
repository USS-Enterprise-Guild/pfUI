# Fix: GetColoredTimeString String Concatenation

## Issue

The `GetColoredTimeString` function in `api/api.lua` performs string concatenation on every call, creating garbage. This function is called every 0.1 seconds for each active cooldown.

### Current Code (lines 1219-1279)

```lua
function pfUI.api.GetColoredTimeString(remaining)
  -- ...
  return color_low .. round(remaining)  -- String allocation every call
  -- ...
  return color_normal .. round(remaining)  -- String allocation every call
end
```

### Impact

- Called every 0.1 seconds per active cooldown
- With 10+ cooldowns active, that's 100+ string allocations per second
- Cooldowns often show the same values (5, 4, 3, 2, 1 seconds)
- Same strings are recreated repeatedly

## Proposed Fix

Cache formatted strings for common time values. Since cooldowns frequently show integer seconds 1-99 and decimal values 0.1-5.0 with milliseconds enabled, cache these pre-formatted strings.

### Changes

1. Create cache tables for low (≤5s) and normal (6-99s) integer second values
2. Create cache for low millisecond values (0.1-5.0)
3. On first access, populate the cache with the formatted string
4. Return cached string on subsequent calls

### Implementation

```lua
local time_cache_low = {}
local time_cache_normal = {}
local time_cache_ms = {}

-- In the function, for normal seconds (6-99):
local rounded = round(remaining)
if not time_cache_normal[rounded] then
  time_cache_normal[rounded] = color_normal .. rounded
end
return time_cache_normal[rounded]

-- Similar for low seconds and milliseconds
```

## Testing

1. Verify cooldown text displays correctly
2. Verify all time formats (days, hours, minutes, seconds, milliseconds) work
3. Monitor memory allocation with many active cooldowns
