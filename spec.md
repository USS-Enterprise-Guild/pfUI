# Fix: ActionBar Module Iterator Allocations in OnUpdate

## Issue

The `BarsUpdate` function in `modules/actionbar.lua` creates multiple iterator closures every frame by calling `pairs()` multiple times in separate loops.

### Current Code (lines 772-815)

```lua
-- run cached usable usable actions
if eventcache["ACTIONBAR_UPDATE_USABLE"] then
  eventcache["ACTIONBAR_UPDATE_USABLE"] = nil
  for id, button in pairs(buttoncache) do  -- Iterator #1
    ButtonUsableUpdate(button)
  end
end

-- run cached cooldown events
if eventcache["ACTIONBAR_UPDATE_COOLDOWN"] then
  eventcache["ACTIONBAR_UPDATE_COOLDOWN"] = nil
  for id, button in pairs(buttoncache) do  -- Iterator #2
    ButtonCooldownUpdate(button)
  end
end

-- run cached action state events
if eventcache["ACTIONBAR_UPDATE_STATE"] then
  eventcache["ACTIONBAR_UPDATE_STATE"] = nil
  for id, button in pairs(buttoncache) do  -- Iterator #3
    ButtonIsActiveUpdate(button)
  end
end

for id in pairs(updatecache) do  -- Iterator #4
  -- ...
end

-- Throttle check happens HERE (too late)
if ( this.tick or .2) > GetTime() then return else this.tick = GetTime() + .2 end

for id, button in pairs(buttoncache) do  -- Iterator #5
  if button:IsShown() then ButtonRangeUpdate(button) end
end
```

### Impact

- Each `pairs()` call creates an iterator closure and state table
- 3-5 iterator allocations per frame, every frame
- With 120+ buttons in buttoncache, each iteration is non-trivial
- **Result:** Consistent GC pressure from iterator garbage

## Proposed Fix

Combine the three event-driven `buttoncache` iterations into a single loop that checks all conditions.

### Changes

1. Cache the event flags before the loop
2. Clear the event flags before the loop
3. Use a single `pairs(buttoncache)` iteration that checks all flags
4. Keep the throttled range update loop separate (it's already throttled)

### Implementation

```lua
-- cache and clear event flags
local update_usable = eventcache["ACTIONBAR_UPDATE_USABLE"]
local update_cooldown = eventcache["ACTIONBAR_UPDATE_COOLDOWN"]
local update_state = eventcache["ACTIONBAR_UPDATE_STATE"]
eventcache["ACTIONBAR_UPDATE_USABLE"] = nil
eventcache["ACTIONBAR_UPDATE_COOLDOWN"] = nil
eventcache["ACTIONBAR_UPDATE_STATE"] = nil

-- single iteration for all event-driven updates
if update_usable or update_cooldown or update_state then
  for id, button in pairs(buttoncache) do
    if update_usable then ButtonUsableUpdate(button) end
    if update_cooldown then ButtonCooldownUpdate(button) end
    if update_state then ButtonIsActiveUpdate(button) end
  end
end
```

## Testing

1. Verify action bar buttons update correctly when usable state changes
2. Verify cooldown displays update properly
3. Verify button state (pressed/active) updates correctly
4. Monitor memory allocation rate before/after the change
