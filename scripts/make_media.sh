#!/bin/zsh
# README görsellerini gerçek uygulamadan yeniden üretir: ekran görüntüleri ve GIF'ler.
# Uygulama kendi pencerelerini yakalar; ekran kaydı izni gerekmez. Ekranda birkaç pencere ve
# kısa bir mola ekranı açılıp kapanır. Örnek veri ayrı bir veritabanına yazılır, gerçek verine dokunulmaz.
#   ./scripts/make_media.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh >/dev/null
APP=build/Houra.app/Contents/MacOS/Houra
DEMO="$HOME/Library/Application Support/Houra Demo"
WORK=$(mktemp -d)
mkdir -p "$DEMO" assets
export HOURA_LANG=en HOURA_DB="$DEMO/houra.sqlite"

fresh() { rm -f "$HOURA_DB"; "$APP" --demo >/dev/null; }

# Bu haftanın örnek notu: Bugün sayfasındaki "Bu hafta" kartı ve yeni oturumdaki "Haftanın listesi" için
mkdir -p "$DEMO/Notes"
cat > "$DEMO/Notes/Week $(date +%V).md" <<'EOF'
##### Client work
- [ ] Send the storyboard to Mia
- [w] Final cut feedback
	- 24.10: waiting for notes
- [ ] October invoice
##### Video
- [ ] Episode 12
	- [x] Script ✅ 2026-10-20
	- [ ] Record the voice-over
	- [ ] Edit and colour
##### Thesis
- [ ] Rewrite the methods section
- [ ] Pilot with two participants
##### Personal
- [ ] Book the dentist
EOF
WEEK=(-weeklyTemplate "~/Library/Application Support/Houra Demo/Notes/Week {WW}.md")

fresh
"$APP" --snapshot "$WORK/snap" "${WEEK[@]}" &
sleep 16; kill $! 2>/dev/null || true
for f in panel-today panel-stats panel-sessions panel-settings categories-picker new-session; do cp "$WORK/snap/$f.png" assets/; done

gif() { # ad, genişlik, renk sayısı
    ffmpeg -y -loglevel error -framerate 12 -i "$WORK/$1/f%05d.png" \
        -vf "scale=$2:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${3}:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
        -loop 0 "assets/$1.gif"
}
for scenario in flow widgets snap stats rest rest-stretches stretches; do
    fresh
    "$APP" --record "$scenario" "$WORK/$scenario" "${WEEK[@]}"
done
gif flow 880 128; gif widgets 728 192; gif snap 960 192; gif stats 1000 192
ffmpeg -y -loglevel error -framerate 12 -i "$WORK/rest/f%05d.png" \
    -vf "fps=8,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=48[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" -loop 0 assets/rest.gif
ffmpeg -y -loglevel error -framerate 12 -i "$WORK/rest-stretches/f%05d.png" \
    -vf "fps=8,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" -loop 0 assets/rest-stretches.gif
ffmpeg -y -loglevel error -framerate 12 -i "$WORK/stretches/f%05d.png" \
    -vf "fps=10,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -loop 0 assets/stretches.gif

rm -rf "$WORK"
echo "Görseller assets/ altında yenilendi."
