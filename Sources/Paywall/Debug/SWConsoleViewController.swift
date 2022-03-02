//
//  File.swift
//  
//
//  Created by Jake Mor on 9/13/21.
//

import UIKit
import Foundation
import StoreKit

final class SWConsoleViewController: UIViewController {
  var products: [SKProduct] = []
  var tableViewCellData: [(String, String)] = []

  lazy var productPicker: UIPickerView = {
    let picker = UIPickerView()
    picker.delegate = self
    picker.dataSource = self
    picker.translatesAutoresizingMaskIntoConstraints = false
    picker.tintColor = primaryColor
    picker.backgroundColor = lightBackgroundColor
    return picker
  }()

  lazy var tableView: UITableView = {
    let tableView = UITableView()
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.backgroundView = nil
    tableView.backgroundColor = .clear
    tableView.delegate = self
    tableView.dataSource = self
    tableView.allowsSelection = false
    tableView.allowsMultipleSelection = false
    return tableView
  }()

  init(products: [SKProduct]) {
    super.init(nibName: nil, bundle: nil)
    self.products = products
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = darkBackgroundColor
    title = "Template Variables"
    view.addSubview(tableView)
    view.addSubview(productPicker)

    NSLayoutConstraint.activate([
      productPicker.widthAnchor.constraint(equalTo: view.widthAnchor),
      productPicker.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.618),
      productPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      productPicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      tableView.widthAnchor.constraint(equalTo: view.widthAnchor),
      tableView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
      tableView.bottomAnchor.constraint(equalTo: productPicker.topAnchor),
      tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
    ])

    if #available(iOS 13.0, *) {
      let appearance = UINavigationBarAppearance()
      appearance.configureWithOpaqueBackground()
      appearance.backgroundColor = lightBackgroundColor
      appearance.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
      navigationController?.navigationBar.standardAppearance = appearance
      navigationController?.navigationBar.scrollEdgeAppearance = navigationController?.navigationBar.standardAppearance
    }

    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Done",
      style: .plain,
      target: self,
      action: #selector(addTapped)
    )
    navigationItem.rightBarButtonItem?.tintColor = primaryColor
    if #available(iOS 11.0, *) {
      navigationItem.largeTitleDisplayMode = .never
    }

    productPicker.reloadAllComponents()
    reloadTableView()
  }

	@objc func addTapped() {
		self.dismiss(animated: true, completion: nil)
	}

  func reloadTableView() {
    let index = productPicker.selectedRow(inComponent: 0)

    tableViewCellData = []
    let product = products[index]
    for i in product.legacyEventData {
      tableViewCellData.append(i)
    }

    tableViewCellData.sort { first, second in
      let (firstKey, _) = first
      let (secondKey, _) = second
      return firstKey < secondKey
    }

    tableView.reloadData()
  }
}

extension SWConsoleViewController: UIPickerViewDelegate, UIPickerViewDataSource {
  func numberOfComponents(in pickerView: UIPickerView) -> Int {
    1
  }

  func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
    products.count
  }

  func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
    let attributedString = NSAttributedString(
      string: products[row].productIdentifier,
      attributes: [NSAttributedString.Key.foregroundColor: primaryColor]
    )
    return attributedString
  }

  func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
    reloadTableView()
  }
}

extension SWConsoleViewController: UITableViewDelegate, UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    return 1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return tableViewCellData.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")

    let productLevels = ["primary", "secondary", "tertiary"]
    var selectedProduct: String?
    let i = productPicker.selectedRow(inComponent: 0)

    if i < productLevels.count {
      selectedProduct = productLevels[i]
    }

    let (key, value) = tableViewCellData[indexPath.row]
    cell.textLabel?.text = value
    cell.textLabel?.textColor = .white
    let text: String
    if let selectedProduct = selectedProduct {
      text = "\(selectedProduct).\(key)"
    } else {
      text = key
    }
    cell.detailTextLabel?.text = "{{ \(text) }}"
    cell.detailTextLabel?.textColor = UIColor.white.withAlphaComponent(0.618)
    cell.backgroundView = nil
    cell.backgroundColor = .clear
    cell.contentView.backgroundColor = .clear

    return cell
  }
}
