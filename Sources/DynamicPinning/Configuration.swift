//
//  Configuration.swift
//  DynamicPinning
//
//  Created by Artem Melnik on 17.10.2025.
//

import Foundation

/// Holds the SDK's configuration, provided during initialization.
internal struct Configuration {
    let signingPublicKey: String
    let pinningServiceURL: URL
    let domains: [String]
    let includeBackupPins: Bool
}
