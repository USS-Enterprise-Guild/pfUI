# Profile Chat Configuration Restoration

**Date:** 2026-01-28
**Status:** Approved

## Problem

When loading a profile from another character, pfUI copies `pfUI_config` but does not restore:
- WoW chat frame configuration (which message types go to which tab)
- Chat frame positions, sizes, and names
- Extra chat windows beyond the default setup

## Solution

Save and restore WoW's native chat frame configuration as part of pfUI profiles.

## Data Structure

New config section `C.chatframes`:

```lua
C.chatframes = {
  [1] = {  -- ChatFrame1
    name = "General",
    messages = {"SAY", "YELL", "WHISPER", "GUILD", ...},
    channels = {"World", "Trade", ...},
    position = {point, relativeTo, relativePoint, x, y},
    width = 400,
    height = 200,
    fontSize = 12,
    locked = true,
    docked = true,
  },
  [2] = { ... },  -- ChatFrame2
  [3] = { ... },  -- Extra windows
  -- up to NUM_CHAT_WINDOWS
}
```

## Implementation

### Files to Modify

1. **`modules/gui.lua`** (~line 1465)
   - Before saving profile, call `pfUI.chat.SaveChatConfig()`

2. **`modules/chat.lua`**
   - Add `pfUI.chat.SaveChatConfig()` - captures all chat frames to `C.chatframes`
   - Add `pfUI.chat.LoadChatConfig()` - restores chat frames from `C.chatframes`
   - Call `LoadChatConfig()` during initialization if `C.chatframes` exists

3. **`api/config.lua`**
   - Add `chatframes = {}` to config defaults

### Save Flow

1. Loop through `ChatFrame1` to `ChatFrame[NUM_CHAT_WINDOWS]`
2. For each visible/configured frame, capture:
   - `GetChatWindowInfo(id)` - name, fontSize, colors, locked, docked
   - `GetChatWindowMessages(id)` - message groups
   - `GetChatWindowChannels(id)` - channels
   - `GetPoint()`, `GetWidth()`, `GetHeight()` - position/size
3. Store in `C.chatframes[id]`

### Load Flow

1. On `PLAYER_ENTERING_WORLD`, check if `C.chatframes` exists
2. For each saved chat frame:
   - Create frame if needed via `FCF_OpenNewWindow()`
   - Clear existing message groups and channels
   - Add saved message groups via `ChatFrame_AddMessageGroup()`
   - Add saved channels via `ChatFrame_AddChannel()`
   - Set position, size, name, colors via FCF_* functions

### Edge Cases

- **No saved config:** Skip restoration, use current setup
- **Frame doesn't exist:** Create via `FCF_OpenNewWindow()`
- **Channel doesn't exist:** Skip silently

## Behavior

Chat configuration is **always applied** when loading a profile. No prompts or flags.

## Future Work

Tracked separately: Configurable chat window system allowing N windows managed through pfUI settings GUI, not just hardcoded left/right panels.

## Scope

~100-150 lines of new code across 3 files.
