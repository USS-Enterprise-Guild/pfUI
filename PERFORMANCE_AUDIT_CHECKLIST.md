# pfUI Performance Audit Checklist

A systematic checklist for auditing Lua modules for performance issues. Based on established patterns from prior optimizations in this codebase.

## Quick Reference: Priority Levels

- **P1 (Critical)**: OnUpdate handlers, hot paths called every frame
- **P2 (High)**: Patterns in event handlers, frequent user interactions
- **P3 (Medium)**: Initialization code, infrequent operations

---

## 1. String Operations

### 1.1 Replace `string.format` with Concatenation

**Why**: `string.format` has parsing overhead. Direct concatenation (`..`) is faster for simple cases.

**Pattern to find**:
```lua
string.format("%s%s", a, b)
string.format("%s", value)
```

**Replace with**:
```lua
a .. b
tostring(value)  -- or just value if already a string
```

**Exceptions**: Keep `string.format` for:
- Complex formatting (`%.2f`, `%d` with non-string types needing conversion)
- Readability-critical code outside hot paths

**Established in**: nameplates.lua (#16), libhealth.lua (#13), libcast.lua (#14)

---

### 1.2 Use `table.concat` for Loop Concatenation

**Why**: String concatenation in loops is O(n^2) - each iteration creates a new intermediate string.

**Anti-pattern**:
```lua
local result = ""
for i = 1, n do
  result = result .. items[i] .. ", "
end
```

**Correct pattern**:
```lua
local parts = {}
for i = 1, n do
  table.insert(parts, items[i])
end
local result = table.concat(parts, ", ")
```

**Priority**: P1 if in hot path, P2 otherwise

**Established in**: buff.lua, unitframes.lua (#6)

---

### 1.3 Cache Formatted Strings

**Why**: Repeatedly formatting the same values creates garbage. Cache results keyed by input.

**Anti-pattern**:
```lua
-- Called every 0.1s per cooldown
function GetTimeString(remaining)
  return color .. round(remaining)  -- New string every call
end
```

**Correct pattern**:
```lua
local time_cache = {}
function GetTimeString(remaining)
  local rounded = round(remaining)
  if not time_cache[rounded] then
    time_cache[rounded] = color .. rounded
  end
  return time_cache[rounded]
end
```

**When to use**: Functions called frequently with limited input domains (e.g., cooldown seconds 1-99)

**Established in**: api.lua GetColoredTimeString (#5)

---

### 1.4 Pre-cache Constant Strings Outside Hot Paths

**Why**: String expressions with constants can be computed once at load time.

**Anti-pattern**:
```lua
frame:SetScript("OnUpdate", function()
  text:SetText("|cffff3333 --- " .. T["NEW TIMER"] .. " ---")
end)
```

**Correct pattern**:
```lua
local newTimerText = "|cffff3333 --- " .. T["NEW TIMER"] .. " ---"
frame:SetScript("OnUpdate", function()
  text:SetText(newTimerText)
end)
```

**Established in**: panel.lua (#15)

---

## 2. Iterator Optimization

### 2.1 Use `next()` Instead of `pairs()` in Hot Paths

**Why**: `pairs()` allocates an iterator function on each call. `next()` with manual iteration avoids this.

**Anti-pattern**:
```lua
-- In OnUpdate or frequently-called function
for sender, amount in pairs(heals[name]) do
  -- process
end
```

**Correct pattern**:
```lua
local sender, amount = next(unitheals)
while sender do
  -- process
  sender, amount = next(unitheals, sender)
end
```

**Priority**: P1 for OnUpdate handlers, P2 for event handlers

**Established in**: libpredict.lua (#12)

---

### 2.2 Use Numeric Loops for Array-like Tables

**Why**: `for i=1,n` is faster than `pairs()` for sequential integer-indexed tables.

**Anti-pattern**:
```lua
-- frame.buffs is indexed 1-32
for id, data in pairs(frame.buffs) do
  -- process
end
```

**Correct pattern**:
```lua
for id = 1, 32 do
  local data = frame.buffs[id]
  if data then
    -- process
  end
end
```

**Established in**: buffwatch.lua (#10)

---

### 2.3 Cache Table Lookups Before Iteration

**Why**: Repeated table indexing has lookup cost. Cache in a local variable.

**Anti-pattern**:
```lua
if not heals[name] then return 0 end
for sender, amount in pairs(heals[name]) do
  heals[name][sender] = nil
end
```

**Correct pattern**:
```lua
local unitheals = heals[name]
if not unitheals then return 0 end
for sender, amount in pairs(unitheals) do
  unitheals[sender] = nil
end
```

**Established in**: libpredict.lua (#12)

---

## 3. OnUpdate Throttling

### 3.1 Add Time-based Throttle to OnUpdate Handlers

**Why**: OnUpdate fires every frame (60+ times/second). Most logic doesn't need per-frame updates.

**Anti-pattern**:
```lua
frame:SetScript("OnUpdate", function()
  -- Runs 60+ times per second
  UpdateDisplay()
end)
```

**Correct pattern**:
```lua
frame:SetScript("OnUpdate", function()
  if (this.tick or 0) > GetTime() then return end
  this.tick = GetTime() + 0.1  -- 10 updates per second max
  UpdateDisplay()
end)
```

**Common intervals**:
- `0.1` (100ms): UI updates, cooldown text
- `0.2-0.5` (200-500ms): Less critical displays
- `1.0+`: Very infrequent checks

**Established in**: panel.lua (#15)

---

### 3.2 Track Next Event Time to Skip Empty Iterations

**Why**: If nothing needs processing, skip entirely rather than iterating an empty/irrelevant table.

**Anti-pattern**:
```lua
frame:SetScript("OnUpdate", function()
  for timestamp, targets in pairs(events) do
    if GetTime() >= timestamp then
      events[timestamp] = nil
    end
  end
end)
```

**Correct pattern**:
```lua
local nextEventTime = nil

frame:SetScript("OnUpdate", function()
  if not nextEventTime or GetTime() < nextEventTime then return end

  local newNextTime = nil
  for timestamp, targets in pairs(events) do
    if GetTime() >= timestamp then
      events[timestamp] = nil
    elseif not newNextTime or timestamp < newNextTime then
      newNextTime = timestamp
    end
  end
  nextEventTime = newNextTime
end)
```

**Established in**: libpredict.lua (#12)

---

## 4. Lookup Optimization

### 4.1 Use Reverse Lookup Tables for Bidirectional Relationships

**Why**: Nested iteration to find "all X for sender Y" is O(n*m). Reverse lookup is O(1) + O(targets).

**Anti-pattern**:
```lua
-- O(targets * senders) to stop heals from one sender
function HealStop(sender)
  for target, t in pairs(heals) do
    for tsender in pairs(heals[target]) do
      if sender == tsender then
        heals[target][tsender] = nil
      end
    end
  end
end
```

**Correct pattern**:
```lua
local senderToTargets = {}  -- Maintain reverse lookup

function Heal(sender, target, amount)
  heals[target] = heals[target] or {}
  heals[target][sender] = amount
  -- Maintain reverse lookup
  senderToTargets[sender] = senderToTargets[sender] or {}
  senderToTargets[sender][target] = true
end

function HealStop(sender)
  local targets = senderToTargets[sender]
  if targets then
    for target in pairs(targets) do
      if heals[target] then
        heals[target][sender] = nil
      end
    end
    senderToTargets[sender] = nil
  end
end
```

**Established in**: libpredict.lua (#11)

---

## 5. Memory/GC Patterns

### 5.1 Avoid Creating Tables in Hot Paths

**Why**: Table creation triggers garbage collection. Reuse tables or pre-allocate.

**Anti-pattern**:
```lua
frame:SetScript("OnUpdate", function()
  local data = { a = 1, b = 2 }  -- New table every frame
  ProcessData(data)
end)
```

**Correct pattern**:
```lua
local data = { a = 0, b = 0 }  -- Reusable table
frame:SetScript("OnUpdate", function()
  data.a = 1
  data.b = 2
  ProcessData(data)
end)
```

---

### 5.2 Prefer `table.wipe` Over New Table Assignment

**Why**: Reusing a wiped table avoids allocation; assigning `{}` creates garbage.

**Anti-pattern**:
```lua
cache = {}  -- Old table becomes garbage
```

**Correct pattern**:
```lua
table.wipe(cache)  -- Reuse existing table (if available in Lua version)
-- Or manually: for k in pairs(cache) do cache[k] = nil end
```

---

### 5.3 Local Variable Caching for Globals

**Why**: Global lookups go through `_G` table. Locals are stack-based and faster.

**Pattern for hot paths**:
```lua
-- At module/file scope
local GetTime = GetTime
local UnitHealth = UnitHealth
local pairs = pairs

-- Now use the locals in OnUpdate handlers
```

**Note**: Only worthwhile in genuinely hot paths. Don't over-optimize initialization code.

---

## 6. Conditional Optimization

### 6.1 Order Conditions by Likelihood (Early Exit)

**Why**: Short-circuit evaluation means first-failing condition skips the rest.

**Pattern**: Put most likely to fail (or cheapest to check) conditions first.

```lua
-- If most frames don't have this flag, check it first
if not frame.needsUpdate then return end
if (this.tick or 0) > GetTime() then return end
-- expensive operations here
```

---

### 6.2 Combine Nested Conditionals

**Why**: Reduces branching overhead and improves readability.

**Anti-pattern**:
```lua
if a then
  if b then
    if c or d then
      doSomething()
    end
  end
end
```

**Correct pattern**:
```lua
if a and b and (c or d) then
  doSomething()
end
```

---

## Audit Procedure

For each module being audited:

1. **Identify hot paths**: Search for `OnUpdate`, `OnEvent` handlers
2. **Check string operations**: Search for `string.format`, `..` in loops
3. **Check iterators**: Search for `pairs(` in hot paths
4. **Check for caching opportunities**: Repeated computations with same inputs
5. **Document findings**: Note line numbers, pattern type, and priority

### Search Commands

```bash
# Find OnUpdate handlers
grep -n "OnUpdate" modules/file.lua

# Find string.format usage
grep -n "string.format" modules/file.lua

# Find pairs in potential hot paths
grep -n "pairs(" modules/file.lua

# Find string concatenation in loops
grep -B5 -A5 '\.\..*for\|for.*\.\.' modules/file.lua
```

---

## References

- [Wowpedia UI Best Practices](https://wowpedia.fandom.com/wiki/UI_best_practices)
- [Lua Users Wiki: Optimising Garbage Collection](http://lua-users.org/wiki/OptimisingGarbageCollection)
- [WoWInterface Performance Discussion](https://www.wowinterface.com/forums/showthread.php?t=36067)

---

*Document version: 1.0*
*Created: 2026-01-08*
*Based on pfUI optimizations through commit 9aea85e1*
