// File generated manually for Firebase configuration
// Project: kitahack-8b81a

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // TODO: Replace these values with your actual Firebase project configuration

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD5h7MV3o67ubBeNIeGtJxsJchnpYHNGtA',
    appId: '1:777852765437:android:327159179f18e7fc48aa94',
    messagingSenderId: '777852765437',
    projectId: 'kitahack-8b81a',
    databaseURL: 'https://kitahack-8b81a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'kitahack-8b81a.firebasestorage.app',
  );

  // Get these from Firebase Console -> Project Settings -> General -> Your apps

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBDxEIGunvRzEymtJxSPt9OGn0MHGLy3Fs',
    appId: '1:777852765437:ios:56c6abaeddb8933348aa94',
    messagingSenderId: '777852765437',
    projectId: 'kitahack-8b81a',
    databaseURL: 'https://kitahack-8b81a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'kitahack-8b81a.firebasestorage.app',
    iosBundleId: 'com.kitahack.blindAssist',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyASwclUYj-lxfqk4srNZbzMpsX9-yUULSw',
    appId: '1:777852765437:web:e5d49fd706036b5648aa94',
    messagingSenderId: '777852765437',
    projectId: 'kitahack-8b81a',
    authDomain: 'kitahack-8b81a.firebaseapp.com',
    databaseURL: 'https://kitahack-8b81a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'kitahack-8b81a.firebasestorage.app',
    measurementId: 'G-10P4TVD4ZT',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBDxEIGunvRzEymtJxSPt9OGn0MHGLy3Fs',
    appId: '1:777852765437:ios:56c6abaeddb8933348aa94',
    messagingSenderId: '777852765437',
    projectId: 'kitahack-8b81a',
    databaseURL: 'https://kitahack-8b81a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'kitahack-8b81a.firebasestorage.app',
    iosBundleId: 'com.kitahack.blindAssist',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyASwclUYj-lxfqk4srNZbzMpsX9-yUULSw',
    appId: '1:777852765437:web:754dfb03c64cda6d48aa94',
    messagingSenderId: '777852765437',
    projectId: 'kitahack-8b81a',
    authDomain: 'kitahack-8b81a.firebaseapp.com',
    databaseURL: 'https://kitahack-8b81a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'kitahack-8b81a.firebasestorage.app',
    measurementId: 'G-CE2470VSE2',
  );

}