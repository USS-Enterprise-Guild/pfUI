# Profile Chat Configuration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Save and restore WoW chat frame configuration when saving/loading pfUI profiles.

**Architecture:** Add `SaveChatConfig()` and `LoadChatConfig()` functions to the chat module. Hook into profile save/create to capture chat state, and apply saved state on PLAYER_ENTERING_WORLD when `C.chatframes` exists.

**Tech Stack:** Lua (WoW 1.12.1/2.4.3 API), pfUI framework

---

## Task 1: Add Default Config Entry

**Files:**
- Modify: `api/config.lua:31` (inside `pfUI:LoadConfig()`)

**Step 1: Add chatframes default**

Add after line 62 (after the `gui` section, before `buffs`):

```lua
  pfUI:UpdateConfig("chatframes", nil,           nil,                nil)
```

This creates an empty `C.chatframes` table if it doesn't exist.

**Step 2: Commit**

```bash
git add api/config.lua
git commit -m "feat(config): add chatframes default config entry"
```

---

## Task 2: Implement SaveChatConfig Function

**Files:**
- Modify: `modules/chat.lua` (add after `SetupChannels` function, around line 578)

**Step 1: Add SaveChatConfig function**

Insert after the `SetupChannels` function (after line 578):

```lua
  function pfUI.chat.SaveChatConfig()
    C.chatframes = {}

    for i = 1, NUM_CHAT_WINDOWS do
      local frame = _G["ChatFrame" .. i]
      local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(i)

      -- skip unconfigured frames
      if not name or name == "" then
        -- frame exists but has no name, still save if it has content
        if not frame or not frame:IsVisible() then
          break
        end
      end

      local frameData = {
        name = name or "",
        fontSize = fontSize or 12,
        r = r or 0,
        g = g or 0,
        b = b or 0,
        alpha = alpha or 0,
        shown = shown and "1" or "0",
        locked = locked and "1" or "0",
        docked = docked and "1" or "0",
        messages = {},
        channels = {},
      }

      -- save message groups
      local messages = { GetChatWindowMessages(i) }
      for _, msg in ipairs(messages) do
        if msg and msg ~= "" then
          table.insert(frameData.messages, msg)
        end
      end

      -- save channels
      local channels = { GetChatWindowChannels(i) }
      -- GetChatWindowChannels returns: name1, zone1, name2, zone2, ...
      for j = 1, table.getn(channels), 2 do
        local chanName = channels[j]
        if chanName and chanName ~= "" then
          table.insert(frameData.channels, chanName)
        end
      end

      -- save position and size
      local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
      frameData.position = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName() or nil,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
      }
      frameData.width = frame:GetWidth()
      frameData.height = frame:GetHeight()

      C.chatframes[i] = frameData
    end
  end
```

**Step 2: Commit**

```bash
git add modules/chat.lua
git commit -m "feat(chat): add SaveChatConfig function to capture chat frame state"
```

---

## Task 3: Implement LoadChatConfig Function

**Files:**
- Modify: `modules/chat.lua` (add after `SaveChatConfig` function)

**Step 1: Add LoadChatConfig function**

Insert after `SaveChatConfig`:

```lua
  function pfUI.chat.LoadChatConfig()
    if not C.chatframes or not next(C.chatframes) then
      return
    end

    for i, frameData in pairs(C.chatframes) do
      local frame = _G["ChatFrame" .. i]

      -- create frame if it doesn't exist (for frames 4+)
      if not frame and i > 2 then
        FCF_OpenNewWindow(frameData.name or ("Chat " .. i))
        frame = _G["ChatFrame" .. i]
      end

      if frame then
        -- set window properties
        FCF_SetWindowName(frame, frameData.name or "")
        FCF_SetWindowColor(frame, frameData.r or 0, frameData.g or 0, frameData.b or 0)
        FCF_SetWindowAlpha(frame, frameData.alpha or 0)
        FCF_SetChatWindowFontSize(nil, frame, frameData.fontSize or 12)

        if frameData.locked == "1" then
          FCF_SetLocked(frame, 1)
        else
          FCF_SetLocked(frame, nil)
        end

        -- handle docking
        if frameData.docked == "1" then
          FCF_DockFrame(frame)
        else
          FCF_UnDockFrame(frame)
        end

        -- clear and restore message groups
        ChatFrame_RemoveAllMessageGroups(frame)
        if frameData.messages then
          for _, msg in ipairs(frameData.messages) do
            ChatFrame_AddMessageGroup(frame, msg)
          end
        end

        -- clear and restore channels
        ChatFrame_RemoveAllChannels(frame)
        if frameData.channels then
          for _, chan in ipairs(frameData.channels) do
            ChatFrame_AddChannel(frame, chan)
          end
        end

        -- restore position and size (for undocked frames)
        if frameData.docked ~= "1" and frameData.position then
          frame:ClearAllPoints()
          local pos = frameData.position
          local parent = pos.relativeTo and _G[pos.relativeTo] or UIParent
          frame:SetPoint(pos.point or "BOTTOMLEFT", parent, pos.relativePoint or "BOTTOMLEFT", pos.xOfs or 0, pos.yOfs or 0)
        end

        if frameData.width then
          frame:SetWidth(frameData.width)
        end
        if frameData.height then
          frame:SetHeight(frameData.height)
        end

        frame:SetUserPlaced(true)
      end
    end

    FCF_DockUpdate()
  end
```

