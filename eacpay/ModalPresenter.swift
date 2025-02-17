import LocalAuthentication
import SafariServices
import SwiftUI
import UIKit

class ModalPresenter: Subscriber, Trackable {
	// MARK: - Public

	var walletManager: WalletManager?
	init(store: Store, walletManager: WalletManager, window: UIWindow, apiClient: BRAPIClient) {
		self.store = store
		self.window = window
		self.walletManager = walletManager
		modalTransitionDelegate = ModalTransitionDelegate(type: .regular, store: store)
		wipeNavigationDelegate = StartNavigationDelegate(store: store)
		noAuthApiClient = apiClient
		addSubscriptions()
	}

	// MARK: - Private

	private let store: Store
	private let window: UIWindow
	private let alertHeight: CGFloat = 260.0
	private let modalTransitionDelegate: ModalTransitionDelegate
	private let messagePresenter = MessageUIPresenter()
	private let securityCenterNavigationDelegate = SecurityCenterNavigationDelegate()
	private let verifyPinTransitionDelegate = TransitioningDelegate()
	private let noAuthApiClient: BRAPIClient

	private var currentRequest: PaymentRequest?
	private var reachability = ReachabilityMonitor()
	private var notReachableAlert: InAppAlert?
	private let wipeNavigationDelegate: StartNavigationDelegate

	private func addSubscriptions() {
		store.subscribe(self,
		                selector: { $0.rootModal != $1.rootModal },
		                callback: { state in
		                	Task { @MainActor in
		                		self.presentModal(state.rootModal)
		                	}
		                })
		store.subscribe(self,
		                selector: { $0.alert != $1.alert && $1.alert != nil },
		                callback: { self.handleAlertChange($0.alert) })

		// Subscribe to prompt actions
		store.subscribe(self, name: .promptUpgradePin, callback: { _ in
			self.presentUpgradePin()
		})
		store.subscribe(self, name: .promptPaperKey, callback: { _ in
			self.presentWritePaperKey()
		})
		store.subscribe(self, name: .promptBiometrics, callback: { _ in
			self.presentBiometricsSetting()
		})
		store.subscribe(self, name: .promptShareData, callback: { _ in
			self.promptShareData()
		})
		store.subscribe(self, name: .recommendRescan, callback: { _ in
			self.presentRescan()
		})

		store.subscribe(self, name: .scanQr, callback: { _ in
			self.handleScanQrURL()
		})
		store.subscribe(self, name: .copyWalletAddresses(nil, nil), callback: {
			guard let trigger = $0 else { return }
			if case let .copyWalletAddresses(success, error) = trigger {
				self.handleCopyAddresses(success: success, error: error)
			}
		})
		reachability.didChange = { isReachable in
			if isReachable {
				self.hideNotReachable()
			} else {
				self.showNotReachable()
			}
		}
		store.subscribe(self, name: .lightWeightAlert(""), callback: {
			guard let trigger = $0 else { return }
			if case let .lightWeightAlert(message) = trigger {
				self.showLightWeightAlert(message: message)
			}
		})
		store.subscribe(self, name: .showAlert(nil), callback: {
			guard let trigger = $0 else { return }
			if case let .showAlert(alert) = trigger {
				if let alert = alert {
					self.topViewController?.present(alert, animated: true, completion: nil)
				}
			}
		})
	}

	// MARK: - Prompts

	private func presentRescan() {
		let vc = ReScanViewController(store: store)
		let nc = UINavigationController(rootViewController: vc)
		nc.setClearNavbar()
		vc.addCloseNavigationItem()
		topViewController?.present(nc, animated: true, completion: nil)
	}

	func presentBiometricsSetting() {
		guard let walletManager = walletManager else { return }
		let biometricsSettings = BiometricsSettingsViewController(walletManager: walletManager, store: store)
		biometricsSettings.addCloseNavigationItem(tintColor: .white)
		let nc = ModalNavigationController(rootViewController: biometricsSettings)
		biometricsSettings.presentSpendingLimit = strongify(self) { myself in
			myself.pushBiometricsSpendingLimit(onNc: nc)
		}
		nc.setDefaultStyle()
		nc.isNavigationBarHidden = true
		nc.delegate = securityCenterNavigationDelegate
		topViewController?.present(nc, animated: true, completion: nil)
	}

