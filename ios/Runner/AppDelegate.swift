import Flutter
import UIKit
import GoogleMaps
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase
    FirebaseApp.configure()

    // Initialize Google Maps. The key comes from ios/Flutter/Secrets.xcconfig
    // (gitignored, see Secrets.xcconfig.example) via the GMSApiKey Info.plist
    // entry - never hardcoded in source. Fails loudly rather than silently
    // shipping a build with no map tiles if the local secret isn't set up.
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsApiKey.isEmpty,
       mapsApiKey != "YOUR_GOOGLE_MAPS_IOS_API_KEY" {
      GMSServices.provideAPIKey(mapsApiKey)
    } else {
      print("⚠️ GoHard: Google Maps API key is not configured. Copy ios/Flutter/Secrets.xcconfig.example to ios/Flutter/Secrets.xcconfig and fill in a real key. Map features will not work until this is fixed.")
    }

    GeneratedPluginRegistrant.register(with: self)

    // Register for remote notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle APNs token registration
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
