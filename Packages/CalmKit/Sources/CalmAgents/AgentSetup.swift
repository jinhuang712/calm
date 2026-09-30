import CalmModel
import Foundation

/// How an agent connects to Calm, for the Agents panel (FEATURES.md → F5, DESIGNS.md → Agents).
public enum AgentSetup: Sendable, Equatable {
    /// Connected inside Calm with nothing written to the agent's own settings.
    case automatic
    /// Calm reads the notifications the agent already sends; nothing to set up.
    case notifications
    /// Files Calm may add to the agent's config folder, with the user's consent. Paths are
    /// relative to the home folder; each file carries `AgentSetup.marker` so Calm only ever
    /// removes files it wrote.
    case files([String: String])
    /// Nothing Calm can safely set up yet; the text says what the user can do.
    case hint(String)

    /// The line every file Calm writes into another tool's config contains.
    public static let marker = "Written by Calm Terminal"
}

public extension AgentAdapter {
    var configFolder: String? {
        nil
    }

    var setup: AgentSetup {
        .notifications
    }

    /// How the agent connects right now, for agents whose own config decides it. Most don't.
    func currentSetup(home _: URL) -> AgentSetup {
        setup
    }
}

public extension ClaudeCodeAdapter {
    var configFolder: String? {
        ".claude"
    }

    var setup: AgentSetup {
        .automatic
    }
}

public extension CodexAdapter {
    var configFolder: String? {
        ".codex"
    }
}

public extension OpenCodeAdapter {
    var configFolder: String? {
        ".config/opencode"
    }

    var setup: AgentSetup {
        .files([".config/opencode/plugins/calm/tui.ts": Self.pluginSource])
    }

