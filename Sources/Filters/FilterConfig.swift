//
//  FilterConfig.swift
//
//
//  Created by Jake Gundersen on 5/5/24.
//

import Foundation

public struct FilterConfig {
    public let configOptions: [FilterConfigOption]
    
    public init(configOptions: [FilterConfigOption]) {
        self.configOptions = configOptions
    }
    
//    convenience initializer for single parameter filters
    public init?(key: String, filter: String, value: Any) {
        var filterConfigOption: FilterConfigOption?
        if let flt = value as? Float {
            filterConfigOption = FilterConfigOption(keyName: key, filterName: filter, floatValue: flt)
        } else if let doub = value as? Double {
            filterConfigOption = FilterConfigOption(keyName: key, filterName: filter, floatValue: Float(doub))
        } else if let str = value as? String {
            filterConfigOption = FilterConfigOption(keyName: key, filterName: filter, stringValue: str)
        } else if let integer = value as? Int {
            filterConfigOption = FilterConfigOption(keyName: key, filterName: filter, intValue: integer)
        }
        
        if let fco = filterConfigOption {
            self.configOptions = [fco]
        } else {
            return nil
        }
    }
}

public struct FilterConfigOption {
    public enum FilterConfigOptionType {
        case coreImage
    }
    
    public enum ValueType {
        case Float
        case String
        case Int
    }
    
    public let keyName: String
    public let filterName: String = ""
    var floatValue: Float = 0.0
    var stringValue: String = ""
    var intValue: Int = 0
    let configType: FilterConfigOptionType
    let valueType: ValueType
    
    public init(keyName: String, filterName: String, configType: FilterConfigOptionType = .coreImage, floatValue: Float) {
        self.keyName = keyName
        self.configType = configType
        self.valueType = .Float
        self.floatValue = floatValue
    }
    
    public init(keyName: String, filterName: String, configType: FilterConfigOptionType = .coreImage, stringValue: String) {
        self.keyName = keyName
        self.configType = configType
        self.valueType = .String
        self.stringValue = stringValue
    }
    
    public init(keyName: String, filterName: String, configType: FilterConfigOptionType = .coreImage, intValue: Int) {
        self.keyName = keyName
        self.configType = configType
        self.valueType = .Int
        self.intValue = intValue
    }
    
    public func configValue() -> Any {
        switch valueType {
        case .Float:
            return floatValue
        case .String:
            return stringValue
        case .Int:
            return intValue
        }
    }
}
