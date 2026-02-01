import React, { useState, useRef } from 'react';
import { Mic, Send, Image as ImageIcon, X, CircleStop } from 'lucide-react';
import { fileToGenerativePart } from '../services/gemini';

const InputArea = ({ onSendMessage, disabled }) => {
    const [inputText, setInputText] = useState('');
    const [isRecording, setIsRecording] = useState(false);
    const [selectedImage, setSelectedImage] = useState(null);
    const mediaRecorderRef = useRef(null);
    const audioChunksRef = useRef([]);

    const handleStartRecording = async () => {
        try {
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            mediaRecorderRef.current = new MediaRecorder(stream);
            audioChunksRef.current = [];

            mediaRecorderRef.current.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    audioChunksRef.current.push(event.data);
                }
            };

            mediaRecorderRef.current.onstop = () => {
                const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/webm' }); // Use webm for wider support
                // Convert blob to base64 to send to parent/Gemini
                const reader = new FileReader();
                reader.readAsDataURL(audioBlob);
                reader.onloadend = () => {
                    const base64data = reader.result.split(',')[1];
                    onSendMessage({
                        text: null,
                        image: selectedImage ? selectedImage.data : null, // Pass base64 part
                        audio: { inlineData: { data: base64data, mimeType: 'audio/webm' } }
                    });
                    setSelectedImage(null); // Clear image after send
                }
            };

            mediaRecorderRef.current.start();
            setIsRecording(true);
        } catch (err) {
            console.error("Error accessing microphone:", err);
            alert("Could not access microphone. Please ensure permissions are granted.");
        }
    };

    const handleStopRecording = () => {
        if (mediaRecorderRef.current && isRecording) {
            mediaRecorderRef.current.stop();
            setIsRecording(false);
            // Stop all tracks to release mic
            mediaRecorderRef.current.stream.getTracks().forEach(track => track.stop());
        }
    };

    const handleImageSelect = async (e) => {
        const file = e.target.files[0];
        if (file) {
            const part = await fileToGenerativePart(file);
            setSelectedImage({ file, data: part });
        }
    };

    const handleTextSend = async (e) => {
        e.preventDefault();
        if (!inputText.trim() && !selectedImage) return;

        onSendMessage({
            text: inputText,
            image: selectedImage ? selectedImage.data : null,
            audio: null
        });
        setInputText('');
        setSelectedImage(null);
    };

    return (
        <div className="input-area" style={{
            position: 'fixed',
            bottom: 0,
            left: 0,
            right: 0,
            backgroundColor: '#000',
            borderTop: '2px solid var(--accent-color)',
            padding: '16px',
            display: 'flex',
            flexDirection: 'column',
            gap: '12px'
        }}>
            {/* Image Preview */}
            {selectedImage && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', padding: '8px', backgroundColor: '#333' }}>
                    <img src={URL.createObjectURL(selectedImage.file)} alt="Selected attachment" style={{ height: '50px', width: '50px', objectFit: 'cover' }} />
                    <button
                        onClick={() => setSelectedImage(null)}
                        aria-label="Remove image"
                        className="touch-target"
                        style={{ background: 'none', border: 'none', color: 'var(--text-main)' }}
                    >
                        <X size={24} />
                    </button>
                </div>
            )}

            <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
                {/* Image Upload */}
                <label className="touch-target" style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    cursor: 'pointer',
                    padding: '12px',
                    backgroundColor: 'var(--surface-1)',
                    borderRadius: '50%'
                }}>
                    <input
                        type="file"
                        accept="image/*"
                        onChange={handleImageSelect}
                        style={{ display: 'none' }}
                        disabled={disabled}
                    />
                    <ImageIcon size={32} color="var(--accent-color)" />
                    <span className="sr-only">Upload Image</span>
                </label>

                {/* Text Input */}
                <input
                    type="text"
                    value={inputText}
                    onChange={(e) => setInputText(e.target.value)}
                    placeholder={isRecording ? "Recording audio..." : "Type a message..."}
                    disabled={disabled || isRecording}
                    onKeyDown={(e) => e.key === 'Enter' && handleTextSend(e)}
                    style={{
                        flex: 1,
                        padding: '12px',
                        fontSize: '18px',
                        backgroundColor: 'var(--surface-2)',
                        color: 'var(--text-main)',
                        border: '1px solid var(--accent-color)',
                        borderRadius: '8px',
                        height: '48px'
                    }}
                />

                {/* Send / Mic Button */}
                {inputText || selectedImage ? (
                    <button
                        onClick={handleTextSend}
                        disabled={disabled}
                        className="touch-target"
                        aria-label="Send message"
                        style={{
                            backgroundColor: 'var(--accent-color)',
                            border: 'none',
                            borderRadius: '50%',
                            padding: '12px',
                            color: '#000'
                        }}
                    >
                        <Send size={32} />
                    </button>
                ) : (
                    <button
                        onClick={isRecording ? handleStopRecording : handleStartRecording}
                        disabled={disabled}
                        className="touch-target"
                        aria-label={isRecording ? "Stop recording" : "Start recording"}
                        style={{
                            backgroundColor: isRecording ? '#FF0000' : 'var(--accent-color)',
                            border: 'none',
                            borderRadius: '50%',
                            padding: '12px',
                            color: '#000'
                        }}
                    >
                        {isRecording ? <CircleStop size={32} /> : <Mic size={32} />}
                    </button>
                )}
            </div>
        </div>
    );
};

export default InputArea;
