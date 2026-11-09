# -*- coding: utf-8 -*-
"""Günlük AGS denemesini doğrular ve icerik/ags/index.json'a ekler.

Kullanım: python3 ci/deneme_dogrula.py icerik/ags/gunluk/YYYY-MM-DD.json
Şema: {"tarih": "YYYY-MM-DD", "ad": str, "sorular": [{"id", "ders", "konu",
"soru", "secenekler": [5 farklı metin], "cevap": 0-4, "aciklama"}]}
"""
import glob
import json
import os
import re
import sys

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def hata(m):
    print("HATA:", m)
    sys.exit(1)


def main(yol):
    with open(os.path.join(KOK, "assets/ags_icerik.json"), encoding="utf-8") as f:
        icerik = json.load(f)
    konular = {d["id"]: {k["ad"] for k in d["konular"]} for d in icerik["dersler"]}
    eski_metin = {s["soru"].strip().lower() for s in icerik["sorular"]}
    eski_id = {s["id"] for s in icerik["sorular"]}
    hedef = os.path.abspath(yol)
    for p in glob.glob(os.path.join(KOK, "icerik/ags/gunluk/*.json")):
        if os.path.abspath(p) == hedef:
            continue
        with open(p, encoding="utf-8") as f:
            for s in json.load(f).get("sorular", []):
                eski_id.add(s.get("id"))
                eski_metin.add(str(s.get("soru", "")).strip().lower())

    with open(yol, encoding="utf-8") as f:
        d = json.load(f)
    tarih = d.get("tarih", "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", tarih):
        hata("tarih YYYY-MM-DD olmalı")
    if os.path.basename(yol) != tarih + ".json":
        hata("dosya adı tarihle aynı olmalı")
    sorular = d.get("sorular")
    if not isinstance(sorular, list) or not 10 <= len(sorular) <= 40:
        hata("10-40 soru olmalı")
    gorulen = set()
    cevaplar = []
    for i, s in enumerate(sorular, 1):
        for k in ("id", "ders", "konu", "soru", "secenekler", "cevap", "aciklama"):
            if k not in s:
                hata(f"{i}. soruda '{k}' yok")
        if s["ders"] not in konular:
            hata(f"{i}. soru: bilinmeyen ders {s['ders']}")
        if s["konu"] not in konular[s["ders"]]:
            hata(f"{i}. soru: '{s['konu']}' konusu {s['ders']} dersinde yok. Geçerli: {sorted(konular[s['ders']])}")
        sec = s["secenekler"]
        if not isinstance(sec, list) or len(sec) != 5 or len({str(x).strip() for x in sec}) != 5:
            hata(f"{i}. soru: 5 farklı seçenek olmalı")
        if not isinstance(s["cevap"], int) or not 0 <= s["cevap"] <= 4:
            hata(f"{i}. soru: cevap 0-4 arası olmalı")
        if not str(s["soru"]).strip() or not str(s["aciklama"]).strip():
            hata(f"{i}. soru: metin ve açıklama boş olamaz")
        if s["id"] in eski_id or s["id"] in gorulen:
            hata(f"{i}. soru: id tekrar ediyor ({s['id']})")
        if str(s["soru"]).strip().lower() in eski_metin:
            hata(f"{i}. soru daha önce sorulmuş")
        gorulen.add(s["id"])
        cevaplar.append(s["cevap"])
    if max(cevaplar.count(c) for c in range(5)) > len(cevaplar) * 0.4:
        hata("cevap şıkları dengesiz (bir şık %40'tan fazla)")

    idx_yol = os.path.join(KOK, "icerik/ags/index.json")
    with open(idx_yol, encoding="utf-8") as f:
        idx = json.load(f)
    liste = [x for x in idx.get("denemeler", []) if x.get("tarih") != tarih]
    liste.append({"tarih": tarih, "dosya": f"gunluk/{tarih}.json", "soru": len(sorular)})
    liste.sort(key=lambda x: x["tarih"], reverse=True)
    with open(idx_yol, "w", encoding="utf-8") as f:
        json.dump({"denemeler": liste}, f, ensure_ascii=False, indent=1)
    print(f"Tamam: {tarih}, {len(sorular)} soru; index'te {len(liste)} deneme.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        hata("kullanım: deneme_dogrula.py <dosya>")
    main(sys.argv[1])
