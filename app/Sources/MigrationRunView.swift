import SwiftUI
import MygrationCore

/// Live progress of an executing migration — one line per action, with status.
struct MigrationRunView: View {
    let source: Ledger
    let selected: Set<String>
    let targetRoot: String
    @StateObject private var exec = Executor()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exec.done ? "Migration complete" : "Migrating…")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("from \(source.machine.host) → this Mac")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                if !exec.done { Spinner(size: 22) }
            }
            .padding(18)
            Divider().opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(exec.lines) { line in
                            HStack(spacing: 10) {
                                icon(line.status)
                                Text(line.text).font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(line.status == .fail ? .red : .primary)
                                Spacer()
                            }.id(line.id)
                        }
                    }.padding(16)
                }
                .onChange(of: exec.lines.count) { _, _ in
                    if let last = exec.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            Divider().opacity(0.4)
            HStack {
                Text("\(exec.lines.filter { $0.status == .ok }.count) done · \(exec.lines.filter { $0.status == .fail }.count) failed")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button(exec.done ? "Close" : "Run in background") { dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(16)
        }
        .frame(minWidth: 560, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { exec.start(source: source, selected: selected, targetRoot: targetRoot) }
    }

    @ViewBuilder private func icon(_ s: Executor.Line.Status) -> some View {
        switch s {
        case .running: Spinner(size: 14)
        case .ok:   Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .fail: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .info: Image(systemName: "info.circle").foregroundStyle(.blue)
        case .skip: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}
