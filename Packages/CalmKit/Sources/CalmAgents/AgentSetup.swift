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

    /// OpenCode 2 runs the agent in a shared background service, so a plugin can't tell which
    /// terminal it belongs to (DESIGNS.md → Agents, open questions). What it does send are its
    /// own attention notifications, which stay off until `attention.notifications` is set.
    var setup: AgentSetup {
        .hint("Calm sees when OpenCode runs. To see when it needs you, set attention.notifications to true in ~/.config/opencode/cli.json.")
    }

    /// Once the user has turned the notifications on there is nothing left to set up.
    func currentSetup(home: URL) -> AgentSetup {
        Self.attentionNotificationsOn(home: home) ? .notifications : setup
    }

    /// Reads `attention.notifications` from `cli.json` (OpenCode 2's settings; it migrates the
    /// old `tui.json` into it). Off is the default, so anything unreadable counts as off. JSON5
    /// tolerates the comments and trailing commas OpenCode's own parser accepts.
    internal static func attentionNotificationsOn(home: URL) -> Bool {
        let url = home.appending(path: ".config/opencode/cli.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data, options: .json5Allowed) as? [String: Any],
              let attention = root["attention"] as? [String: Any]
        else { return false }
        return attention["notifications"] as? Bool == true
    }
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
    /// saw; `ui_prompt_start`/`ui_prompt_end` → needs you and back. Every report also says which
    /// conversation this is (`ctx.sessionManager.getSessionFile()`/`getSessionId()`, read each
    /// time because `/new` and `/resume` change it), so Calm reads that transcript exactly
    /// instead of looking for it. pi awaits handlers, so reports are spawned detached and never
    /// waited for; nothing starts in the factory itself.
    internal static let extensionSource = """
    // \(AgentSetup.marker): reports this pi session's state to Calm, only inside Calm.
    // Delete this file (or use Calm → Agents… → Disconnect) to stop.
    import { spawn } from "node:child_process";

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
      let outcome = "completed";
      pi.on("agent_start", (_event: any, ctx: any) => report(ctx, "working"));
      pi.on("agent_before_settle", (event: any) => {
        outcome = event?.outcome ?? "completed";
      });
      pi.on("agent_settled", (_event: any, ctx: any) =>
        report(ctx, outcome === "error" ? "failed" : outcome === "aborted" ? "idle" : "done"),
      );
      pi.on("ui_prompt_start", (event: any, ctx: any) => report(ctx, "needs-you", event?.title));
      pi.on("ui_prompt_end", (_event: any, ctx: any) => report(ctx, "working"));
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
}