	private func promptShareData() {
		let shareData = ShareDataViewController(store: store)
		let nc = ModalNavigationController(rootViewController: shareData)
		nc.setDefaultStyle()
		nc.isNavigationBarHidden = true
		nc.delegate = securityCenterNavigationDelegate
		shareData.addCloseNavigationItem()
		topViewController?.present(nc, animated: true, completion: nil)
	}

	func presentWritePaperKey() {
		guard let vc = topViewController else { return }
		presentWritePaperKey(fromViewController: vc)
	}

	func presentUpgradePin() {
		guard let walletManager = walletManager else { return }
		let updatePin = UpdatePinViewController(store: store, walletManager: walletManager, type: .update)
		let nc = ModalNavigationController(rootViewController: updatePin)
		nc.setDefaultStyle()
		nc.isNavigationBarHidden = true
		nc.delegate = securityCenterNavigationDelegate
		updatePin.addCloseNavigationItem()
		topViewController?.present(nc, animated: true, completion: nil)
	}

	private func presentModal(_ type: RootModal, configuration: ((UIViewController) -> Void)? = nil) {
		guard type != .loginScan else { return presentLoginScan() }
		guard let vc = rootModalViewController(type)
		else {
			store.perform(action: RootModalActions.Present(modal: .none))
			return
		}
		vc.transitioningDelegate = modalTransitionDelegate
		vc.modalPresentationStyle = .overFullScreen
		vc.modalPresentationCapturesStatusBarAppearance = true
		configuration?(vc)
		topViewController?.present(vc, animated: true, completion: {
			self.store.perform(action: RootModalActions.Present(modal: .none))
			self.store.trigger(name: .hideStatusBar)
		})
	}

	private func handleAlertChange(_ type: AlertType?) {
		guard let type = type else { return }
		presentAlert(type, completion: {
			self.store.perform(action: SimpleReduxAlert.Hide())
		})
	}

	private func presentAlert(_ type: AlertType, completion: @escaping () -> Void) {
		let alertView = AlertView(type: type)
		guard let window = UIApplication.shared.windows.filter({ $0.isKeyWindow }).first
		else {
			saveEvent("ERROR: Window not found in the UIApplication window stack")
			return
		}

		let size = window.bounds.size
		window.addSubview(alertView)

		let topConstraint = alertView.constraint(.top, toView: window, constant: size.height)
		alertView.constrain([
			alertView.constraint(.width, constant: size.width),
			alertView.constraint(.height, constant: alertHeight + 25.0),
			alertView.constraint(.leading, toView: window, constant: nil),
			topConstraint,
		])
		window.layoutIfNeeded()

		UIView.spring(0.6, animations: {
			topConstraint?.constant = size.height - self.alertHeight
			window.layoutIfNeeded()
		}, completion: { _ in
			alertView.animate()
			UIView.spring(0.6, delay: 3.0, animations: {
				topConstraint?.constant = size.height
				window.layoutIfNeeded()
			}, completion: { _ in
				// TODO: - Make these callbacks generic
				if case let .paperKeySet(callback) = type {
					callback()
				}
				if case let .pinSet(callback) = type {
					callback()
				}
				if case let .sweepSuccess(callback) = type {
					callback()
				}
				completion()
				alertView.removeFromSuperview()
			})
		})
	}

	private func rootModalViewController(_ type: RootModal) -> UIViewController? {
		switch type {
		case .none:
			return nil
		case .send:
			return makeSendView()
		case .receive:
			return receiveView(isRequestAmountVisible: true)
		case .menu:
			return menuViewController()
		case .loginScan:
			return nil // The scan view needs a custom presentation
		case .loginAddress:
			return receiveView(isRequestAmountVisible: false)
		case .manageWallet:
			return ModalViewController(childViewController: ManageWalletViewController(store: store), store: store)
		case .wipeEmptyWallet:
			return wipeEmptyView()
		case .requestAmount:
			guard let wallet = walletManager?.wallet else { return nil }
			let requestVc = RequestAmountViewController(wallet: wallet, store: store)
			requestVc.presentEmail = { [weak self] bitcoinURL, image in
				self?.messagePresenter.presenter = self?.topViewController
				self?.messagePresenter.presentMailCompose(bitcoinURL: bitcoinURL, image: image)
			}
			requestVc.presentText = { [weak self] bitcoinURL, image in
				self?.messagePresenter.presenter = self?.topViewController
				self?.messagePresenter.presentMessageCompose(bitcoinURL: bitcoinURL, image: image)
			}
			return ModalViewController(childViewController: requestVc, store: store)
		}
	}

