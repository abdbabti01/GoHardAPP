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
    // entry - never hardcoded in source. A missing key is NOT harmless: the
    // Maps SDK aborts the app (GMSServices checkServicePreconditions) the
    // first time a map is created. The "Check Google Maps key" build phase
    // (ios/scripts/check_maps_key.sh) fails keyless builds, so reaching the
    // else-branch means an explicit compile-only build
    // (GOHARD_ALLOW_MISSING_MAPS_KEY = YES) that must never be installed for
    // testing or distributed.
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsApiKey.isEmpty,
       mapsApiKey != "YOUR_GOOGLE_MAPS_IOS_API_KEY" {
      GMSServices.provideAPIKey(mapsApiKey)
    } else {
      print("🛑 GoHard: Google Maps API key is NOT configured. This is a compile-only build: opening Running (any map) will CRASH the app. Copy ios/Flutter/Secrets.xcconfig.example to ios/Flutter/Secrets.xcconfig and set a real iOS key before installing on a device.")
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
