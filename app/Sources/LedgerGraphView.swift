import SwiftUI
import SceneKit
import MygrationCore

/// Native 3D constellation of a machine's Ledger — glowing category clusters
/// orbiting a core, with HDR bloom and built-in camera control (drag to orbit,
/// scroll to zoom). The native cousin of the web star-map.
struct LedgerGraphView: View {
    let ledger: Ledger

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.043, blue: 0.078).ignoresSafeArea()
            SceneKitGraph(ledger: ledger).ignoresSafeArea()
            VStack {
                HStack {
                    GraphHUD(ledger: ledger)
                    Spacer()
                }
                Spacer()
                HStack {
                    GraphLegend(ledger: ledger)
                    Spacer()
                    Text("drag to orbit · scroll to zoom")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(20)
        }
    }
}

// MARK: - graph model

private enum GCat: String, CaseIterable {
    case machine, repo, agent, svc, env, key, brew
    var color: NSColor {
        switch self {
        case .machine: return NSColor(srgbRed: 1.0, green: 0.85, blue: 0.54, alpha: 1)
        case .repo:    return NSColor(srgbRed: 0.22, green: 0.83, blue: 0.81, alpha: 1)
        case .agent:   return NSColor(srgbRed: 0.69, green: 0.55, blue: 1.0, alpha: 1)
        case .svc:     return NSColor(srgbRed: 0.96, green: 0.63, blue: 0.29, alpha: 1)
        case .env:     return NSColor(srgbRed: 0.31, green: 0.85, blue: 0.60, alpha: 1)
        case .key:     return NSColor(srgbRed: 1.0, green: 0.44, blue: 0.57, alpha: 1)
        case .brew:    return NSColor(srgbRed: 1.0, green: 0.54, blue: 0.36, alpha: 1)
        }
    }
    var label: String {
        switch self {
        case .machine: return "Machine"; case .repo: return "Repositories"
        case .agent: return "AI agents"; case .svc: return "Local services"
        case .env: return "Env files"; case .key: return "Keychain secrets"; case .brew: return "Homebrew"
        }
    }
}

private struct GNode { let id: Int; let cat: GCat; let name: String; let r: CGFloat
    let warn: Bool; let secret: Bool; var p: SIMD3<Float> }
private struct GLink { let a: Int; let b: Int }

private func buildGraph(_ L: Ledger) -> ([GNode], [GLink]) {
    var nodes: [GNode] = []; var links: [GLink] = []; var id = 0
    func rnd() -> Float { Float.random(in: -6...6) }
    @discardableResult func add(_ cat: GCat, _ name: String, r: CGFloat,
                                warn: Bool = false, secret: Bool = false) -> Int {
        nodes.append(GNode(id: id, cat: cat, name: name, r: r, warn: warn, secret: secret,
                           p: SIMD3(rnd(), rnd(), rnd()))); defer { id += 1 }; return id
    }
    let core = add(.machine, L.machine.host, r: 1.6)
    var hubs: [GCat: Int] = [:]
    for cat in [GCat.repo, .agent, .svc, .env, .key, .brew] {
        let h = add(cat, cat.label, r: 0.9); links.append(GLink(a: core, b: h)); hubs[cat] = h
    }
    var repoIdx: [String: Int] = [:]
    for r in L.repos { let n = add(.repo, r.name, r: r.dirty ? 0.6 : 0.48, warn: r.dirty)
        links.append(GLink(a: hubs[.repo]!, b: n)); repoIdx[r.name] = n }
    for a in L.agents { let n = add(.agent, a.name, r: 0.5 + min(0.6, CGFloat(a.bytes)/4.5e8), secret: a.hasSecrets)
        links.append(GLink(a: hubs[.agent]!, b: n)) }
    for s in L.services { links.append(GLink(a: hubs[.svc]!, b: add(.svc, s.name, r: 0.55))) }
    for e in L.envFiles { let comps = (e.path as NSString).pathComponents
        let proj = comps.count >= 2 ? comps[comps.count - 2] : ""
        let n = add(.env, (e.path as NSString).lastPathComponent, r: 0.38)
        links.append(GLink(a: hubs[.env]!, b: n))
        if let r = repoIdx.first(where: { proj.contains($0.key) || $0.key.contains(proj) })?.value { links.append(GLink(a: n, b: r)) } }
    for k in L.keychainRefs { let n = add(.key, k.service, r: 0.5, secret: true)
        links.append(GLink(a: hubs[.key]!, b: n))
        let base = k.service.split(separator: "-").first.map(String.init) ?? ""
        if let r = repoIdx.first(where: { $0.key.lowercased().contains(base.lowercased()) })?.value { links.append(GLink(a: n, b: r)) } }
    for f in L.brew.formulae { links.append(GLink(a: hubs[.brew]!, b: add(.brew, f.name, r: 0.34))) }
    for c in L.brew.casks { links.append(GLink(a: hubs[.brew]!, b: add(.brew, c.name, r: 0.42))) }
    forceLayout(&nodes, links)
    return (nodes, links)
}

