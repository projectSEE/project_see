import { GoogleGenerativeAI } from "@google/generative-ai";

let genAI = null;
let model = null;

export const initializeGemini = (apiKey) => {
  genAI = new GoogleGenerativeAI(apiKey);
  model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
};

export const sendMessageToGemini = async (promptText, imageParts = [], audioPart = null) => {
  if (!model) throw new Error("Gemini API not initialized. Please provide an API Key.");

  try {
    const parts = [];
    if (promptText) parts.push({ text: promptText });
    
    // Add images if any
    if (imageParts && imageParts.length > 0) {
      parts.push(...imageParts);
    }

    // Add audio if any (Gemini expects inline data for audio usually)
    if (audioPart) {
        parts.push(audioPart);
    }
    
    const result = await model.generateContent(parts);
    const response = await result.response;
    return response.text();
  } catch (error) {
    console.error("Error communicating with Gemini:", error);
    throw error;
  }
};

export const fileToGenerativePart = async (file) => {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onloadend = () => {
             const base64Data = reader.result.split(',')[1];
             resolve({
                 inlineData: {
                     data: base64Data,
                     mimeType: file.type
                 }
             });
        };
        reader.onerror = reject;
        reader.readAsDataURL(file);
    });
}
