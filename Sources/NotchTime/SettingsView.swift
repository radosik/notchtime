import SwiftUI
import NotchTimeCore

struct SettingsView: View {
    @ObservedObject var store: TimeStore
    @State private var newClient = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Name on reports")
                HStack(spacing: 10) {
                    TextField("Radomyr", text: Binding(get: { store.reportName }, set: { store.reportName = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Text("→ Time_Report_Summary_\(store.reportName.isEmpty ? "…" : store.reportName)_01_09_2026-30_09_2026.xlsx")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Clients")

                HStack(spacing: 8) {
                    Text("Client").frame(width: 150, alignment: .leading)
                    Text("$ / hour").frame(width: 70, alignment: .leading)
                    Text("Projects (comma separated)").frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(width: 24, height: 1)
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textFaint)

                VStack(spacing: 6) {
                    ForEach(store.clients) { c in
                        ClientRow(client: c, store: store)
                    }
                }

                HStack(spacing: 8) {
                    TextField("New client (e.g. JOSH)", text: $newClient)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit(addClient)
                    Button("Add", action: addClient)
                        .buttonStyle(PillowButtonStyle(tint: .cloud, size: 12, horizontal: 14, vertical: 5))
                        .disabled(newClient.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
                .padding(.top, 4)
            }

            Text(store.fileURL.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: 560)
        .background(Theme.surface.ignoresSafeArea())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.text)
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
        HStack(spacing: 8) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            TextField("20", text: $rate)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Solestra, Other", text: $projects)
                .textFieldStyle(.roundedBorder)
            Button {
                store.deleteClient(client.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .contentShape(Circle())
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
