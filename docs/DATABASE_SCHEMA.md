# KitaHack Firebase Realtime Database Documentation

This document describes the Firebase Realtime Database schema for the Visual Assistant App. Use this as a reference for API design, frontend development, and Firebase security rules.

---

## Overview

The database stores four main categories of data:
1. **User Profiles** - Basic user information
2. **Accessibility Settings** - User preferences for accessibility features
3. **Conversation History** - Chat messages with 3-day retention
4. **Points of Interest (POIs)** - Location data with accessibility information

---

## Database Structure

```
root/
├── users/
│   └── {userId}/
│       ├── profile/
│       ├── accessibilitySettings/
│       └── conversations/
│
└── pois/
    └── {uniquePOIId}/
```

---

## Schema Details

### 1. User Profile

**Path:** `/users/{userId}/profile`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | User's display name |
| `email` | string | Yes | User's email address |
| `lastActive` | number (timestamp) | Yes | Unix timestamp of last activity |

**Example:**
```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "lastActive": 1706385600000
}
```

---

### 2. Accessibility Settings

**Path:** `/users/{userId}/accessibilitySettings`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `visualImpairment` | boolean | `false` | User has visual impairment |
| `hearingImpairment` | boolean | `false` | User has hearing impairment |
| `mobilityImpairment` | boolean | `false` | User has mobility impairment |
| `preferredVoice` | string | `"Kore"` | TTS voice preference |
| `speechRate` | number | `1.0` | Speech rate (0.5 - 2.0) |
| `highContrastMode` | boolean | `true` | Enable high contrast UI |

**Example:**
```json
{
  "visualImpairment": true,
  "hearingImpairment": false,
  "mobilityImpairment": false,
  "preferredVoice": "Kore",
  "speechRate": 0.9,
  "highContrastMode": true
}
```

---

### 3. Conversation History

**Path:** `/users/{userId}/conversations/{messageId}`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `role` | string | Yes | `"user"` or `"assistant"` |
| `content` | string | Yes | Message text content |
| `timestamp` | number | Yes | Unix timestamp (milliseconds) |
| `hasImage` | boolean | No | Whether message included an image |

**Retention Policy:** Messages older than **3 days** are automatically deleted.

**Example:**
```json
{
  "role": "user",
  "content": "What's near me?",
  "timestamp": 1706385600000,
  "hasImage": false
}
```

---

### 4. Points of Interest (POIs)

**Path:** `/pois/{uniquePOIId}`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | POI display name |
| `type` | string | Yes | Category (see types below) |
| `description` | string | Yes | Detailed description |
| `coords` | object | Yes | Geographic coordinates |
| `coords.latitude` | number | Yes | Latitude coordinate |
| `coords.longitude` | number | Yes | Longitude coordinate |
| `accessibilityFeatures` | object | Yes | Accessibility info |
| `audioGuidanceURL` | string | No | URL to audio guidance file |
| `contactInfo` | string | No | Contact phone/email |
| `safetyNotes` | string | No | Safety warnings or tips |
| `lastUpdated` | number | Yes | Unix timestamp of last update |

**POI Types:**
- `shop_entrance`
- `restaurant`
- `public_transport`
- `parking`
- `hospital`
- `restroom`
- `elevator`
- `ramp`
- `crossing`

**Accessibility Features Object:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `wheelchairAccessible` | boolean | `false` | Wheelchair accessible |
| `hasRamp` | boolean | `false` | Has accessibility ramp |
| `hasElevator` | boolean | `false` | Has elevator |
| `brailleSignage` | boolean | `false` | Has braille signage |
| `audioAnnouncements` | boolean | `false` | Has audio announcements |
| `tactileFlooring` | boolean | `false` | Has tactile floor indicators |

**Example:**
```json
{
  "name": "KitaHack Cafe Entrance",
  "type": "shop_entrance",
  "description": "The main entrance to KitaHack Cafe. There's a slight ramp leading up to double automatic sliding doors. The cafe is known for its excellent coffee and accessible seating.",
  "coords": {
    "latitude": 3.1390,
    "longitude": 101.6869
  },
  "accessibilityFeatures": {
    "wheelchairAccessible": true,
    "hasRamp": true,
    "hasElevator": false,
    "brailleSignage": false,
    "audioAnnouncements": false,
    "tactileFlooring": false
  },
  "audioGuidanceURL": "gs://your-project-id.appspot.com/audio/kitahack_cafe_entrance.mp3",
  "contactInfo": "+60123456789",
  "safetyNotes": "Watch out for delivery bikes in the morning. Pavement can be uneven directly outside the door.",
  "lastUpdated": 1706385600000
}
```

---

## Firebase Security Rules (Recommended)

```javascript
{
  "rules": {
    "users": {
      "$userId": {
        // Users can only read/write their own data
        ".read": "auth != null && auth.uid == $userId",
        ".write": "auth != null && auth.uid == $userId"
      }
    },
    "pois": {
      // Anyone authenticated can read POIs
      ".read": "auth != null",
      // Only admins can write POIs
      ".write": "auth != null && root.child('admins').child(auth.uid).exists()"
    }
  }
}
```

---

## API Usage Examples

### Reading User Settings (Dart/Flutter)
```dart
final ref = FirebaseDatabase.instance.ref('users/$userId/accessibilitySettings');
final snapshot = await ref.get();
final settings = snapshot.value as Map<dynamic, dynamic>?;
```

### Querying Nearby POIs
```dart
// Query all POIs and filter by distance client-side
// (Firebase RTDB doesn't support geoqueries natively)
final ref = FirebaseDatabase.instance.ref('pois');
final snapshot = await ref.get();
```

### Saving a Message
```dart
final ref = FirebaseDatabase.instance.ref('users/$userId/conversations').push();
await ref.set({
  'role': 'user',
  'content': messageText,
  'timestamp': ServerValue.timestamp,
  'hasImage': false,
});
```

---

## Contact

For questions about this schema, contact the development team.

**Last Updated:** February 2026
