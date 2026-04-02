# ClaudeStatus.spoon

A [Hammerspoon](https://www.hammerspoon.org/) spoon that adds per-session menu bar indicators for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Each active session gets its own menu bar item showing the project directory name and a color-coded status dot.

## Status States

| State | Dot | Meaning |
|-------|-----|---------|
| Working | Animated orange/white dot and label | Claude is processing |
| Calling | Black dot, orange background | Claude needs user input (e.g., permission prompt) |
| Done | White dot | Claude finished its turn |
| Error | Red dot and label | Something went wrong |

The label is the basename of the session's working directory (e.g., `my-project`). When subagents are active, it includes the count (e.g., `×3 my-project`).

Clicking a menu bar item focuses the IDE window for that project's directory.

## How It Works

Claude Code [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) write status to `~/.claude/status-<pid>` files. Each file contains three lines: the status, the working directory, and the active subagent count. The spoon watches that directory and updates menu bar items accordingly. Dead sessions are automatically cleaned up.

## Prerequisites

- **macOS** — Hammerspoon is macOS-only
- **[Hammerspoon](https://www.hammerspoon.org/)** — installed and running
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — Anthropic's CLI for Claude

## Installation

1. Clone or copy `ClaudeStatus.spoon` to `~/.hammerspoon/Spoons/`
2. Add the hooks to `~/.claude/settings.json` (see [Hook Configuration](#hook-configuration))
3. Load the spoon in your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("ClaudeStatus")
spoon.ClaudeStatus:start()
```

4. Reload your Hammerspoon config (click the Hammerspoon menu bar icon → Reload Config, or `Cmd+Shift+R`)

## Hook Configuration

Merge the following `hooks` key into your existing `~/.claude/settings.json`. Don't replace the whole file — you likely have other settings in there already.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "for f in ~/.claude/status-*; do [ -f \"$f\" ] && pid=$(basename \"$f\" | sed 's/status-//') && ! kill -0 \"$pid\" 2>/dev/null && rm -f \"$f\"; done; true"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=~/.claude/status-$PPID; n=$(sed -n '3p' \"$f\" 2>/dev/null); printf 'working\\n%s\\n%s\\n' \"$PWD\" \"$n\" > \"$f\""
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=~/.claude/status-$PPID; n=$(sed -n '3p' \"$f\" 2>/dev/null); printf 'calling\\n%s\\n%s\\n' \"$PWD\" \"$n\" > \"$f\""
          }
        ]
      }
    ],
    "Elicitation": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=~/.claude/status-$PPID; n=$(sed -n '3p' \"$f\" 2>/dev/null); printf 'calling\\n%s\\n%s\\n' \"$PWD\" \"$n\" > \"$f\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=~/.claude/status-$PPID; n=$(sed -n '3p' \"$f\" 2>/dev/null); printf 'working\\n%s\\n%s\\n' \"$PWD\" \"$n\" > \"$f\""
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "printf 'done\\n%s\\n0\\n' \"$PWD\" > ~/.claude/status-$PPID"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "printf 'done\\n%s\\n0\\n' \"$PWD\" > ~/.claude/status-$PPID"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "printf 'error\\n%s\\n0\\n' \"$PWD\" > ~/.claude/status-$PPID"
          }
        ]
      }
    ],
    "CwdChanged": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=~/.claude/status-$PPID; s=$(head -1 \"$f\" 2>/dev/null || echo working); n=$(sed -n '3p' \"$f\" 2>/dev/null); printf '%s\\n%s\\n%s\\n' \"$s\" \"$PWD\" \"$n\" > \"$f\""
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=~/.claude/status-$PPID; s=$(head -1 \"$f\" 2>/dev/null || echo working); p=$(sed -n '2p' \"$f\" 2>/dev/null || echo \"$PWD\"); n=$(sed -n '3p' \"$f\" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s\\n%s\\n%s\\n' \"$s\" \"$p\" \"$n\" > \"$f\""
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=~/.claude/status-$PPID; s=$(head -1 \"$f\" 2>/dev/null || echo working); p=$(sed -n '2p' \"$f\" 2>/dev/null || echo \"$PWD\"); n=$(sed -n '3p' \"$f\" 2>/dev/null || echo 1); n=$((n - 1)); [ \"$n\" -lt 0 ] && n=0; printf '%s\\n%s\\n%s\\n' \"$s\" \"$p\" \"$n\" > \"$f\""
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "rm -f ~/.claude/status-$PPID"
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

-- Click behavior (set these to your own apps)
spoon.ClaudeStatus.terminalApp = "Terminal"   -- fallback terminal app
spoon.ClaudeStatus.ideApp = "VS Code"         -- IDE to focus on click

-- Colors (hs.drawing.color tables)
spoon.ClaudeStatus.callingColor = { red = 0.851, green = 0.467, blue = 0.341 }
spoon.ClaudeStatus.workingColor = { red = 0.851, green = 0.467, blue = 0.341 }
spoon.ClaudeStatus.errorColor = { red = 1, green = 0.2, blue = 0.2 }

spoon.ClaudeStatus:start()
```

`terminalApp` and `ideApp` default to "Warp" and "Windsurf" respectively — change these to match your setup.

## License

MIT
