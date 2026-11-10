// Esneme hareketleri. Animasyonlar Studio/esneme.py ile Blender'da üretildi (360 px) ve Stretches klasöründe gelir.
// Bel grubu uzun oturmaktan gelen bel ağrısı için; her hareket ayrı bir iş görür, birbirini tekrar edenler çıkarıldı.
function stretchGroups() {
  const m = (id, name, hint, dose, sets = 2) => ({ id, name, hint, dose, sets });
  const again = (s, hint, dose = s.dose) => ({ ...s, hint, dose });
  const reps = (n) => T(`${n} tekrar`, `${n} reps`);
  const hold = (n) => T(`${n} sn tut`, `hold ${n} s`);
  const eachSide = (n) => T(`her yanda ${n} sn tut`, `hold ${n} s each side`);
  const eachArm = T('her kolda 20 sn tut', 'hold 20 s each arm');

  const deadBug = m('deadbug', 'Dead bug', T('Sırtüstü, belin yerde kalsın; karşı kol ve bacağı yavaşça uzatıp geri getir. Son sette iki bacağın havada, dizler bükük 20 sn dur.', 'On your back, lower back down; slowly extend the opposite arm and leg, then return. On the last set hold both legs up, knees bent, for 20 s.'), T('her yana 8 tekrar', '8 reps each side'));
  const kneeHug = m('kneehug', T('Dizleri göğse çek', 'Knees to chest'), T('Sırtüstü, iki dizini kollarınla göğsüne doğru çek, belini yere bırak.', 'On your back, hug both knees toward your chest and let your lower back sink into the floor.'), hold(30));
  const twist = m('twist', T('Bacakları yana devir', 'Lying knee twist'), T('Sırtüstü, dizler bükük ve havada; bacaklarını yavaşça bir yana indir, omuzların yerde kalsın, sonra öbür yana.', 'On your back, knees bent and up; lower them slowly to one side with shoulders down, then the other.'), T('her yana 8 tekrar', '8 reps each side'));
  const tiltBridge = m('bridge', T('Pelvik tiltten köprüye', 'Pelvic tilt into bridge'), T('Önce belini yere bastır, sonra kalçanı omurga omurga kaldır ve aynı yoldan indir.', 'Press your lower back down first, then peel your hips up one vertebra at a time and roll back down.'), reps(10));
  const curlUp = m('curlup', 'Curl-up', T('Bir dizin bükük, ellerin belinin altında; başını ve omuzlarını birkaç santim kaldır, belini bükme.', 'One knee bent, hands under your lower back; lift head and shoulders a few centimetres without bending your lower back.'), T('6 tekrar, her biri 8 sn', '6 reps, 8 s each'));
  const sidePlank = m('sideplank', T('Yan köprü', 'Side plank'), T('Yan yat, dirseğin omzunun altında; kalçanı kaldırıp vücudunu düz tut, sonra diğer yan.', 'Lie on your side, elbow under shoulder; lift your hips and hold a straight line, then the other side.'), eachSide(20));
  const quad = m('quad', T('Kalça önünü esnet', 'Hip flexor and quad'), T('Yan yat, üstteki ayağını arkadan tutup topuğunu kalçana çek; dizin geride kalsın. Oturmaktan kısalan kalça önünü açar.', 'Lie on your side, hold your top foot behind you and draw the heel to your glute, knee back. Opens the front of the hip that sitting shortens.'), eachSide(30));
  const proneLift = m('prone', T('Yüzüstü gövde kaldırma', 'Prone back lift'), T('Yüzüstü, kollar yanda; göğsünü yerden birkaç santim kaldır, boynunu düz tut.', 'Face down, arms at your sides; lift your chest a few centimetres, neck long.'), reps(10));
  const upDog = m('updog', T('Yukarı bakan köpek', 'Upward dog'), T('Yüzüstü, eller kaburgaların yanında; kollarını yavaşça açarak göğsünü kaldır, kalçan yerde kalsın. Zor gelirse dirseklerini yerde bırak.', "Face down, hands by your ribs; straighten your arms slowly to lift your chest, hips stay down. If it's too much, stay on your elbows."), T('8 tekrar, her biri 2 sn', '8 reps, 2 s each'));
  const chairGlute = m('chairglute', T('Sandalyede kalça esnet', 'Seated glute stretch'), T('Sandalyede bir ayak bileğini öbür dizinin üstüne koy, sırtın düz öne eğil.', 'On a chair, cross one ankle over the other knee and lean forward with a straight back.'), eachSide(30));
  const pelvicStand = m('pelvicstand', T('Ayakta pelvik tilt', 'Standing pelvic tilt'), T('Dizler hafif bükük, karnını içeri çek ve leğenini yavaşça öne arkaya devir.', 'Knees soft, draw your belly in and slowly rock your pelvis forward and back.'), reps(10));

  const neck = m('neck', T('Boynunu esnet', 'Neck stretch'), T('Başını yana yatır, eliyle hafifçe bastır; omzun aşağıda kalsın. Sonra diğer yana.', 'Tilt your head to the side and press lightly with your hand, shoulder down. Then the other side.'), eachSide(20));
  const neckForward = m('neckforward', T('Boynunu öne esnet', 'Neck stretch forward'), T('Ellerini başının arkasında kenetle, başını yavaşça öne ve yana indir.', 'Clasp your hands behind your head and ease it slowly forward and to the side.'), eachSide(20));
  const sideBend = m('sidebend', T('Yana esne', 'Side bend'), T('Bir kolunu başının üstünden aşır, gövdeni yavaşça yana eğ.', 'Take one arm over your head and bend slowly to the side.'), eachSide(20));
  const triceps = m('triceps', T('Arka kolu esnet', 'Overhead triceps'), T('Elini sırtına indir, diğer elinle dirseği hafifçe aşağı çek.', 'Drop your hand down your back and ease the elbow down with the other hand.'), eachArm);
  const crossBody = m('crossbody', T('Omzu çapraz çek', 'Cross-body shoulder'), T('Kolunu göğsünün önünden geçir, diğer kolunla kendine doğru çek.', 'Bring your arm across your chest and pull it in with the other arm.'), eachArm);
  const upperArm = m('upperarm', T('Üst kolu çek', 'Upper arm stretch'), T('Kolunu omuz hizasında karşıya uzat, diğer elinle dirseğinden kendine çek.', 'Reach your arm across at shoulder height and pull it in at the elbow with the other hand.'), eachArm);
  const wristPull = m('wristpull', T('Bileği yana çek', 'Side wrist pull'), T('Bir elinle diğer bileğini tut, kolunu göğsünün önünden yana doğru çek.', 'Hold one wrist with the other hand and pull the arm across in front of your chest.'), eachArm);
  const chest = m('chest', T('Göğsünü aç', 'Open the chest'), T('Kollarını önde birleştir, sonra yana açıp göğsünü genişlet.', 'Bring your arms together in front, then swing them open and widen the chest.'), reps(10));
  const upperBack = m('upperback', T('Sırtını yuvarla', 'Round the upper back'), T('Ellerini önde kenetle, öne uzanırken sırtını yuvarla.', 'Clasp your hands in front and round your upper back as you reach forward.'), hold(20));
  const wrists = m('wrists', T('Bileklerini çevir', 'Wrist circles'), T('Klavyeden kalkan bileklerini iki yöne de yavaşça çevir.', 'Slowly circle your keyboard-tired wrists both ways.'), T('her yöne 10 tur', '10 circles each way'));
  const squatReach = m('squatreach', T('Çömel ve uzan', 'Squat to reach'), T('Çömel, kalkarken kollarını başının üstüne uzat.', 'Squat down, then reach your arms overhead as you stand.'), reps(8));
  const scapPush = m('scappush', T('Masada kürek itişi', 'Desk scapula push'), T('Ellerini masaya koy, kolların düz kalsın; göğsünü kollarının arasına indir, sonra kürek kemiklerini açarak it.', 'Hands on the desk, arms straight; let your chest sink between them, then push your shoulder blades apart.'), reps(10));

  return [
    { name: T('Genel', 'General'), moves: [neck, sideBend, chest, upperBack, crossBody, pelvicStand, wrists, squatReach, triceps] },
    { name: T('Bel', 'Lower back'), moves: [deadBug, kneeHug, twist, tiltBridge, curlUp, sidePlank, quad, proneLift, upDog, chairGlute, pelvicStand] },
    { name: T('Boyun ve sırt', 'Neck and back'), moves: [neck, neckForward, upperBack, chest, sideBend] },
    { name: T('Kol ve bilek', 'Arms and wrists'), moves: [triceps, crossBody, upperArm, wristPull, wrists] },
    // Sol omuz: masa başı duruşundan, arkada ve boyundan omza yayılan ağrı; baş üstü hareketler yok.
    { name: T('Sol omuz', 'Left shoulder'), moves: [
      again(neck, T('Başını sağa yatır, sağ elinle hafifçe bastır; sol omzun aşağıda kalsın.', 'Tilt your head right and press lightly with your right hand; keep your left shoulder down.'), hold(30)),
      again(neckForward, T('Başını sağ koltuk altına bakar gibi öne ve sağa indir; sol omzun aşağıda kalsın.', 'Lower your head forward and right as if looking at your right armpit; keep your left shoulder down.'), hold(30)),
      again(scapPush, T('Ellerini masaya koy; göğsünü indir, sonra kürek kemiklerini açarak it. Sol tarafın da aynı ölçüde çalışsın.', 'Hands on the desk; let your chest sink, then push your shoulder blades apart. Let the left side work as much as the right.')),
      again(chest, T('Kollarını yana açıp göğsünü genişlet; omuzlarını kulaklarından uzak tut.', 'Open your arms wide and broaden your chest; keep your shoulders away from your ears.')),
      again(upperBack, T('Ellerini önde kenetle, kürek kemiklerinin arasını açarak öne uzan.', 'Clasp your hands in front and reach forward, spreading your shoulder blades.')),
      again(crossBody, T('Sol kolunu göğsünün önünden geçir, sağ kolunla nazikçe çek. Batan bir ağrı olursa bırak.', 'Bring your left arm across your chest and ease it in with the right. Stop if you feel a sharp pain.'), hold(30)),
    ] },
  ];
}
