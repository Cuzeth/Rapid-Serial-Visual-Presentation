//
//  Item.swift
//  pulsereader
//
//  Created by CZTH on 2/13/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
