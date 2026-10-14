import ReplayKit
import VideoToolbox

// ReplayKit Broadcast Upload Extension — her kare için çağrılır.
// Kare → H.264 (VideoToolbox) → … → WebRTC üzerinden iletim.
//
// NOT: WebRTC native SDK (GoogleWebRTC veya WebRTC.framework) projeye
// bağımlılık olarak eklenmeli ve burada kullanılmalıdır. Bu dosya yalnızca
// kare alma ve codec sırasını gösterir; WebRTC entegrasyonu yer tutucu.

class BroadcastHandler: RPBroadcastSampleHandler {

    // WebRTC peer connection buraya enjekte edilir (App Group üzerinden).
    // Gerçek entegrasyon: AppGroup UserDefaults ile sinyal konfigürasyonu paylaşılır.

    private var encoder: VTCompressionSession?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        setupEncoder()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            guard let session = encoder,
                  let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            // VideoToolbox encode: CMSampleBuffer → H.264 NAL units
            VTCompressionSessionEncodeFrame(
                session, imageBuffer: imageBuffer,
                presentationTimeStamp: pts,
                duration: .invalid,
                frameProperties: nil,
                infoFlagsOut: nil,
                outputHandler: { [weak self] status, _, sampleBuffer in
                    guard status == noErr, let sb = sampleBuffer else { return }
                    // TODO: H.264 NAL → WebRTC track (GoogleWebRTC RTCVideoTrack)
                    _ = sb
                }
            )
        case .audioApp, .audioMic:
            // TODO: PCM → Opus → WebRTC audio track
            break
        @unknown default:
            break
        }
    }

    override func broadcastFinished() {
        if let session = encoder { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) }
        encoder = nil
    }

    private func setupEncoder() {
        var session: VTCompressionSession?
        let err = VTCompressionSessionCreate(
            allocator: nil,
            width: 1920, height: 1080,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard err == noErr, let s = session else { return }
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: NSNumber(value: 4_000_000))
        VTCompressionSessionPrepareToEncodeFrames(s)
        encoder = s
    }
}