/// Simple 3D force-directed layout, run to convergence once at build time.
private func forceLayout(_ nodes: inout [GNode], _ links: [GLink]) {
    var pos = nodes.map(\.p); var vel = [SIMD3<Float>](repeating: .zero, count: nodes.count)
    for _ in 0..<400 {
        for i in 0..<pos.count {
            for j in (i+1)..<pos.count {
                var d = pos[i] - pos[j]; let dist2 = max(simd_length_squared(d), 0.01)
                if dist2 > 400 { continue }
                d = simd_normalize(d) * (2.2 / dist2)
                vel[i] += d; vel[j] -= d
            }
        }
        for l in links {
            var d = pos[l.b] - pos[l.a]; let dist = max(simd_length(d), 0.01)
            let f = (dist - 3.0) * 0.02; d = simd_normalize(d) * f
            vel[l.a] += d; vel[l.b] -= d
        }
        for i in 0..<pos.count {
            vel[i] += -pos[i] * 0.004        // gravity to origin
            vel[i] *= 0.85; pos[i] += vel[i]
        }
    }
    for i in 0..<nodes.count { nodes[i].p = pos[i] }
}

// MARK: - SceneKit

private struct SceneKitGraph: NSViewRepresentable {
    let ledger: Ledger
    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = Self.scene(ledger)
        v.allowsCameraControl = true
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        return v
    }
    func updateNSView(_ v: SCNView, context: Context) {}

    static func scene(_ L: Ledger) -> SCNScene {
        let (nodes, links) = buildGraph(L)
        let scene = SCNScene()
        let root = SCNNode(); scene.rootNode.addChildNode(root)

        for n in nodes {
            let sphere = SCNSphere(radius: n.r)
            sphere.segmentCount = 24
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = n.cat.color
            m.emission.contents = n.cat.color   // self-lit → blooms
            sphere.materials = [m]
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(n.p.x, n.p.y, n.p.z)
            root.addChildNode(node)
            if n.secret {   // rose halo ring
                let ring = SCNTorus(ringRadius: n.r + 0.18, pipeRadius: 0.03)
                let rm = SCNMaterial(); rm.lightingModel = .constant
                rm.emission.contents = GCat.key.color; ring.materials = [rm]
                let rnode = SCNNode(geometry: ring); node.addChildNode(rnode)
                rnode.eulerAngles.x = .pi/2
            }
            if n.cat == .machine || n.r > 0.85 { node.addChildNode(textNode(n.name, size: n.r)) }
        }
        // links as thin glowing cylinders
        for l in links {
            let a = nodes[l.a].p, b = nodes[l.b].p
            root.addChildNode(cylinder(from: SCNVector3(a.x,a.y,a.z), to: SCNVector3(b.x,b.y,b.z)))
        }
        // camera + bloom
        let cam = SCNCamera()
        cam.wantsHDR = true; cam.bloomIntensity = 1.4; cam.bloomThreshold = 0.25
        cam.bloomBlurRadius = 14; cam.wantsExposureAdaptation = false
        let camNode = SCNNode(); camNode.camera = cam; camNode.position = SCNVector3(0, 0, 26)
        scene.rootNode.addChildNode(camNode)
        // gentle idle rotation
        root.runAction(.repeatForever(.rotateBy(x: 0, y: .pi*2, z: 0, duration: 90)))
        return scene
    }

    static func textNode(_ s: String, size: CGFloat) -> SCNNode {
        let t = SCNText(string: s, extrusionDepth: 0); t.font = .systemFont(ofSize: 1, weight: .semibold)
        t.flatness = 0.1
        let m = SCNMaterial(); m.lightingModel = .constant; m.emission.contents = NSColor.white
        t.materials = [m]
        let node = SCNNode(geometry: t)
        let s2: Float = 0.35
        node.scale = SCNVector3(s2, s2, s2)
        node.position = SCNVector3(Float(size) + 0.3, Float(size), 0)
        node.constraints = [SCNBillboardConstraint()]   // always face camera
        return node
    }

    static func cylinder(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let v = SCNVector3(b.x-a.x, b.y-a.y, b.z-a.z)
        let len = CGFloat(sqrt(v.x*v.x + v.y*v.y + v.z*v.z))
        let cyl = SCNCylinder(radius: 0.012, height: len)
        let m = SCNMaterial(); m.lightingModel = .constant
        m.emission.contents = NSColor(white: 0.55, alpha: 1); m.transparency = 0.35
        cyl.materials = [m]
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
        node.look(at: b, up: SCNVector3(0,1,0), localFront: SCNVector3(0,1,0))
        return node
    }
}

// MARK: - overlays

private struct GraphHUD: View {
    let ledger: Ledger
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MYGRATION · MACHINE LEDGER")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(3).foregroundStyle(.secondary)
            Text("The Ledger.").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("\(ledger.machine.host)  ·  \(ledger.machine.arch)  ·  macOS \(ledger.machine.macOS)")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GraphLegend: View {
    let ledger: Ledger
    private var counts: [(GCat, Int)] {
        [(.repo, ledger.repos.count), (.agent, ledger.agents.count), (.svc, ledger.services.count),
         (.env, ledger.envFiles.count), (.key, ledger.keychainRefs.count),
         (.brew, ledger.brew.formulae.count + ledger.brew.casks.count)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(counts, id: \.0.rawValue) { cat, n in
                HStack(spacing: 10) {
                    Circle().fill(Color(cat.color)).frame(width: 9, height: 9)
                        .shadow(color: Color(cat.color), radius: 5)
                    Text(cat.label).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Text("\(n)").font(.system(size: 12, design: .monospaced)).monospacedDigit()
                }
            }
        }
        .padding(16).frame(width: 210)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
