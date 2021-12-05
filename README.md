# Gleap iOS SDK

![Gleap iOS SDK Intro](https://raw.githubusercontent.com/GleapSDK/Gleap-iOS-SDK/main/Resources/GleapHeaderImage.png)

The [Gleap SDK for iOS](https://www.gleap.io) is the easiest way to integrate Gleap into your apps!

You have two ways to set up the Gleap SDK for iOS. The easiest way ist to install and link the SDK with CocoaPods. If you haven't heard about [CocoaPods](https://cocoapods.org) yet, we strongly encourage you to check out their getting started here (it's super easy to get started & worth using 😍)

## Docs & Examples

Checkout our [documentation](https://docs.gleap.io/ios) for full reference.


## Installation with Swift Package Manager

The [Swift Package Manager](https://www.swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the swift compiler. It is in early development, but Gleap does support its use on supported platforms.

To get started, open your Xcode project and select File > Add packages...

Now you need to paste the following Package URL to the search bar in the top right corner. Hit enter to confirm.

**Package URL:**
```
https://github.com/GleapSDK/Gleap-iOS-SDK
```

Now confirm with add package. The Gleap SDK is almost installed successfully.
Let's carry on with the initialization 🎉

![Gleap iOS SDK for Swift Package Manager](https://raw.githubusercontent.com/GleapSDK/Gleap-iOS-SDK/main/Resources/GleapSwiftPackageManager.png)

## Installation with CocoaPods

Open a terminal window and navigate to the location of the Xcode project for your app.

**Create a Podfile if you don't have one:**

```
$ pod init
```

**Open your Podfile and add:**

```
pod 'Gleap'
```

**Save the file and run:**

```
$ pod install
```

This creates an .xcworkspace file for your app. Use this file for all future development on your application.

The Gleap SDK is almost installed successfully.
Let's carry on with the initialization 🎉

Open your XCode project (.xcworkspace) and open your App Delegate (AppDelegate.swift)


**Import the Gleap SDK**

Import the Gleap SDK by adding the following import below your other imports.

```
import Gleap
```

**Initialize the SDK**

The last step is to initialize the Gleap SDK by adding the following Code to the end of the ```applicationDidFinishLaunchingWithOptions``` delegate:

```
Gleap.initialize(withToken: "YOUR_API_KEY")
```

(Your API key can be found in the project settings within Gleap)