    /// An OpenCode TUI plugin (API read from 2.0.19's source, `@opencode/plugin/tui`). OpenCode 2
    /// runs the agent in one shared background service whose environment is whichever terminal
    /// started it, so a server plugin can't tell which Calm session a report is for. A TUI plugin
    /// runs in the terminal's own `opencode` process, with that terminal's `CALM_*` variables,
    /// and the folder holds only `tui.ts`, so the service never loads it (it looks for `server`
    /// or `index`).
    ///
    /// The TUI hears every session's events, so it reports only those of the session on its own
    /// screen (`ui.router.current()`): a turn of that session itself (not a subagent's) for
    /// working, done, failed and interrupted, and any ask under it (a permission or a question,
    /// also a subagent's) for needs you, back to working once all are answered. Every report names
    /// the session, so Calm follows `/new` and tells two OpenCodes in one folder apart. Handlers
    /// run inside the TUI's event batch, so reports are spawned detached; anything unexpected is
    /// skipped quietly.
    ///
    /// It also keeps a running OpenCode in Calm's theme: Calm rewrites `themes/calm.json` (two
    /// folders up) when its theme or the appearance changes (`AgentSetupFiles.syncTheme`), and
    /// OpenCode re-reads its themes on SIGUSR2 (2.0.19's `subscribeRefresh`), so the plugin sends
    /// its own process one, only while OpenCode listens for it: unhandled, SIGUSR2 ends a process.
    internal static let pluginSource = """
    // \(AgentSetup.marker): reports this OpenCode session's state to Calm and follows Calm's theme, only inside Calm.
    // Delete this folder (or use Calm → Agents… → Disconnect) to stop.
    import { spawn } from "node:child_process";
    import { watch } from "node:fs";
    import { fileURLToPath } from "node:url";

    export default {
      id: "calm",
      setup(context: any) {
        const cli = process.env.CALM_CLI;
        if (!cli || !process.env.CALM_SESSION_ID) return;
        const database = `${process.env.HOME}/.local/share/opencode/opencode.db`;
        // The root of the session on screen, or nothing on the home page.
        const current = (): string | undefined => {
          try {
            const route = context.ui.router.current();
            return route?.type === "session" ? context.data.session.root(route.sessionID) : undefined;
          } catch {
            return undefined;
          }
        };
        const report = (session: string, state: string, message?: string) => {
          try {
            const args = ["status", "--agent", "openCode", "--agent-session", session, "--transcript", database, state];
            if (message) args.push(String(message).slice(0, 300));
            spawn(cli, args, { stdio: "ignore", detached: true }).unref();
          } catch {}
        };
        // A turn of the session on screen itself, not of a subagent under it.
        const turn = (sessionID: string | undefined, state: string, message?: string) => {
          const session = current();
          if (session && sessionID === session) report(session, state, message);
        };
        // An ask anywhere under the session on screen; answered once none is left.
        const asks = new Set<string>();
        const ask = (sessionID: string | undefined, id: string | undefined, message: string) => {
          const session = current();
          if (!session || !sessionID || !id) return;
          try {
            if (context.data.session.root(sessionID) !== session) return;
          } catch {
            return;
          }
          asks.add(id);
          report(session, "needs-you", message);
        };
        const answered = (id: string | undefined) => {
          const session = current();
          if (!id || !asks.delete(id) || !session || asks.size > 0) return;
          report(session, "working");
        };
        const listen = (type: string, handler: (data: any) => void) => {
          try {
            return context.data.on(type, (event: any) => {
              try {
                handler(event?.data ?? {});
              } catch {}
            });
          } catch {
            return () => {};
          }
        };
        // Calm's theme file changed: OpenCode reloads its themes on SIGUSR2, if it still listens.
        const followTheme = () => {
          try {
            let timer: any;
            const folder = fileURLToPath(new URL("../../themes/", import.meta.url));
            const watcher = watch(folder, (_event: string, name: string | null) => {
              if (name && name !== "calm.json") return;
              clearTimeout(timer);
              timer = setTimeout(() => {
                try {
                  if (process.listenerCount("SIGUSR2") > 0) process.kill(process.pid, "SIGUSR2");
                } catch {}
              }, 200);
            });
            return () => {
              clearTimeout(timer);
              watcher.close();
            };
          } catch {
            return () => {};
          }
        };
        const dispose = [
          followTheme(),
          listen("session.execution.started", (data) => turn(data.sessionID, "working")),
          listen("session.execution.succeeded", (data) => turn(data.sessionID, "done")),
          listen("session.execution.failed", (data) => turn(data.sessionID, "failed", data.error?.message)),
          listen("session.execution.interrupted", (data) => turn(data.sessionID, "idle")),
          listen("permission.asked", (data) =>
            ask(data.sessionID, data.id, typeof data.action === "string" ? `Allow ${data.action}` : "Needs permission"),
          ),
          listen("permission.replied", (data) => answered(data.requestID)),
          listen("form.created", (data) => ask(data.form?.sessionID, data.form?.id, data.form?.title ?? "Needs an answer")),
          listen("form.replied", (data) => answered(data.id)),
          listen("form.cancelled", (data) => answered(data.id)),
        ];
        return () => dispose.reverse().forEach((cleanup) => cleanup());
      },
    };

    """
}

public extension PiAdapter {
    var configFolder: String? {
        ".pi/agent"
    }

    var setup: AgentSetup {
        .files([".pi/agent/extensions/calm.ts": Self.extensionSource])
    }

