import CalmModel
import Testing

struct CalmSettingsKeysTests {
    private func key(_ name: String) throws -> CalmSettings.Key {
        try #require(CalmSettings.key(named: name))
    }

    /// The registry says what the typed accessors do: the same choices, and their defaults when
    /// config.toml is empty. A choice added to an enum and not here would fail.
    @Test func `each key's default and choices are what Calm reads`() throws {
        let empty = CalmSettings()
        #expect(try key("motion").defaultValue == empty.motion.rawValue)
        #expect(try key("ui-size").defaultValue == empty.interfaceSize.rawValue)
        #expect(try key("window.background").defaultValue == empty.windowBackground.rawValue)
        #expect(try key("window.layout").defaultValue == empty.windowLayout.rawValue)
        #expect(try key("session-cards").defaultValue == empty.sessionCardSize.rawValue)
        #expect(try key("agents.notify").defaultValue == empty.notifyStates.rawValue)
        #expect(try key("session-cards-fit").defaultValue == String(empty.sessionCardsFit))
        #expect(try key("sidebar.footer").defaultValue == String(empty.sidebarFooter))
        #expect(try key("auto-grouping").defaultValue == String(empty.autoGrouping))
        #expect(try key("agents.sound").defaultValue == String(empty.notificationSound))
        #expect(try key("motion").kind == .choice(CalmSettings.MotionLevel.allCases.map(\.rawValue)))
    }

    @Test func `keys are found by name, and unknown ones aren't`() {
        #expect(CalmSettings.key(named: "Motion")?.name == "motion")
        #expect(CalmSettings.key(named: "motoin") == nil)
        #expect(Set(CalmSettings.keys.map(\.name)).count == CalmSettings.keys.count)
    }

    @Test func `a value is written as Settings writes it, and the default removes the key`() throws {
        #expect(try CalmSettings.change("reduced", for: key("motion")) == .success(.write("reduced")))
        #expect(try CalmSettings.change("FULL", for: key("motion")) == .success(.remove))
        #expect(try CalmSettings.change("on", for: key("agents.sound")) == .success(.write("true")))
        #expect(try CalmSettings.change("no", for: key("agents.sound")) == .success(.remove))
        #expect(try CalmSettings.change("false", for: key("auto-grouping")) == .success(.write("false")))
    }

    @Test func `a value a key doesn't take says what it takes`() throws {
        let motion = try key("motion")
        let sound = try key("agents.sound")
        #expect(CalmSettings.change("fast", for: motion) == .failure(CalmSettings.KeyError(key: motion, value: "fast")))
        #expect(CalmSettings.KeyError(key: motion, value: "fast").description == "motion can't be 'fast': it takes full, reduced or off")
        #expect(CalmSettings.KeyError(key: sound, value: "maybe").description == "agents.sound can't be 'maybe': it takes true or false")
    }

    @Test func `a theme is written by its own name, even the default one`() throws {
        let theme = try key("theme")
        let themes = ["Calm", "Ink", "Paper"]
        #expect(CalmSettings.change("ink", for: theme, themes: themes) == .success(.write("Ink")))
        #expect(CalmSettings.change("calm", for: theme, themes: themes) == .success(.write("Calm")))
        #expect(CalmSettings.change("Nord", for: theme, themes: themes)
            == .failure(CalmSettings.KeyError(key: theme, value: "Nord", among: themes)))
        // Without the list of themes (a calm outside an app), any name is taken.
        #expect(CalmSettings.change("Nord", for: theme) == .success(.write("Nord")))
    }

    @Test func `an editor by name, an app by path, or automatic`() throws {
        let editor = try key("editor")
        #expect(CalmSettings.change("Cursor", for: editor) == .success(.write("cursor")))
        #expect(CalmSettings.change("/Applications/Nova.app", for: editor) == .success(.write("/Applications/Nova.app")))
        #expect(CalmSettings.change("automatic", for: editor) == .success(.remove))
        #expect(CalmSettings.change("notepad", for: editor) == .failure(CalmSettings.KeyError(key: editor, value: "notepad")))
    }

    @Test func `the value in force is config.toml's, else the default`() throws {
        let settings = CalmSettings(text: "motion = \"reduced\"\n[agents]\nsound = true\n")
        #expect(try settings.value(of: key("motion")) == "reduced")
        #expect(try settings.value(of: key("agents.sound")) == "true")
        #expect(try settings.value(of: key("ui-size")) == "standard")
        // An unset theme has no value (the Ghostty config's colors, else Calm): a script reads "".
        #expect(try settings.value(of: key("theme")).isEmpty)
    }
}
