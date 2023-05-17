//
//  File.swift
//  
//
//  Created by brian on 7/21/21.
//
// swiftlint:disable file_length implicitly_unwrapped_optional type_body_length

import WebKit
import UIKit
import SafariServices
import Combine

@objc(SWKPaywallViewController)
public class PaywallViewController: UIViewController, SWWebViewDelegate, LoadingDelegate {
  // MARK: - Public Properties
  /// A publisher that emits ``PaywallState`` objects, which tell you the state of the presented paywall.
  public var paywallStatePublisher: AnyPublisher<PaywallState, Never>? {
    return paywallStateSubject?.eraseToAnyPublisher()
  }

  /// Defines whether the presentation should animate based on the presentation style.
  @objc public var presentationIsAnimated: Bool {
    return presentationStyle != .fullscreenNoAnimation
  }

  // MARK: - Internal Properties
  override public var preferredStatusBarStyle: UIStatusBarStyle {
    if let isDark = view.backgroundColor?.isDarkColor, isDark {
      return .lightContent
    }
    return .darkContent
  }
  /// The paywall to feed into the view controller.
  var paywall: Paywall

  /// The request associated with the presentation of the paywall.
  var request: PresentationRequest?

  /// The cache key for the view controller.
  var cacheKey: String

  /// Determines whether the paywall is presented or not.
  var isActive: Bool {
    return isPresented || isBeingPresented
  }

  /// The web view that the paywall is displayed in.
  let webView: SWWebView

  /// The paywall info
  var paywallInfo: PaywallInfo {
    return paywall.getInfo(
      fromEvent: request?.presentationInfo.eventData,
      factory: factory
    )
  }

  /// The loading state of the paywall.
  var loadingState: PaywallLoadingState = .unknown {
    didSet {
      if loadingState != oldValue {
        loadingStateDidChange(from: oldValue)
      }
    }
  }

  var delegate: PaywallViewControllerDelegateAdapter?

  // MARK: - Private Properties
  /// Internal passthrough subject that emits ``PaywallState`` objects. These state objects feed back to
  /// the caller of ``Superwall/register(event:params:handler:feature:)``
  ///
  /// This publisher is set on presentation of the paywall.
  private var paywallStateSubject: PassthroughSubject<PaywallState, Never>!

  private weak var eventDelegate: PaywallViewControllerEventDelegate?

  /// Defines whether the view controller is being presented or not.
  private var isPresented = false

  /// Stores the completion block when calling dismiss.
  private var dismissCompletionBlock: (() -> Void)?

  /// Stores the ``PaywallResult`` on dismiss of paywall.
  private var paywallResult: PaywallResult?

  /// A timer that shows the refresh buttons/modal when it fires.
	private var showRefreshTimer: Timer?

  /// Defines when Safari is presenting in app.
	private var isSafariVCPresented = false

  /// The presentation style for the paywall.
  private var presentationStyle: PaywallPresentationStyle

  /// A loading spinner that appears when making a purchase.
  private var loadingViewController: LoadingViewController?

  /// A shimmer view that appears when loading the webpage.
  private var shimmerView: ShimmerView?

  /// A button that refreshes the paywall presentation.
  private lazy var refreshPaywallButton: UIButton = {
    ButtonFactory.make(
      imageNamed: "reload_paywall",
      target: self,
      action: #selector(reloadWebView)
    )
	}()

  /// A button that exits the paywall.
  private lazy var exitButton: UIButton = {
    ButtonFactory.make(
      imageNamed: "exit_paywall",
      target: self,
      action: #selector(forceClose)
    )
  }()

  /// The push presentation animation transition delegate.
  private let transitionDelegate = PushTransitionDelegate()

  /// Defines whether the refresh alert view controller has been created.
  private var hasRefreshAlertController = false

  /// Cancellable observer.
  private var resignActiveObserver: AnyCancellable?

  private var presentationWillPrepare = true
  private var presentationDidFinishPrepare = false

  private unowned let factory: TriggerSessionManagerFactory
  private unowned let storage: Storage
  private unowned let deviceHelper: DeviceHelper
  private unowned let paywallManager: PaywallManager
  private weak var cache: PaywallViewControllerCache?

