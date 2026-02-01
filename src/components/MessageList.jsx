import React, { useRef, useEffect } from 'react';
import ReactMarkdown from 'react-markdown';

const MessageList = ({ messages }) => {
    const bottomRef = useRef(null);

    // Auto-scroll to bottom
    useEffect(() => {
        bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [messages]);

    return (
        <div style={{
            flex: 1,
            overflowY: 'auto',
            padding: '16px',
            paddingBottom: '100px', // Space for InputArea
            display: 'flex',
            flexDirection: 'column',
            gap: '16px'
        }}>
            {messages.length === 0 && (
                <div style={{ textAlign: 'center', marginTop: '40px', color: '#888' }}>
                    <p>Welcome! I am your visual assistant.</p>
                    <p>Tap the microphone to speak, or upload an image.</p>
                </div>
            )}

            {messages.map((msg, index) => (
                <div
                    key={index}
                    style={{
                        alignSelf: msg.role === 'user' ? 'flex-end' : 'flex-start',
                        maxWidth: '85%',
                        backgroundColor: msg.role === 'user' ? '#333' : '#111',
                        border: msg.role === 'user' ? '1px solid #555' : '1px solid var(--accent-color)',
                        borderRadius: '12px',
                        padding: '12px',
                        color: 'var(--text-main)',
                        fontSize: '1.2rem',
                        wordBreak: 'break-word'
                    }}
                >
                    <strong>{msg.role === 'user' ? 'You' : 'Assistant'}</strong>
                    {msg.image && (
                        <div style={{ marginTop: '8px', marginBottom: '8px' }}>
                            <span style={{ fontSize: '0.9rem', color: '#ccc' }}>[Image Uploaded]</span>
                        </div>
                    )}
                    {msg.audio && (
                        <div style={{ marginTop: '8px', marginBottom: '8px' }}>
                            <span style={{ fontSize: '0.9rem', color: '#ccc' }}>[Audio Sent]</span>
                        </div>
                    )}
                    <div style={{ marginTop: '4px' }}>
                        <ReactMarkdown>{msg.text}</ReactMarkdown>
                    </div>
                </div>
            ))}
            <div ref={bottomRef} />
        </div>
    );
};

export default MessageList;
