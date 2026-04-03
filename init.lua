--- === ClaudeMenuBarStatus ===
---
--- Per-session menu bar status indicator for Claude Code.
---
--- Each active Claude Code session gets its own menu bar item showing the
--- working directory name and a status indicator:
---   - Animated ASCII spinner (· ✻ ✽ ✶ ✳ ✢) = working (Claude is processing)
---   - ✳ with orange background = calling (Claude needs user input)
---   - ✳ = done (Claude finished its turn)
---   - x = error (something went wrong)
---
--- Status is driven by Claude Code hooks that write to ~/.claude/status-<pid> files.
--- Each file contains three lines: the status, the working directory, and the subagent count.
---
--- Clicking a menu bar item focuses the IDE window for that project.
---
--- Required Claude Code hooks in ~/.claude/settings.json:
---   - SessionStart: cleans up dead PID status files
---   - UserPromptSubmit: writes "working"
---   - PermissionRequest: writes "calling"
---   - Elicitation: writes "calling"
---   - PostToolUse: writes "working"
---   - PostToolUseFailure: writes "done"
---   - Stop: writes "done"
---   - StopFailure: writes "error"
---   - CwdChanged: updates working directory
---   - SubagentStart: increments subagent count
---   - SubagentStop: decrements subagent count
---   - SessionEnd: deletes status file

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ClaudeMenuBarStatus"
obj.version = "1.0"
obj.author = "Francis Rupert"
obj.license = "MIT"

--- ClaudeMenuBarStatus.statusDir
--- Variable
--- Directory where Claude Code status files are stored. Default: ~/.claude
obj.statusDir = os.getenv("HOME") .. "/.claude"

--- ClaudeMenuBarStatus.pollInterval
--- Variable
--- Seconds between full status file scans. Compensates for missed pathwatcher events. Default: 2
obj.pollInterval = 2

--- ClaudeMenuBarStatus.animInterval
--- Variable
--- Seconds between animation frame changes for the "working" state. Default: 0.3
obj.animInterval = 0.3

--- ClaudeMenuBarStatus.debounceSeconds
--- Variable
--- Seconds a "calling" status must persist before showing yellow.
--- Filters out brief flickers from auto-approved tool permission requests. Default: 2
obj.debounceSeconds = 2

--- ClaudeMenuBarStatus.dotFont
--- Variable
--- Font used for the status indicator character. Default: { name = "Menlo", size = 10 }
obj.dotFont = { name = "Menlo", size = 10 }

--- ClaudeMenuBarStatus.statusDots
--- Variable
--- ASCII characters for non-animated states. Keys: "calling", "done", "error".
obj.statusDots = {
    calling = "✳",
    done    = "✳",
    error   = "x",
}

--- ClaudeMenuBarStatus.workingFrames
--- Variable
--- Array of ASCII characters that cycle to animate the "working" state.
obj.workingFrames = { "·", "✻", "✽", "✶", "✳", "✢" }

--- ClaudeMenuBarStatus.callingColor
--- Variable
--- hs.drawing.color table for the "calling" state background. Default: #d97757
obj.callingColor = { red = 0.851, green = 0.467, blue = 0.341 }

--- ClaudeMenuBarStatus.workingColor
--- Variable
--- hs.drawing.color table for the "working" state text. Default: #d97757
obj.workingColor = { red = 0.851, green = 0.467, blue = 0.341 }

--- ClaudeMenuBarStatus.errorColor
--- Variable
--- hs.drawing.color table for the "error" state text. Default: red
obj.errorColor = { red = 1, green = 0.2, blue = 0.2 }

--- ClaudeMenuBarStatus.terminalApp
--- Variable
--- Name of the terminal application to activate on menu bar click. Default: "Warp"
obj.terminalApp = "Warp"

--- ClaudeMenuBarStatus.ideApp
--- Variable
--- Name of the IDE application to focus on menu bar click. Default: "Windsurf"
obj.ideApp = "Windsurf"

-- Internal state (not user-configurable)
obj.homePath = os.getenv("HOME")
obj.menuItems = {}
obj.sessions = {}
obj.workingFrame = 1
obj.watcher = nil
obj.pollTimer = nil
obj.animTimer = nil

