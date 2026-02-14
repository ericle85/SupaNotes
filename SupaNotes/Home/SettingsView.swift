import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                HStack {
                    Text("Trash Retention")
                    Spacer()
                    Text("30 days")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
