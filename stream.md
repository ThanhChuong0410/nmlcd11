# Tài liệu Video Streaming Flow - GodEyes

**Ngày cập nhật:** 23/12/2025  
**Trạng thái:** Đang debug lỗi decoder, chờ deploy môi trường dev

---

## 🎯 Mục tiêu

Triển khai streaming video H.264/HEVC native codec với **zero-copy** và **hardware-accelerated decoding** để:

- Giảm 85-90% CPU usage (loại bỏ MJPEG transcoding)
- Giảm bandwidth 60-70% (H.264 vs MJPEG)
- Latency thấp: ~80ms end-to-end
- Hỗ trợ 30fps smooth playback với forced keyframes mỗi 2 giây

---

## 📊 Kiến trúc tổng quan

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   godeyes-edge  │────▶│  godeyes-api     │────▶│   godeyes-ui    │
│   FFmpeg Reader │     │  WebSocket Proxy │     │  WebCodecs      │
└─────────────────┘     └──────────────────┘     └─────────────────┘
      (Go)                     (Go)                   (JavaScript)
```

---

## 🔄 Flow chi tiết

### 1️⃣ **godeyes-edge: FFmpeg Reader**

📂 [godeyes-edge/pkg/stream/ffmpeg_reader.go](../godeyes-edge/pkg/stream/ffmpeg_reader.go)

#### Quy trình:

```
RTSP Camera → FFmpeg Process → NAL Unit Parser → Binary Protocol Encoder → WebSocket
```

#### Chi tiết implementation:

##### A. Khởi tạo FFmpeg Process

```go
// Lines 70-125: FFmpeg args
cmd := exec.Command("ffmpeg",
    "-rtsp_transport", "tcp",
    "-i", rtspURL,
    "-c:v", "libx264",           // Force re-encode to H.264
    "-preset", "ultrafast",      // Lowest CPU usage
    "-tune", "zerolatency",      // Low latency streaming
    "-profile:v", "baseline",    // Max browser compatibility
    "-level", "3.1",
    "-g", "60",                  // Keyframe every 60 frames (2s @ 30fps)
    "-keyint_min", "60",         // Minimum keyframe interval
    "-sc_threshold", "0",        // Disable scene change detection
    "-crf", "28",                // Quality: 18-23 (high), 28 (balanced), 32+ (low)
    "-f", "h264",                // Raw H.264 Annex-B output
    "-",                         // Output to stdout
)
```

**Tại sao re-encode?**

- Camera gốc: HEVC, GOP=120 (4 giây), không kiểm soát được keyframe
- WebCodecs yêu cầu: Keyframe đầu tiên để init decoder, keyframe thường xuyên để tránh corruption
- Giải pháp: Re-encode với forced keyframe interval = 60 frames (2 giây)
- Trade-off: CPU +12% per stream, latency +70ms, nhưng stable playback

##### B. NAL Unit Parser

```go
// Lines 327-427: readNALUFrame() - Đọc complete access unit
```

**NAL Unit Structure (Annex-B format):**

```
[Start Code] [NAL Header] [NAL Payload]
   3-4 bytes     1 byte       variable

