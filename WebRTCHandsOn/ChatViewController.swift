//
//  ChatViewController.swift
//  WebRTCHandsOn
//
//  Created by Tanaka, Tomohiro on 2017/06/18.
//  Copyright © 2017年 Tanaka, Tomohiro. All rights reserved.
//

import UIKit
import WebRTC
import Starscream
import SwiftyJSON

class ChatViewController: UIViewController, WebSocketDelegate, RTCPeerConnectionDelegate {

    @IBOutlet weak var remoteVideoView: RTCEAGLVideoView!
    @IBOutlet weak var cameraPreview: RTCCameraPreviewView!
    
    var websocket: WebSocket! = nil
    
    //WebRTCの処理
    var peerConnectionFactory: RTCPeerConnectionFactory! = nil
    
    //映像、音声ソースの取得処理
    var audioSource: RTCAudioSource?
    var videoSource: RTCAVFoundationVideoSource?
    
    //映像・音声の追加
    var peerConnection: RTCPeerConnection! = nil
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        peerConnectionFactory = RTCPeerConnectionFactory()
        
        startVideo()
        
        websocket = WebSocket(url: URL(string:
            "wss://conf.space/WebRTCHandsOnSig/tom19911201")!)
        websocket.delegate = self
        websocket.connect()

        // Do any additional setup after loading the view.
    }
    
    //NavigationBarから呼ばれた時に生成するメソッド
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(true)
        hangUp()
        websocket.disconnect()
    }
    
    deinit {
        if peerConnection != nil {
            hangUp()
        }
        audioSource = nil
        videoSource = nil
        peerConnectionFactory = nil
    }
    
    @IBAction func HangUp(_ sender: Any) {
        hangUp()
    }
    
    @IBAction func Connect(_ sender: Any) {
        // Connectボタンを押した時
        if peerConnection == nil {
            peerConnection = prepareNewConnection()
        }
    }
    
    //SDPの入っているRTCSessionDescription型のdescから必要な値を取り出してJSONに格納しwebsocket.writeで相手に送信
    func sendSDP(_ desc: RTCSessionDescription) {
        LOG("---sending sdp ---")
        let jsonSdp: JSON = [
            "sdp": desc.sdp, // SDP本体
            "type": RTCSessionDescription.string(
                for: desc.type) // offer か answer か
        ]
        // JSONを生成
        let message = jsonSdp.rawString()!
        LOG("sending SDP=" + message)
        // 相手に送信
        websocket.write(string: message)
    }
    
    //PeerConnectionを作ってからofferを相手に送るところまでをmakeOffer関数にまとめて作る
    func makeOffer() {
        // PeerConnectionを生成
        peerConnection = prepareNewConnection()
        // Offerの設定 今回は映像も音声も受け取る
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ], optionalConstraints: nil)
        let offerCompletion = {
            (offer: RTCSessionDescription?, error: Error?) in
            // Offerの生成が完了した際の処理
            if error != nil { return }
            self.LOG("createOffer() succsess")
            
            let setLocalDescCompletion = {(error: Error?) in
                // setLocalDescCompletionが完了した際の処理
                if error != nil { return }
                self.LOG("setLocalDescription() succsess")
                // 相手に送る
                self.sendSDP(offer!)
            }
            // 生成したOfferを自分のSDPとして設定
            self.peerConnection.setLocalDescription(offer!,
                                                    completionHandler: setLocalDescCompletion)
        }
        // Offerを生成
        self.peerConnection.offer(for: constraints,
                                  completionHandler: offerCompletion)
    }
    
    
    /*
    @IBAction func closeButtonAction(_ sender: Any) {
        // Closeボタンを押した時
        hangup()
        websocket.disconnect()
        _ = self.navigationController?.popToRootViewController(animated: true)
    }
    */

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //取得処理はstartVideoというメンバ関数にまとめる
    func startVideo() {
        // 音声ソースの設定
        let audioSourceConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil, optionalConstraints: nil)
        // 音声ソースの生成
        audioSource = peerConnectionFactory
            .audioSource(with: audioSourceConstraints)
        
        
        // 映像ソースの設定
        let videoSourceConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil, optionalConstraints: nil)
        videoSource = peerConnectionFactory
            .avFoundationVideoSource(with: videoSourceConstraints)
        // 映像ソースをプレビューに設定
        cameraPreview.captureSession = videoSource?.captureSession
    }
    
    //RTCPeerConnectionの作成
    func prepareNewConnection() -> RTCPeerConnection {
        // STUN/TURNサーバーの指定
        let configuration = RTCConfiguration()
        configuration.iceServers = [
            RTCIceServer.init(urlStrings:
                ["stun:stun.l.google.com:19302"])]
        // PeerConecctionの設定(今回はなし)
        let peerConnectionConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil)
        // PeerConnectionの初期化
        peerConnection = peerConnectionFactory.peerConnection(
            with: configuration, constraints: peerConnectionConstraints, delegate: self)
        
        ////音声の追加
        // 音声トラックの作成
        let localAudioTrack = peerConnectionFactory.audioTrack(with: audioSource!, trackId: "ARDAMSa0")
        // PeerConnectionからAudioのSenderを作成
        let audioSender = peerConnection.sender(
            withKind: kRTCMediaStreamTrackKindAudio,
            streamId: "ARDAMS")
        // Senderにトラックを設定
        audioSender.track = localAudioTrack
        
        
        ////映像の追加
        // 映像トラックの作成
        let localVideoTrack = peerConnectionFactory.videoTrack(with: videoSource!, trackId: "ARDAMSv0")
        // PeerConnectionからVideoのSenderを作成
        let videoSender = peerConnection.sender(
            withKind: kRTCMediaStreamTrackKindVideo,
            streamId: "ARDAMS")
        // Senderにトラックを設定
        videoSender.track = localVideoTrack
        
        return peerConnection
    }
    
    //終話処理の作成
    func hangUp() {
        if peerConnection != nil {
            if peerConnection.iceConnectionState != RTCIceConnectionState.closed {
                peerConnection.close()
            }
            peerConnection = nil
            LOG("peerConnection is closed.")
        }
    }
    
    
    //Log
    func LOG(_ body: String = "",
             function: String = #function,
             line: Int = #line)
    {
        print("[\(function) : \(line)] \(body)")
    }
    
    //WebSocket用Log関数************************************
    func websocketDidConnect(socket: WebSocket) {
        LOG()
    }
    
    //WebSocketLog取り用専用delegate
    func websocketDidDisconnect(socket: WebSocket,
                                error: NSError?) {
        LOG("error: \(String(describing: error?.localizedDescription))")
    }
    
    func websocketDidReceiveMessage(socket: WebSocket,
                                    text: String) {
        LOG("message: \(text)")
    }
    
    func websocketDidReceiveData(socket: WebSocket,
                                 data: Data) {
        LOG("data.count: \(data.count)")
    }
    
    
    //RTCPeerConnectionDelegate***************************
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange stateChanged: RTCSignalingState) {
        // 接続情報交換の状況が変化した際に呼ばれます
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd stream: RTCMediaStream) {
        // 映像/音声が追加された際に呼ばれます
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove stream: RTCMediaStream) {
        // 映像/音声削除された際に呼ばれます
    }
    
    func peerConnectionShouldNegotiate(_
        peerConnection: RTCPeerConnection) {
        // 接続情報の交換が必要になった際に呼ばれます
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange newState: RTCIceConnectionState) {
        // PeerConnectionの接続状況が変化した際に呼ばれます
        var state = ""
        switch (newState) {
        case RTCIceConnectionState.checking:
            state = "checking"
        case RTCIceConnectionState.completed:
            state = "completed"
        case RTCIceConnectionState.connected:
            state = "connected"
        case RTCIceConnectionState.closed:
            state = "closed"
            hangUp()
        case RTCIceConnectionState.failed:
            state = "failed"
            hangUp()
        case RTCIceConnectionState.disconnected:
            state = "disconnected"
        default:
            break
        }
        LOG("ICE connection Status has changed to \(state)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange newState: RTCIceGatheringState) {
        // 接続先候補の探索状況が変化した際に呼ばれます
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didGenerate candidate: RTCIceCandidate) {
        // Candidate(自分への接続先候補情報)が生成された際に呼ばれます
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didOpen dataChannel: RTCDataChannel) {
        // DataChannelが作られた際に呼ばれます
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove candidates: [RTCIceCandidate]) {
        // Candidateが削除された際に呼ばれます
    }
    
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
