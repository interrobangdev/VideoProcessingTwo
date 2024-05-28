//
//  FilterAnimator.swift
//  
//
//  Created by Jake Gundersen on 5/14/24.
//

import Foundation

public class LinearFunction: TweenFunctionProvider {
    public init() {}
    
    public func tweenValue(input: Double) -> Double {
        return input
    }
}



public class FilterAnimator {
    public enum AnimationValueType {
        case SingleValue
        case Point
    }
    
    var id: String = UUID().uuidString
    var type: AnimationValueType
    var animationProperty: FilterProperty
    var startValue: Double?
    var endValue: Double?
    var startPoint: CGPoint?
    var endPoint: CGPoint?
    var startTime: Double
    var endTime: Double
    var tweenFunctionProvider: TweenFunctionProvider
    
    public init(id: String = UUID().uuidString, type: AnimationValueType, animationProperty: FilterProperty, startValue: Double? = nil, endValue: Double? = nil, startPoint: CGPoint? = nil, endPoint: CGPoint? = nil, startTime: Double, endTime: Double, tweenFunctionProvider: TweenFunctionProvider) {
        self.id = id
        self.type = type
        self.startValue = startValue
        self.endValue = endValue
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.startTime = startTime
        self.endTime = endTime
        self.tweenFunctionProvider = tweenFunctionProvider
        self.animationProperty = animationProperty
    }
    
    public func tweenValue(time: Double) -> Any {
        var percentComplete = (time - startTime) / (endTime - startTime)
        if percentComplete > 1.0 {
            percentComplete = 1.0
        } else if percentComplete < 0.0 {
            percentComplete = 0.0
        }
        percentComplete = tweenFunctionProvider.tweenValue(input: percentComplete)
        
        if type == .SingleValue {
            guard let sv = startValue,
                  let ev = endValue else { return percentComplete }
            return ((ev - sv) * percentComplete) + sv
        } else {
//        else if type == .Point {
            guard let sp = startPoint,
                  let ep = endPoint else { return CGPoint.zero }
            return ((ep - sp) * percentComplete) + sp
        }
    }
}
