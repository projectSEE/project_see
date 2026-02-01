import React, { useState } from 'react';
import MessageList from './components/MessageList';
import InputArea from './components/InputArea';
import { initializeGemini, sendMessageToGemini } from './services/gemini';
import { Key } from 'lucide-react';

function App() {
  const [messages, setMessages] = useState([]);
  const [apiKey, setApiKey] = useState('');
  const [isConfigured, setIsConfigured] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleSetApiKey = (e) => {
    e.preventDefault();
    if (apiKey.trim()) {
      initializeGemini(apiKey);
      setIsConfigured(true);
    }
  };

  const handleSendMessage = async ({ text, image, audio }) => {
    setLoading(true);

    // Construct user message for display
    const newUserMsg = { role: 'user', text: text || (audio ? "(Audio Message)" : "(Image)"), image, audio };
    setMessages(prev => [...prev, newUserMsg]);

    try {
      const imageParts = image ? [image] : [];
      // If we have audio, we pass it. If we have text, we pass it.
      // Note: Gemini Flash handles text + audio or text + image.

      let responseText = await sendMessageToGemini(text, imageParts, audio ? audio.inlineData : null);

      const newBotMsg = { role: 'model', text: responseText };
      setMessages(prev => [...prev, newBotMsg]);

      // Simple Text-to-Speech specifically for vision impaired users
      if ('speechSynthesis' in window) {
        const utterance = new SpeechSynthesisUtterance(responseText);
        window.speechSynthesis.speak(utterance);
      }

    } catch (error) {
      console.error(error);
      setMessages(prev => [...prev, { role: 'model', text: "Sorry, I encountered an error. Please try again." }]);
    } finally {
      setLoading(false);
    }
  };

  if (!isConfigured) {
    return (
      <div style={{ padding: '20px', height: '100vh', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
        <h1 style={{ fontSize: '2rem', marginBottom: '20px' }}>Setup Visual Assistant</h1>
        <p style={{ marginBottom: '20px' }}>Please enter your Gemini API Key to continue.</p>
        <form onSubmit={handleSetApiKey} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <label htmlFor="apiKey" className="sr-only">API Key</label>
          <div style={{ position: 'relative' }}>
            <Key style={{ position: 'absolute', top: '12px', left: '12px', color: '#888' }} />
            <input
              id="apiKey"
              type="password"
              value={apiKey}
              onChange={e => setApiKey(e.target.value)}
              placeholder="Paste API Key here"
              style={{
                width: '100%',
                padding: '12px 12px 12px 40px',
                fontSize: '18px',
                backgroundColor: '#222',
                color: '#fff',
                border: '1px solid var(--accent-color)',
                boxSizing: 'border-box'
              }}
            />
          </div>
          <button
            type="submit"
            style={{
              padding: '16px',
              fontSize: '20px',
              backgroundColor: 'var(--accent-color)',
              color: 'black',
              border: 'none',
              fontWeight: 'bold',
              cursor: 'pointer'
            }}
          >
            Start
          </button>
        </form>
      </div>
    );
  }

  return (
    <div className="App" style={{ height: '100vh', display: 'flex', flexDirection: 'column' }}>
      <header style={{ padding: '16px', borderBottom: '1px solid #333' }}>
        <h1 style={{ margin: 0, fontSize: '1.5rem', ariaLevel: 1 }}>Visual Assistant</h1>
      </header>

      <main style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <MessageList messages={messages} />
        {loading && (
          <div style={{
            position: 'fixed',
            bottom: '100px',
            left: 0,
            right: 0,
            textAlign: 'center',
            backgroundColor: 'rgba(0,0,0,0.8)',
            padding: '8px',
            color: 'var(--accent-color)'
          }}>
            Processing...
          </div>
        )}
      </main>

      <InputArea onSendMessage={handleSendMessage} disabled={loading} />
    </div>
  );
}

export default App;
