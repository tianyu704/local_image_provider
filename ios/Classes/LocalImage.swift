//
//  LocalImage.swift
//  local_image_provider
//
//  Created by Stephen Owens on 2019-09-10.
//

import Foundation

public struct LocalImage:Codable {
    public var id: String
    public var creationDate: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var lat: Double
    public var lon: Double
}
