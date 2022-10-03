//
//  TrackEventViewController.swift
//  SuperwallUIKitExample
//
//  Created by Yusuf Tör on 05/04/2022.
//

import UIKit
import Superwall
import Combine

final class TrackEventViewController: UIViewController {
  @IBOutlet private var subscriptionLabel: UILabel!
  private var subscribedCancellable: AnyCancellable?
  private var trackCancellable: AnyCancellable?

  static func fromStoryboard() -> TrackEventViewController {
    let storyboard = UIStoryboard(
      name: "Main",
      bundle: nil
    )
    let controller = storyboard.instantiateViewController(
      withIdentifier: "TrackEventViewController"
    ) as! TrackEventViewController
    // swiftlint:disable:previous force_cast

    return controller
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    subscribedCancellable = StoreKitService.shared.isSubscribed
      .sink { [weak self] isSubscribed in
        if isSubscribed {
          self?.subscriptionLabel.text = "You currently have an active subscription. Therefore, the paywall will never show. For the purposes of this app, delete and reinstall the app to clear subscriptions."
        } else {
          self?.subscriptionLabel.text = "You do not have an active subscription so the paywall will show when clicking the button."
        }
      }
    navigationItem.hidesBackButton = true
  }

  @IBAction private func logOut() {
    Task {
      await SuperwallService.logOut()
      await navigationController?.popToRootViewController(animated: true)
    }
  }

  @IBAction private func trackEvent() {
    Superwall.track(
      event: "MyEvent"
    ) { paywallState in
      switch paywallState {
      case .presented(let paywallInfo):
        print("paywall info is", paywallInfo)
      case .dismissed(let result):
        switch result.state {
        case .purchased(let productId):
          print("The purchased product ID is", productId)
        case .closed:
          print("The paywall was closed.")
        case .restored:
          print("The product was restored.")
        }
      case .skipped(let reason):
        switch reason {
        case .holdout(let experiment):
          print("The user is in a holdout group, with id \(experiment.id) and group id \(experiment.groupId)")
        case .noRuleMatch:
          print("The user did not match any rules")
        case .triggerNotFound:
          print("The trigger wasn't found on the dashboard.")
        case .error(let error):
          print("Failed to present paywall. Consider a native paywall fallback", error)
        }
      }
    }
  }

  // The below function gives an example of how to track an event using Combine publishers:
  /*
  func trackEventUsingCombine() {
    trackCancellable = Superwall
      .track(event: "MyEvent")
      .sink { paywallState in
        switch paywallState {
        case .presented(let paywallInfo):
          print("paywall info is", paywallInfo)
        case .dismissed(let result):
          switch result.state {
          case .closed:
            print("User dismissed the paywall.")
          case .purchased(productId: let productId):
            print("Purchased a product with id \(productId), then dismissed.")
          case .restored:
            print("Restored purchases, then dismissed.")
          }
        case .skipped(let reason):
          switch reason {
          case .noRuleMatch:
            print("The user did not match any rules")
          case .holdout(let experiment):
            print("The user is in a holdout group, with experiment id: \(experiment.id), group id: \(experiment.groupId), paywall id: \(experiment.variant.paywallId ?? "")")
          case .triggerNotFound:
            print("The trigger wasn't found on the dashboard.")
          case .error(let error):
            print("Failed to present paywall. Consider a native paywall fallback", error)
          }
        }
      }
  }*/
}