	// MARK: - View Lifecycle

	init(
    paywall: Paywall,
    eventDelegate: PaywallViewControllerEventDelegate? = nil,
    delegate: PaywallViewControllerDelegateAdapter? = nil,
    deviceHelper: DeviceHelper,
    factory: TriggerSessionManagerFactory,
    storage: Storage,
    paywallManager: PaywallManager,
    webView: SWWebView,
    cache: PaywallViewControllerCache?
  ) {
    self.cache = cache
    self.cacheKey = PaywallCacheLogic.key(
      identifier: paywall.identifier,
      locale: deviceHelper.locale
    )
    self.deviceHelper = deviceHelper
		self.eventDelegate = eventDelegate
    self.delegate = delegate

    self.factory = factory
    self.storage = storage
    self.paywall = paywall
    self.paywallManager = paywallManager
    self.webView = webView

    presentationStyle = paywall.presentation.style
    super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

  public override func viewDidLoad() {
    super.viewDidLoad()
		configureUI()
    loadWebView()
	}

  private func configureUI() {
    modalPresentationCapturesStatusBarAppearance = true
    setNeedsStatusBarAppearanceUpdate()
    view.backgroundColor = paywall.backgroundColor

    view.addSubview(webView)
    webView.alpha = 0.0

    let loadingColor = self.paywall.backgroundColor.readableOverlayColor
    view.addSubview(refreshPaywallButton)
    refreshPaywallButton.imageView?.tintColor = loadingColor.withAlphaComponent(0.5)

    view.addSubview(exitButton)
    exitButton.imageView?.tintColor = loadingColor.withAlphaComponent(0.5)

    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      webView.topAnchor.constraint(equalTo: view.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),

      refreshPaywallButton.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 17),
      refreshPaywallButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: 0),
      refreshPaywallButton.widthAnchor.constraint(equalToConstant: 55),
      refreshPaywallButton.heightAnchor.constraint(equalToConstant: 55),