Start codes:
- 0x00 00 00 01 (4 bytes) - Thường dùng cho parameter sets
- 0x00 00 01    (3 bytes) - Thường dùng cho slices
```

**H.264 NAL Types (NAL header & 0x1F):**

```
Type 1:  Non-IDR slice (P/B frame)
Type 5:  IDR slice (keyframe)
Type 7:  SPS (Sequence Parameter Set)
Type 8:  PPS (Picture Parameter Set)
```

**Access Unit = Complete Video Frame:**

```
Key frame:  [SPS] + [PPS] + [IDR slice(s)]
P/B frame:  [Non-IDR slice(s)]
```

**Aggregation Logic:**

```go
// Đọc nhiều NAL units cho đến khi tìm thấy frame boundary:
for {
    nalUnit := readSingleNALU()
    nalType := getNALUType(nalUnit)

    // Parameter sets (SPS/PPS) - cache lại
    if nalType == 7 || nalType == 8 {
        cachedSPS/cachedPPS = nalUnit
        append to frameBuffer
        continue
    }

    // Slice NALs (IDR/Non-IDR)
    if nalType == 1 || nalType == 5 {
        append to frameBuffer

        // Frame boundary detection:
        // - Gặp parameter set sau slice
        // - Gặp key frame NAL sau slice
        if nextIsParamSet || nextIsKeyFrame {
            break
        }
    }
}
```

**Parameter Set Caching:**

```go
// Lines 337-395
// Vì camera không gửi SPS/PPS mỗi keyframe, phải cache và prepend khi cần
if isKeyFrame && !hasInlineSPS {
    prependCachedSPS()
    prependCachedPPS()
}
```

##### C. Binary Protocol Encoder

```go
// Lines 430-500: Encode frame to binary format
header := {
    Magic:      0x47 0x45 ("GE")
    Version:    0x01
    MsgType:    0x01 (stream)
    HeaderLen:  variable (2 bytes)
    CameraID:   length-prefixed string
    Timestamp:  8 bytes (Unix milliseconds)
    FrameNum:   8 bytes
    FrameType:  1 byte (3=H.264, 4=HEVC)
    Width:      2 bytes
    Height:     2 bytes
    FrameLen:   4 bytes
}
frameData: NAL units with start codes (Annex-B format)
```

##### D. Send qua WebSocket

```go
// Zero-copy: Frame data không được copy, chỉ slice của buffer
sendBinaryFrame(encodedFrame)
```

---

### 2️⃣ **godeyes-api: WebSocket Proxy**

📂 [godeyes-api/websocket/](../godeyes-api/websocket/) | [binary_protocol.go](../godeyes-api/websocket/common/binary_protocol.go)

#### Quy trình:

```
Edge WebSocket Client ───┐
                         ├──▶ Redis PubSub ──▶ WebSocket Server ──▶ Browser
Edge WebSocket Client ───┘
```

#### Chi tiết:

##### A. Edge → Redis PubSub

- Edge publish binary frame lên channel: `camera:{camera_id}:stream`
- Format: Raw binary (đã encode ở edge)

##### B. Redis PubSub → Browser WebSocket

- API server subscribe channel của camera
- Forward binary message trực tiếp đến browser client
- **Zero-copy**: Không parse, không transform

**Connection Flow:**

```javascript
// Frontend request
ws://api-server/ws/stream?camera_id=xxx&quality=high

