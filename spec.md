# Fix: Castbar Timer Text Updates Every Frame

## Issue

The castbar OnUpdate handler in `modules/castbar.lua` performs string concatenation and `string.format()` operations every frame while casting, even when the displayed value hasn't changed.

### Current Code (lines 150-157)

```lua
if this.showtimer then
  if this.delay and this.delay > 0 then
    local delay = "|cffffaaaa" .. (channel and "-" or "+") .. round(this.delay,1) .. " |r "
    this.bar.right:SetText(delay .. string.format("%.1f",cur) .. " / " .. round(max,1))
  else
    this.bar.right:SetText(string.format("%.1f",cur) .. " / " .. round(max,1))
  end
end
```

### Impact

- `string.format("%.1f", cur)` creates a new string every frame
- String concatenation `..` creates multiple temporary strings every frame
- 60+ frames/second during casting = 60+ string allocations/second per castbar
- With player + target + focus castbars, this multiplies

## Proposed Fix

Only update the timer text when the displayed value changes. Since we display with 1 decimal place, track when `floor(cur * 10)` changes.

### Changes

1. Track the last displayed current time value (as integer tenths)
2. Only perform string operations when this value changes
3. Cache the max value string since it doesn't change during a cast

### Implementation

```lua
if this.showtimer then
  local curTenths = math.floor(cur * 10)
  if this.lastCurTenths ~= curTenths or this.lastDelay ~= this.delay then
    this.lastCurTenths = curTenths
    this.lastDelay = this.delay

    -- cache max string if not already cached for this cast
    if not this.maxStr then
      this.maxStr = round(max, 1)
    end

    if this.delay and this.delay > 0 then
      local sign = channel and "-" or "+"
      this.bar.right:SetText("|cffffaaaa" .. sign .. round(this.delay,1) .. " |r " .. string.format("%.1f",cur) .. " / " .. this.maxStr)
    else
      this.bar.right:SetText(string.format("%.1f",cur) .. " / " .. this.maxStr)
    end
  end
end
```

Also clear the cached values when a new cast starts (in the `this.endTime ~= endTime` block).

## Testing

1. Verify castbar timer text still updates smoothly during casting
2. Verify delay indicator shows correctly when cast is pushed back
3. Verify timer resets properly between casts
4. Monitor memory allocation rate before/after the change
