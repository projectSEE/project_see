const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendHazardNotification = onDocumentCreated("hazards/{hazardId}", async (event) => {
    const hazardData = event.data.data();

    const message = {
        notification: {
            title: "🚨 PROJECT S.E.E. ALERT",
            body: `Emergency: ${hazardData.type} detected!`,
        },
        topic: "emergency_broadcast",
    };

    try {
        await admin.messaging().send(message);
        console.log("Push Notification Sent Successfully!");
    } catch (error) {
        console.error("Error sending notification:", error);
    }
});