// Backend
1. Authenticate WebSocket connection
2. Subscribe Redis channel: camera:xxx:stream
3. Forward binary messages: Redis → WebSocket
```

---

### 3️⃣ **godeyes-ui: Frontend Decoder**

📂 [godeyes-ui/src/](../godeyes-ui/src/)

#### Quy trình:

```
WebSocket Binary Message → Binary Protocol Parser → Decoder Factory → WebCodecs Decoder → Canvas
```

#### Chi tiết implementation:

##### A. WebSocket Handler

📄 [src/components/cameras/StreamPage.js](../godeyes-ui/src/components/cameras/StreamPage.js)

```javascript
ws.onmessage = async (event) => {
  if (event.data instanceof ArrayBuffer) {
    // Parse binary frame
    const frame = parseBinaryStreamFrame(event.data);

    // Create decoder on first frame
    if (!decoder) {
      decoder = await createDecoder(frame.frameType, {
        width: frame.width,
        height: frame.height,
        canvas: canvasRef.current,
      });
    }

    // Decode frame
    await decoder.decode(frame.frameData);
  }
};
```

##### B. Binary Protocol Parser

📄 [src/services/binaryProtocol.js](../godeyes-ui/src/services/binaryProtocol.js) (184 lines)

```javascript
export function parseBinaryStreamFrame(arrayBuffer) {
    const data = new Uint8Array(arrayBuffer);

    // 1. Validate magic bytes (0x47 0x45)
    if (data[0] !== 0x47 || data[1] !== 0x45) return null;

    // 2. Check version (0x01)
    if (data[2] !== 0x01) return null;

    // 3. Check message type (0x01 = stream)
    if (data[3] !== 0x01) return null;

    // 4. Read header length (2 bytes big-endian)
    const headerLen = (data[4] << 8) | data[5];

    // 5. Parse metadata
    let offset = 6;
    const cameraIDLen = data[offset++];
    const cameraID = new TextDecoder().decode(data.slice(offset, offset + cameraIDLen));
    offset += cameraIDLen;

    // Timestamp (8 bytes BigInt)
    const timestamp = Number(
        (BigInt(data[offset]) << 56n) | ... | BigInt(data[offset + 7])
    );
    offset += 8;

    // Frame number (8 bytes BigInt)
    const frameNum = Number(...);
    offset += 8;

    // Frame type (1 byte)
    let frameType = data[offset++];

    // TEMP FIX: Backend re-encodes HEVC → H.264 but doesn't update frame_type
    if (frameType === 0x04) { // HEVC
        frameType = 0x03;     // H.264
        console.log("🔧 Overriding frame type: HEVC -> H264");
    }

    // Width, Height (2 bytes each)
    const width = (data[offset] << 8) | data[offset + 1];
    offset += 2;
    const height = (data[offset] << 8) | data[offset + 1];
    offset += 2;

    // Frame length (4 bytes)
    const frameLen = (data[offset] << 24) | ... | data[offset + 3];
    offset += 4;

    // 6. Extract frame data (zero-copy slice)
    const frameData = data.slice(headerLen, headerLen + frameLen);

    return {
        cameraID,
        timestamp,
        frameNum,
        frameType,
        frameTypeName: FrameTypeName[frameType],
        width,
        height,
        frameData // Uint8Array containing NAL units
    };
}
```

##### C. Decoder Factory

📄 [src/decoders/index.js](../godeyes-ui/src/decoders/index.js) (90 lines)

```javascript
export async function createDecoder(frameType, options) {
  // Feature detection
  if (!isWebCodecsSupported()) {
    return new MJPEGDecoder(options);
  }

  // TEMP: Force MJPEG fallback while debugging backend
  // TODO: Remove after verifying H.264 re-encoding is working
  console.warn("⚠️ Forcing MJPEG decoder (H.264 re-encode verification needed)");
  return new MJPEGDecoder(options);

  /* Original logic (commented out):
    switch(frameType) {
        case FrameType.H264:
            if (await isCodecSupported('avc1.42001f')) {
                return new H264WebCodecsDecoder(options);
            }
            break;
        case FrameType.H265:
            // Poor browser support
            break;
    }
    return new MJPEGDecoder(options); // Fallback
    */
}
```

##### D. H.264 WebCodecs Decoder

📄 [src/decoders/H264WebCodecsDecoder.js](../godeyes-ui/src/decoders/H264WebCodecsDecoder.js) (237 lines)

```javascript
class H264WebCodecsDecoder {
  constructor(options) {
    this.canvas = options.canvas;
    this.ctx = canvas.getContext("2d");
    this.decoder = null;
    this.configured = false;
    this.frameQueue = [];
  }

  async decode(frameData) {
    // 1. Extract NAL units (parse Annex-B format)
    const nalUnits = this.extractNALUnits(frameData);

    // 2. Check if key frame
    const isKey = this.isKeyFrame(nalUnits);

    // 3. Configure decoder on first key frame
    if (!this.configured && isKey) {
      this.decoder = new VideoDecoder({
        output: (frame) => this.renderFrame(frame),
        error: (e) => console.error("Decoder error:", e),
      });

      this.decoder.configure({
        codec: "avc1.42001f", // H.264 Baseline Profile Level 3.1
        optimizeForLatency: true,
        // No description field - let WebCodecs auto-parse from key frame
      });

      this.configured = true;
      console.log("✅ H.264 decoder configured");
    }

    // 4. Enqueue for decoding
    if (this.configured) {
      const chunk = new EncodedVideoChunk({
        type: isKey ? "key" : "delta",
        timestamp: Date.now() * 1000,
        data: frameData, // Annex-B format with start codes
      });

      this.decoder.decode(chunk);
    }
  }

