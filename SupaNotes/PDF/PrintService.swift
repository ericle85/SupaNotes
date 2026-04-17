import UIKit

enum PrintService {
    static func print(pdfData: Data, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = pdfData
        controller.present(animated: true, completionHandler: nil)
    }
}
