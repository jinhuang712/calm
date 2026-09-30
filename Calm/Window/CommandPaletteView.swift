import SwiftUI

/// The ⌘P command palette: a quiet, centered list of what has no key of its own.
struct CommandPaletteView: View {
    let commands: [PaletteCommand]
    let isDark: Bool
    let onRun: (PaletteCommand) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [PaletteCommand] {
        CommandMatcher.filter(commands, query: query)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                TextField("Run a command", text: $query)
                    .textFieldStyle(.plain)
                    .calmFont(size: 16)
                    .padding(.horizontal, 18.scaled)
                    .frame(height: 50.scaled)
                    .focused($fieldFocused)
                    .onSubmit(runSelection)
                    .onChange(of: query) { selection = 0 }

                Divider().opacity(0.5)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2.scaled) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                                row(command, selected: index == selection)
                                    .onTapGesture { onRun(command) }
                            }
                        }
                        .padding(6.scaled)
                    }
                    .frame(maxHeight: 360.scaled)
                    .onChange(of: selection) {
                        if results.indices.contains(selection) {
                            proxy.scrollTo(results[selection].id, anchor: .center)
                        }
                    }
                }

                if results.isEmpty {
                    Text("No matching command")
                        .calmFont(size: 13)
                        .foregroundStyle(.secondary)
                        .frame(height: 44.scaled)
                }
            }
            .frame(width: 560.scaled)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14.scaled, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14.scaled, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08)),
            )
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .padding(.top, 90.scaled)
        }
        .environment(\.colorScheme, isDark ? .dark : .light)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) {
            Motion.animate(.easeOut(duration: 0.12)) { selection = min(selection + 1, max(results.count - 1, 0)) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            Motion.animate(.easeOut(duration: 0.12)) { selection = max(selection - 1, 0) }
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    /// The selected row says in one short line what it does, under its name; the others are one line.
    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 12.scaled) {
            VStack(alignment: .leading, spacing: 2.scaled) {
                Text(command.title)
                    .calmFont(size: 13, weight: .medium)
                    .foregroundStyle(.primary)
                if selected, !command.detail.isEmpty {
                    Text(command.detail)
                        .calmFont(size: 12)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 12)
            if !command.trailing.isEmpty {
                Text(command.trailing)
                    .calmFont(size: 12)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12.scaled)
        .padding(.vertical, 7.scaled)
        .background(
            RoundedRectangle(cornerRadius: 8.scaled, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.08) : .clear),
        )
        .contentShape(Rectangle())
    }

    private func runSelection() {
        guard results.indices.contains(selection) else { return }
        onRun(results[selection])
    }
}