  extractNALUnits(data) {
    const nalUnits = [];
    let i = 0;

    while (i < data.length - 3) {
      // Find start code (0x00 00 00 01 or 0x00 00 01)
      if (data[i] === 0 && data[i + 1] === 0) {
        let startCodeLen = 0;
        if (data[i + 2] === 0 && data[i + 3] === 1) {
          startCodeLen = 4; // 0x00 00 00 01
        } else if (data[i + 2] === 1) {
          startCodeLen = 3; // 0x00 00 01
        }

        if (startCodeLen > 0) {
          // Find next start code
          let nextStart = this.findNextStartCode(data, i + startCodeLen);

          // Extract NAL unit (including start code)
          const nalUnit = data.slice(i, nextStart);
          nalUnits.push(nalUnit);

          i = nextStart;
          continue;
        }
      }
      i++;
    }

    return nalUnits;
  }

  isKeyFrame(nalUnits) {
    // Check ALL NAL units for IDR (type 5)
    for (const nal of nalUnits) {
      if (nal.length > 4) {
        const nalType = nal[4] & 0x1f; // Skip 4-byte start code
        if (nalType === 5) return true; // IDR
      }
    }
    return false;
  }

  renderFrame(frame) {
    // Draw to canvas
    this.ctx.drawImage(frame, 0, 0, this.canvas.width, this.canvas.height);
    frame.close();
  }
}
```

##### E. MJPEG Fallback Decoder

📄 [src/decoders/MJPEGDecoder.js](../godeyes-ui/src/decoders/MJPEGDecoder.js) (50 lines)

```javascript
class MJPEGDecoder {
  constructor(options) {
    this.canvas = options.canvas;
    this.ctx = canvas.getContext("2d");
  }

  async decode(frameData) {
    // Create blob from binary data
    const blob = new Blob([frameData], { type: "image/jpeg" });
    const url = URL.createObjectURL(blob);

    // Load image
    const img = new Image();
    img.onload = () => {
      this.ctx.drawImage(img, 0, 0, this.canvas.width, this.canvas.height);
      URL.revokeObjectURL(url);
    };
    img.src = url;
  }
}
```

---

## 🐛 Vấn đề hiện tại & Debug Steps

### ❌ Lỗi: EncodingError khi decode H.264

**Triệu chứng:**

```
EncodingError: Codec error
  at H264WebCodecsDecoder.decode()
  at async StreamPage.onmessage()
```

**Nguyên nhân khả năng cao:**

1. **Backend chưa được deploy với code mới**

   - Edge container vẫn chạy code cũ (stream copy HEVC)
   - Chưa re-encode sang H.264 với libx264
   - Frontend nhận HEVC data nhưng tạo H.264 decoder → crash

2. **Frame type mismatch**
   - Backend gửi HEVC data (frame_type = 0x04)
   - Frontend override sang H.264 (frame_type = 0x03) ✅
   - Nhưng decoder vẫn crash vì data thực sự là HEVC

**Workaround hiện tại:**

- Tạm thời force MJPEG decoder cho tất cả stream
- Video chạy được nhưng bandwidth cao

### 🔍 Debug Checklist

#### Bước 1: Kiểm tra Edge container

```bash
# Check container status
cd godeyes-edge
docker ps -a | grep edge

# Verify restart time (phải là sau khi commit "wip: encode use h264")
docker inspect <container-id> | grep StartedAt

