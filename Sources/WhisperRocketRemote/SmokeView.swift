import SwiftUI

struct SmokeView: View {
    let report: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WhisperRocket Remote — smoke test")
                .font(.headline)
            ForEach(report, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
