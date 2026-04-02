# ClaudeStatus.spoon

A [Hammerspoon](https://www.hammerspoon.org/) spoon that adds per-session menu bar indicators for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Each active session gets its own menu bar item showing the project directory name and a color-coded status dot.

## Status States

| State | Dot | Meaning |
|-------|-----|---------|
| Working | Animated orange/white | Claude is processing |
| Calling | Black dot, orange background | Claude needs user input (e.g., permission prompt) |
| Done | White dot | Claude finished its turn |
| Error | Red dot | Something went wrong |

Clicking a menu bar item focuses the IDE window for that project's directory.

## How It Works

Claude Code [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) write status to `~/.claude/status-<pid>` files. The spoon watches that directory and updates menu bar items accordingly. Dead sessions are automatically cleaned up.

## Installation

1. Clone or copy `ClaudeStatus.spoon` to `~/.hammerspoon/Spoons/`
2. Add the hooks to `~/.claude/settings.json` (see [Hook Configuration](#hook-configuration))
3. Load the spoon in your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("ClaudeStatus")
spoon.ClaudeStatus:start()
```

## Hook Configuration

Add these hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "for f in ~/.claude/status-*; do [ -f \"$f\" ] && pid=$(basename \"$f\" | sed 's/status-//') && ! kill -0 \"$pid\" 2>/dev/null && rm \"$f\"; done; true"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "printf 'working\\n%s\\n' \"$PWD\" > ~/.claude/status-$CLAUDE_SESSION_PID"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "printf 'calling\\n%s\\n' \"$PWD\" > ~/.claude/status-$CLAUDE_SESSION_PID"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "agents=$(find ~/.claude/status-* 2>/dev/null | xargs grep -l \"^working\" 2>/dev/null | grep -v \"status-$CLAUDE_SESSION_PID\" | while read f; do pid=$(basename \"$f\" | sed 's/status-//'); ppid=$(ps -o ppid= -p \"$pid\" 2>/dev/null | tr -d ' '); [ \"$ppid\" = \"$CLAUDE_SESSION_PID\" ] && echo x; done | wc -l | tr -d ' '); printf 'working\\n%s\\n%s\\n' \"$PWD\" \"$agents\" > ~/.claude/status-$CLAUDE_SESSION_PID"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "printf 'done\\n%s\\n' \"$PWD\" > ~/.claude/status-$CLAUDE_SESSION_PID"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "rm -f ~/.claude/status-$CLAUDE_SESSION_PID"
          }
        ]
      }
    ]
  }
}
```

## Configuration (Optional)

All options have sensible defaults — no configuration is needed. If you want to customize behavior, override any of these in your `init.lua` before calling `:start()`:

```lua
hs.loadSpoon("ClaudeStatus")

-- Timing
spoon.ClaudeStatus.pollInterval = 2       -- seconds between full scans
spoon.ClaudeStatus.animInterval = 0.3     -- seconds between animation frames
spoon.ClaudeStatus.debounceSeconds = 2    -- ignore brief "calling" flickers

-- Click behavior
spoon.ClaudeStatus.terminalApp = "Warp"      -- fallback terminal app
spoon.ClaudeStatus.ideApp = "Windsurf"       -- IDE to focus on click

-- Colors (hs.drawing.color tables)
spoon.ClaudeStatus.callingColor = { red = 0.851, green = 0.467, blue = 0.341 }
spoon.ClaudeStatus.workingColor = { red = 0.851, green = 0.467, blue = 0.341 }
spoon.ClaudeStatus.errorColor = { red = 1, green = 0.2, blue = 0.2 }

spoon.ClaudeStatus:start()
```

## License

MIT
