# Fix: Buff Tooltip String Accumulation in Loop

## Issue

The buff tooltip "Unbuffed" list feature in both `modules/buff.lua` and `api/unitframes.lua` uses string concatenation in a loop, causing O(n²) memory allocations.

### Current Code (buff.lua lines 155-179, unitframes.lua lines 76-100)

```lua
local playerlist = ""
local first = true

if UnitInRaid("player") then
  for i=1,40 do
    local unitstr = "raid" .. i
    if not UnitHasBuff(unitstr, texture) and UnitName(unitstr) then
      playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor(unitstr) .. UnitName(unitstr) .. "|r"
      first = nil
    end
  end
end
```

### Impact

- Each `playerlist = playerlist .. ...` creates a new string
- In a 40-person raid, this can create 40+ intermediate strings
- O(n²) memory usage pattern (total bytes allocated grows quadratically)
- Called on every buff tooltip hover with Shift held

## Proposed Fix

Use `table.insert()` to collect player names, then `table.concat()` once at the end.

### Changes

1. Replace `playerlist = ""` with `local playerlist = {}`
2. Replace concatenation with `table.insert(playerlist, ...)`
3. Replace final use with `table.concat(playerlist, ", ")`
4. Apply same fix to both buff.lua and unitframes.lua

### Implementation

```lua
local playerlist = {}

if UnitInRaid("player") then
  for i=1,40 do
    local unitstr = "raid" .. i
    if not UnitHasBuff(unitstr, texture) and UnitName(unitstr) then
      table.insert(playerlist, GetUnitColor(unitstr) .. UnitName(unitstr) .. "|r")
    end
  end
end
-- ...

if table.getn(playerlist) > 0 then
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(T["Unbuffed"] .. ":", .3, 1, .8)
  GameTooltip:AddLine(table.concat(playerlist, ", "),1,1,1,1)
  GameTooltip:Show()
end
```

## Testing

1. Verify buff tooltip "Unbuffed" list shows correctly in raid
2. Verify buff tooltip works correctly in party
3. Verify tooltip displays player names with correct colors
4. Monitor memory allocation when hovering buffs with Shift
