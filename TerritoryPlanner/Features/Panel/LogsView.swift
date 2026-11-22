import SwiftUI

struct LogsView: View {
    @Environment(PlannerViewModel.self) private var vm
    @State private var filter: LogEntry.Level?
    @State private var autoScroll = true

    private var entries: [LogEntry] {
        guard let filter else { return vm.logs }
        return vm.logs.filter { $0.level == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        Chip(title: "Все", isSelected: filter == nil) { filter = nil }
                        ForEach(LogEntry.Level.allCases) { level in
                            Chip(title: level.title, systemImage: level.systemImage, isSelected: filter == level) {
                                filter = filter == level ? nil : level
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                ShareLink(item: vm.logsAsText, subject: Text("Territory Planner — журнал")) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 34, height: 34)
                }
                .disabled(vm.logs.isEmpty)

                Button(role: .destructive) {
                    withAnimation { vm.clearLogs() }
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 34, height: 34)
                }
                .disabled(vm.logs.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if entries.isEmpty {
                ContentUnavailableView("Журнал пуст", systemImage: "text.alignleft", description: Text("События построения, импорта и воспроизведения появятся здесь."))
                    .frame(maxHeight: 280)
            } else {
                ScrollViewReader { proxy in
                    List(entries) { entry in
                        LogRow(entry: entry)
                            .id(entry.id)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.hairline)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear { scrollToBottom(proxy, animated: false) }
                    .onChange(of: vm.logs.count) { scrollToBottom(proxy, animated: true) }
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard autoScroll, let last = entries.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.level.systemImage)
                .font(.caption)
                .foregroundStyle(entry.level.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text(Formatters.logTimestamp.string(from: entry.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .textSelection(.enabled)
    }
}
