import Foundation
import Network
import CallKit
import AVFoundation
import Sodium
import Opus

#if os(iOS)
class CallKitHandler: NSObject, CXProviderDelegate {
    private let provider: CXProvider
    private let controller = CXCallController()
    private var activeCallUUID: UUID?
    var onCallStart: (() -> Void)?
    var onCallEnd: (() -> Void)?

    override init() {
        let config = CXProviderConfiguration(localizedName: "Finchcord")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        self.provider = CXProvider(configuration: config)

        super.init()
        self.provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(from handle: String) {
        let uuid = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                print("Failed to report incoming call: \(error)")
            }
        }
        activeCallUUID = uuid
    }

    func startOutgoingCall(to handle: String) {
        let uuid = UUID()
        let handle = CXHandle(type: .generic, value: handle)
        let startCall = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: startCall)
        controller.request(transaction, completion: { _ in })
        activeCallUUID = uuid
    }

    func endCall() {
        guard let uuid = activeCallUUID else { return }
        let endCall = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCall)
        controller.request(transaction, completion: { _ in })
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
        onCallStart?()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        onCallEnd?()
    }
    
    func providerDidReset(_ provider: CXProvider) {
        
    }
}
#endif

class DiscordVoiceClient {
    let sodium = Sodium()
    var wsTask: URLSessionWebSocketTask?
    var udpConnection: NWConnection?
    var voiceServerIP: String = ""
    var voiceServerPort: UInt16 = 0
    var ssrc: UInt32 = 0
    var secretKey: Bytes = []
    var sequence: UInt16 = 0
    var rtpTimestamp: UInt32 = 0

    let engine = AVAudioEngine()
    let inputNode: AVAudioInputNode
    let outputNode = AVAudioPlayerNode()
    let bus = 0
    var opusEncoder: Opus.Encoder?
    var opusDecoder: Opus.Decoder?
    var opusOutput = [UInt8](repeating: 0, count: 4000)

    init() {
        inputNode = engine.inputNode
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        opusEncoder = try? Opus.Encoder(format: format, application: .voip)
        opusDecoder = try? Opus.Decoder(format: format)

        engine.attach(outputNode)
        engine.connect(outputNode, to: engine.mainMixerNode, format: format)
    }

    func connectToVoiceWebSocket(url: URL) {
        let session = URLSession(configuration: .default)
        wsTask = session.webSocketTask(with: url)
        wsTask?.resume()
        listenForMessages()
    }

