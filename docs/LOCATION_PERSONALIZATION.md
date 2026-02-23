
# Location-Based Personalization: "Digital Memories for Locations"

This feature enables the Visual Assistant to provide context-aware, personalized guidance by "remembering" specific details about locations important to the user.

## The Concept

The system allows the AI to access a digital memory bank of location-specific notes. Instead of generic advice, the AI can offer highly specific instructions based on where the user is standing.

## How It Works

1.  **Personal Database**:
    Each user has a private collection of `saved_locations` in the database.
    *   **Example Entry**:
        *   **Name**: "My Office Entrance"
        *   **Location**: `[3.1390, 101.6869]`
        *   **Personal Note**: "The badge reader is on the left wall at waist height. Watch out for the glass door."

2.  **Automatic Detection**:
    *   When the user opens the chat or sends a message, the app checks their current GPS coordinates.
    *   If the user is within a small radius (e.g., 20 meters) of a saved location, the app retrieves the corresponding note.

3.  **Smart Context Injection**:
    *   The retrieved note is silently injected into the AI's system prompt.
    *   **Result**: The AI "knows" the context before the user even asks.

## User Benefits

### 1. Enhanced Safety
*   **Proactive Warnings**: The user doesn't need to remember every hazard. The AI automatically reminds them of critical safety info (e.g., "Mind the gap at this station", "Uneven pavement here").

### 2. Personalized Convenience
*   **Tailored Guidance**: The AI can offer specific help relevant to the user's routine (e.g., "You're at your favorite cafe. Do you want to know the daily special?").

### 3. Zero-Friction Interaction
*   **No Repetition**: The user doesn't need to type lengthy context ("I'm at the office, remember the door..."). The AI is already aware of the surroundings and the user's specific needs for that location.