**Step 2: Commit**

```bash
git add modules/chat.lua
git commit -m "feat(chat): add LoadChatConfig function to restore chat frame state"
```

---

## Task 4: Hook Save Profile to Capture Chat Config

**Files:**
- Modify: `modules/gui.lua:1468-1469` (inside "Save profile" button handler)

**Step 1: Add SaveChatConfig call before saving profile**

Change lines 1468-1469 from:

```lua
            if pfUI_profiles[C.global.profile] then
              pfUI_profiles[C.global.profile] = CopyTable(C)
```

To:

```lua
            if pfUI_profiles[C.global.profile] then
              if pfUI.chat and pfUI.chat.SaveChatConfig then
                pfUI.chat.SaveChatConfig()
              end
              pfUI_profiles[C.global.profile] = CopyTable(C)
```

**Step 2: Commit**

```bash
git add modules/gui.lua
git commit -m "feat(gui): call SaveChatConfig before saving profile"
```

---

## Task 5: Hook Create Profile to Capture Chat Config

**Files:**
- Modify: `modules/gui.lua:1487` (inside "Create Profile" button handler)

**Step 1: Add SaveChatConfig call before creating profile**

Change line 1487 from:

```lua
              pfUI_profiles[profile] = CopyTable(C)
```

To:

```lua
              if pfUI.chat and pfUI.chat.SaveChatConfig then
                pfUI.chat.SaveChatConfig()
              end
              pfUI_profiles[profile] = CopyTable(C)
```

**Step 2: Commit**

```bash
git add modules/gui.lua
git commit -m "feat(gui): call SaveChatConfig before creating profile"
```

---

## Task 6: Call LoadChatConfig on Login

**Files:**
- Modify: `modules/chat.lua:580-590` (inside `pfUI.chat:SetScript("OnEvent", ...)`)

**Step 1: Add LoadChatConfig call in OnEvent handler**

Change lines 580-590 from:

```lua
  pfUI.chat:SetScript("OnEvent", function()
    -- set the default chat
    FCF_SelectDockFrame(SELECTED_CHAT_FRAME)

    -- update all chat settings
    pfUI.chat:RefreshChat()
    FCF_DockUpdate()
    if C.chat.right.enable == "0" then
      pfUI.chat.right:Hide()
    end
  end)
```

To:

```lua
  pfUI.chat:SetScript("OnEvent", function()
    -- set the default chat
    FCF_SelectDockFrame(SELECTED_CHAT_FRAME)

    -- restore chat configuration from profile if available
    if pfUI.chat.LoadChatConfig then
      pfUI.chat.LoadChatConfig()
    end

    -- update all chat settings
    pfUI.chat:RefreshChat()
    FCF_DockUpdate()
    if C.chat.right.enable == "0" then
      pfUI.chat.right:Hide()
    end
  end)
```

**Step 2: Commit**

```bash
git add modules/chat.lua
git commit -m "feat(chat): call LoadChatConfig on PLAYER_ENTERING_WORLD"
```

---

## Task 7: In-Game Verification

**No code changes - manual testing**

**Step 1: Test on Character A**
1. Log into Character A
2. Create/configure chat windows (add a new tab, move channels around)
3. Open pfUI settings → General → Profile
4. Create a new profile called "TestProfile"
5. Verify no errors in chat

**Step 2: Test on Character B**
1. Log into Character B (fresh character or different chat setup)
2. Note current chat window configuration
3. Open pfUI settings → General → Profile
4. Select "TestProfile" and click "Load profile"
5. After reload, verify:
   - Chat windows match Character A's setup
   - Message types are in correct tabs
   - Channels are assigned correctly
   - Window positions match (for undocked windows)

**Step 3: Final commit (if all tests pass)**

```bash
git add -A
git commit -m "docs: add implementation plan for profile chat config" --allow-empty
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add chatframes default config | `api/config.lua` |
| 2 | Implement SaveChatConfig | `modules/chat.lua` |
| 3 | Implement LoadChatConfig | `modules/chat.lua` |
| 4 | Hook Save Profile | `modules/gui.lua` |
| 5 | Hook Create Profile | `modules/gui.lua` |
| 6 | Call LoadChatConfig on login | `modules/chat.lua` |
| 7 | In-game verification | Manual testing |

**Total: ~120 lines of new code**