      exitButton.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 17),
      exitButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 0),
      exitButton.widthAnchor.constraint(equalToConstant: 55),
      exitButton.heightAnchor.constraint(equalToConstant: 55)
    ])
  }

  nonisolated private func trackOpen() async {
    let triggerSessionManager = factory.getTriggerSessionManager()
    await triggerSessionManager.trackPaywallOpen()
    storage.trackPaywallOpen()
    let trackedEvent = await InternalSuperwallEvent.PaywallOpen(paywallInfo: paywallInfo)
    await Superwall.shared.track(trackedEvent)
  }

  nonisolated private func trackClose() async {
    let triggerSessionManager = factory.getTriggerSessionManager()
    let trackedEvent = await InternalSuperwallEvent.PaywallClose(paywallInfo: paywallInfo)
    await Superwall.shared.track(trackedEvent)
    await triggerSessionManager.trackPaywallClose()
  }

  /// Triggered by user closing the paywall when the webview hasn't loaded.
  @objc private func forceClose() {
    dismiss(
      result: .declined
    ) { [weak self] in
      guard let self = self else {
        return
      }
      self.cache?.removePaywallViewController(forKey: self.cacheKey)
    }
  }

  private func loadWebView() {
    let url = paywall.url

    if paywall.webviewLoadingInfo.startAt == nil {
      paywall.webviewLoadingInfo.startAt = Date()
    }

    Task(priority: .utility) {
      let trackedEvent = InternalSuperwallEvent.PaywallWebviewLoad(
        state: .start,
        paywallInfo: self.paywallInfo
      )
      await Superwall.shared.track(trackedEvent)

      let triggerSessionManager = factory.getTriggerSessionManager()
      await triggerSessionManager.trackWebviewLoad(
        forPaywallId: paywallInfo.databaseId,
        state: .start
      )
    }

    if Superwall.shared.options.paywalls.useCachedTemplates {
      let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
      webView.load(request)
    } else {
    let request = URLRequest(url: url)
      webView.load(request)
    }

    loadingState = .loadingURL
  }

  @objc private func reloadWebView() {
    webView.reload()
  }

  // MARK: - State Handling
  func togglePaywallSpinner(isHidden: Bool) {
    if isHidden {
      if loadingState == .manualLoading {
        loadingState = .ready
      }
    } else {
      if loadingState == .ready {
        loadingState = .manualLoading
      }
    }
  }

	func loadingStateDidChange(from oldValue: PaywallLoadingState) {
    switch loadingState {
    case .unknown:
      break
    case .loadingPurchase,
      .manualLoading:
      addLoadingView()
    case .loadingURL:
      addShimmerView()
      showRefreshButtonAfterTimeout(true)
      UIView.springAnimate {
        self.webView.alpha = 0.0
        self.webView.transform = CGAffineTransform.identity.translatedBy(x: 0, y: -10)
      }
    case .ready:
      let translation = CGAffineTransform.identity.translatedBy(x: 0, y: 10)
      let spinnerDidShow = oldValue == .loadingPurchase || oldValue == .manualLoading
      webView.transform = spinnerDidShow ? .identity : translation
      showRefreshButtonAfterTimeout(false)
      hideLoadingView()

      if !spinnerDidShow {
        UIView.animate(
          withDuration: 0.6,
          delay: 0.25,
          animations: {
            self.shimmerView?.alpha = 0.0
            self.webView.alpha = 1.0
            self.webView.transform = .identity
          },
          completion: { _ in
            self.shimmerView?.removeFromSuperview()
            self.shimmerView = nil
          }
        )
			}
		}
	}

  private func addShimmerView(onPresent: Bool = false) {
    guard shimmerView == nil else {
      return
    }
    guard loadingState == .loadingURL || loadingState == .unknown else {
      return
    }
    guard isActive || onPresent else {
      return
    }
    let shimmerView = ShimmerView(
      backgroundColor: paywall.backgroundColor,
      tintColor: paywall.backgroundColor.readableOverlayColor,
      isLightBackground: !paywall.backgroundColor.isDarkColor
    )
    view.insertSubview(shimmerView, belowSubview: webView)
    NSLayoutConstraint.activate([
      shimmerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      shimmerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      shimmerView.topAnchor.constraint(equalTo: view.topAnchor),
      shimmerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    self.shimmerView = shimmerView
  }

  private func addLoadingView() {
    guard Superwall.shared.options.paywalls.transactionBackgroundView == .spinner else {
      return
    }

    if loadingViewController == nil {
      let loadingViewController = LoadingViewController(delegate: self)
      view.addSubview(loadingViewController.view)

      NSLayoutConstraint.activate([
        loadingViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        loadingViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        loadingViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
        loadingViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
      ])
      self.loadingViewController = loadingViewController
    } else {
      loadingViewController?.show()
    }
  }

  private func hideLoadingView() {
    guard let loadingViewController = loadingViewController else {
      return
    }
    loadingViewController.hide()
  }

  // MARK: - Timeout

  private func showRefreshButtonAfterTimeout(_ isVisible: Bool) {
		showRefreshTimer?.invalidate()
		showRefreshTimer = nil

		if isVisible {
      showRefreshTimer = Timer.scheduledTimer(
        withTimeInterval: 5.0,
        repeats: false
      ) { [weak self] _ in
        guard let self = self else {
          return
        }

        self.view.bringSubviewToFront(self.refreshPaywallButton)
        self.view.bringSubviewToFront(self.exitButton)

        self.refreshPaywallButton.isHidden = false
        self.refreshPaywallButton.alpha = 0.0
        self.exitButton.isHidden = false
        self.exitButton.alpha = 0.0

        Task(priority: .utility) {
          let trackedEvent = InternalSuperwallEvent.PaywallWebviewLoad(
            state: .timeout,
            paywallInfo: self.paywallInfo
          )
          await Superwall.shared.track(trackedEvent)
        }

        UIView.springAnimate(withDuration: 2) {
          self.refreshPaywallButton.alpha = 1.0
          self.exitButton.alpha = 1.0
        }
      }
		} else {
			hideRefreshButton()
		}
	}

	private func hideRefreshButton() {
		showRefreshTimer?.invalidate()
		showRefreshTimer = nil
    UIView.springAnimate(
      animations: {
        self.refreshPaywallButton.alpha = 0.0
        self.exitButton.alpha = 0.0
      },
      completion: { _ in
        self.refreshPaywallButton.isHidden = true
        self.exitButton.isHidden = true
      }
    )
	}

  // MARK: - Presentation Logic

  /// Sets the event data for use in ``PaywallInfo`` and the state publisher
  /// for callbacks.
  func set(
    request: PresentationRequest,
    paywallStatePublisher: PassthroughSubject<PaywallState, Never>
  ) {
    self.request = request
    self.paywallStateSubject = paywallStatePublisher
  }

  func present(
    on presenter: UIViewController,
    request: PresentationRequest,
    presentationStyleOverride: PaywallPresentationStyle?,
    paywallStatePublisher: PassthroughSubject<PaywallState, Never>,
    completion: @escaping (Bool) -> Void
  ) {
    if Superwall.shared.isPaywallPresented
      || presenter is PaywallViewController
      || isBeingPresented {
      return completion(false)
    }
    Superwall.shared.presentationItems.window?.makeKeyAndVisible()

    set(
      request: request,
      paywallStatePublisher: paywallStatePublisher
    )

    setPresentationStyle(withOverride: presentationStyleOverride)

    presenter.present(
      self,
      animated: presentationIsAnimated
    ) {
      completion(true)
    }
  }

  private func setPresentationStyle(withOverride override: PaywallPresentationStyle?) {
    if let override = override,
      override != .none {
      presentationStyle = override
    } else {
      presentationStyle = paywall.presentation.style
    }

    switch presentationStyle {
    case .modal:
      modalPresentationStyle = .pageSheet
    case .fullscreen:
      modalPresentationStyle = .overFullScreen
    case .push:
      modalPresentationStyle = .custom
      transitioningDelegate = transitionDelegate
    case .fullscreenNoAnimation:
      modalPresentationStyle = .overFullScreen
    case .drawer:
      modalPresentationStyle = .pageSheet
      if #available(iOS 16.0, *),
        UIDevice.current.userInterfaceIdiom == .phone {
        sheetPresentationController?.detents = [
          .custom(resolver: { context in
            return 0.7 * context.maximumDetentValue
          })
        ]
      }
    case .none:
      break
    }
  }

  @MainActor
  func presentAlert(
    title: String? = nil,
    message: String? = nil,
    actionTitle: String? = nil,
    closeActionTitle: String = "Done",
    action: (() -> Void)? = nil,
    onClose: (() -> Void)? = nil
  ) {
    guard presentedViewController == nil else {
      return
    }
    let alertController = AlertControllerFactory.make(
      title: title,
      message: message,
      actionTitle: actionTitle,
      closeActionTitle: closeActionTitle,
      action: action,
      onClose: onClose,
      sourceView: self.view
    )

    present(alertController, animated: true) { [weak self] in
      if let loadingState = self?.loadingState,
        loadingState != .loadingURL {
        self?.loadingState = .ready
      }
    }
  }
}

// MARK: - PaywallMessageHandlerDelegate
extension PaywallViewController: PaywallMessageHandlerDelegate {
  func eventDidOccur(_ paywallEvent: PaywallWebEvent) {
    Task {
      await eventDelegate?.eventDidOccur(
        paywallEvent,
        on: self
      )
    }
  }

  func presentSafariInApp(_ url: URL) {
    guard UIApplication.shared.canOpenURL(url) else {
      Logger.debug(
        logLevel: .warn,
        scope: .paywallViewController,
        message: "Invalid URL provided for \"Open URL\" click behavior."
      )
      return
    }
    let safariVC = SFSafariViewController(url: url)
    safariVC.delegate = self
    self.isSafariVCPresented = true
    present(safariVC, animated: true)
  }

  func presentSafariExternal(_ url: URL) {
    UIApplication.shared.open(url)
  }

  func openDeepLink(_ url: URL) {
    dismiss(
      result: .declined
    ) { [weak self] in
      self?.eventDidOccur(.openedDeepLink(url: url))
      UIApplication.shared.open(url)
    }
  }
}

// MARK: - View Lifecycle
extension PaywallViewController {
  override public func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    cache?.activePaywallVcKey = cacheKey

    if isSafariVCPresented {
      return
    }

    if #available(iOS 15.0, *),
      !deviceHelper.isMac {
      webView.setAllMediaPlaybackSuspended(false) // ignore-xcode-12
    }

    presentationWillBegin()
  }

  /// Prepares the view controller for presentation. Only called once per presentation.
  private func presentationWillBegin() {
    guard presentationWillPrepare else {
      return
    }
    addShimmerView(onPresent: true)

    view.alpha = 1.0
    view.transform = .identity

    paywall.closeReason = nil
    Superwall.shared.dependencyContainer.delegateAdapter.willPresentPaywall(withInfo: paywallInfo)

    webView.scrollView.contentOffset = CGPoint.zero
    if loadingState == .ready {
      webView.messageHandler.handle(.templateParamsAndUserAttributes)
    }

    presentationWillPrepare = false
  }

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    presentationDidFinish()
  }

  /// Lets the view controller know that presentation has finished. Only called once per presentation.
  private func presentationDidFinish() {
    if presentationDidFinishPrepare {
      return
    }
    Superwall.shared.storePresentationObjects(request, paywallStateSubject)
    isPresented = true
    Superwall.shared.dependencyContainer.delegateAdapter.didPresentPaywall(withInfo: paywallInfo)
    Task {
      await trackOpen()
    }
    GameControllerManager.shared.setDelegate(self)
    presentationDidFinishPrepare = true
  }

  override public func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    guard isPresented else {
      return
    }
    if isSafariVCPresented {
      return
    }
    willDismiss()
  }

  override public func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    guard isPresented else {
      return
    }
    if isSafariVCPresented {
      return
    }
    Task(priority: .utility) {
      await trackClose()
    }

    if #available(iOS 15.0, *),
      !deviceHelper.isMac {
      webView.setAllMediaPlaybackSuspended(true) // ignore-xcode-12
    }

    resetPresentationPreparations()

    didDismiss()
  }

  private func resetPresentationPreparations() {
    presentationWillPrepare = true
    presentationDidFinishPrepare = false
  }

  func dismiss(
    result: PaywallResult,
    closeReason: PaywallCloseReason = .systemLogic,
    completion: (() -> Void)? = nil
  ) {
    dismissCompletionBlock = completion
    paywallResult = result
    paywall.closeReason = closeReason

    if let delegate = delegate {
      delegate.didFinish(
        controller: self,
        swiftResult: result,
        objcResult: result.convertForObjc()
      )
    } else {
      dismiss(animated: presentationIsAnimated)
    }
  }

  private func willDismiss() {
    Superwall.shared.presentationItems.paywallInfo = paywallInfo
    Superwall.shared.dependencyContainer.delegateAdapter.willDismissPaywall(withInfo: paywallInfo)
  }

  private func didDismiss() {
    // Reset spinner
    let isShowingSpinner = loadingState == .loadingPurchase || loadingState == .manualLoading
    if isShowingSpinner {
      self.loadingState = .ready
    }

    Superwall.shared.dependencyContainer.delegateAdapter.didDismissPaywall(withInfo: paywallInfo)

    let result = paywallResult ?? .declined
    paywallStateSubject?.send(.dismissed(paywallInfo, result))

    if paywall.closeReason == .systemLogic {
      paywallStateSubject?.send(completion: .finished)
      paywallStateSubject = nil
    }

    // Reset state
    Superwall.shared.destroyPresentingWindow()
    GameControllerManager.shared.clearDelegate(self)

    paywallResult = nil
    cache?.activePaywallVcKey = nil
    isPresented = false

    dismissCompletionBlock?()
    dismissCompletionBlock = nil
  }
}

// MARK: - SFSafariViewControllerDelegate
extension PaywallViewController: SFSafariViewControllerDelegate {
  public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
		isSafariVCPresented = false
	}
}

// MARK: - GameControllerDelegate
extension PaywallViewController: GameControllerDelegate {
  func gameControllerEventDidOccur(event: GameControllerEvent) {
    guard let payload = event.jsonString else {
      return
    }
    let script = "window.paywall.accept([\(payload)])"
    webView.evaluateJavaScript(script)
    Logger.debug(
      logLevel: .debug,
      scope: .gameControllerManager,
      message: "Received Event",
      info: ["payload": payload],
      error: nil
    )
  }
}