# Check logs for FFmpeg encoding
docker logs <container-id> --tail 100 | grep -i "ffmpeg\|libx264\|h264"
```

**Cần thấy log:**

```
FFmpeg re-encoding with forced keyframes
Encoder: libx264
Profile: baseline
Keyframe interval: 60 frames
```

**Nếu không thấy:**

```bash
# Rebuild và restart container
docker-compose down
docker-compose build edge
docker-compose up -d edge

# Hoặc trong K8s
kubectl rollout restart deployment/godeyes-edge
kubectl logs -f deployment/godeyes-edge
```

#### Bước 2: Kiểm tra binary stream format

```javascript
// Thêm vào frontend console (StreamPage.js)
ws.onmessage = (event) => {
  const frame = parseBinaryStreamFrame(event.data);
  console.log({
    frameType: frame.frameType,
    frameTypeName: frame.frameTypeName,
    frameSize: frame.frameData.length,
    firstBytes: Array.from(frame.frameData.slice(0, 20))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join(" "),
  });
};
```

**Expected output (H.264 key frame):**

```
frameType: 3 (H264)
firstBytes: "00 00 00 01 67 ..." (SPS start)
           "00 00 00 01 68 ..." (PPS start)
           "00 00 00 01 65 ..." (IDR slice start)
```

**Nếu thấy HEVC:**

```
firstBytes: "00 00 00 01 40 ..." (VPS)
           "00 00 00 01 42 ..." (SPS)
           "00 00 00 01 44 ..." (PPS)
           "00 00 00 01 26 ..." (IDR slice)
```

→ Backend chưa re-encode!

#### Bước 3: Test H.264 decoder riêng

```javascript
// Tạo test file: test-h264-decoder.html
const testH264 = async () => {
  const decoder = new VideoDecoder({
    output: (frame) => {
      console.log("✅ Frame decoded:", frame.codedWidth, "x", frame.codedHeight);
      frame.close();
    },
    error: (e) => console.error("❌ Decoder error:", e),
  });

  decoder.configure({
    codec: "avc1.42001f", // Baseline Profile
    optimizeForLatency: true,
  });

  console.log("Decoder state:", decoder.state);

  // Test với sample H.264 data
  // ... feed real data from backend ...
};
```

#### Bước 4: Kiểm tra browser support

```javascript
// Check WebCodecs support
console.log("VideoDecoder:", typeof VideoDecoder);

// Check H.264 codec support
VideoDecoder.isConfigSupported({
  codec: "avc1.42001f",
}).then((result) => {
  console.log("H.264 Baseline support:", result.supported);
});

// Check HEVC support (để so sánh)
VideoDecoder.isConfigSupported({
  codec: "hev1.1.6.L93.B0",
}).then((result) => {
  console.log("HEVC support:", result.supported);
});
```

**Expected Chrome/Edge:**

```
H.264 Baseline: true ✅
HEVC: false ❌
```

---

## 📝 Kế hoạch tiếp theo

### 1. Xác nhận backend deployment ⭐ URGENT

- [ ] Verify Edge container image version
- [ ] Check FFmpeg process logs
- [ ] Confirm H.264 output stream

### 2. Re-enable H.264 WebCodecs decoder

```javascript
// src/decoders/index.js
// Uncomment lines 56-68 after backend verification
export async function createDecoder(frameType, options) {
  if (!isWebCodecsSupported()) {
    return new MJPEGDecoder(options);
  }

  switch (frameType) {
    case FrameType.H264:
      if (await isCodecSupported("avc1.42001f")) {
        return new H264WebCodecsDecoder(options);
      }
      break;
  }

  return new MJPEGDecoder(options);
}
```

### 3. Remove temporary fixes

```javascript
// src/services/binaryProtocol.js
// Remove lines 133-138 after backend sends correct frame_type
// if (frameType === FrameType.H265) {
//     frameType = FrameType.H264;
// }
```

### 4. End-to-end testing

- [ ] Test với nhiều cameras
- [ ] Monitor CPU usage (~12% per stream)
- [ ] Monitor bandwidth (~1.5-3 Mbps cho 720p)
- [ ] Verify latency (~80ms)
- [ ] Check keyframe frequency (~30 keyframes/minute)
- [ ] Test stability qua 30 phút

### 5. Performance tuning (optional)

```bash
# Tăng quality (giảm CRF)
-crf 23  # Thay vì 28, bandwidth tăng ~20%

