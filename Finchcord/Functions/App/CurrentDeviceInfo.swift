//
//  CurrentDeviceInfo.swift
//  Stossycord
//
//  Created by Stossy11 on 19/9/2024.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif


class CurrentDeviceInfo {
    
    public static let shared = CurrentDeviceInfo()
    
    public init() {}
    
    var Country: String = Locale.current.region?.identifier ?? "US"
    
    let currentTimeZone = TimeZone.current

    // Get the time zone identifier (e.g., "America/New_York")
    let timeZoneIdentifier = TimeZone.current.identifier
    
    let preferredLanguages = Locale.preferredLanguages
    
    #if os(macOS)
    let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
    #else
    let systemVersion = UIDevice.current.systemVersion
    #endif
    
    public var deviceInfo: DeviceInfo {
        let deviceInfo = DeviceInfo(
            os: "Mac OS X", // from C++: "Windows" -> "Mac OS X"
            browser: "Safari", // from C++: "Chrome" -> "Safari"
            device: "", // same as C++
            systemLocale: "en-US", // fixed as per C++
            browserUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X \(self.systemVersion)) AppleWebKit/\(getWebKitVersion()) (KHTML, like Gecko) Version/17.4 Safari/\(getWebKitVersion())", // adapted UA string
            browserVersion: "17.4", // Safari version
            osVersion: self.systemVersion, // dynamic OS version
            referrer: "", // same as C++
            referringDomain: "", // same as C++
            referrerCurrent: "", // same as C++
            referringDomainCurrent: "", // same as C++
            releaseChannel: "stable", // same as C++
            clientBuildNumber: 318966, // from m_build_number
            clientEventSource: "", // same as C++
            designId: 0, // no equivalent in C++, assuming safe default
            hasClientMods: false, // new: from C++ msg.Properties.HasClientMods
            capabilities: 4605 // new: from C++ msg.Capabilities
        )
        return deviceInfo
    }
    
    
}
