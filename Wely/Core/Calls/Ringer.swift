import AudioToolbox

/// Rings and vibrates every two seconds while a call waits for an answer.
final class Ringer {
    private var task: Task<Void, Never>?
    private static let ringtone: SystemSoundID = 1005

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                AudioServicesPlayAlertSound(Self.ringtone)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
