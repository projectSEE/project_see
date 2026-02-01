const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

// Trigger: Runs whenever a NEW document is created in the "hazards" collection
exports.sendHazardAlert = onDocumentCreated("hazards/{docId}", async (event) => {
  
  // 1. Get the data that was just saved
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();

  const hazardType = data.type;

  // 2. Create the Notification Message
  const message = {
    notification: {
      title: "🚨 DANGER REPORTED!",
      body: `Review needed: ${hazardType} detected nearby.`,
    },
    data: {
      lat: String(data.latitude),
      long: String(data.longitude),
      sound: "alarm"
    },
    // Topic: Send to everyone listening to "safety_alerts"
    topic: "safety_alerts", 
  };

  // 3. Send the message using FCM
  try {
    await getMessaging().send(message);
    console.log("Alert sent successfully:", message);
  } catch (error) {
    console.error("Error sending alert:", error);
  }
});