    func listenForMessages() {
        wsTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket error: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    print("Received text: \(text)")
                    // TODO: Parse and respond to opcodes
                default:
                    break
                }
            }
            self?.listenForMessages()
        }
    }

    func startUDPConnection(to ip: String, port: UInt16) {
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(rawValue: port)!
        udpConnection = NWConnection(host: host, port: port, using: .udp)
        udpConnection?.start(queue: .main)
        receiveUDP()
    }

    func receiveUDP() {
        udpConnection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                print("UDP receive error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            self.processIncomingPacket(data)
            self.receiveUDP()
        }
    }

    func processIncomingPacket(_ data: Data) {
        guard data.count > 12 else { return }
        let rtpHeader = data.prefix(12)
        let encrypted = data.suffix(from: 12)

        var nonce = [UInt8](repeating: 0, count: 24)
        for i in 0..<12 { nonce[i] = rtpHeader[i] }

        guard let decrypted = sodium.secretBox.open(nonceAndAuthenticatedCipherText: nonce + encrypted, secretKey: secretKey) else {
            print("Failed to decrypt incoming packet")
            return
        }

        guard let decoder = opusDecoder else { return }

        do {
            let buffer = try decoder.decode(Data(decrypted))
            outputNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        } catch {
            print("Opus decode failed: \(error)")
        }
    }

    func sendUDP(_ data: Data) {
        udpConnection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("UDP Send Error: \(error)")
            }
        }))
    }

    func startCapturing() {
        let format = inputNode.outputFormat(forBus: bus)

        inputNode.installTap(onBus: bus, bufferSize: 960, format: format) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.processAudio(buffer: buffer)
        }

        do {
            try engine.start()
            outputNode.play()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    func stopCapturing() {
        inputNode.removeTap(onBus: bus)
        engine.stop()
    }

    func processAudio(buffer: AVAudioPCMBuffer) {
        guard let encoder = opusEncoder else { return }

        do {
            let encodedSize = try encoder.encode(buffer, to: &opusOutput)
            let opusData = Array(opusOutput.prefix(encodedSize))
            sendVoicePacket(opusData: opusData)
            rtpTimestamp &+= 960
        } catch {
            print("Opus encode failed: \(error)")
        }
    }

    func sendVoicePacket(opusData: [UInt8]) {
        sequence &+= 1

        var rtpHeader = [UInt8](repeating: 0, count: 12)
        rtpHeader[0] = 0x80
        rtpHeader[1] = 0x78
        rtpHeader[2] = UInt8((sequence >> 8) & 0xFF)
        rtpHeader[3] = UInt8(sequence & 0xFF)
        rtpHeader[4...7] = withUnsafeBytes(of: rtpTimestamp.bigEndian, Array.init)[0...3]
        rtpHeader[8...11] = withUnsafeBytes(of: ssrc.bigEndian, Array.init)[0...3]

        var nonce = [UInt8](repeating: 0, count: 24)
        for i in 0..<12 { nonce[i] = rtpHeader[i] }

        guard let encrypted = sodium.secretBox.seal(message: opusData, secretKey: secretKey, nonce: nonce) else {
            print("Encryption failed")
            return
        }

        let finalPacket = rtpHeader + encrypted
        sendUDP(Data(finalPacket))
    }
}

class DiscordGatewayClient {
    var socket: URLSessionWebSocketTask?
    let token: String
    let userID: String
    let guildID: String
    let channelID: String
    var sessionID: String = ""
    var voiceToken: String = ""
    var voiceEndpoint: String = ""

    init(token: String, userID: String, guildID: String, channelID: String) {
        self.token = token
        self.userID = userID
        self.guildID = guildID
        self.channelID = channelID
    }

    func connect() {
        let url = URL(string: "wss://gateway.discord.gg/?v=9&encoding=json")!
        socket = URLSession(configuration: .default).webSocketTask(with: url)
        socket?.resume()
        listen()
        identify()
    }

    func identify() {
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "properties": [
                    "$os": "ios",
                    "$browser": "finchcord",
                    "$device": "finchcord"
                ],
                "intents": 0
            ]
        ]
        send(payload)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.sendVoiceStateUpdate()
        }
    }

    func sendVoiceStateUpdate() {
        let payload: [String: Any] = [
            "op": 4,
            "d": [
                "guild_id": guildID,
                "channel_id": channelID,
                "self_mute": false,
                "self_deaf": false
            ]
        ]
        send(payload)
    }

    func send(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let json = String(data: data, encoding: .utf8) {
            socket?.send(.string(json)) { error in
                if let error = error {
                    print("Gateway send error: \(error)")
                }
            }
        }
    }

    func listen() {
        socket?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("Gateway error: \(error)")
            case .success(let message):
                if case .string(let text) = message {
                    self?.handle(text)
                }
                self?.listen()
            }
        }
    }

    func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let op = json["op"] as? Int else { return }

        if op == 0, let t = json["t"] as? String {
            if t == "VOICE_STATE_UPDATE" {
                if let d = json["d"] as? [String: Any],
                   let session = d["session_id"] as? String {
                    self.sessionID = session
                    print("Session ID: \(sessionID)")
                }
            } else if t == "VOICE_SERVER_UPDATE" {
                if let d = json["d"] as? [String: Any] {
                    self.voiceToken = d["token"] as? String ?? ""
                    self.voiceEndpoint = d["endpoint"] as? String ?? ""
                    print("Voice server: \(voiceEndpoint) \nToken: \(voiceToken)")
                }
            }
        }
    }
}
