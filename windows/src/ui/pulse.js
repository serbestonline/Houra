// Serbest oturumdaki mola hatırlatması: ekran üç kez beyaz yanıp söner; ilk ekrandaki pencere çanı da çalar.
// Ses dosyası yok: yumuşak vuruşlu, yükselen iki çan (Mi ve Si) o an sentezlenir.
function chime() {
  const audio = new AudioContext(), out = audio.createGain();
  out.gain.value = 0.6;
  out.connect(audio.destination);
  for (const [frequency, amplitude, delay] of [[659, 0.16, 0], [988, 0.12, 0.45]]) {
    const tone = audio.createOscillator(), envelope = audio.createGain(), at = audio.currentTime + delay;
    tone.frequency.value = frequency;
    envelope.gain.setValueAtTime(0, at);
    envelope.gain.linearRampToValueAtTime(amplitude, at + 0.03);   // yumuşak vuruş
    envelope.gain.setTargetAtTime(0, at + 0.03, 0.7);              // kısa sönüm
    tone.connect(envelope).connect(out);
    tone.start(at); tone.stop(at + 4);
  }
}

document.getElementById('root').append(h('div.flash'));
if (query.get('sound')) chime();
