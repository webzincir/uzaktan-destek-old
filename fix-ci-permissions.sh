#!/bin/bash
# Bu script'i uzaktan-destek klasorunun icinde calistirin.
# Org'un contents:write iznini kisitlamasindan kaynaklanan workflow
# validasyon hatasini cozer.
set -e

echo "Klasor kontrolu..."
if [ ! -f ".github/workflows/flutter-build.yml" ]; then
  echo "HATA: dogru klasorde degilsiniz."
  exit 1
fi

python - <<'PYEOF'
import re
from pathlib import Path

f = Path(".github/workflows/flutter-build.yml")
t = f.read_text(encoding="utf-8")

# --- 1) generate-sbom job'unu tamamen kaldir (contents:write istiyor, org izin vermiyor) ---
sbom_block = (
    "  generate-sbom:\n"
    "    runs-on: ubuntu-latest\n"
    "\n"
    "    permissions:\n"
    "      contents: write\n"
    "\n"
    "    steps:\n"
    "      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4\n"
    "        with:\n"
    "          submodules: recursive\n"
    "\n"
    "      - name: Install Syft\n"
    "        uses: anchore/sbom-action/download-syft@v0\n"
    "\n"
    "      - name: Generate SBOM\n"
    "        run: |\n"
    "          syft dir:. \\\n"
    "            -o cyclonedx-json=rustdesk.sbom.json\n"
    "\n"
    "      - name: Publish Release\n"
    "        uses: softprops/action-gh-release@de2c0eb89ae2a093876385947365aca7b0e5f844 # v1\n"
    "        if: env.UPLOAD_ARTIFACT == 'true'\n"
    "        with:\n"
    "          prerelease: true\n"
    "          tag_name: ${{ env.TAG_NAME }}\n"
    "          files: |\n"
    "            rustdesk.sbom.json\n"
    "\n"
)

if sbom_block in t:
    t = t.replace(sbom_block, "", 1)
    print("generate-sbom job'u kaldirildi.")
else:
    print("generate-sbom job'u zaten yok / farkli (atlaniyor).")

# --- 2) Windows job'una izin gerektirmeyen artifact yukleme adimi ekle ---
old_publish = (
    "      - name: Publish Release\n"
    "        uses: softprops/action-gh-release@de2c0eb89ae2a093876385947365aca7b0e5f844 # v1\n"
    "        if: env.UPLOAD_ARTIFACT == 'true'\n"
    "        with:\n"
    "          prerelease: true\n"
    "          tag_name: ${{ env.TAG_NAME }}\n"
    "          files: |\n"
    "            ./SignOutput/rustdesk-*.msi\n"
    "            ./SignOutput/rustdesk-*.exe\n"
)

new_publish = (
    "      - name: Upload Windows installer (artifact, izin gerektirmez)\n"
    "        if: env.UPLOAD_ARTIFACT == 'true'\n"
    "        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1\n"
    "        with:\n"
    "          name: web-zincir-windows-installer-${{ matrix.job.arch }}\n"
    "          path: |\n"
    "            ./SignOutput/rustdesk-*.msi\n"
    "            ./SignOutput/rustdesk-*.exe\n"
    "\n"
    "      - name: Publish Release\n"
    "        uses: softprops/action-gh-release@de2c0eb89ae2a093876385947365aca7b0e5f844 # v1\n"
    "        if: env.UPLOAD_ARTIFACT == 'true'\n"
    "        continue-on-error: true\n"
    "        with:\n"
    "          prerelease: true\n"
    "          tag_name: ${{ env.TAG_NAME }}\n"
    "          files: |\n"
    "            ./SignOutput/rustdesk-*.msi\n"
    "            ./SignOutput/rustdesk-*.exe\n"
)

n = t.count(old_publish)
if n == 1:
    t = t.replace(old_publish, new_publish, 1)
    print("Windows job'una artifact yukleme adimi eklendi.")
elif n == 0:
    print("Publish Release adimi zaten degistirilmis / farkli (atlaniyor).")
else:
    raise SystemExit(f"HATA: beklenmedik sekilde {n} eslesme bulundu, elle kontrol edin.")

f.write_text(t, encoding="utf-8")
PYEOF

echo ""
echo "Commit ediliyor..."
git add -A
git commit -m "CI: generate-sbom kaldirildi, Windows ciktisi izin gerektirmeyen artifact olarak da yukleniyor"

echo ""
echo "===================================================="
echo "TAMAMLANDI. Push edin:"
echo "  git push origin master"
echo "===================================================="
