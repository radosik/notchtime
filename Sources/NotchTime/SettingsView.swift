import SwiftUI
import NotchTimeCore

struct SettingsView: View {
    @ObservedObject var store: TimeStore
    @State private var newClient = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Name on reports") {
                TextField("Radomyr", text: Binding(get: { store.reportName }, set: { store.reportName = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Text("Used in the export file name: Time_Report_Summary_<name>_01_09_2026-30_09_2026.xlsx")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
            }

            section("Clients") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Client").frame(width: 120, alignment: .leading)
                        Text("$/hour").frame(width: 70, alignment: .leading)
                        Text("Projects (comma separated)").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 24)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textDim)

                    ForEach(store.clients) { c in
                        ClientRow(client: c, store: store)
                    }

                    HStack {
                        TextField("New client (e.g. JOSH)", text: $newClient)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .onSubmit(addClient)
                        Button("Add", action: addClient)
                            .buttonStyle(PillowButtonStyle(tint: .cloud, size: 12, horizontal: 14, vertical: 6))
                            .disabled(newClient.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            Text("Data lives in \(store.fileURL.path)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .textSelection(.enabled)
        }
        .padding(22)
        .frame(minWidth: 520, minHeight: 380)
        .background(Theme.surface.ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            content()
        }
    }

    private func addClient() {
        let name = newClient.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _ = store.addClient(name: name)
        newClient = ""
    }
}

struct ClientRow: View {
    let client: Client
    @ObservedObject var store: TimeStore
    @State private var name: String
    @State private var rate: String
    @State private var projects: String

    init(client: Client, store: TimeStore) {
        self.client = client
        self.store = store
        _name = State(initialValue: client.name)
        _rate = State(initialValue: ClientRow.format(client.hourlyRate))
        _projects = State(initialValue: client.projects.joined(separator: ", "))
    }

    var body: some View {
        HStack {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            TextField("20", text: $rate)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Solestra, Other", text: $projects)
                .textFieldStyle(.roundedBorder)
            Button {
                store.deleteClient(client.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Remove client (entries keep their time, lose the client)")
        }
        .onChange(of: name) { _, _ in commit() }
        .onChange(of: rate) { _, _ in commit() }
        .onChange(of: projects) { _, _ in commit() }
    }

    private func commit() {
        var c = client
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { c.name = trimmed }
        if let r = Double(rate.replacingOccurrences(of: ",", with: ".")) { c.hourlyRate = r }
        c.projects = projects.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.updateClient(c)
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
