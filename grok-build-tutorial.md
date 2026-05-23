# Grok Build TUI — Complete Tutorial

**A practical, end-to-end guide to mastering the Grok Build Terminal User Interface for software engineering.**

This tutorial is written from real usage experience on projects like [Aegis](https://github.com) (air-gapped AI platform deployment engine). It combines official documentation with battle-tested workflows.

---

## 1. What is Grok Build?

Grok Build is xAI’s **terminal-first AI coding assistant**. It runs as a rich TUI that can:

- Read and understand your entire codebase
- Run shell commands, edit files, search the web
- Maintain long-term memory across sessions
- Delegate work to specialized sub-agents
- Follow project-specific rules (`AGENTS.md`)
- Use reusable **Skills** (codified workflows)
- Work in Plan Mode before making changes
- Integrate with IDEs via the Agent Client Protocol (ACP)

It supports three main modes of operation:

| Mode          | Use Case                              | Command                  |
|---------------|---------------------------------------|--------------------------|
| **TUI**       | Interactive daily coding              | `grok`                   |
| **Headless**  | Scripting, CI/CD, automation          | `grok -p "..."`          |
| **Agent Mode**| IDE integration (Zed, Neovim, etc.)   | `grok agent stdio`       |

---

## 2. Installation & Authentication

### Install

```bash
# macOS / Linux
curl -fsSL https://x.ai/cli/install.sh | bash

# Specific version
curl -fsSL https://x.ai/cli/install.sh | bash -s 0.1.42
```

Verify:

```bash
grok --version
grok update
```

### First Launch & Authentication

```bash
grok
```

On first run it opens a browser for authentication with grok.com. Credentials are stored in `~/.grok/auth.json`.

**For CI / headless / no-browser environments**, use an API key:

```bash
export XAI_API_KEY="xai-..."
grok -p "Hello"
```

---

## 3. The TUI Interface

When you run `grok`, you get a full-screen TUI with two panes:

- **Scrollback** (top): Conversation history, tool calls, file edits, thinking traces.
- **Prompt** (bottom): Where you type.

**Navigation basics**:
- `Tab` / `Esc` — Toggle between prompt and scrollback
- When scrollback is focused: `j`/`k` (or arrows) to move between entries
- `Enter` (in prompt) — Send message
- `Ctrl+C` — Cancel current generation

Use `@` to attach files or directories:

```
@src/main.go
@internal/generator/generator.go:80-120
@manifests/k8s/
```

---

## 4. Keyboard Shortcuts & Input Modes

Grok supports two navigation styles:

### Simple Mode (default)
- Arrow keys for navigation
- Any printable key focuses the prompt

### Vim Mode (recommended for heavy users)

Enable it permanently:

```toml
# ~/.grok/config.toml
[ui]
vim_mode = true
```

Or toggle live with:

```
/vim-mode
```

**Key Vim bindings (scrollback focused)**:

| Keys       | Action                          |
|------------|---------------------------------|
| `j` / `k`  | Next / previous entry           |
| `h` / `l`  | Collapse / expand entry         |
| `e`        | Toggle fold                     |
| `⇧E`       | Expand / collapse all           |
| `g` / `G`  | Top / bottom of scrollback      |
| `⇧L` / `⇧H`| Jump to next / previous user turn |
| `y`        | Copy block content              |
| `r`        | Toggle raw markdown             |
| `Enter`    | Open in fullscreen viewer       |

See the full reference in `~/.grok/docs/user-guide/03-keyboard-shortcuts.md`.

---

## 5. Essential Slash Commands

Type `/` in the prompt to access commands. Important ones:

### Session & Context
| Command              | Description |
|----------------------|-------------|
| `/new`               | Start a fresh session |
| `/load` or `/resume` | Browse or load previous sessions |
| `/compact [hint]`    | Compress history (very useful on long sessions) |
| `/session-info`      | Show current session ID, token usage, etc. |
| `/flush`             | Force rich summary into workspace memory |

### Workflow
| Command              | Description |
|----------------------|-------------|
| `/plan`              | Toggle Plan Mode |
| `/yolo` or `/always-approve` | Toggle auto-approval of tool calls |
| `/multiline`         | Toggle multiline input (`Ctrl+Enter` to send) |

### Advanced
| Command              | Description |
|----------------------|-------------|
| `/model grok-build`  | Switch model |
| `/skillify`          | Capture current workflow as a reusable Skill |
| `/hooks`             | Manage hooks |
| `/memory`            | Open memory browser |

**Pro tip**: Use `/compact "keep Phase 5 architecture decisions and TESTING.md structure"` before long breaks.

---

## 6. Configuration (`~/.grok/config.toml`)

Key useful settings:

```toml
[models]
default = "grok-build"

[ui]
vim_mode = true                    # Highly recommended
simple_mode = true

[session]
auto_compact_threshold_percent = 80   # Compact earlier on long projects

[features]
codebase_indexing = true
lsp_tools = false                  # Enable if you want LSP awareness
```

Full reference: `~/.grok/docs/user-guide/05-configuration.md`

---

## 7. Sessions & Long-Running Work

Grok **automatically** saves every session to `~/.grok/sessions/`.

### Best Practices for Long Projects

1. **Before major breaks**:
   ```bash
   /flush
   /compact keep the important architectural decisions
   ```

2. **Resuming**:
   - Just run `grok` in the project directory — recent sessions appear on the welcome screen.
   - Or use `/load`.

3. **When context feels bloated**:
   - `/compact` with specific instructions about what to preserve.

See also: [grok-build-usage.md](grok-build-usage.md) (Session Hygiene section).

---

## 8. Memory System (`/flush`, Workspace Memory)

Grok has two layers:

- **Session history** — Raw conversation (auto-saved)
- **Memory** — Structured, searchable knowledge across sessions

**Workspace memory** lives at:
`~/.grok/memory/<project-slug>-<hash>/MEMORY.md`

### Key Commands

- `/flush` — Best way to capture important decisions, patterns, and lessons.
- "remember X" — Tells Grok to write something to `MEMORY.md`.
- `/memory` — Browse and edit memory files.

**Recommendation**: At the end of every major phase (or before leaving a project for a while), run `/flush`.

---

## 9. Skills — Reusable Workflows

Skills are the killer feature for repeatability.

A skill is a `SKILL.md` file with YAML frontmatter + step-by-step instructions.

### Using Skills

Grok will automatically suggest or invoke relevant skills when your prompt matches the `description` in the frontmatter.

### Creating Skills

The best way:

```
/skillify
```

Or after finishing a workflow:

```
/skillify "the process we just used to add a new inference engine"
```

Grok will:
- Analyze your recent tool calls and edits
- Walk you through an interview
- Generate a high-quality `SKILL.md`
- Let you choose **Project** (`./.grok/skills/`) or **Personal** (`~/.grok/skills/`)

**Highly recommended**: Turn repetitive processes (adding profiles, updating validation, releasing, etc.) into skills.

---

## 10. Project Rules (`AGENTS.md`)

Place an `AGENTS.md` (or `Claude.md`, `AGENT.md`) at the root of your repo.

Grok automatically reads it and injects the content into every prompt for that project.

This is the single highest-leverage thing you can do for any long-term project.

Example contents:
- Build/test commands
- Architecture conventions
- "Always update TESTING.md when adding features"
- Safety rules
- Preferred patterns

See the [AGENTS.md](AGENTS.md) we created for this project as a real example.

---

## 11. Plan Mode — Think Before You Code

For anything architecturally significant, use **Plan Mode**.

### How to Use

1. Tell Grok:  
   `"Before making changes, enter plan mode and design the approach."`

2. Grok explores the codebase (read-only) and writes a plan to `plan.md` in the session.

3. When ready, it calls `exit_plan_mode`.

4. You review the plan and choose:
   - `a` → Approve and start implementing
   - `x` → Reject and give feedback (plan review mode)

**Use Plan Mode when**:
- Multiple reasonable approaches exist
- High risk of costly rework
- You want to discuss trade-offs first

---

## 12. Subagents & Personas — Parallel Specialized Work

Instead of one agent doing everything, spawn specialized child agents.

### Common Subagent Types

- `explore` — Read-only research agent (great for investigation)
- `plan` — Produces implementation plans
- `general-purpose` — Full capabilities

### Personas (Behavioral Specializations)

- `implementer`
- `reviewer`
- `researcher`
- `test-writer`
- `security-auditor`
- `design-doc-writer`

**Example**:

```
"Spawn an 'explore' subagent to research vLLM deployment patterns in air-gapped K8s, then spawn an 'implementer' persona to write the deployment manifest."
```

Subagents run in their own context windows and can be given different capability modes (`read-only`, `read-write`, `execute`, `all`).

This is one of the most powerful ways to scale complex work.

---

## 13. Advanced Usage

### Headless / Scripting

```bash
# One-shot
grok -p "Run the test suite and summarize failures"

# Named session (stateful)
grok -p "Continue the deployment work" -s aegis-deploy

# Resume most recent
grok -p "What were we doing?" -c
```

### Background Tasks & Monitors

Use the `monitor` tool for long-running processes (logs, CI, etc.).

### Sandbox Mode

```bash
grok --sandbox
```

Runs with restricted filesystem and command execution — useful for experimenting safely.

### IDE Integration (Agent Mode)

```bash
grok agent stdio
```

Used by Zed, Neovim plugins, etc.

---

## 14. Recommended Daily Workflow (Battle-Tested)

1. **Start the day** — Run `grok` in your project. Resume the most relevant session or start fresh with `/new`.
2. **Before big changes** — Consider `/plan` or explicitly ask for Plan Mode.
3. **During complex work** — Use subagents (`explore` + `implementer` + `reviewer`).
4. **At major milestones** — `/flush` + `/compact`.
5. **When you repeat something 2–3 times** — `/skillify` it.
6. **End of phase** — Update `TESTING.md`, `PLAN.md`, and `AGENTS.md` as needed.

See [grok-build-usage.md](grok-build-usage.md) for more refined prompting patterns.

---

## 15. Pro Tips

- **Be explicit with constraints** — "Do not touch the ollama path in this change."
- **Define success criteria** in the prompt.
- **Reference your own docs** — "See AGENTS.md and TESTING.md".
- **Use `/flush` liberally** on long projects.
- **Build a library of Skills** — this is where Grok becomes truly yours.
- **Keep `AGENTS.md` updated** — it pays dividends forever.
- **Use Plan Mode** more than you think you need to.

---

## 16. Further Reading (Official Docs)

All official guides live in:

```
~/.grok/docs/user-guide/
```

Key files:
- `01-getting-started.md`
- `03-keyboard-shortcuts.md`
- `04-slash-commands.md`
- `05-configuration.md`
- `08-skills.md`
- `11-project-rules.md`
- `12-memory.md`
- `15-subagents.md`
- `16-sessions.md`
- `18-plan-mode.md`

---

**This tutorial was captured from extensive real-world usage on the Aegis project (May 2026).**

It is meant to be living — update it as you discover new powerful patterns or as Grok Build evolves.

---

*Created for the Aegis repository. Feel free to adapt for your own projects.*