	private func wipeEmptyView() -> UIViewController? {
		guard let walletManager = walletManager else { return nil }

		let wipeEmptyvc = WipeEmptyWalletViewController(walletManager: walletManager, store: store, didTapYesDelete: ({ [weak self] in
			guard let myself = self else { return }
			myself.wipeWallet()
		}))
		return ModalViewController(childViewController: wipeEmptyvc, store: store)
	}

	private func makeSendView() -> UIViewController? {
		guard !store.state.walletState.isRescanning
		else {
			let alert = UIAlertController(title: S.LitewalletAlert.error.localize(), message: S.Send.isRescanning.localize(), preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: S.Button.ok.localize(), style: .cancel, handler: nil))
			topViewController?.present(alert, animated: true, completion: nil)
			return nil
		}
		guard let walletManager = walletManager else { return nil }
		guard let kvStore = walletManager.apiClient?.kv else { return nil }

		let sendVC = SendViewController(store: store, sender: Sender(walletManager: walletManager, kvStore: kvStore, store: store), walletManager: walletManager, initialRequest: currentRequest)
		currentRequest = nil

		if store.state.isLoginRequired {
			sendVC.isPresentedFromLock = true
		}

		let root = ModalViewController(childViewController: sendVC, store: store)
		sendVC.presentScan = presentScan(parent: root)
		sendVC.presentVerifyPin = { [weak self, weak root] bodyText, callback in
			guard let myself = self else { return }
			guard let myroot = root else { return }

			let vc = VerifyPinViewController(bodyText: bodyText, pinLength: myself.store.state.pinLength, callback: callback)
			vc.transitioningDelegate = myself.verifyPinTransitionDelegate
			vc.modalPresentationStyle = .overFullScreen
			vc.modalPresentationCapturesStatusBarAppearance = true
			myroot.view.isFrameChangeBlocked = true
			myroot.present(vc, animated: true, completion: nil)
		}
		sendVC.onPublishSuccess = { [weak self] in
			self?.presentAlert(.sendSuccess, completion: {})
		}
		return root
	}

	private func receiveView(isRequestAmountVisible: Bool) -> UIViewController? {
		guard let wallet = walletManager?.wallet else { return nil }
		let receiveVC = ReceiveViewController(wallet: wallet, store: store, isRequestAmountVisible: isRequestAmountVisible)
		let root = ModalViewController(childViewController: receiveVC, store: store)
		receiveVC.presentEmail = { [weak self, weak root] address, image in
			guard let root = root else { return }
			self?.messagePresenter.presenter = root
			self?.messagePresenter.presentMailCompose(litecoinAddress: address, image: image)
		}
		receiveVC.presentText = { [weak self, weak root] address, image in
			guard let root = root else { return }
			self?.messagePresenter.presenter = root
			self?.messagePresenter.presentMessageCompose(address: address, image: image)
		}
		return root
	}

	private func menuViewController() -> UIViewController? {
		let menu = MenuViewController()
		let root = ModalViewController(childViewController: menu, store: store)
		menu.didTapSecurity = { [weak self, weak menu] in
			self?.modalTransitionDelegate.reset()
			menu?.dismiss(animated: true) {
				self?.presentSecurityCenter()
			}
		}

		menu.didTapSupport = { [weak self, weak menu] in
			menu?.dismiss(animated: true, completion: {
				let urlString = FoundationSupport.dashboard

				guard let url = URL(string: urlString) else { return }

				LWAnalytics.logEventWithParameters(itemName: ._20201118_DTS)

				let vc = SFSafariViewController(url: url)
				self?.topViewController?.present(vc, animated: true, completion: nil)
			})
		}
		menu.didTapLock = { [weak self, weak menu] in
			menu?.dismiss(animated: true) {
				self?.store.trigger(name: .lock)
			}
		}
		menu.didTapSettings = { [weak self, weak menu] in
			menu?.dismiss(animated: true) {
				self?.presentSettings()
			}
		}
		return root
	}

	private func presentLoginScan() {
		guard let top = topViewController else { return }
		let present = presentScan(parent: top)
		store.perform(action: RootModalActions.Present(modal: .none))
		present { paymentRequest in
			guard let request = paymentRequest else { return }
			self.currentRequest = request
			self.presentModal(.send)
		}
	}

	private func presentSettings() {
		guard let top = topViewController else { return }
		guard let walletManager = walletManager else { return }
		let settingsNav = UINavigationController()
		let sections = ["About", "Wallet", "Manage", "Support", "Blockchain"]

		let rows = [
			"About": [Setting(title: S.Settings.litewalletVersion.localize(), accessoryText: {
				AppVersion.string
			}, callback: {}),
			Setting(title: S.Settings.litewalletEnvironment.localize(), accessoryText: {
				var envName = "Release"
				#if Debug || Testflight
					envName = "Debug"
				#endif
				return envName
			}, callback: {}),
			Setting(title: S.Settings.litewalletPartners.localize(), callback: {
				let partnerView = UIHostingController(rootView: PartnersView(viewModel: PartnerViewModel()))
				settingsNav.pushViewController(partnerView, animated: true)
			}),
			Setting(title: S.Settings.socialLinks.localize(), callback: {
				settingsNav.pushViewController(AboutViewController(), animated: true)
			}),

			],
			"Wallet":
				[
					Setting(title: S.Settings.importTile.localize(), callback: { [weak self] in
						guard let myself = self else { return }
						guard let walletManager = myself.walletManager else { return }
						let importNav = ModalNavigationController()
						importNav.setClearNavbar()
						importNav.setWhiteStyle()
						let start = StartImportViewController(walletManager: walletManager, store: myself.store)
						start.addCloseNavigationItem(tintColor: .white)
						start.navigationItem.title = S.Import.title.localize()
						importNav.viewControllers = [start]
						settingsNav.dismiss(animated: true, completion: {
							myself.topViewController?.present(importNav, animated: true, completion: nil)
						})
					}),
					Setting(title: S.Settings.wipe.localize(), callback: { [weak self] in
						guard let myself = self else { return }
						guard let walletManager = myself.walletManager else { return }
						let nc = ModalNavigationController()
						nc.setClearNavbar()
						nc.setWhiteStyle()
						nc.delegate = myself.wipeNavigationDelegate
						let start = StartWipeWalletViewController {
							let recover = EnterPhraseViewController(store: myself.store, walletManager: walletManager, reason: .validateForWipingWallet {
								myself.wipeWallet()
							})
							nc.pushViewController(recover, animated: true)
						}
						start.addCloseNavigationItem(tintColor: .white)
						start.navigationItem.title = S.WipeWallet.title.localize()
						nc.viewControllers = [start]
						settingsNav.dismiss(animated: true, completion: {
							myself.topViewController?.present(nc, animated: true, completion: nil)
						})
					}),
					Setting(title: S.ShowWords.modalTitle.localize(), callback: { [weak self] in

						guard let myself = self else { return }
						guard let walletManager = myself.walletManager else { return }

						let showSeedsView = UIHostingController(rootView:
							SeedWordContainerView(walletManager: walletManager))
						settingsNav.pushViewController(showSeedsView, animated: true)

					}),
				],
			"Manage": [
				Setting(title: S.Settings.languages.localize(), callback: strongify(self) { _ in
					settingsNav.pushViewController(LanguageSelectionViewController(), animated: true)
				}),
				Setting(title: LAContext.biometricType() == .face ? S.Settings.faceIdLimit.localize() : S.Settings.touchIdLimit.localize(), accessoryText: { [weak self] in
					guard let myself = self else { return "" }
					guard let rate = myself.store.state.currentRate else { return "" }
					let amount = Amount(amount: walletManager.spendingLimit, rate: rate, maxDigits: myself.store.state.maxDigits)
					return amount.localCurrency
				}, callback: {
					self.pushBiometricsSpendingLimit(onNc: settingsNav)
				}),
				Setting(title: S.Settings.currency.localize(), accessoryText: {
					let code = self.store.state.defaultCurrencyCode
					let components: [String: String] = [NSLocale.Key.currencyCode.rawValue: code]
					let identifier = Locale.identifier(fromComponents: components)
					return Locale(identifier: identifier).currencyCode ?? ""
				}, callback: {
					guard let wm = self.walletManager else { print("NO WALLET MANAGER!"); return }
					settingsNav.pushViewController(DefaultCurrencyViewController(walletManager: wm, store: self.store), animated: true)
				}),
				Setting(title: S.Settings.currentLocale.localize(), accessoryText: {
					// Get the current locale
					let currentLocale = Locale.current

					if let regionCode = currentLocale.regionCode,
					   let displayName = currentLocale.localizedString(forRegionCode: regionCode)
					{
						return displayName
					} else {
						return ""
					}

				}, callback: {
					let localeView = UIHostingController(rootView: LocaleChangeView(viewModel: LocaleChangeViewModel()))
					settingsNav.pushViewController(localeView, animated: true)
				}),
				Setting(title: S.Settings.sync.localize(), callback: {
					let alert = UIAlertController(title: S.ReScan.alertTitle.localize(), message: S.ReScan.alertMessage.localize(), preferredStyle: .alert)
					alert.addAction(UIAlertAction(title: S.Button.cancel.localize(), style: .default, handler: { _ in
						alert.dismiss(animated: true)
					}))
					alert.addAction(UIAlertAction(title: S.ReScan.alertAction.localize(), style: .default, handler: { _ in
						self.store.trigger(name: .rescan)
						LWAnalytics.logEventWithParameters(itemName: ._20200112_DSR)
						alert.dismiss(animated: true)
						self.topViewController?.dismiss(animated: true)
					}))
					self.topViewController?.present(alert, animated: true)
				}),
				Setting(title: S.UpdatePin.updateTitle.localize(), callback: strongify(self) { myself in
					let updatePin = UpdatePinViewController(store: myself.store, walletManager: walletManager, type: .update)
					settingsNav.pushViewController(updatePin, animated: true)
				}),
			],
			"Support": [
				Setting(title: S.Settings.shareData.localize(), callback: {
					settingsNav.pushViewController(ShareDataViewController(store: self.store), animated: true)
				}),
			],
			"Blockchain": [
				Setting(title: S.Settings.advancedTitle.localize(), callback: { [weak self] in
					guard let myself = self else { return }
					guard let walletManager = myself.walletManager else { return }
					let sections = ["Network"]
					var networkRows = [Setting]()
					networkRows = [Setting(title: "Earthcoin Nodes", callback: {
						let nodeSelector = NodeSelectorViewController(walletManager: walletManager)
						settingsNav.pushViewController(nodeSelector, animated: true)
					})]

					// TODO: Develop this feature for issues with the TXID
					//                    if UserDefaults.didSeeCorruption {
					//                        networkRows.append(
					//                            Setting(title: S.WipeWallet.deleteDatabase, callback: {
					//                                self?.deleteDatabase()
					//                            })
					//                        )
					//                    }

					let advancedSettings = ["Network": networkRows]
					let advancedSettingsVC = SettingsViewController(sections: sections, rows: advancedSettings, optionalTitle: S.Settings.advancedTitle.localize())
					settingsNav.pushViewController(advancedSettingsVC, animated: true)
				}),
			],
		]

		let settings = SettingsViewController(sections: sections, rows: rows)
		settings.addCloseNavigationItem()
		settingsNav.viewControllers = [settings]
		top.present(settingsNav, animated: true, completion: nil)
	}

	private func presentScan(parent: UIViewController) -> PresentScan {
		return { [weak parent] scanCompletion in
			guard ScanViewController.isCameraAllowed
			else {
				self.saveEvent("scan.cameraDenied")
				if let parent = parent {
					ScanViewController.presentCameraUnavailableAlert(fromRoot: parent)
				}
				return
			}
			let vc = ScanViewController(completion: { paymentRequest in
				scanCompletion(paymentRequest)
				parent?.view.isFrameChangeBlocked = false
			}, isValidURI: { address in
				address.isValidAddress
			})
			parent?.view.isFrameChangeBlocked = true
			parent?.present(vc, animated: true, completion: {})
		}
	}

	private func presentSecurityCenter() {
		guard let walletManager = walletManager else { return }
		let securityCenter = SecurityCenterViewController(store: store, walletManager: walletManager)
		let nc = ModalNavigationController(rootViewController: securityCenter)
		nc.setDefaultStyle()
		nc.isNavigationBarHidden = true
		nc.delegate = securityCenterNavigationDelegate
		securityCenter.didTapPin = { [weak self] in
			guard let myself = self else { return }
			let updatePin = UpdatePinViewController(store: myself.store, walletManager: walletManager, type: .update)
			nc.pushViewController(updatePin, animated: true)
		}
		securityCenter.didTapBiometrics = strongify(self) { myself in
			let biometricsSettings = BiometricsSettingsViewController(walletManager: walletManager, store: myself.store)
			biometricsSettings.presentSpendingLimit = {
				myself.pushBiometricsSpendingLimit(onNc: nc)
			}
			nc.pushViewController(biometricsSettings, animated: true)
		}
		securityCenter.didTapPaperKey = { [weak self] in
			self?.presentWritePaperKey(fromViewController: nc)
		}

		window.rootViewController?.present(nc, animated: true, completion: nil)
	}

	private func pushBiometricsSpendingLimit(onNc: UINavigationController) {
		guard let walletManager = walletManager else { return }

		let verify = VerifyPinViewController(bodyText: S.VerifyPin.continueBody.localize(), pinLength: store.state.pinLength, callback: { [weak self] pin, vc in
			guard let myself = self else { return false }
			if walletManager.authenticate(pin: pin) {
				vc.dismiss(animated: true, completion: {
					let spendingLimit = BiometricsSpendingLimitViewController(walletManager: walletManager, store: myself.store)
					onNc.pushViewController(spendingLimit, animated: true)
				})
				return true
			} else {
				return false
			}
		})
		verify.transitioningDelegate = verifyPinTransitionDelegate
		verify.modalPresentationStyle = .overFullScreen
		verify.modalPresentationCapturesStatusBarAppearance = true
		onNc.present(verify, animated: true, completion: nil)
	}

	private func presentWritePaperKey(fromViewController vc: UIViewController) {
		guard let walletManager = walletManager else { return }
		let paperPhraseNavigationController = UINavigationController()
		paperPhraseNavigationController.setClearNavbar()
		paperPhraseNavigationController.setWhiteStyle()
		paperPhraseNavigationController.modalPresentationStyle = .overFullScreen
		let start = StartPaperPhraseViewController(store: store, callback: { [weak self] in
			guard let myself = self else { return }
			let verify = VerifyPinViewController(bodyText: S.VerifyPin.continueBody.localize(), pinLength: myself.store.state.pinLength, callback: { pin, vc in
				if walletManager.authenticate(pin: pin) {
					var write: WritePaperPhraseViewController?
					write = WritePaperPhraseViewController(store: myself.store, walletManager: walletManager, pin: pin, callback: { [weak self] in
						guard let myself = self else { return }
						let confirmVC = UIStoryboard(name: "Phrase", bundle: nil).instantiateViewController(withIdentifier: "ConfirmPaperPhraseViewController") as? ConfirmPaperPhraseViewController
						confirmVC?.store = myself.store
						confirmVC?.walletManager = myself.walletManager
						confirmVC?.pin = pin
						confirmVC?.didCompleteConfirmation = {
							confirmVC?.dismiss(animated: true, completion: {
								myself.store.perform(action: SimpleReduxAlert.Show(.paperKeySet(callback: {
									myself.store.perform(action: HideStartFlow())

								})))
							})
						}
						// write?.navigationItem.title = S.SecurityCenter.Cells.paperKeyTitle
						if let confirm = confirmVC {
							paperPhraseNavigationController.pushViewController(confirm, animated: true)
						}
					})
					write?.hideCloseNavigationItem()
					/// write?.navigationItem.title = S.SecurityCenter.Cells.paperKeyTitle

					vc.dismiss(animated: true, completion: {
						guard let write = write else { return }
						paperPhraseNavigationController.pushViewController(write, animated: true)
					})
					return true
				} else {
					return false
				}
			})
			verify.transitioningDelegate = self?.verifyPinTransitionDelegate
			verify.modalPresentationStyle = .overFullScreen
			verify.modalPresentationCapturesStatusBarAppearance = true
			paperPhraseNavigationController.present(verify, animated: true, completion: nil)
		})
		start.navigationItem.title = S.SecurityCenter.Cells.paperKeyTitle.localize()

		if UserDefaults.writePaperPhraseDate != nil {
			start.addCloseNavigationItem(tintColor: .lightGray)
		} else {
			start.hideCloseNavigationItem()
		}

		paperPhraseNavigationController.viewControllers = [start]
		vc.present(paperPhraseNavigationController, animated: true, completion: nil)
	}

	private func wipeWallet() {
		let group = DispatchGroup()
		let alert = UIAlertController(title: S.WipeWallet.alertTitle.localize(), message: S.WipeWallet.alertMessage.localize(), preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: S.Button.cancel.localize(), style: .default, handler: nil))
		alert.addAction(UIAlertAction(title: S.WipeWallet.wipe.localize(), style: .default, handler: { _ in
			self.topViewController?.dismiss(animated: true, completion: {
				let activity = BRActivityViewController(message: S.WipeWallet.wiping.localize())
				self.topViewController?.present(activity, animated: true, completion: nil)

				group.enter()
				DispatchQueue.walletQueue.async {
					self.walletManager?.peerManager?.disconnect()
					group.leave()
				}

				group.enter()
				DispatchQueue.walletQueue.asyncAfter(deadline: .now() + 2.0) {
					print("::: Pausing to show 'Wiping' Dialog")
					group.leave()
				}

				group.notify(queue: .main) {
					if let canForceWipeWallet = (self.walletManager?.wipeWallet(pin: "forceWipe")),
					   canForceWipeWallet
					{
						self.store.trigger(name: .reinitWalletManager {
							activity.dismiss(animated: true, completion: {
								print("::: Reiniting the WalletManager")
							})
						})
					} else {
						let failure = UIAlertController(title: S.WipeWallet.failedTitle.localize(), message: S.WipeWallet.failedMessage.localize(), preferredStyle: .alert)
						failure.addAction(UIAlertAction(title: S.Button.ok.localize(), style: .default, handler: nil))
						self.topViewController?.present(failure, animated: true, completion: nil)
					}
				}
			})
		}))
		topViewController?.present(alert, animated: true, completion: nil)
	}

	private func handleScanQrURL() {
		guard !store.state.isLoginRequired else { presentLoginScan(); return }

		if topViewController is MainViewController || topViewController is LoginViewController {
			presentLoginScan()
		} else {
			LWAnalytics.logEventWithParameters(itemName: ._20210427_HCIEEH)
			if let presented = UIApplication.shared.windows.filter({ $0.isKeyWindow }).first?.rootViewController?.presentedViewController {
				presented.dismiss(animated: true, completion: {
					self.presentLoginScan()
				})
			}
		}
	}

	private func handleCopyAddresses(success: String?, error _: String?) {
		guard let walletManager = walletManager else { return }
		let alert = UIAlertController(title: S.URLHandling.addressListAlertTitle.localize(), message: S.URLHandling.addressListAlertMessage.localize(), preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: S.Button.cancel.localize(), style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: S.URLHandling.copy.localize(), style: .default, handler: { [weak self] _ in
			guard let myself = self else { return }
			let verify = VerifyPinViewController(bodyText: S.URLHandling.addressListVerifyPrompt.localize(), pinLength: myself.store.state.pinLength, callback: { [weak self] pin, view in
				if walletManager.authenticate(pin: pin) {
					self?.copyAllAddressesToClipboard()
					view.dismiss(animated: true, completion: {
						self?.store.perform(action: SimpleReduxAlert.Show(.addressesCopied))
						if let success = success, let url = URL(string: success) {
							UIApplication.shared.open(url, options: [:], completionHandler: nil)
						}
					})
					return true
				} else {
					return false
				}
			})
			verify.transitioningDelegate = self?.verifyPinTransitionDelegate
			verify.modalPresentationStyle = .overFullScreen
			verify.modalPresentationCapturesStatusBarAppearance = true
			self?.topViewController?.present(verify, animated: true, completion: nil)
		}))
		topViewController?.present(alert, animated: true, completion: nil)
	}

	private func copyAllAddressesToClipboard() {
		guard let wallet = walletManager?.wallet else { return }
		let addresses = wallet.allAddresses.filter { wallet.addressIsUsed($0) }
		UIPasteboard.general.string = addresses.joined(separator: "\n")
	}

	private var topViewController: UIViewController? {
		var viewController = window.rootViewController
		while viewController?.presentedViewController != nil {
			viewController = viewController?.presentedViewController
		}
		return viewController
	}

	private func showNotReachable() {
		guard notReachableAlert == nil else { return }
		let alert = InAppAlert(message: S.LitewalletAlert.noInternet.localize(), image: #imageLiteral(resourceName: "BrokenCloud"))
		notReachableAlert = alert
		guard let window = UIApplication.shared.windows.filter({ $0.isKeyWindow }).first
		else {
			saveEvent("ERROR: Window not found in the UIApplication window stack")
			return
		}
		let size = window.bounds.size
		window.addSubview(alert)
		let bottomConstraint = alert.bottomAnchor.constraint(equalTo: window.topAnchor, constant: 0.0)
		alert.constrain([
			alert.constraint(.width, constant: size.width),
			alert.constraint(.height, constant: InAppAlert.height),
			alert.constraint(.leading, toView: window, constant: nil),
			bottomConstraint,
		])
		window.layoutIfNeeded()
		alert.bottomConstraint = bottomConstraint
		alert.hide = {
			self.hideNotReachable()
		}
		UIView.spring(C.animationDuration, animations: {
			alert.bottomConstraint?.constant = InAppAlert.height
			window.layoutIfNeeded()
		}, completion: { _ in })
	}

	private func hideNotReachable() {
		UIView.animate(withDuration: C.animationDuration, animations: {
			self.notReachableAlert?.bottomConstraint?.constant = 0.0
			self.notReachableAlert?.superview?.layoutIfNeeded()
		}, completion: { _ in
			self.notReachableAlert?.removeFromSuperview()
			self.notReachableAlert = nil
		})
	}

	private func showLightWeightAlert(message: String) {
		let alert = LightWeightAlert(message: message)

		guard let view = UIApplication.shared.windows.filter({ $0.isKeyWindow }).first
		else {
			saveEvent("ERROR: Window not found in the UIApplication window stack")
			return
		}

		view.addSubview(alert)
		alert.constrain([
			alert.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			alert.centerYAnchor.constraint(equalTo: view.centerYAnchor),
		])
		alert.background.effect = nil
		UIView.animate(withDuration: 0.6, animations: {
			alert.background.effect = alert.effect
		}, completion: { _ in
			UIView.animate(withDuration: 0.6, delay: 1.0, options: [], animations: {
				alert.background.effect = nil
			}, completion: { _ in
				alert.removeFromSuperview()
			})
		})
	}
}

class SecurityCenterNavigationDelegate: NSObject, UINavigationControllerDelegate {
	func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated _: Bool) {
		guard let coordinator = navigationController.topViewController?.transitionCoordinator else { return }

		if coordinator.isInteractive {
			coordinator.notifyWhenInteractionChanges { context in
				// We only want to style the view controller if the
				// pop animation wasn't cancelled
				if !context.isCancelled {
					self.setStyle(navigationController: navigationController, viewController: viewController)
				}
			}
		} else {
			setStyle(navigationController: navigationController, viewController: viewController)
		}
	}

	func setStyle(navigationController: UINavigationController, viewController: UIViewController) {
		if viewController is SecurityCenterViewController {
			navigationController.isNavigationBarHidden = true
		} else {
			navigationController.isNavigationBarHidden = false
		}

		if viewController is BiometricsSettingsViewController {
			navigationController.setWhiteStyle()
		} else {
			navigationController.setDefaultStyle()
		}
	}
}
