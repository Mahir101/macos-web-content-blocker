import BlockerCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            StatusTab().tabItem { Label("Status", systemImage: "shield") }
            DomainsTab().tabItem { Label("Domains", systemImage: "list.bullet") }
            EventsTab().tabItem { Label("Activity", systemImage: "clock") }
            SettingsTab().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding()
    }
}

// MARK: - Status

private struct StatusTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.accessibilityTrusted {
                    Banner(
                        text: "Accessibility permission is required for monitoring.",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange
                    ) {
                        Button("Grant Access") { model.requestAccessibility() }
                    }
                }

                GroupBox("Service") {
                    VStack(alignment: .leading, spacing: 8) {
                        row("Status", model.config.enabled ? "Protecting" : "Disabled",
                            tint: model.config.enabled ? .green : .red)
                        if let since = model.state.runningSince {
                            row("Running since", since.formatted(date: .abbreviated, time: .shortened))
                        }
                        row("VPN active", model.state.vpnActive ? "Yes (still enforcing)" : "No")
                    }.padding(6)
                }

                GroupBox("Detections") {
                    VStack(alignment: .leading, spacing: 8) {
                        row("Total detections", "\(model.state.detectionsTotal)")
                        if let domain = model.state.lastDetectionDomain {
                            row("Last domain", domain)
                        }
                        if let at = model.state.lastDetectionAt {
                            row("Last detection", at.formatted(date: .abbreviated, time: .standard))
                        }
                        if model.state.inCooldown, let until = model.state.cooldownUntil {
                            row("Cooldown until", until.formatted(date: .omitted, time: .standard), tint: .orange)
                        } else {
                            row("Cooldown", "Inactive")
                        }
                    }.padding(6)
                }
            }
            .padding()
        }
    }
}

// MARK: - Domains

private struct DomainsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var newBlock = ""
    @State private var newAllow = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Custom blocklist") {
                VStack(alignment: .leading) {
                    HStack {
                        TextField("e.g. example.com or *.example.com", text: $newBlock)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            model.addCustomDomain(newBlock); newBlock = ""
                        }.disabled(newBlock.isEmpty)
                    }
                    DomainList(domains: model.customDomains) { model.removeCustomDomain($0) }
                }.padding(6)
            }

            GroupBox("Whitelist (never blocked)") {
                VStack(alignment: .leading) {
                    HStack {
                        TextField("e.g. health.example.com", text: $newAllow)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            model.addWhitelistDomain(newAllow); newAllow = ""
                        }.disabled(newAllow.isEmpty)
                    }
                    DomainList(domains: model.whitelist) { model.removeWhitelistDomain($0) }
                }.padding(6)
            }

            GroupBox("Auto-blocked at runtime (\(model.runtimeDomains.count))") {
                DomainList(domains: model.runtimeDomains, onDelete: nil)
                    .frame(maxHeight: 120)
                    .padding(6)
            }
        }
        .padding()
    }
}

private struct DomainList: View {
    let domains: [String]
    let onDelete: ((String) -> Void)?

    var body: some View {
        if domains.isEmpty {
            Text("None").foregroundStyle(.secondary).padding(.vertical, 4)
        } else {
            List(domains, id: \.self) { domain in
                HStack {
                    Text(domain)
                    Spacer()
                    if let onDelete {
                        Button(role: .destructive) { onDelete(domain) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 80)
        }
    }
}

// MARK: - Events

private struct EventsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Table(model.recentEvents.indices.map { IndexedEvent(id: $0, event: model.recentEvents[$0]) }) {
            TableColumn("Time") { e in
                Text(e.event.timestamp.formatted(date: .omitted, time: .standard))
            }
            TableColumn("Browser") { e in Text(e.event.browser) }
            TableColumn("Domain") { e in Text(e.event.domain ?? "-") }
            TableColumn("Score") { e in Text("\(e.event.score)") }
            TableColumn("Action") { e in Text(e.event.action) }
        }
    }

    struct IndexedEvent: Identifiable { let id: Int; let event: BlockEvent }
}

// MARK: - Settings

private struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var threshold: Double = 100
    @State private var cooldown: Double = 60

    var body: some View {
        Form {
            Section("Detection") {
                VStack(alignment: .leading) {
                    Text("Block threshold: \(Int(threshold))")
                    Slider(value: $threshold, in: 30...200, step: 10) {
                        Text("Threshold")
                    } onEditingChanged: { editing in
                        if !editing { model.updateThreshold(Int(threshold)) }
                    }
                    Text("A known adult domain scores 100. Lower = stricter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("Cooldown: \(Int(cooldown))s")
                    Slider(value: $cooldown, in: 0...300, step: 15) {
                        Text("Cooldown")
                    } onEditingChanged: { editing in
                        if !editing { model.updateCooldown(cooldown) }
                    }
                }
            }

            Section("Protection") {
                DisableControl()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            threshold = Double(model.config.blockThreshold)
            cooldown = model.config.cooldownSeconds
        }
    }
}

private struct DisableControl: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if !model.config.enabled {
            HStack {
                Text("Protection is disabled.").foregroundStyle(.red)
                Spacer()
                Button("Re-enable now") { model.reEnable() }
            }
        } else {
            switch model.disableStatus {
            case .notRequested:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Disabling requires a \(Int(model.config.disableDelayHours))-hour waiting period.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Request disable", role: .destructive) { model.requestDisable() }
                }
            case .waiting(let until):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Disable available \(until.formatted(date: .abbreviated, time: .shortened)).")
                        .foregroundStyle(.orange)
                    Button("Cancel request") { model.cancelDisable() }
                }
            case .readyToConfirm:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting period complete.").foregroundStyle(.orange)
                    HStack {
                        Button("Confirm disable", role: .destructive) { model.confirmDisable() }
                        Button("Cancel") { model.cancelDisable() }
                    }
                }
            }
        }
    }
}

// MARK: - Shared

@MainActor
private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
    HStack {
        Text(label).foregroundStyle(.secondary)
        Spacer()
        Text(value).foregroundStyle(tint)
    }
}

private struct Banner<Action: View>: View {
    let text: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
            Spacer()
            action()
        }
        .padding()
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
