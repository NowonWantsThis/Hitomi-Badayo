import Foundation

enum NetworkSessionPrivacy {
    static func disableSystemCredentialPersistence(in configuration: URLSessionConfiguration) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
    }
}
