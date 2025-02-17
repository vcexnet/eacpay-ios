import UIKit

class SyncProgressHeaderView: UITableViewCell, Subscriber {
	@IBOutlet var headerLabel: UILabel!
	@IBOutlet var timestampLabel: UILabel!
	@IBOutlet var progressView: UIProgressView!
	@IBOutlet var noSendImageView: UIImageView!
	private let dateFormatter: DateFormatter = {
		let df = DateFormatter()
		df.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
		return df
	}()

	var progress: CGFloat = 0.0 {
		didSet {
			progressView.alpha = 1.0
			progressView.progress = Float(progress)
			progressView.setNeedsDisplay()
		}
	}

	var headerMessage: SyncState = .success {
		didSet {
			switch headerMessage {
			case .connecting: headerLabel.text = S.SyncingHeader.connecting.localize()
			case .syncing: headerLabel.text = S.SyncingHeader.syncing.localize()
			case .success:
				headerLabel.text = ""
			}
			headerLabel.setNeedsDisplay()
		}
	}

	var timestamp: UInt32 = 0 {
		didSet {
			timestampLabel.text = dateFormatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
			timestampLabel.setNeedsDisplay()
		}
	}

	var isRescanning: Bool = false {
		didSet {
			if isRescanning {
				headerLabel.text = S.SyncingHeader.rescanning.localize()
				timestampLabel.text = ""
				progressView.alpha = 0.0
				noSendImageView.alpha = 1.0
			} else {
				headerLabel.text = ""
				timestampLabel.text = ""
				progressView.alpha = 1.0
				noSendImageView.alpha = 0.0
			}
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		progressView.transform = progressView.transform.scaledBy(x: 1, y: 2)
	}

	override func setSelected(_ selected: Bool, animated: Bool) {
		super.setSelected(selected, animated: animated)
	}
}