    /// A pi extension (API checked against pi 0.87.1's `extensions/types.d.ts`): `agent_start`
    /// → working; `agent_settled` → done, failed or idle by the outcome `agent_before_settle`
    /// saw; `ui_prompt_start`/`ui_prompt_end` → needs you and back, but only for a prompt that
    /// opens during a run (pi reports every `ctx.ui.custom`, a passive overlay included, as a
    /// prompt; one opened at `session_start` would otherwise read as needs you from the first
    /// moment, and its end as a working nobody asked for). Every report also says which
    /// conversation this is (`ctx.sessionManager.getSessionFile()`/`getSessionId()`, read each
    /// time because `/new` and `/resume` change it), so Calm reads that transcript exactly
    /// instead of looking for it. pi awaits handlers, so reports are spawned detached and never
    /// waited for; nothing starts in the factory itself.
    ///
    /// It also dresses pi in Calm's theme (`themes/calm.json`, which Calm keeps to the colors on
    /// screen, see `PiTheme`), when pi's own is one of its built-ins (`system`, `dark`, `light`):
    /// a theme the user made stays. Read against 0.99.1's source: `ctx.ui.setTheme` with a name
    /// also saves it to `settings.json`, which would carry Calm's theme outside Calm, so the
    /// extension builds pi's theme object from the file with the class of the theme in use and
    /// sets that, which isn't saved, and which pi leaves alone when the terminal's colors or
    /// appearance change (`reapplyForTerminal`). pi doesn't watch an object's file, so the
    /// extension watches `themes/` and sets the theme again when Calm rewrites it. `/reload`,
    /// `/new`, `/resume` and `/fork` emit `session_start` and then call
    /// `themeController.applyFromSettings()`, which puts the setting's theme back a few
    /// milliseconds later (seen on 0.99.1: `dark` 10 ms after `session_start`), so for two
    /// seconds after each `session_start` the extension looks every 10 ms and sets Calm's again
    /// where pi's has taken its place. It stops its watcher at `session_shutdown`, because a
    /// reload runs the file again.
    internal static let extensionSource = """
    // \(AgentSetup.marker): reports this pi session's state to Calm and dresses it in Calm's theme, only inside Calm.
    // Delete this file (or use Calm → Agents… → Disconnect) to stop.
    import { spawn } from "node:child_process";
    import { readFileSync, watch } from "node:fs";
    import { join } from "node:path";

    export default function (pi: any) {
      const cli = process.env.CALM_CLI;
      if (!cli || !process.env.CALM_SESSION_ID) return;
      const conversation = (ctx: any): string[] => {
        try {
          const file = ctx?.sessionManager?.getSessionFile?.();
          const id = ctx?.sessionManager?.getSessionId?.();
          return [...(file ? ["--transcript", file] : []), ...(id ? ["--agent-session", id] : [])];
        } catch {
          return [];
        }
      };
      const report = (ctx: any, state: string, message?: string) => {
        try {
          const args = ["status", "--agent", "pi", ...conversation(ctx), state];
          if (message) args.push(message);
          spawn(cli, args, { stdio: "ignore", detached: true }).unref();
        } catch {}
      };
      // Calm's theme, set as a theme object (by name pi would save it to settings.json), and
      // again whenever Calm rewrites its file. pi's built-ins give way; a theme of the user's stays.
      const themes = join(process.env.PI_CODING_AGENT_DIR || join(process.env.HOME ?? "", ".pi", "agent"), "themes");
      // pi's background roles (0.99.1's BACKGROUND_TOKENS); every other color is a foreground.
      const backgrounds = new Set([
        "selectedBg", "searchMatchBg", "userMessageBg", "customMessageBg", "toolPendingBg", "toolSuccessBg", "toolErrorBg",
      ]);
      const builtIn = new Set(["system", "dark", "light", "calm"]);
      let ui: any;
      const wearCalm = () => {
        try {
          const current = ui?.theme;
          if (!current || typeof ui.setTheme !== "function" || !builtIn.has(current.name)) return;
          const file = JSON.parse(readFileSync(join(themes, "calm.json"), "utf8"));
          const fg: any = {};
          const bg: any = {};
          for (const [key, value] of Object.entries(file.colors ?? {})) (backgrounds.has(key) ? bg : fg)[key] = value;
          ui.setTheme(new current.constructor(fg, bg, current.mode, { name: "calm", appearance: file.appearance }));
        } catch {}
      };
      // /reload, /new, /resume and /fork all end in pi putting its own theme back, a few
      // milliseconds after session_start (0.99.1: themeController.applyFromSettings()), so
      // look again for a moment and set Calm's wherever pi's has taken its place.
      let settling: any;
      const wearCalmAgain = () => {
        clearInterval(settling);
        let ticks = 0;
        settling = setInterval(() => {
          try {
            if (ui?.theme?.name !== "calm") wearCalm();
          } catch {}
          if (++ticks >= 200) clearInterval(settling);
        }, 10);
        settling.unref();
      };
      let watcher: any;
      let timer: any;
      pi.on("session_start", (_event: any, ctx: any) => {
        if (!ctx?.hasUI) return;
        ui = ctx.ui;
        wearCalm();
        wearCalmAgain();
        if (watcher) return;
        try {
          watcher = watch(themes, (_type: string, name: string | null) => {
            if (name && name !== "calm.json") return;
            clearTimeout(timer);
            timer = setTimeout(wearCalm, 150);
          });
          watcher.unref();
        } catch {}
      });
      // A reload runs this file again; the watcher of this run would stay behind.
      pi.on("session_shutdown", () => {
        clearInterval(settling);
        clearTimeout(timer);
        try {
          watcher?.close();
        } catch {}
        watcher = undefined;
      });
      let outcome = "completed";
      // A prompt holds the agent up only during a run. Outside one it is the user's own doing
      // (a slash command's picker) or an extension's passive overlay, which pi also reports as
      // a prompt and which stays open for good: pi-briefly opens one when a session starts.
      let running = false;
      let asked = false;
      pi.on("agent_start", (_event: any, ctx: any) => {
        running = true;
        asked = false;
        report(ctx, "working");
      });
      pi.on("agent_before_settle", (event: any) => {
        outcome = event?.outcome ?? "completed";
      });
      pi.on("agent_settled", (_event: any, ctx: any) => {
        running = false;
        asked = false;
        report(ctx, outcome === "error" ? "failed" : outcome === "aborted" ? "idle" : "done");
      });
      pi.on("ui_prompt_start", (event: any, ctx: any) => {
        if (!running) return;
        asked = true;
        report(ctx, "needs-you", event?.title);
      });
      pi.on("ui_prompt_end", (_event: any, ctx: any) => {
        if (!asked) return;
        asked = false;
        if (running) report(ctx, "working");
      });
    }

    """
}

