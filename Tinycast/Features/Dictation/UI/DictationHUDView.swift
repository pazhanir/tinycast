import SwiftUI

enum DictationHUDState: Equatable {
    case listening
    case transcribing
    case success
    case error(String)
}

struct DictationHUDView: View {
    let state: DictationHUDState
    let audioLevel: Float
    let providerName: String
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // State Icon
            ZStack {
                switch state {
                case .listening:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                case .transcribing:
                    ProgressView()
                        .controlSize(.small)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 20, height: 20)

            // Content / Waveform
            VStack(alignment: .leading, spacing: 2) {
                switch state {
                case .listening:
                    HStack(spacing: 8) {
                        Text("Listening…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        // Live audio waveform bars
                        WaveformBarsView(level: audioLevel)
                            .frame(width: 70, height: 16)
                    }
                    Text("Press hotkey or ↵ to finish")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                case .transcribing:
                    Text("Transcribing…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(providerName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                case .success:
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Pasting into active app…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                case .error(let message):
                    Text("Dictation Failed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Stop / Cancel button
            if state == .listening {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Finish dictating")
            } else if case .error = state {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .frame(minWidth: 240, maxWidth: 320)
    }
}

private struct WaveformBarsView: View {
    let level: Float
    private let barCount = 10

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(index: index, total: barCount, level: level)
            }
        }
    }
}

private struct WaveformBar: View {
    let index: Int
    let total: Int
    let level: Float

    var body: some View {
        // Curve the height based on position and current RMS level
        let mid = Float(total - 1) / 2.0
        let dist = abs(Float(index) - mid) / mid
        let factor = max(0.2, 1.0 - (dist * 0.5))
        let height = max(4.0, CGFloat(level * factor * 16.0))

        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor.opacity(0.85))
            .frame(width: 3, height: height)
            .animation(.easeInOut(duration: 0.08), value: height)
    }
}
