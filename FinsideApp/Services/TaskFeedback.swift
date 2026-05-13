import AudioToolbox
import UIKit

enum TaskFeedback {
    static func toggle(toDone: Bool) {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.prepare()
        gen.impactOccurred(intensity: 0.85)
        if toDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
                AudioServicesPlaySystemSound(1_104)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
            }
        }
    }
}