--- ClaudeMenuBarStatus:styledTitle(dot, label, color) -> hs.styledtext
--- Method
--- Build a styled menu bar title with a small dot and a label, optionally colored.
---
--- Parameters:
---  * dot - emoji string for the status indicator
---  * label - directory name string
---  * color - optional hs.drawing.color table applied to both dot and label
---
--- Returns:
---  * hs.styledtext object
function obj:styledTitle(dot, label, color, bgColor)
    local dotStyle = { font = self.dotFont, baselineOffset = 2 }
    local labelStyle = { font = self.font }
    if color then
        dotStyle.color = color
        labelStyle.color = color
    end
    if bgColor then
        dotStyle.backgroundColor = bgColor
        labelStyle.backgroundColor = bgColor
    end
    local padStyle = { font = self.font }
    if color then padStyle.color = color end
    if bgColor then padStyle.backgroundColor = bgColor end
    return hs.styledtext.new("\u{2004}", padStyle) .. hs.styledtext.new(dot, dotStyle) .. hs.styledtext.new(" ", labelStyle) .. hs.styledtext.new(label .. "\u{2004}", labelStyle)
end

--- ClaudeMenuBarStatus:dirLabel(pwd, agents) -> string
--- Method
--- Extract a short display name from a full directory path.
--- Returns "~" for the home directory, or the basename otherwise.
--- Prepends agent count if > 0 (e.g., "×3 dialtone").
---
--- Parameters:
---  * pwd - full directory path, or nil
---  * agents - number of active subagents, or nil
---
--- Returns:
---  * string label for the menu bar
function obj:dirLabel(pwd, agents)
    local name
    if not pwd or pwd == "" then name = "claude"
    elseif pwd == self.homePath then name = "~"
    else name = pwd:match("([^/]+)$") or "claude"
    end
    if agents and agents > 0 then
        name = "×" .. agents .. " " .. name
    end
    return name
end

--- ClaudeMenuBarStatus:focusIdeWindow(pwd)
--- Method
--- Focus the IDE window for the given directory by opening it via `open -a`.
--- macOS handles switching to the correct Space automatically.
--- Falls back to activating the IDE app, then the terminal app.
---
--- Parameters:
---  * pwd - full directory path from the Claude session
function obj:focusIdeWindow(pwd)
    if pwd and pwd ~= "" then
        os.execute('open -a "' .. self.ideApp .. '" "' .. pwd .. '"')
    else
        local app = hs.application.find(self.ideApp) or hs.application.find(self.terminalApp)
        if app then app:activate() end
    end
end

