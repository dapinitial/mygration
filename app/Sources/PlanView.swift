import SwiftUI
import MygrationCore

/// The à-la-carte migration plan: the real Ledger rendered as grouped, toggleable
/// items — each showing HOW it travels. Check what you want; the summary tallies
/// it live. This is DECISIONS-as-UI, driven by real discovery.
struct PlanView: View {
    let ledger: Ledger
    @State private var selected: Set<String> = []
    @State private var items: [PlanItem] = []
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                    ForEach(PlanCat.allCases, id: \.self) { cat in
                        let group = items.filter { $0.cat == cat }
                        if !group.isEmpty { section(cat, group) }
                    }
                }
                .padding(20)
            }
            summaryBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: build)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MIGRATION PLAN").font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(3).foregroundStyle(.secondary)
            Text("Choose what moves to your new Mac")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("\(ledger.machine.host) · \(ledger.machine.arch) → Apple Silicon · pick à la carte")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private func section(_ cat: PlanCat, _ group: [PlanItem]) -> some View {
        Section {
            ForEach(group) { item in row(item) }
        } header: {
            let ids = Set(group.map(\.id)); let on = ids.isSubset(of: selected)
            HStack(spacing: 10) {
                Circle().fill(cat.color).frame(width: 9, height: 9).shadow(color: cat.color, radius: 4)
                Text(cat.label).font(.system(size: 13, weight: .semibold))
                Text("\(group.count)").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Button(on ? "Deselect all" : "Select all") {
                    if on { selected.subtract(ids) } else { selected.formUnion(ids) }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.tint)
            }
            .padding(.vertical, 6).padding(.horizontal, 4)
            .background(.regularMaterial)
        }
    }

    private func row(_ item: PlanItem) -> some View {
        let isOn = selected.contains(item.id)
        return HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.selectable ? .primary : .secondary)
                if let note = item.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(item.warn ? .orange : .secondary)
                }
            }
            Spacer()
            TravelBadge(item.travel)
        }
        .padding(.vertical, 7).padding(.horizontal, 12)
        .background(isOn ? Color.accentColor.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture { guard item.selectable else { return }
            if isOn { selected.remove(item.id) } else { selected.insert(item.id) } }
        .opacity(item.selectable ? 1 : 0.75)
    }

    private var summaryBar: some View {
        let picks = items.filter { selected.contains($0.id) }
        let bytes = picks.reduce(0) { $0 + $1.bytes }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(picks.count) of \(items.filter(\.selectable).count) items")
                    .font(.system(size: 13, weight: .semibold))
                Text(byteLabel(bytes) + " · " + spanLabel(picks))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                running = true
            } label: {
                Label("Migrate selected", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(picks.isEmpty)
        }
        .padding(16)
        .background(.thinMaterial)
        .overlay(Divider().opacity(0.4), alignment: .top)
        .sheet(isPresented: $running) {
            MigrationRunView(source: ledger, selected: selected,
                             targetRoot: Collect.discoverCodeRoots().first ?? (NSHomeDirectory() + "/Sites"))
        }
    }

    // MARK: build items from the real ledger

    private func build() {
        var out: [PlanItem] = []
        func item(_ cat: PlanCat, _ id: String, _ name: String, _ travel: Travel,
                  note: String? = nil, warn: Bool = false, bytes: Int = 0, selectable: Bool = true) {
            out.append(PlanItem(id: "\(cat.rawValue):\(id)", cat: cat, name: name, travel: travel,
                                note: note, warn: warn, bytes: bytes, selectable: selectable))
        }
        for r in ledger.repos {
            item(.repos, r.name, r.name, r.remote != nil ? .git : .manual,
                 note: r.remote == nil ? "no remote — push it first" : (r.dirty ? "uncommitted changes" : nil),
                 warn: r.remote == nil || r.dirty)
        }
        for a in ledger.agents {
            let t: Travel = a.regenerateOnly ? .regenerate : (a.hasSecrets ? .encrypted : .copy)
            item(.agents, a.id, a.name, t,
                 note: [a.hasSecrets ? "holds secrets" : nil, a.pathKeyed ? "re-keyed on restore" : nil,
                        a.reauth.map { "re-auth: \($0)" }].compactMap { $0 }.joined(separator: " · "),
                 bytes: a.bytes)
        }
        for s in ledger.services {
            item(.services, s.id, s.name, s.dataFound.isEmpty ? .reinstall : .dump,
                 note: s.dataFound.isEmpty ? "config travels · daemon reinstalls" : (s.dumpHint ?? "needs a dump"))
        }
        for e in ledger.envFiles { item(.env, e.path, (e.path as NSString).lastPathComponent, .encrypted,
                                         note: e.path, bytes: e.bytes) }
        for k in ledger.keychainRefs { item(.keychain, k.service, k.service, .reauth,
                                             note: "re-enter once on the new Mac", selectable: false) }
        for f in ledger.brew.formulae { item(.brew, "f-"+f.name, f.name, .reinstall) }
        for c in ledger.brew.casks { item(.brew, "c-"+c.name, c.name, .reinstall) }
        items = out
        selected = Set(out.filter { $0.selectable && $0.travel != .manual }.map(\.id))  // sensible default
    }

    private func byteLabel(_ b: Int) -> String {
        b > 1_000_000 ? String(format: "%.1f GB", Double(b)/1e9) : "\(b/1000) KB"
    }
    private func spanLabel(_ picks: [PlanItem]) -> String {
        Dictionary(grouping: picks, by: \.cat).sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value.count) \($0.key.short)" }.joined(separator: ", ")
    }
}

// MARK: - model

enum Travel: String {
    case git = "git clone", encrypted = "encrypted", reinstall = "reinstall native"
    case reauth = "re-auth", regenerate = "regenerate", copy = "copy", dump = "dump", manual = "manual"
    var color: Color {
        switch self {
        case .git: return .cyan; case .encrypted: return .pink; case .reinstall: return .orange
        case .reauth: return .yellow; case .regenerate: return .purple; case .copy: return .green
        case .dump: return .mint; case .manual: return .gray
        }
    }
}

struct TravelBadge: View {
    let t: Travel; init(_ t: Travel) { self.t = t }
    var body: some View {
        Text(t.rawValue).font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(t.color.opacity(0.14), in: Capsule())
            .foregroundStyle(t.color).overlay(Capsule().strokeBorder(t.color.opacity(0.3)))
    }
}

enum PlanCat: String, CaseIterable {
    case repos, agents, services, env, keychain, brew
    var label: String {
        switch self {
        case .repos: return "Repositories"; case .agents: return "AI agents"
        case .services: return "Local services"; case .env: return "Env files"
        case .keychain: return "Keychain secrets"; case .brew: return "Homebrew"
        }
    }
    var short: String {
        switch self { case .repos: return "repos"; case .agents: return "agents"
        case .services: return "services"; case .env: return "env"; case .keychain: return "keys"; case .brew: return "brew" }
    }
    var color: Color {
        switch self {
        case .repos: return .cyan; case .agents: return .purple; case .services: return .orange
        case .env: return .mint; case .keychain: return .pink; case .brew: return .orange
        }
    }
}

struct PlanItem: Identifiable {
    let id: String; let cat: PlanCat; let name: String; let travel: Travel
    let note: String?; let warn: Bool; let bytes: Int; let selectable: Bool
}