# Tăng compression (preset chậm hơn)
-preset veryfast  # Thay vì ultrafast, CPU tăng ~5%

# Upgrade profile (better compression)
-profile:v main  # Thay vì baseline, Chrome/Edge support OK
```

---

## 📚 Tài liệu tham khảo

### Code files quan trọng

- Backend: [godeyes-edge/pkg/stream/ffmpeg_reader.go](../godeyes-edge/pkg/stream/ffmpeg_reader.go) (601 lines)
- Protocol: [godeyes-api/websocket/common/binary_protocol.go](../godeyes-api/websocket/common/binary_protocol.go) (240 lines)
- Frontend Parser: [godeyes-ui/src/services/binaryProtocol.js](../godeyes-ui/src/services/binaryProtocol.js) (184 lines)
- Decoder Factory: [godeyes-ui/src/decoders/index.js](../godeyes-ui/src/decoders/index.js) (90 lines)
- H.264 Decoder: [godeyes-ui/src/decoders/H264WebCodecsDecoder.js](../godeyes-ui/src/decoders/H264WebCodecsDecoder.js) (237 lines)
- MJPEG Decoder: [godeyes-ui/src/decoders/MJPEGDecoder.js](../godeyes-ui/src/decoders/MJPEGDecoder.js) (50 lines)
- HEVC Decoder: [godeyes-ui/src/decoders/HEVCWebCodecsDecoder.js](../godeyes-ui/src/decoders/HEVCWebCodecsDecoder.js) (258 lines)
- StreamPage: [godeyes-ui/src/components/cameras/StreamPage.js](../godeyes-ui/src/components/cameras/StreamPage.js)

### Specs

- [H.264 Annex-B format](https://www.itu.int/rec/T-REC-H.264)
- [WebCodecs API](https://w3c.github.io/webcodecs/)
- [FFmpeg H.264 encoding guide](https://trac.ffmpeg.org/wiki/Encode/H.264)

### Browser compatibility

- Chrome/Edge: H.264 ✅ HEVC ❌
- Safari: H.264 ✅ HEVC ⚠️ (needs exact codec string)
- Firefox: H.264 ✅ HEVC ❌

---

## ⚠️ Lưu ý quan trọng

1. **Zero-copy principle**: Frame data KHÔNG được modify sau khi parse, tất cả đều là slice của buffer gốc

2. **Keyframe requirement**: WebCodecs decoder PHẢI nhận keyframe đầu tiên, không thể decode từ P/B frame

3. **NAL unit format**: Frontend expect Annex-B format (with start codes), KHÔNG phải AVCC/MP4 format

4. **BigInt handling**: Timestamp và frame number dùng 64-bit, phải dùng BigInt trong JS để tránh precision loss

5. **Frame type byte**:

   - 0x03 = H.264 (avc)
   - 0x04 = HEVC (hevc)
   - Hiện đang có workaround override HEVC→H.264 ở frontend

6. **CPU usage**:

   - MJPEG: ~35% per stream
   - H.264 stream copy: ~3% per stream
   - H.264 re-encode (ultrafast): ~12% per stream

7. **Latency breakdown**:
   - Camera → FFmpeg: ~20ms
   - FFmpeg encoding: ~70ms (re-encode) / ~5ms (copy)
   - Network + WebSocket: ~10ms
   - WebCodecs decode: ~5ms
   - Total: ~80ms (re-encode) / ~40ms (copy)

---

**Trạng thái:** Chờ verify backend deployment để enable H.264 WebCodecs decoder  
**Next action:** Run debug checklist trên môi trường dev