--- ClaudeMenuBarStatus:update()
--- Method
--- Scan all status files, update menu bar items, and clean up stale entries.
--- Called by the pathwatcher and poll timer.
---
--- For each ~/.claude/status-<pid> file:
---  1. Remove if the PID is no longer running (dead process cleanup)
---  2. Debounce "calling" state — ignore if less than debounceSeconds old
---     (filters auto-approved PermissionRequest flicker)
---  3. Create or update the corresponding menu bar item
---  4. Remove menu bar items for sessions that no longer have status files
function obj:update()
    local activePids = {}

    local iter, dir = hs.fs.dir(self.statusDir)
    if iter then
        for entry in iter, dir do
            local pid = entry:match("^status%-(%d+)$")
            if pid then
                local path = self.statusDir .. "/" .. entry
                local alive = os.execute("kill -0 " .. pid .. " 2>/dev/null")
                if not alive then
                    os.remove(path)
                else
                    local attrs = hs.fs.attributes(path)
                    local f = io.open(path, "r")
                    if f and attrs then
                        local status = f:read("*l")
                        local pwd = f:read("*l")
                        local agents = tonumber(f:read("*l")) or 0
                        f:close()
                        if status == "calling" and (os.time() - attrs.modification) < self.debounceSeconds then
                            status = self.sessions[pid] and self.sessions[pid].status or "working"
                        end
                        if status and (self.statusDots[status] or status == "working") then
                            activePids[pid] = { status = status, pwd = pwd, agents = agents }
                        end
                    elseif f then
                        f:close()
                    end
                end
            end
        end
    end

    for pid, info in pairs(activePids) do
        if not self.menuItems[pid] then
            self.menuItems[pid] = hs.menubar.new()
            local capturedPid = pid
            self.menuItems[pid]:setClickCallback(function()
                local info = self.sessions[capturedPid]
                self:focusIdeWindow(info and info.pwd)
            end)
        end
        local label = self:dirLabel(info.pwd, info.agents)
        if info.status == "calling" then
            local fg, bg = { black = 1 }, self.callingColor
            local style = { font = self.font, color = fg, backgroundColor = bg }
            local dotStyle = { font = self.dotFont, baselineOffset = 2, color = fg, backgroundColor = bg }
            self.menuItems[pid]:setTitle(
                hs.styledtext.new("\u{2004}", style)
                .. hs.styledtext.new(self.statusDots["calling"], dotStyle)
                .. hs.styledtext.new(" ", style)
                .. hs.styledtext.new(label .. "\u{2004}", style)
            )
        elseif info.status == "working" then
            self.menuItems[pid]:setTitle(self:styledTitle(self.workingFrames[self.workingFrame], label, self.workingColor))
        elseif info.status == "error" then
            self.menuItems[pid]:setTitle(self:styledTitle(self.statusDots["error"], label, self.errorColor))
        else
            self.menuItems[pid]:setTitle(self:styledTitle(self.statusDots["done"], label))
        end
        self.menuItems[pid]:returnToMenuBar()
    end

    self.sessions = activePids

    for pid, menu in pairs(self.menuItems) do
        if not activePids[pid] then
            menu:removeFromMenuBar()
            menu:delete()
            self.menuItems[pid] = nil
        end
    end
end

--- ClaudeMenuBarStatus:animate()
--- Method
--- Advance the working animation frame and update titles for all "working" sessions.
--- Called by the animation timer. No file I/O — only updates menu bar title strings.
function obj:animate()
    self.workingFrame = (self.workingFrame % #self.workingFrames) + 1
    for pid, info in pairs(self.sessions) do
        if info.status == "working" and self.menuItems[pid] then
            self.menuItems[pid]:setTitle(self:styledTitle(self.workingFrames[self.workingFrame], self:dirLabel(info.pwd, info.agents), self.workingColor))
        end
    end
end

--- ClaudeMenuBarStatus:start() -> ClaudeMenuBarStatus
--- Method
--- Start watching for Claude Code status changes.
--- Creates a pathwatcher on the status directory, a poll timer for missed events,
--- and an animation timer for the "working" state.
---
--- Returns:
---  * The ClaudeMenuBarStatus object
function obj:start()
    local function safeUpdate()
        local ok, err = pcall(function() self:update() end)
        if not ok then print("ClaudeMenuBarStatus error: " .. tostring(err)) end
    end
    local function safeAnimate()
        local ok, err = pcall(function() self:animate() end)
        if not ok then print("ClaudeMenuBarStatus animate error: " .. tostring(err)) end
    end

    -- Global refs to prevent garbage collection
    claudeWatcher = hs.pathwatcher.new(self.statusDir, safeUpdate):start()
    claudePollTimer = hs.timer.doEvery(self.pollInterval, safeUpdate)
    claudeAnimTimer = hs.timer.doEvery(self.animInterval, safeAnimate)

    self.watcher = claudeWatcher
    self.pollTimer = claudePollTimer
    self.animTimer = claudeAnimTimer

    safeUpdate()
    return self
end

--- ClaudeMenuBarStatus:stop() -> ClaudeMenuBarStatus
--- Method
--- Stop all watchers, timers, and remove all menu bar items.
---
--- Returns:
---  * The ClaudeMenuBarStatus object
function obj:stop()
    if self.watcher then self.watcher:stop() end
    if self.pollTimer then self.pollTimer:stop() end
    if self.animTimer then self.animTimer:stop() end
    for pid, menu in pairs(self.menuItems) do
        menu:removeFromMenuBar()
        menu:delete()
    end
    self.menuItems = {}
    self.sessions = {}
    return self
end

return obj