/// Installs and removes an agent's setup files. Never overwrites or removes a file Calm didn't write.
public enum AgentSetupFiles {
    public enum State: Equatable, Sendable {
        case notInstalled
        case connected
        /// A file is in the way that Calm didn't write.
        case conflict(String)
    }

    public static func state(of files: [String: String], home: URL) -> State {
        var present = 0
        for path in files.keys.sorted() {
            let url = home.appending(path: path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard text.contains(AgentSetup.marker) else { return .conflict(path) }
            present += 1
        }
        return present == files.count ? .connected : .notInstalled
    }

    public static func install(_ files: [String: String], home: URL) throws {
        if case let .conflict(path) = state(of: files, home: home) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: path])
        }
        for (path, contents) in files {
            let url = home.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Brings files Calm wrote earlier (the user connected the agent) up to date with this
    /// version's contents. Only a file that carries the marker and differs is rewritten; one
    /// that isn't there, or that the user made, is left alone. Returns the paths rewritten.
    @discardableResult
    public static func refresh(_ files: [String: String], home: URL) throws -> [String] {
        var rewritten: [String] = []
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            let url = home.appending(path: path)
            guard let current = try? String(contentsOf: url, encoding: .utf8), current.contains(AgentSetup.marker),
                  current != contents
            else { continue }
            try contents.write(to: url, atomically: true, encoding: .utf8)
            rewritten.append(path)
        }
        return rewritten
    }

    public static func remove(_ files: [String: String], home: URL) throws {
        for path in files.keys {
            let url = home.appending(path: path)
            guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains(AgentSetup.marker) else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Keeps an adapter's theme file (`themeFilePath`) in step with the colors on screen: written
    /// while the agent is connected (its setup files are all there) and a Calm theme is on screen,
    /// removed otherwise, so Disconnect or the user's own Ghostty colors take it away. A file there
    /// that Calm didn't write is never touched. Returns whether the file changed.
    @discardableResult
    public static func syncTheme(
        for adapter: any AgentAdapter,
        colors: (colors: CalmTheme.Colors, mode: CalmTheme.Mode)?,
        home: URL,
    ) throws -> Bool {
        guard let path = adapter.themeFilePath else { return false }
        let url = home.appending(path: path)
        let current = try? String(contentsOf: url, encoding: .utf8)
        if let current, !current.contains(AgentSetup.marker) {
            return false
        }
        var connected = false
        if case let .files(files) = adapter.setup {
            connected = state(of: files, home: home) == .connected
        }
        guard connected, let colors, let contents = adapter.themeFile(for: colors.colors, mode: colors.mode) else {
            guard current != nil else { return false }
            try FileManager.default.removeItem(at: url)
            return true
        }
        guard current != contents else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return true
    }
}
