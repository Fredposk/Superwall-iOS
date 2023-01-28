//
//  File.swift
//  
//
//  Created by Yusuf Tör on 13/12/2022.
//

import Foundation
import StoreKit

/// The protocol that handles Superwall's subscription-related logic.
///
/// By default, the Superwall SDK handles all subscription-related logic.
///
/// However, if you'd like more control, you can return a ``SubscriptionController`` in
/// the delegate when configuring the SDK via
/// ``Superwall/configure(apiKey:delegate:options:)-65jyx``.
///
/// To learn how to implement the ``SubscriptionController`` in your app
/// and best practices, see <doc:AdvancedConfiguration>.
@MainActor
public protocol SubscriptionController: AnyObject {
  /// Called when the user initiates purchasing of a product.
  ///
  /// Add your purchase logic here and return its result. You can use Apple's StoreKit APIs,
  /// or if you use RevenueCat, you can call [`Purchases.shared.purchase(product:)`](https://revenuecat.github.io/purchases-ios-docs/4.13.4/documentation/revenuecat/purchases/purchase(product:completion:)).
  /// - Parameters:
  ///   - product: The `SKProduct` the user would like to purchase.
  ///
  /// - Returns: A``PurchaseResult`` object, which is the result of your purchase logic.
  /// **Note**: Make sure you handle all cases of ``PurchaseResult``.
  func purchase(product: SKProduct) async -> PurchaseResult

  /// Called when the user initiates a restore.
  ///
  /// Add your restore logic here, making sure that the user's subscription status is updated after restore,
  /// and return its result.
  ///
  /// - Returns: A boolean that's `true` if the user's purchases were restored or `false` if they weren't.
  func restorePurchases() async -> Bool

  /// Decides whether a paywall should be presented based on whether the user has an active
  /// subscription.
  ///
  /// - Warning: A paywall will never show if this function returns `true`.
  /// - Returns: A boolean that indicates whether or not the user has an active subscription.
  func isUserSubscribed() -> Bool
}