import BRCore
import MachO
import PushNotifications
import SwiftUI
import UIKit

class MainViewController: UIViewController, Subscriber, LoginViewControllerDelegate {
	// MARK: - Private

	private let store: Store
	private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
	private var isLoginRequired = false
	private let loginView: LoginViewController
	private let tempLoginView: LoginViewController
	private let loginTransitionDelegate = LoginTransitionDelegate()

	let appDelegate = UIApplication.shared.delegate as! AppDelegate

	var walletManager: WalletManager? {
		didSet {
			guard let walletManager = walletManager else { return }
			if !walletManager.noWallet {
				loginView.walletManager = walletManager
				loginView.transitioningDelegate = loginTransitionDelegate
				loginView.modalPresentationStyle = .overFullScreen
				loginView.modalPresentationCapturesStatusBarAppearance = true
				loginView.shouldSelfDismiss = true
				present(loginView, animated: false, completion: {
					self.tempLoginView.remove()
				})
			}
		}
	}

	init(store: Store) {
		self.store = store
		loginView = LoginViewController(store: store, isPresentedForLock: false)
		tempLoginView = LoginViewController(store: store, isPresentedForLock: false)
		super.init(nibName: nil, bundle: nil)
	}

	override func viewDidLoad() {
		view.backgroundColor = .liteWalletBlue

		navigationController?.navigationBar.tintColor = .liteWalletBlue
		navigationController?.navigationBar.titleTextAttributes = [
			NSAttributedString.Key.foregroundColor: UIColor.darkText,
			NSAttributedString.Key.font: UIFont.customBold(size: 17.0),
		]

		navigationController?.navigationBar.isTranslucent = false
		navigationController?.navigationBar.barTintColor = .liteWalletBlue
		loginView.delegate = self

		// detect jailbreak so we can throw up an idiot warning, in viewDidLoad so it can't easily be swizzled out
		if !E.isSimulator {
			var s = stat()
			var isJailbroken = (stat("/bin/sh", &s) == 0) ? true : false
			for i in 0 ..< _dyld_image_count() {
				guard !isJailbroken else { break }
				// some anti-jailbreak detection tools re-sandbox apps, so do a secondary check for any MobileSubstrate dyld images
				if strstr(_dyld_get_image_name(i), "MobileSubstrate") != nil {
					isJailbroken = true
				}
			}

			NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
			                                       object: nil,
			                                       queue: nil)
			{ _ in
				self.showJailbreakWarnings(isJailbroken: isJailbroken)
			}
		}

		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
		                                       object: nil,
		                                       queue: nil)
		{ _ in
			if UserDefaults.writePaperPhraseDate != nil
			{}
		}

		addSubscriptions()
		addAppLifecycleNotificationEvents()
		addTemporaryStartupViews()
	}

	func didUnlockLogin() {
		let hasSeenAnnounce = UserDefaults.standard.bool(forKey: hasSeenAnnounceView)

		// Check Locale - Assume unsupported if nil
		let currentLocaleCountry = Locale.current.regionCode ?? "RU"
		var userIsMoonPaySupported = true
		for unsupportedLocale in UnsupportedCountries.allCases {
			let truncatedCode = unsupportedLocale.localeCode.suffix(2)

			if currentLocaleCountry == truncatedCode {
				userIsMoonPaySupported = false
				let unsupportedDict: [String: String] = ["unsupported_country": unsupportedLocale.localeCode]
				LWAnalytics.logEventWithParameters(itemName: ._20240527_UBM, properties: unsupportedDict)
				break
			}
		}

		if userIsMoonPaySupported {
			guard let tabVC = UIStoryboard(name: "Main", bundle: nil)
				.instantiateViewController(withIdentifier: "TabBarViewController")
				as? TabBarViewController
			else {
				NSLog("TabBarViewController not intialized")
				return
			}

			tabVC.store = store
			tabVC.walletManager = walletManager
			tabVC.userIsMoonPaySupported = userIsMoonPaySupported

			addChildViewController(tabVC, layout: {
				tabVC.view.constrain(toSuperviewEdges: nil)
				tabVC.view.alpha = 0
				tabVC.view.layoutIfNeeded()
			})

			UIView.animate(withDuration: 0.3, delay: 0.1, options: .transitionCrossDissolve, animations: {
				tabVC.view.alpha = 1
			}) { _ in
				NSLog("US MainView Controller presented")
			}
		} else {
			guard let noBuyTabVC = UIStoryboard(name: "Main", bundle: nil)
				.instantiateViewController(withIdentifier: "NoBuyTabBarViewController")
				as? NoBuyTabBarViewController
			else {
				NSLog("TabBarViewController not intialized")
				return
			}

			noBuyTabVC.store = store
			noBuyTabVC.walletManager = walletManager

			addChildViewController(noBuyTabVC, layout: {
				noBuyTabVC.view.constrain(toSuperviewEdges: nil)
				noBuyTabVC.view.alpha = 0
				noBuyTabVC.view.layoutIfNeeded()
			})

			UIView.animate(withDuration: 0.3, delay: 0.1, options: .transitionCrossDissolve, animations: {
				noBuyTabVC.view.alpha = 1
			}) { _ in
				NSLog("US MainView Controller presented")
			}
		}
		delay(4.0) {
			self.appDelegate.pushNotifications.registerForRemoteNotifications()
		}
	}

	private func addTemporaryStartupViews() {
		guardProtected(queue: DispatchQueue.main) {
			if !WalletManager.staticNoWallet {
				self.addChildViewController(self.tempLoginView, layout: {
					self.tempLoginView.view.constrain(toSuperviewEdges: nil)
				})
			} else {
				// Adds a litewalletBlue card view the hides work while thread finishes
				let launchView = LaunchCardHostingController()
				self.addChildViewController(launchView, layout: {
					launchView.view.constrain(toSuperviewEdges: nil)
					launchView.view.isUserInteractionEnabled = false
				})
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					launchView.remove()
				}
			}
		}
	}

	private func addSubscriptions() {
		store.subscribe(self, selector: { $0.isLoginRequired != $1.isLoginRequired },
		                callback: { self.isLoginRequired = $0.isLoginRequired
		                })
	}

	private func addAppLifecycleNotificationEvents() {
		NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: nil) { _ in
			UIView.animate(withDuration: 0.1, animations: {
				self.blurView.alpha = 0.0
			}, completion: { _ in
				self.blurView.removeFromSuperview()
			})
		}

		NotificationCenter.default.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: nil) { _ in
			if !self.isLoginRequired, !self.store.state.isPromptingBiometrics {
				self.blurView.alpha = 1.0
				self.view.addSubview(self.blurView)
				self.blurView.constrain(toSuperviewEdges: nil)
			}
		}
	}

	private func showJailbreakWarnings(isJailbroken: Bool) {
		guard isJailbroken else { return }
		let totalSent = walletManager?.wallet?.totalSent ?? 0
		let message = totalSent > 0 ? S.JailbreakWarnings.messageWithBalance.localize() : S.JailbreakWarnings.messageWithBalance.localize()
		let alert = UIAlertController(title: S.JailbreakWarnings.title.localize(), message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: S.JailbreakWarnings.ignore.localize(), style: .default, handler: nil))
		if totalSent > 0 {
			alert.addAction(UIAlertAction(title: S.JailbreakWarnings.wipe.localize(), style: .default, handler: nil)) // TODO: - implement wipe
		} else {
			alert.addAction(UIAlertAction(title: S.JailbreakWarnings.close.localize(), style: .default, handler: { _ in
				exit(0)
			}))
		}
		present(alert, animated: true, completion: nil)
	}

	override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
		return .fade
	}

	override var preferredStatusBarStyle: UIStatusBarStyle {
		return .lightContent
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
