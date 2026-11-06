"""Derlenen APK'nın ci/debug.keystore ile imzalandığını doğrular."""
import hashlib
import struct
import subprocess
import sys

apk, keystore = sys.argv[1], sys.argv[2]


def lp(b, o):
    n = struct.unpack_from("<I", b, o)[0]
    return b[o + 4:o + 4 + n], o + 4 + n


d = open(apk, "rb").read()
e = d.rfind(b"PK\x05\x06")
cd = struct.unpack_from("<I", d, e + 16)[0]
if d[cd - 16:cd] != b"APK Sig Block 42":
    sys.exit("APK imza bloğu bulunamadı")
size = struct.unpack_from("<Q", d, cd - 24)[0]
o, son, apk_sertifika = cd - size, cd - 24, None
while o < son:
    n, i = struct.unpack_from("<QI", d, o)
    deger = d[o + 12:o + 8 + n]
    o += 8 + n
    if i in (0x7109871A, 0xF05368C0):  # v2 / v3 imza
        imzacilar, _ = lp(deger, 0)
        imzaci, _ = lp(imzacilar, 0)
        veri, _ = lp(imzaci, 0)
        _, q = lp(veri, 0)
        sertifikalar, _ = lp(veri, q)
        sertifika, _ = lp(sertifikalar, 0)
        apk_sertifika = hashlib.sha256(sertifika).hexdigest()
        break

anahtar = subprocess.run(
    ["keytool", "-exportcert", "-keystore", keystore, "-storepass", "android",
     "-alias", "androiddebugkey"],
    capture_output=True, check=True).stdout
anahtar_sertifika = hashlib.sha256(anahtar).hexdigest()

print("APK   :", apk_sertifika)
print("Anahtar:", anahtar_sertifika)
if apk_sertifika != anahtar_sertifika:
    sys.exit("HATA: APK, ci/debug.keystore ile imzalanmamış!")
print("İmza doğru.")
