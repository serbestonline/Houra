import AppKit

// Mola hatırlatmasının sesi: dosya yok, açılışta küçük bir WAV olarak sentezlenir.
// İki nota: yumuşak vuruşlu, yükselen iki çan (Mi ve Si), kısa sönüm.

enum Chime {
    private static let rate = 44_100.0
    private static let length = 4.0
    private static let attack = 0.03
    private static let decay = 0.7                  // sönüm zaman sabiti, saniye
    private static let tones: [(freq: Double, amp: Double, delay: Double)] = [(659, 0.16, 0), (988, 0.12, 0.45)]
    private static var sound: NSSound?              // çalarken bırakılmasın

    static func play() {
        sound = NSSound(data: wav())
        sound?.volume = 0.6
        sound?.play()
    }

    /// 16 bit, tek kanal PCM WAV.
    static func wav() -> Data {
        let n = Int(length * rate)
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / rate
            var v = 0.0
            for tone in tones where t >= tone.delay {
                let u = t - tone.delay
                v += tone.amp * min(1, u / attack) * exp(-u / decay) * sin(2 * .pi * tone.freq * u)
            }
            v *= min(1, (length - t) / 0.3)          // sonda tık olmasın
            var s = Int16(max(-1, min(1, v)) * 32_767).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func put<T: FixedWidthInteger>(_ x: T) { var le = x.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return d + pcm
    }
}
