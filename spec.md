# Fix: Cooldown Module String Concatenation in OnUpdate

## Issue

The `pfCooldownOnUpdate` function in `modules/cooldown.lua` performs string concatenation operations **before** the throttle check, causing excessive garbage collection pressure.

### Current Code (lines 10-23)

```lua
local function pfCooldownOnUpdate()
  parent = this:GetParent()
  if not parent then this:Hide() end
  parent_name = parent:GetName()

  -- avoid to set cooldowns on invalid frames
  if parent_name and _G[parent_name .. "Cooldown"] then      -- STRING ALLOC #1
    if not _G[parent_name .. "Cooldown"]:IsShown() then      -- STRING ALLOC #2
      this:Hide()
    end
  end

  -- only run every 0.1 seconds from here on
  if ( this.tick or .1) > GetTime() then return else this.tick = GetTime() + .1 end
```

### Impact

- String concatenation `parent_name .. "Cooldown"` runs **every frame** (60+ times/second)
- Happens **twice** per frame (lines 16 and 17)
- Multiplied by number of active cooldowns (50+ action buttons, inventory items, etc.)
- **Result:** 6000+ temporary string allocations per second, creating significant GC pressure

## Proposed Fix

Cache the cooldown frame reference when the `pfCooldownText` frame is created, and use the cached reference in the OnUpdate handler.

### Changes

1. In `pfCreateCoolDown`: Store the parent's cooldown frame reference on the pfCooldownText frame
2. In `pfCooldownOnUpdate`: Use the cached reference instead of building the string each frame

### Implementation

```lua
-- In pfCreateCoolDown, after creating the frame:
local parent_name = cooldown:GetParent() and cooldown:GetParent():GetName()
if parent_name then
  cooldown.pfCooldownText.cooldownRef = _G[parent_name .. "Cooldown"]
end

-- In pfCooldownOnUpdate, replace lines 15-20:
if this.cooldownRef and not this.cooldownRef:IsShown() then
  this:Hide()
  return
end
```

## Testing

1. Verify cooldowns still display correctly on action bars
2. Verify cooldowns hide properly when the underlying cooldown animation is hidden
3. Monitor memory allocation rate before/after the change
