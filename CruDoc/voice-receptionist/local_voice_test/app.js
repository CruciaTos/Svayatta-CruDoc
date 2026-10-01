// Local Voice Testing Sandbox - Audio Client
// Protocols:
//   Input:  16,000 Hz, 1-channel, 16-bit linear PCM (little-endian binary frames)
//   Output: 24,000 Hz, 1-channel, 16-bit linear PCM (little-endian binary frames)
//   Events: JSON string frames for transcript, speaking status, clinic metadata, and error handling

(function () {
  'use strict';

  // DOM Elements
  const btnStart = document.getElementById('btnStart');
  const btnStop = document.getElementById('btnStop');
  const btnClearTranscript = document.getElementById('btnClearTranscript');
  const wsStatusChip = document.getElementById('wsStatusChip');
  const wsStatusDot = document.getElementById('wsStatusDot');
  const wsStatusText = document.getElementById('wsStatusText');
  const sessionStateBadge = document.getElementById('sessionStateBadge');
  const micStatusText = document.getElementById('micStatusText');
  const speakerStatusText = document.getElementById('speakerStatusText');
  const clinicNameDisplay = document.getElementById('clinicNameDisplay');
  const orbWrapper = document.getElementById('orbWrapper');
  const visualizerLabel = document.getElementById('visualizerLabel');
  const waveformCanvas = document.getElementById('waveformCanvas');
  const transcriptFeed = document.getElementById('transcriptFeed');
  const emptyState = document.getElementById('emptyState');
  const logToggle = document.getElementById('logToggle');
  const logTerminal = document.getElementById('logTerminal');
  const logContent = document.getElementById('logContent');
  const logCountBadge = document.getElementById('logCountBadge');

  const canvasCtx = waveformCanvas ? waveformCanvas.getContext('2d') : null;

  // Audio & WebSocket State
  let ws = null;
  let micMediaStream = null;
  let audioInputContext = null;
  let audioOutputContext = null;
  let scriptProcessor = null;
  let inputSource = null;
  let playbackNextTime = 0;
  let isSessionActive = false;
  let logCount = 0;
  let animFrameId = null;
  let currentAudioLevel = 0;

  // Helper: Append log
  function logEvent(source, message, data = null) {
    const timestamp = new Date().toISOString().substring(11, 19);
    logCount++;
    if (logCountBadge) logCountBadge.textContent = logCount;
    const line = `[${timestamp}] [${source}] ${message} ${data ? JSON.stringify(data) : ''}\n`;
    if (logContent) {
      logContent.textContent += line;
      logTerminal.scrollTop = logTerminal.scrollHeight;
    }
  }

  // Toggle log terminal
  if (logToggle && logTerminal) {
    logToggle.addEventListener('click', () => {
      logTerminal.classList.toggle('hidden');
    });
  }

  // Update WS Status
  function setConnectionStatus(state, label) {
    if (!wsStatusDot || !wsStatusText) return;
    wsStatusDot.className = `status-dot ${state}`;
    wsStatusText.textContent = label;
  }

  // Update Visualizer State
  function setOrbState(state, label) {
    if (!orbWrapper || !visualizerLabel) return;
    orbWrapper.className = `orb-wrapper ${state}`;
    visualizerLabel.textContent = label;
    if (sessionStateBadge) {
      sessionStateBadge.textContent = state ? state.toUpperCase() : 'IDLE';
    }
  }

  // Clear Transcript
  if (btnClearTranscript) {
    btnClearTranscript.addEventListener('click', () => {
      transcriptFeed.innerHTML = '';
      if (emptyState) transcriptFeed.appendChild(emptyState);
    });
  }

  // Append Transcript Message
  function appendTranscript(role, text) {
    if (!text || !text.trim()) return;
    if (emptyState && emptyState.parentNode === transcriptFeed) {
      transcriptFeed.removeChild(emptyState);
    }

    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const isUser = role === 'user';

    const msgEl = document.createElement('div');
    msgEl.className = `chat-msg ${isUser ? 'user' : 'assistant'}`;

    const headerEl = document.createElement('div');
    headerEl.className = 'msg-header';
    headerEl.textContent = `${isUser ? 'Caller (You)' : 'AI Receptionist'} • ${time}`;

    const bubbleEl = document.createElement('div');
    bubbleEl.className = 'msg-bubble';
    bubbleEl.textContent = text;

    msgEl.appendChild(headerEl);
    msgEl.appendChild(bubbleEl);
    transcriptFeed.appendChild(msgEl);
    transcriptFeed.scrollTop = transcriptFeed.scrollHeight;
  }

  // Linear interpolation resampler for PCM audio
  function downsampleBuffer(buffer, inputSampleRate, outputSampleRate) {
    if (outputSampleRate === inputSampleRate) {
      return buffer;
    }
    const sampleRateRatio = inputSampleRate / outputSampleRate;
    const newLength = Math.round(buffer.length / sampleRateRatio);
    const result = new Float32Array(newLength);
    let offsetResult = 0;
    let offsetBuffer = 0;
    while (offsetResult < result.length) {
      const nextOffsetBuffer = Math.round((offsetResult + 1) * sampleRateRatio);
      let accum = 0, count = 0;
      for (let i = offsetBuffer; i < nextOffsetBuffer && i < buffer.length; i++) {
        accum += buffer[i];
        count++;
      }
      result[offsetResult] = count > 0 ? accum / count : 0;
      offsetResult++;
      offsetBuffer = nextOffsetBuffer;
    }
    return result;
  }

  // Convert Float32Array [-1.0, 1.0] to Int16Array [-32768, 32767]
  function floatTo16BitPCM(float32Array) {
    const buffer = new ArrayBuffer(float32Array.length * 2);
    const view = new DataView(buffer);
    for (let i = 0; i < float32Array.length; i++) {
      let s = Math.max(-1, Math.min(1, float32Array[i]));
      view.setInt16(i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true); // little-endian
    }
    return buffer;
  }

  // Playback incoming 24,000 Hz PCM16 audio chunks
  function queueAudioPlayback(pcm16ArrayBuffer) {
    if (!audioOutputContext) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      audioOutputContext = new AudioCtx({ sampleRate: 24000 });
    }

    if (audioOutputContext.state === 'suspended') {
      audioOutputContext.resume();
    }

    const int16 = new Int16Array(pcm16ArrayBuffer);
    const numSamples = int16.length;
    if (numSamples === 0) return;

    // Convert Int16 to Float32
    const float32 = new Float32Array(numSamples);
    for (let i = 0; i < numSamples; i++) {
      float32[i] = int16[i] / (int16[i] < 0 ? 0x8000 : 0x7fff);
    }

    // Measure speaker audio level for visualizer
    let sum = 0;
    for (let i = 0; i < float32.length; i += 16) {
      sum += float32[i] * float32[i];
    }
    currentAudioLevel = Math.min(1, Math.sqrt(sum / (float32.length / 16)) * 4);

    // Create AudioBuffer and schedule
    const audioBuffer = audioOutputContext.createBuffer(1, numSamples, 24000);
    audioBuffer.getChannelData(0).set(float32);

    const source = audioOutputContext.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(audioOutputContext.destination);

    const currentTime = audioOutputContext.currentTime;
    if (playbackNextTime < currentTime) {
      playbackNextTime = currentTime;
    }

    source.start(playbackNextTime);
    playbackNextTime += audioBuffer.duration;
  }

  // Draw animated waveform
  function drawWaveform() {
    if (!canvasCtx || !waveformCanvas) return;
    const width = waveformCanvas.width;
    const height = waveformCanvas.height;
    canvasCtx.clearRect(0, 0, width, height);

    canvasCtx.lineWidth = 2;
    canvasCtx.strokeStyle = isSessionActive ? '#06b6d4' : '#374151';
    canvasCtx.beginPath();

    const mid = height / 2;
    const numPoints = 64;
    const slice = width / numPoints;

    for (let i = 0; i <= numPoints; i++) {
      const t = Date.now() * 0.005 + i * 0.15;
      const amp = isSessionActive ? Math.max(0.08, currentAudioLevel) * (height * 0.4) : 2;
      const y = mid + Math.sin(t) * amp;
      if (i === 0) canvasCtx.moveTo(0, y);
      else canvasCtx.lineTo(i * slice, y);
    }

    canvasCtx.stroke();
    animFrameId = requestAnimationFrame(drawWaveform);
  }

  // Verify provider credentials before starting, so a bad key shows up as a
  // named error here instead of as silence once the call is live.
  async function runPreflight() {
    try {
      const resp = await fetch('/voice-test/preflight');
      const data = await resp.json();

      Object.entries(data.checks || {}).forEach(([name, check]) => {
        logEvent('Preflight', `${name}: ${check.ok ? 'OK' : 'FAILED'} - ${check.detail}`, check.fix || null);
      });

      // Degraded capabilities are logged but never block the call.
      Object.entries(data.warnings || {}).forEach(([name, check]) => {
        if (!check.ok) {
          logEvent('Preflight', `${name}: DEGRADED - ${check.detail}`, check.fix || null);
        }
      });

      if (!data.ready) {
        const failed = Object.entries(data.checks || {}).filter(([, c]) => !c.ok);
        const summary = failed
          .map(([name, c]) => `${name}: ${c.detail}

How to fix:
${c.fix || 'see server log'}`)
          .join('\n\n---\n\n');
        setConnectionStatus('disconnected', 'Preflight failed');
        setOrbState('', `Not ready: ${failed.map(([n]) => n).join(', ')}`);
        alert(`Voice providers are not ready, so the call would be silent.

${summary}`);
        return false;
      }

      logEvent('Preflight', 'All provider checks passed');
      return true;
    } catch (err) {
      // A preflight that cannot run must not block testing.
      logEvent('Preflight', 'Could not run preflight, continuing anyway', err.message);
      return true;
    }
  }

  // Start Voice Session
  async function startSession() {
    btnStart.disabled = true;
    setConnectionStatus('connecting', 'Checking providers...');
    setOrbState('listening', 'Running preflight checks...');

    if (!(await runPreflight())) {
      btnStart.disabled = false;
      return;
    }

    logEvent('Client', 'Requesting microphone access...');
    setConnectionStatus('connecting', 'Connecting...');
    setOrbState('listening', 'Accessing microphone...');

    try {
      micMediaStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });

      if (micStatusText) micStatusText.textContent = 'Active (16kHz)';
      logEvent('Microphone', 'Permission granted and stream acquired');
    } catch (err) {
      logEvent('Microphone', 'Permission denied or device error', err.message);
      setConnectionStatus('disconnected', 'Mic Denied');
      setOrbState('', 'Microphone access denied');
      btnStart.disabled = false;
      alert(`Could not access microphone: ${err.message}. Please allow microphone permissions and try again.`);
      return;
    }

    // Connect WebSocket
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${location.host}/voice-test/ws`;
    logEvent('WebSocket', `Connecting to ${wsUrl}`);

    ws = new WebSocket(wsUrl);
    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      logEvent('WebSocket', 'Connected to voice test backend');
      setConnectionStatus('connected', 'Live Session');
      setOrbState('listening', 'Listening... Speak into your mic');
      isSessionActive = true;
      btnStop.disabled = false;

      initAudioCapture();
    };

    ws.onmessage = (event) => {
      if (event.data instanceof ArrayBuffer) {
        // Incoming TTS audio
        queueAudioPlayback(event.data);
      } else if (typeof event.data === 'string') {
        try {
          const msg = JSON.parse(event.data);
          handleControlMessage(msg);
        } catch (e) {
          logEvent('WebSocket', 'Unrecognized text message', event.data);
        }
      }
    };

    ws.onerror = (err) => {
      logEvent('WebSocket', 'Error encountered', err);
      setConnectionStatus('disconnected', 'Error');
    };

    ws.onclose = (event) => {
      logEvent('WebSocket', `Closed with code ${event.code}`, event.reason);
      stopSession();
    };
  }

  // Handle incoming JSON control events
  function handleControlMessage(msg) {
    logEvent('Server', `Event: ${msg.type}`, msg);

    if (msg.type === 'transcript') {
      appendTranscript(msg.role, msg.text);
    } else if (msg.type === 'speaking') {
      if (msg.value) {
        setOrbState('speaking', 'AI Receptionist is speaking...');
        if (speakerStatusText) speakerStatusText.textContent = 'Streaming audio';
      } else {
        setOrbState('listening', 'Listening... Speak now');
        if (speakerStatusText) speakerStatusText.textContent = 'Ready';
        currentAudioLevel = 0;
      }
    } else if (msg.type === 'clinic') {
      if (clinicNameDisplay) {
        clinicNameDisplay.textContent = msg.name || 'Local Test Clinic';
      }
    } else if (msg.type === 'error') {
      logEvent('Error', msg.message);
      appendTranscript('assistant', `⚠️ ${msg.message}`);
    }
  }

  // Initialize Audio Capture & Streaming
  function initAudioCapture() {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    audioInputContext = new AudioCtx();

    inputSource = audioInputContext.createMediaStreamSource(micMediaStream);
    const bufferSize = 2048;
    scriptProcessor = audioInputContext.createScriptProcessor(bufferSize, 1, 1);

    scriptProcessor.onaudioprocess = (audioProcessingEvent) => {
      if (!isSessionActive || !ws || ws.readyState !== WebSocket.OPEN) return;

      const inputBuffer = audioProcessingEvent.inputBuffer.getChannelData(0);

      // Measure volume level for user speaking
      let sum = 0;
      for (let i = 0; i < inputBuffer.length; i += 8) {
        sum += inputBuffer[i] * inputBuffer[i];
      }
      const rms = Math.sqrt(sum / (inputBuffer.length / 8));
      if (orbWrapper && !orbWrapper.classList.contains('speaking')) {
        currentAudioLevel = Math.min(1, rms * 5);
      }

      // Downsample to 16,000 Hz for Sarvam STT
      const downsampled = downsampleBuffer(inputBuffer, audioInputContext.sampleRate, 16000);
      const pcm16 = floatTo16BitPCM(downsampled);

      try {
        ws.send(pcm16);
      } catch (err) {
        logEvent('WebSocket', 'Failed to send audio chunk', err.message);
      }
    };

    inputSource.connect(scriptProcessor);
    scriptProcessor.connect(audioInputContext.destination);
    logEvent('Audio', `Mic streaming at 16000Hz (source: ${audioInputContext.sampleRate}Hz)`);
  }

  // Stop Session
  function stopSession() {
    isSessionActive = false;
    currentAudioLevel = 0;

    logEvent('Client', 'Stopping session and cleaning up audio resources');

    if (ws) {
      if (ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify({ type: 'stop' }));
          ws.close();
        } catch (e) {}
      }
      ws = null;
    }

    if (scriptProcessor) {
      scriptProcessor.disconnect();
      scriptProcessor = null;
    }
    if (inputSource) {
      inputSource.disconnect();
      inputSource = null;
    }
    if (audioInputContext && audioInputContext.state !== 'closed') {
      audioInputContext.close();
      audioInputContext = null;
    }
    if (micMediaStream) {
      micMediaStream.getTracks().forEach((track) => track.stop());
      micMediaStream = null;
    }

    setConnectionStatus('disconnected', 'Disconnected');
    setOrbState('', 'Click Start to begin testing');
    if (micStatusText) micStatusText.textContent = 'Inactive';
    if (speakerStatusText) speakerStatusText.textContent = 'Ready';

    btnStart.disabled = false;
    btnStop.disabled = true;
  }

  // Attach Event Listeners
  btnStart.addEventListener('click', startSession);
  btnStop.addEventListener('click', stopSession);

  // Initialize Waveform Animation
  animFrameId = requestAnimationFrame(drawWaveform);

  // Initial Log Entry
  logEvent('System', 'Local Voice Testing client ready. Configured for 16kHz PCM In / 24kHz PCM Out.');
})();
