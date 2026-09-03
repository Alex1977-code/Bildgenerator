#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Nachbearbeitung einer KI-Figur fuer Roblox' Avatar Setup.

    blender -b -P tools/roblox_nachbearbeitung.py -- eingabe.glb ausgabe.glb

Im Blender-Text-Editor: EINGABE und AUSGABE unten eintragen, dann
"Skript ausfuehren".

Zusaetzliche Schalter hinter den Dateinamen:

    --nur-messen        nichts aendern, nur den Bericht drucken
    --loecher-fuellen   kleine Randschleifen ausserhalb von Augen und
                        Mund schliessen (siehe Doku 9)
    --teile-neu         vorhandene Kopfteile loeschen und nach dem Bau
                        der Hoehlen neu setzen. Noetig, wenn die fuenf
                        Netze schon in der Datei stehen, das Kopfnetz
                        aber keine Hoehlen hat - sonst stehen die
                        Kugeln vor der Flaeche statt in der Hoehle.

Das Skript misst, was Avatar Setup vom Eingabenetz verlangt, stellt
her, was sich aus der Geometrie herstellen laesst, und meldet den
Rest. Was sich nur beim Erzeugen der Figur entscheidet - Pose, Hals,
Accessoires - kann es nicht reparieren; solche Punkte stehen im
Bericht unter PROMPT.

Was es nicht anfasst
--------------------
Ein Kopf, in dem schon ein Gesicht steckt, bleibt, wie er ist - gleich
ob Hoehlen oder modellierte Augaepfel. Gemessen wird das an einer
Quadrik, die in die Gesichtsflaeche gelegt wird; ein glatter Kugelkopf
trifft sie fast genau, ein Gesicht nicht. Wer stattdessen nur nach
Hoehlen fragt, liest einen fertigen Augapfel als "nichts da" und graebt
hinein - bei jedem Aufruf erneut, weil das Ergebnis wieder keine Hoehle
ist. Genauso bleiben vorhandene Kopfteile stehen, eine schon richtige
Hoehe unveraendert und eine schon eingefrorene Transformation
unberuehrt. Jeder Lauf auf einer fertigen Datei aendert nichts mehr.

Quellen der Anforderungen
-------------------------
"Doku N" ist Punkt N der Liste "Mesh requirements" aus
avatar-setup/auto-setup-requirements.md:

    1 ein oder mehrere Netze          8 symmetrisch
    2 fuenf Kopfteile                 9 wasserdicht ausser Augen/Mund
    3 keine gemeinsamen Punkte       10 keine Accessoires
    4 Dreiecksbudget                 11 deutlicher Hals
    5 humanoide Form                 12 Textur dabei
    6 A- oder T-Pose                 13 Community/Marktplatz-Regeln
    7 Front auf -Z

"Koerper-Doku" ist avatar/character-bodies/specifications.md,
"Marktplatz-Doku" ist marketplace/marketplace-policy.md. "Projekt"
sind Zahlen aus assets/roblox_specs.json und lib/services/*.dart
dieser App.

Achsen - der haeufigste Denkfehler
----------------------------------
In der glTF-Datei steht die Figur in +Y und schaut nach +Z. In
Blender steht sie nach dem Import in +Z und schaut nach -Y; der
Importer dreht das um. Alle Rechnungen hier laufen in
Blender-Koordinaten, der Export dreht sie wieder zurueck.

Dass "vorn" in der Datei +Z ist und nicht -Z, wie Doku 7 es sagt,
ist gemessen und nicht abgeschrieben: Studios glTF-Import spiegelt
die Z-Achse, und zwei Auto-Setup-Laeufe standen rueckwaerts, weil die
Vorbereitung der Doku gefolgt ist statt der Messung (siehe
prepareForAutoSetup in lib/services/roblox_marketplace.dart). Dieses
Skript entscheidet die Blickrichtung nicht nach der Doku und nicht
nach der Annahme, sondern misst sie an den Zehen - und meldet, was
herauskam.

Woher die Gesichtsmasse stammen
-------------------------------
Aus lib/services/roblox_face_parts.dart und roblox_face_sculpt.dart,
unveraendert uebernommen: Feste Masse in Studs gibt es nicht, weil
die Figuren unterschiedlich gross ausfallen. Alle Zahlen sind Anteile
der gemessenen Kopfbreite B und der Kopfhoehe H.
"""

import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# --------------------------------------------------------------------
# Fuer den Text-Editor: hier eintragen, wenn ohne Kommandozeile
# gearbeitet wird.
# --------------------------------------------------------------------
EINGABE = ""
AUSGABE = ""

# --------------------------------------------------------------------
# Masse und Grenzen
# --------------------------------------------------------------------

# Die fuenf Kopfteile, an deren Namen Auto Setup sie erkennt
# (Doku 2). Umbenennen kostet den dynamischen Kopf.
KOPFTEILE = ("LeftEye", "RightEye", "UpperTeeth", "LowerTeeth", "Tongue")

# Dreiecksbudget, Doku 4. Rumpf steht dort mit 1750; die Summe der
# Einzelteile ergibt 10.742 nur mit den Kappen, die Auto Setup selbst
# an die Gliedmassen setzt - deshalb wird gegen beides geprueft.
BUDGET_GESAMT = 10742
BUDGET_KOPF = 4000
BUDGET_ARM = 1248
BUDGET_BEIN = 1248
BUDGET_RUMPF = 1750

# Zielhoehe. Nicht aus der Doku - die nennt nur Grenzen (Koerper-Doku,
# "Body scale": mindestens 3,6, hoechstens 9,5 Studs Gesamthoehe) -,
# sondern aus dem Projekt: assets/roblox_specs.json, scale.characterStuds,
# und marketplaceFigureStuds in lib/services/roblox_marketplace.dart.
# Alle Marktplatz-Grenzen der App sind auf diese Hoehe bezogen.
ZIEL_STUDS = 5.0
MIN_STUDS = 3.6
MAX_STUDS = 9.5

# Kopfband: das oberste Fuenftel der Figur. Dieselbe Annahme wie in
# roblox_face_parts.dart - B und H muessen aus demselben Band kommen
# wie dort, sonst sitzen die Teile woanders als in der App.
KOPF_ANTEIL = 0.2

# Gesichtsteile, Anteile von B (Kopfbreite) und H (Kopfhoehe).
# Uebernommen aus FaceProportions in roblox_face_parts.dart.
AUGE_RADIUS = 0.06          # x B
AUGE_ABSTAND = 0.18         # x B, je Auge von der Mitte
AUGE_HOEHE = 0.55           # x H
AUGE_VERSATZ = 0.4          # x Augenradius, wie tief der Mittelpunkt sitzt
ZAHN_OBEN = 0.36            # x H
ZAHN_UNTEN = 0.33           # x H, nachrangig gegenueber ZAHN_ABSTAND
ZAHN_BREITE = 0.25          # x B
ZAHN_HOEHE = 0.03           # x H
ZAHN_TIEFE = 0.04           # x B
ZAHN_ABSTAND = 0.01         # x H, freier Abstand zwischen den Reihen
ZUNGE_BREITE = 0.15         # x B
ZUNGE_HOEHE = 0.02          # x H
ZUNGE_TIEFE = 0.10          # x B
ZUNGE_RUECKVERSATZ = 0.05   # x B, hinter den Zahnreihen

# Hoehlen, Anteile von B und H. Uebernommen aus
# FaceSculptProportions in roblox_face_sculpt.dart.
HOEHLE_RADIUS = 0.10        # x B
HOEHLE_TIEFE = 0.06         # x B
LID_HOEHE = 0.015           # x B, Grat um die Hoehle
LID_BREITE = 0.5            # x Hoehlenradius
MUND_MITTE = 0.34           # x H
MUND_HALBBREITE = 0.16      # x B
MUND_HALBHOEHE = 0.045      # x H
MUND_TIEFE = 0.08           # x B
LIPPE_HOEHE = 0.015         # x B
LIPPE_BREITE = 0.4          # x Halbachsen
ZIEL_KANTE = 0.035          # x B, Kantenlaenge im Gesichtsbereich
MAX_DURCHGAENGE = 3
MAX_ZUSATZ_DREIECKE = 1500  # faceSculptTriangleBudget

# Ab wann eine Vertiefung als Hoehle zaehlt: 3 % der Kopfbreite
# (FaceCavities.minDepthOfHeadWidth).
HOEHLE_SCHWELLE = 0.03

# Hals: die schmalste Stelle zwischen Kopf und Schulter muss halb so
# breit sein wie der schmalere der beiden (marketplaceNeckRatio). Die
# Zahl kommt aus einem gescheiterten Auto-Setup-Lauf, nicht aus einer
# Schaetzung: Bei 59 % wurde die Kapuze bis zu den Schultern als Kopf
# segmentiert.
HALS_VERHAELTNIS = 0.50

# Pose. T-Pose erkennt man nicht an der Armspanne allein - der
# Marktplatz verlangt 6,22 Studs Spanne bei 5,00 Hoehe, jede zulaessige
# A-Pose liegt damit ueber 0,95 x Hoehe. Der Unterschied liegt in der
# Hoehe des breitesten Bandes (marketplaceTPoseSpan/-Height).
TPOSE_SPANNE = 0.95
TPOSE_HOEHE = 0.68

# Ab welcher Neigung ein Arm als abgespreizt gilt: 0,30 ist rund
# 17 Grad aus der Senkrechten. Darunter haengt er am Koerper - die
# I-Pose, vor der Doku 6 warnt.
ARM_NEIGUNG = 0.30

# Ab wann die Blickrichtung als bestimmt gilt (marketplaceFrontThreshold).
FRONT_SCHWELLE = 0.02

# Waagerechte Schnitte fuer alle Silhouetten-Messungen.
BAENDER = 60

# Zwei Silhouetten-Stuecke gelten als getrennt, wenn zwischen ihnen
# mehr Luft ist als dieser Anteil der Figurenbreite.
INSEL_LUECKE = 0.01


# --------------------------------------------------------------------
# Bericht
# --------------------------------------------------------------------

class Bericht:
    """Sammelt die Zeilen und druckt sie am Ende in drei Bloecken.

    Jede Zeile traegt den Punkt, auf den sie sich stuetzt. Ohne den
    weiss niemand, ob eine Meldung eine Roblox-Anforderung ist oder
    eine Ansicht dieses Skripts.
    """

    def __init__(self):
        self.gemessen = []
        self.geaendert = []
        self.prompt = []
        self.fehler = []

    def messung(self, quelle, text):
        self.gemessen.append((quelle, text))
        print("  gemessen  [%s] %s" % (quelle, text))

    def aenderung(self, quelle, text):
        self.geaendert.append((quelle, text))
        print("  geaendert [%s] %s" % (quelle, text))

    def an_prompt(self, quelle, text):
        self.prompt.append((quelle, text))
        print("  Prompt    [%s] %s" % (quelle, text))

    def problem(self, text):
        self.fehler.append(text)
        print("  FEHLER    %s" % text)

    def drucken(self, ein, aus):
        breit = 70
        print("")
        print("=" * breit)
        print("BERICHT   " + os.path.basename(ein))
        if aus:
            print("Ausgabe   " + os.path.basename(aus))
        print("=" * breit)
        for titel, zeilen in (
            ("GEMESSEN", self.gemessen),
            ("GEAENDERT", self.geaendert),
            ("DAS MUSS DER PROMPT RICHTEN", self.prompt),
        ):
            print("")
            print(titel)
            print("-" * breit)
            if not zeilen:
                print("  (nichts)")
                continue
            for quelle, text in zeilen:
                for i, stueck in enumerate(_umbruch(text, breit - 22)):
                    if i == 0:
                        print("  %-18s %s" % ("[" + quelle + "]", stueck))
                    else:
                        print("  %-18s %s" % ("", stueck))
        if self.fehler:
            print("")
            print("FEHLER")
            print("-" * breit)
            for text in self.fehler:
                print("  " + text)
        print("")
        print("NICHT GEPRUEFT")
        print("-" * breit)
        for zeile in (
            "Doku 5 (humanoide Form): Ob zwei Arme, zwei Beine, ein Rumpf",
            "  und ein Kopf da sind, entscheidet der Prompt - dieses Skript",
            "  zaehlt nur Silhouetten-Inseln und weiss nicht, was sie sind.",
            "Doku 8 (Symmetrie): nicht gemessen.",
            "Doku 13 (Community Standards, Marktplatz-Regeln): nicht",
            "  pruefbar aus der Geometrie.",
            "Doku 12: gemessen wird nur, DASS eine Textur da ist, nicht ob",
            "  sie taugt.",
        ):
            print("  " + zeile)
        print("")
        print("=" * breit)
        print("Doku N = Punkt N der Liste 'Mesh requirements' in")
        print("avatar-setup/auto-setup-requirements.md. Koerper-Doku =")
        print("avatar/character-bodies/specifications.md. Marktplatz-Doku =")
        print("marketplace/marketplace-policy.md. Projekt = Zahlen aus")
        print("assets/roblox_specs.json und lib/services/ dieser App.")
        print("=" * breit)


def _umbruch(text, breite):
    zeilen, aktuell = [], ""
    for wort in text.split():
        if aktuell and len(aktuell) + 1 + len(wort) > breite:
            zeilen.append(aktuell)
            aktuell = wort
        else:
            aktuell = (aktuell + " " + wort).strip()
    if aktuell:
        zeilen.append(aktuell)
    return zeilen or [""]


def _zahl(v, stellen=2):
    return ("%." + str(stellen) + "f") % v


# --------------------------------------------------------------------
# Aufruf
# --------------------------------------------------------------------

def argumente():
    roh = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    nur_messen = False
    loecher_fuellen = False
    teile_neu = False
    dateien = []
    for stueck in roh:
        if stueck == "--nur-messen":
            nur_messen = True
        elif stueck == "--loecher-fuellen":
            loecher_fuellen = True
        elif stueck == "--teile-neu":
            teile_neu = True
        elif stueck.startswith("--"):
            sys.exit("Unbekannter Schalter: " + stueck)
        else:
            dateien.append(stueck)
    ein = dateien[0] if dateien else EINGABE
    aus = dateien[1] if len(dateien) > 1 else AUSGABE
    if not ein:
        sys.exit(
            "Keine Eingabedatei. Aufruf:\n"
            "  blender -b -P roblox_nachbearbeitung.py -- ein.glb aus.glb"
        )
    ein = os.path.abspath(bpy.path.abspath(ein))
    if not os.path.exists(ein):
        sys.exit("Eingabedatei nicht gefunden: " + ein)
    if not aus and not nur_messen:
        stamm, endung = os.path.splitext(ein)
        aus = stamm + "_nachbearbeitet" + (endung or ".glb")
    if aus:
        aus = os.path.abspath(bpy.path.abspath(aus))
    return ein, aus, nur_messen, loecher_fuellen, teile_neu


# --------------------------------------------------------------------
# Szene
# --------------------------------------------------------------------

def laden(pfad, ber):
    """Leere Szene, Datei hinein, Importreste hinaus."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=pfad)

    # Der glTF-Importer legt eine Hilfsform fuer Knochen an und sammelt
    # sie in "glTF_not_exported". Bleibt sie drin, steht spaeter eine
    # Kugel neben der Figur.
    for sammlung in list(bpy.data.collections):
        if sammlung.name.startswith("glTF_not_exported"):
            for obj in list(sammlung.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.collections.remove(sammlung)

    netze = [o for o in bpy.data.objects if o.type == "MESH"]
    if not netze:
        ber.problem("Keine Netze in der Datei.")
        return []
    skelette = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if skelette:
        # Auto Setup baut sein eigenes Rig und verwirft ein
        # mitgebrachtes, wenn es nicht genau der R15-Vorgabe folgt
        # (Doku, "Rig requirements"). Angefasst wird es hier nicht -
        # ein Skelett einzufrieren zerstoert die Bindepose.
        ber.messung(
            "Doku Rig",
            "%d Skelett(e) in der Datei. Bleiben unberuehrt; Auto Setup "
            "baut ohnehin ein eigenes Rig, wenn das mitgebrachte nicht "
            "genau der R15-Vorgabe folgt." % len(skelette),
        )
    return netze


def transformationen_einfrieren(ber, nur_messen):
    """Rechnet Objekt-Transformationen in die Punkte.

    Die Koerper-Doku verlangt eingefrorene Transformationen und Pivots
    auf 0,0,0 ("Transformations", Abschnitt Geometry). Praktisch
    braucht auch dieses Skript das: Es misst in Weltkoordinaten, und
    eine Figur mit Objektskalierung 1,29 ist sonst 6,44 Studs hoch und
    ihre Punkte trotzdem 5,00.
    """
    geskinnt = {
        o.name for o in bpy.data.objects
        if o.type == "MESH"
        and any(m.type == "ARMATURE" for m in o.modifiers)
    }
    offen = [
        o for o in bpy.data.objects
        if o.type == "MESH"
        and o.name not in geskinnt
        and not _ist_einheit(o.matrix_world)
    ]
    if geskinnt:
        ber.messung(
            "Koerper-Doku",
            "%d geskinnte(s) Netz(e) nicht eingefroren - das verschoebe "
            "die Bindepose gegen das Skelett." % len(geskinnt),
        )
    if not offen:
        return
    if nur_messen:
        ber.messung(
            "Koerper-Doku",
            "%d Netz(e) tragen noch eine Objekt-Transformation "
            "(Skalierung/Drehung/Versatz). Nur-messen-Lauf: unveraendert."
            % len(offen),
        )
        return
    for obj in offen:
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
    ber.aenderung(
        "Koerper-Doku",
        "%d Objekt-Transformation(en) in die Punkte gerechnet - die Doku "
        "verlangt eingefrorene Werte und Pivot 0,0,0." % len(offen),
    )


def _ist_einheit(m):
    return all(
        abs(m[i][j] - (1.0 if i == j else 0.0)) < 1e-6
        for i in range(4) for j in range(4)
    )


def koerpernetze():
    """Alle Netze ausser den fuenf Kopfteilen."""
    return [
        o for o in bpy.data.objects
        if o.type == "MESH" and o.name not in KOPFTEILE
    ]


def kopfteile_vorhanden():
    return {
        o.name: o for o in bpy.data.objects
        if o.type == "MESH" and o.name in KOPFTEILE and len(o.data.polygons)
    }


# --------------------------------------------------------------------
# Geometrie-Helfer
# --------------------------------------------------------------------

def dreiecke(objs):
    """Alle Dreiecke in Weltkoordinaten, als Liste von 3 Vektoren."""
    out = []
    for obj in objs:
        me = obj.data
        me.calc_loop_triangles()
        mw = obj.matrix_world
        punkte = [mw @ v.co for v in me.vertices]
        for t in me.loop_triangles:
            a, b, c = t.vertices
            out.append((punkte[a], punkte[b], punkte[c]))
    return out


def bvh_von(tris):
    punkte = []
    flaechen = []
    for t in tris:
        i = len(punkte)
        punkte.extend([tuple(p) for p in t])
        flaechen.append((i, i + 1, i + 2))
    return BVHTree.FromPolygons(punkte, flaechen, all_triangles=True)


def huelle(tris):
    """Bounding-Box ueber Dreiecke: (min, max) als Listen."""
    mn = [float("inf")] * 3
    mx = [float("-inf")] * 3
    for t in tris:
        for p in t:
            for k in range(3):
                mn[k] = min(mn[k], p[k])
                mx[k] = max(mx[k], p[k])
    return mn, mx


def front_wert(vz, y):
    """Wie weit vorn ein Punkt liegt. Gross = weit vorn.

    In Blender liegt die Front bei -Y (vz = -1) oder bei +Y (vz = +1);
    welche von beiden, sagt die Zehenmessung. Mit dieser Funktion
    rechnen alle Gesichtsformeln so, wie sie in den Dart-Diensten
    stehen - dort ist vorn immer +Z.
    """
    return vz * y


def strahl_vorn(bvh, vz, x, z, start):
    """Vorderster Treffer eines Strahls von vorn auf (x, z).

    Rueckgabe als Frontwert, oder None, wenn der Strahl nichts trifft.
    """
    ort, _, _, _ = bvh.ray_cast(
        Vector((x, vz * start, z)), Vector((0.0, -vz, 0.0))
    )
    return None if ort is None else front_wert(vz, ort.y)


def durchstossungen(bvh, vz, x, z, start, hoechstens=12):
    """Wie oft ein Strahl von vorn die Huelle durchstoesst.

    Bei einer geschlossenen Huelle sind es zwei je Volumen. Vier oder
    mehr heissen: an dieser Stelle liegt von vorn gesehen ein Teil vor
    einem anderen - genau das, was Doku 6 verbietet.
    """
    n = 0
    y = vz * start
    richtung = Vector((0.0, -vz, 0.0))
    while n < hoechstens:
        ort, _, _, _ = bvh.ray_cast(Vector((x, y, z)), richtung)
        if ort is None:
            break
        n += 1
        y = ort.y - vz * 1e-4
    return n


class Silhouette:
    """Waagerechte Schnitte durch die Figur.

    Gemessen wird an **Dreiecken, nicht an Punkten**: Ein Dreieck, das
    ein Hoehenband ueberspannt, hat dort gar keinen Punkt, und ein
    grob unterteiltes Bein zerfaellt bei der Punktzaehlung in mehrere
    Inseln. Erst der Querschnitt ergibt die Silhouette, die auch der
    Validator sieht (measureMarketplaceFigure in
    lib/services/roblox_marketplace.dart begruendet das an einem
    Fehlschlag).
    """

    def __init__(self, tris, achse=0, baender=BAENDER):
        self.achse = achse
        mn, mx = huelle(tris)
        self.unten, self.oben = mn[2], mx[2]
        self.hoehe = max(self.oben - self.unten, 1e-9)
        self.breite_gesamt = max(mx[achse] - mn[achse], 1e-9)
        self.n = baender
        self.dz = self.hoehe / baender
        self.luecke = self.breite_gesamt * INSEL_LUECKE
        eimer = [[] for _ in range(baender)]
        for t in tris:
            zmin = min(p[2] for p in t)
            zmax = max(p[2] for p in t)
            i0 = max(0, int((zmin - self.unten) / self.dz) - 1)
            i1 = min(baender - 1, int((zmax - self.unten) / self.dz) + 1)
            for i in range(i0, i1 + 1):
                h = self.hoehe_von(i)
                if zmin <= h <= zmax:
                    eimer[i].append(t)
        self.intervalle = [self._schnitt(eimer[i], self.hoehe_von(i))
                           for i in range(baender)]

    def hoehe_von(self, i):
        return self.unten + (i + 0.5) * self.dz

    def index(self, z):
        return min(self.n - 1, max(0, int((z - self.unten) / self.dz)))

    def anteil(self, i):
        """Hoehe des Bandes als Anteil der Figurenhoehe, 0 unten."""
        return (self.hoehe_von(i) - self.unten) / self.hoehe

    def _schnitt(self, tris, h):
        roh = []
        for t in tris:
            xs = []
            for k in range(3):
                a, b = t[k], t[(k + 1) % 3]
                if (a[2] - h) * (b[2] - h) > 0 or a[2] == b[2]:
                    continue
                anteil = (h - a[2]) / (b[2] - a[2])
                xs.append(a[self.achse] + anteil * (b[self.achse] - a[self.achse]))
            if len(xs) >= 2:
                roh.append((min(xs), max(xs)))
        if not roh:
            return []
        roh.sort()
        zusammen = [list(roh[0])]
        for x0, x1 in roh[1:]:
            if x0 - zusammen[-1][1] <= self.luecke:
                zusammen[-1][1] = max(zusammen[-1][1], x1)
            else:
                zusammen.append([x0, x1])
        return [tuple(v) for v in zusammen]

    def breite(self, i):
        iv = self.intervalle[i]
        return 0.0 if not iv else iv[-1][1] - iv[0][0]

    def inseln(self, i):
        return len(self.intervalle[i])

    def insel_bei(self, i, x):
        for x0, x1 in self.intervalle[i]:
            if x0 - self.luecke <= x <= x1 + self.luecke:
                return (x0, x1)
        return None


# --------------------------------------------------------------------
# Aufstellen: Hoehe, Boden, Blickrichtung
# --------------------------------------------------------------------

def aufstellen(ber, nur_messen):
    """Bringt die Figur auf ZIEL_STUDS, stellt sie auf den Boden.

    Nicht geaendert wird die Drehung. Wohin die Figur schaut, wird
    gemessen und gemeldet - gedreht wird sie nicht, weil das die
    Vorbereitung in der App (prepareForAutoSetup) bereits tut und zwei
    Stellen, die dasselbe drehen, sich gegenseitig aufheben.
    """
    netze = [o for o in bpy.data.objects if o.type == "MESH"]
    tris = dreiecke(netze)
    if not tris:
        ber.problem("Keine Dreiecke gefunden.")
        return None
    mn, mx = huelle(tris)
    hoehe = mx[2] - mn[2]
    breite_x = mx[0] - mn[0]
    tiefe_y = mx[1] - mn[1]

    # Steht sie ueberhaupt? Gemessen wird gegen die **Tiefe**, nicht
    # gegen die Breite: Eine T-Pose ist breiter als hoch, und zwar
    # zwangslaeufig - der Marktplatz verlangt 6,22 Studs Armspanne bei
    # 5,00 Studs Hoehe. Wer Hoehe gegen Breite prueft, weist jede
    # T-Pose-Figur ab. Eine liegende Figur dagegen ist flacher als
    # tief.
    if hoehe < tiefe_y:
        ber.problem(
            "Die Figur ist flacher als tief: %s hoch, %s breit, %s tief. "
            "Sie liegt oder steht auf der falschen Achse - die "
            "Koerper-Doku verlangt 'stand up in positive Y'. Alles "
            "Weitere waere geraten."
            % (_zahl(hoehe), _zahl(breite_x), _zahl(tiefe_y))
        )
        return None
    if hoehe < breite_x * 0.7:
        ber.messung(
            "Koerper-Doku",
            "Die Figur ist deutlich breiter als hoch (%s zu %s). Das "
            "kann eine weite T-Pose sein oder eine liegende Figur - im "
            "Viewer nachsehen." % (_zahl(breite_x), _zahl(hoehe)),
        )

    if breite_x < tiefe_y:
        ber.an_prompt(
            "Koerper-Doku",
            "Die Armspanne liegt auf der Tiefenachse (%s breit, %s tief): "
            "Die Figur steht quer. Die App dreht das in "
            "prepareForAutoSetup; dieses Skript misst nur."
            % (_zahl(breite_x), _zahl(tiefe_y)),
        )

    ber.messung(
        "Projekt",
        "Hoehe %s Studs, Breite %s, Tiefe %s."
        % (_zahl(hoehe), _zahl(breite_x), _zahl(tiefe_y)),
    )
    if hoehe < MIN_STUDS or hoehe > MAX_STUDS:
        ber.messung(
            "Koerper-Doku",
            "Die Hoehe liegt ausserhalb der Spanne %s bis %s Studs, die "
            "die Tabellen 'Body scale' nennen."
            % (_zahl(MIN_STUDS, 1), _zahl(MAX_STUDS, 1)),
        )

    faktor = ZIEL_STUDS / hoehe
    versatz = (
        -(mn[0] + mx[0]) / 2 * faktor,
        -(mn[1] + mx[1]) / 2 * faktor,
        -mn[2] * faktor,
    )
    schief = any(abs(v) > 1e-3 for v in versatz)
    falsch_gross = abs(hoehe - ZIEL_STUDS) > 1e-3
    if not (schief or falsch_gross):
        ber.messung("Projekt", "Stand und Hoehe stimmen schon - nichts geaendert.")
    elif nur_messen:
        ber.messung(
            "Projekt",
            "Nur-messen-Lauf: nicht auf %s Studs gebracht (Faktor waere %s)."
            % (_zahl(ZIEL_STUDS, 1), _zahl(faktor, 3)),
        )
    else:
        m = Matrix.Translation(Vector(versatz)) @ Matrix.Scale(faktor, 4)
        for me in {o.data for o in netze}:
            me.transform(m)
        if falsch_gross:
            ber.aenderung(
                "Projekt",
                "Auf %s Studs gebracht (Faktor %s). Alle Grenzen des "
                "Validators sind auf diese Hoehe bezogen "
                "(assets/roblox_specs.json, scale.characterStuds)."
                % (_zahl(ZIEL_STUDS, 1), _zahl(faktor, 3)),
            )
        if schief:
            ber.aenderung(
                "Koerper-Doku",
                "Nullpunkt mittig unter die Figur gelegt, Fuesse auf 0 - "
                "die Doku verlangt Pivot 0,0,0 und 'stand up in positive Y'.",
            )
        tris = dreiecke(netze)
    return tris


def _schnittpunkte(tris, h):
    """Alle Durchstosspunkte der Dreiecke durch die Ebene z = h.

    Gemessen wird an Dreiecken, nicht an Punkten: Ein Bein aus einem
    einzigen Quader hat zwischen Fuss und Huefte gar keinen Punkt, und
    die Zehenmessung stand dann ohne Zahlen da.
    """
    out = []
    for t in tris:
        for k in range(3):
            a, b = t[k], t[(k + 1) % 3]
            if (a[2] - h) * (b[2] - h) > 0 or a[2] == b[2]:
                continue
            anteil = (h - a[2]) / (b[2] - a[2])
            out.append((a[0] + anteil * (b[0] - a[0]),
                        a[1] + anteil * (b[1] - a[1])))
    return out


def _bandmittel(tris, unten, hoehe, von, bis, schritte=5):
    """Mittlere Tiefe und die beiden Extreme in einem Hoehenband."""
    ys = []
    for i in range(schritte):
        h = unten + hoehe * (von + (bis - von) * (i + 0.5) / schritte)
        ys.extend(y for _, y in _schnittpunkte(tris, h))
    if not ys:
        return None, None, None
    return sum(ys) / len(ys), min(ys), max(ys)


def blickrichtung(tris, ber):
    """Misst an den Zehen, wohin die Figur schaut. Rueckgabe: vz.

    vz = -1 heisst: vorn ist -Y in Blender, also +Z in der Datei - so
    will es die App (prepareForAutoSetup), weil Studios glTF-Import
    die Z-Achse spiegelt. vz = +1 ist die andere Richtung.

    Gemessen wird am Fuss gegen das Schienbein darueber, nicht am
    Rumpf: Ein Bauch wandert nach vorn, eine Kapuze nach hinten, und
    bei einer Figur mit beidem zeigten beide Signale falsch
    (estimateFrontSignal in lib/services/auto_rig.dart).
    """
    mn, mx = huelle(tris)
    hoehe = mx[2] - mn[2]
    tiefe = mx[1] - mn[1]
    if hoehe <= 0 or tiefe <= 0:
        return -1.0, 0.0
    fuss, f_min, f_max = _bandmittel(tris, mn[2], hoehe, 0.01, 0.08)
    schien, _, _ = _bandmittel(tris, mn[2], hoehe, 0.12, 0.28)
    if fuss is None or schien is None:
        ber.messung(
            "Doku 7",
            "Blickrichtung nicht messbar - unten fehlt Geometrie. "
            "Angenommen: vorn ist -Y in Blender (+Z in der Datei).",
        )
        return -1.0, 0.0
    # "Vorn" ist -y, solange vorn bei -Y liegt; deshalb das Vorzeichen.
    # Zwei Signale, beide am Fuss: seine Mitte liegt vor dem
    # Schienbein, und er ragt nach vorn weiter darueber hinaus als nach
    # hinten (Zehen gegen Ferse).
    schienbein = -schien
    signal = (-fuss - schienbein) / tiefe * 2
    signal += ((-f_min - schienbein) - (schienbein - (-f_max))) / tiefe
    if signal > FRONT_SCHWELLE:
        ber.messung(
            "Doku 7",
            "Blickrichtung gemessen (Zehensignal %s): vorn ist -Y in "
            "Blender, +Z in der Datei. So will es die App, weil Studios "
            "glTF-Import die Z-Achse spiegelt; Doku 7 nennt -Z, gemeint "
            "ist dieselbe Seite." % _zahl(signal, 3),
        )
        return -1.0, signal
    if signal < -FRONT_SCHWELLE:
        ber.an_prompt(
            "Doku 7",
            "Die Zehen zeigen nach hinten (Signal %s): In der Datei "
            "schaut die Figur nach -Z. Die Gesichtsteile setzt dieses "
            "Skript auf die gemessene Seite; fuer den Auto-Setup-Lauf "
            "muss die Figur noch um 180 Grad gedreht werden - das tut "
            "prepareForAutoSetup in der App." % _zahl(signal, 3),
        )
        return 1.0, signal
    ber.an_prompt(
        "Doku 7",
        "Blickrichtung nicht bestimmbar (Signal %s): Die Figur sieht von "
        "vorn wie von hinten aus. Angenommen wird vorn = -Y in Blender; "
        "im Viewer nachsehen, sonst sitzt das Gesicht am Hinterkopf."
        % _zahl(signal, 3),
    )
    return -1.0, signal


# --------------------------------------------------------------------
# Hals, Pose, Budget
# --------------------------------------------------------------------

class Zonen:
    """Wo Kopf, Rumpf, Arme und Beine anfangen - aus der Silhouette.

    Ohne Skelett gibt es keine andere Quelle. Alle Grenzen hier sind
    Schaetzungen aus den waagerechten Schnitten und im Bericht auch so
    benannt; Auto Setup zerlegt spaeter selbst.
    """

    def __init__(self, sil, mitte_x):
        self.sil = sil
        self.mitte_x = mitte_x
        self.hals_index = None
        self.hals_breite = 0.0
        self.kopf_breite = 0.0
        self.schulter_breite = 0.0
        self.schritt_index = None
        self._hals_suchen()
        self._schritt_suchen()

    def _hals_suchen(self):
        sil = self.sil
        # Gesucht wird die schmalste Stelle zwischen Scheitel und
        # halber Hoehe, die oben **und** unten breitere Nachbarn hat -
        # sonst gilt jede Verjuengung am Scheitel als Hals.
        oben = sil.n - 1
        unten = sil.index(sil.unten + sil.hoehe * 0.5)
        beste = None
        for i in range(unten, oben):
            b = sil.breite(i)
            if b <= 0:
                continue
            darueber = max([sil.breite(k) for k in range(i + 1, oben + 1)] or [0])
            darunter = max([sil.breite(k) for k in range(unten, i)] or [0])
            if darueber <= b or darunter <= b:
                continue
            if beste is None or b < beste[1]:
                beste = (i, b, darueber, darunter)
        if beste is None:
            return
        self.hals_index, self.hals_breite = beste[0], beste[1]
        self.kopf_breite, self.schulter_breite = beste[2], beste[3]

    def _schritt_suchen(self):
        """Das oberste Band unterhalb der halben Hoehe, in dem die
        Koerpermitte frei ist - dort beginnen die zwei Beine.

        Nicht "zwei Inseln": Auf Hueftehoehe stehen in der A-Pose auch
        die Arme frei neben dem Rumpf, das sind ebenfalls zwei und mehr
        Inseln. An einer echten Figur wanderte der Schritt so auf 55 %
        der Hoehe, und die Beine bekamen 2.700 Dreiecke zugerechnet
        statt gut 1.000. Die Luecke **in der Mitte** hat nur der
        Schritt.
        """
        sil = self.sil
        grenze = sil.index(sil.unten + sil.hoehe * 0.55)
        for i in range(grenze, -1, -1):
            if sil.inseln(i) >= 2 and sil.insel_bei(i, self.mitte_x) is None:
                self.schritt_index = i
                return

    @property
    def hals_verhaeltnis(self):
        bezug = min(self.kopf_breite, self.schulter_breite)
        if bezug <= 0:
            return 1.0
        return self.hals_breite / bezug

    @property
    def hals_hoehe(self):
        if self.hals_index is None:
            return None
        return self.sil.hoehe_von(self.hals_index)

    @property
    def schritt_hoehe(self):
        if self.schritt_index is None:
            return None
        return self.sil.hoehe_von(self.schritt_index)


def hals_melden(zonen, ber):
    if zonen.hals_index is None:
        ber.an_prompt(
            "Doku 11",
            "Kein Hals gefunden: Zwischen Kopf und Schulter gibt es keine "
            "Einschnuerung. Auto Setup setzt die Kopfgrenze an die "
            "schmalste Stelle - ohne Hals wird der halbe Oberkoerper zum "
            "Kopf. Ins Motiv: 'distinct neck, head clearly separated "
            "from the shoulders'.",
        )
        return
    v = zonen.hals_verhaeltnis
    ber.messung(
        "Doku 11",
        "Hals: schmalste Stelle %s Studs bei %s %% der Hoehe, Kopf %s, "
        "Schulter %s - Verhaeltnis %s."
        % (
            _zahl(zonen.hals_breite),
            "%.0f" % (zonen.sil.anteil(zonen.hals_index) * 100),
            _zahl(zonen.kopf_breite),
            _zahl(zonen.schulter_breite),
            _zahl(v),
        ),
    )
    if v > HALS_VERHAELTNIS:
        ber.an_prompt(
            "Doku 11",
            "Der Hals ist mit %s %% zu breit; unter %s %% ist die "
            "Einschnuerung eindeutig (Wert aus einem gescheiterten "
            "Auto-Setup-Lauf, marketplaceNeckRatio). Ins Motiv: "
            "'distinct neck, not merged with the shoulders'."
            % ("%.0f" % (v * 100), "%.0f" % (HALS_VERHAELTNIS * 100)),
        )


def pose_melden(sil, zonen, bvh, vz, tris, ber):
    """Misst die Pose und meldet sie. Aendern kann das nur der Prompt."""
    mn, mx = huelle(tris)
    hoehe = mx[2] - mn[2]
    spanne = mx[0] - mn[0]

    breitestes = max(range(sil.n), key=sil.breite)
    breitestes_anteil = sil.anteil(breitestes)

    def band_max(von, bis):
        i0, i1 = sil.index(mn[2] + hoehe * von), sil.index(mn[2] + hoehe * bis)
        werte = [sil.breite(i) for i in range(i0, i1 + 1)]
        return max(werte) if werte else 0.0

    schulter = band_max(0.68, 0.85)
    haende = band_max(0.30, 0.55)
    # Die Breite knapp unter der Schulter: In der T-Pose steht dort nur
    # der Rumpf, weil die Arme darueber waagerecht abstehen.
    brust = band_max(0.50, 0.62)
    # Wie oft die Silhouette zwischen Huefte und Schulter in drei
    # Stuecke zerfaellt: Arm, Rumpf, Arm. Genau das fehlt in der
    # I-Pose, in der die Arme am Koerper anliegen.
    i0, i1 = sil.index(mn[2] + hoehe * 0.35), sil.index(mn[2] + hoehe * 0.75)
    baender = list(range(i0, i1 + 1))
    frei = sum(1 for i in baender if sil.inseln(i) >= 3)
    frei_anteil = frei / max(len(baender), 1)

    # Wie schraeg die Arme stehen. Gemessen an der Mitte der aeusseren
    # Silhouetten-Insel je Band: Wandert sie nach unten hin nach
    # aussen, ist der Arm abgespreizt; steht sie senkrecht
    # uebereinander, haengt er am Koerper. 1,00 sind 45 Grad, 0,36 sind
    # 20 Grad.
    #
    # Die Zahl der Inseln allein reicht nicht: An einer echten Figur
    # mit senkrecht herabhaengenden Armen war zwischen Arm und Rumpf
    # genug Luft fuer drei Inseln in 60 % der Baender - und das ist
    # trotzdem die I-Pose, vor der Doku 6 warnt.
    neigungen = []
    for seite in (0, -1):
        punkte = [
            (sil.hoehe_von(i),
             (sil.intervalle[i][seite][0] + sil.intervalle[i][seite][1]) / 2)
            for i in baender if sil.inseln(i) >= 3
        ]
        if len(punkte) < 3:
            continue
        zs = np.array([z for z, _ in punkte])
        xs = np.array([x for _, x in punkte])
        if zs.std() < 1e-9:
            continue
        # Nach unten nach aussen heisst: rechts nimmt x mit der Hoehe
        # ab, links zu. Mit dem Seitenvorzeichen wird beides positiv.
        steigung = float(np.polyfit(zs, xs, 1)[0])
        neigungen.append(steigung * (1.0 if seite == -1 else -1.0))
    arm_neigung = -sum(neigungen) / len(neigungen) if neigungen else 0.0

    ber.messung(
        "Doku 6",
        "Pose gemessen: Armspanne %s Studs (%s x Hoehe), breitestes Band "
        "bei %s %% der Hoehe, Schulterband %s, Brustband %s, Band auf "
        "Handhoehe %s, drei Silhouetten-Inseln in %s %% der Baender "
        "zwischen Huefte und Schulter, Armneigung %s (1,00 waeren "
        "45 Grad)."
        % (
            _zahl(spanne),
            _zahl(spanne / hoehe),
            "%.0f" % (breitestes_anteil * 100),
            _zahl(schulter),
            _zahl(brust),
            _zahl(haende),
            "%.0f" % (frei_anteil * 100),
            _zahl(arm_neigung),
        ),
    )

    # Entschieden wird an der Luft zwischen Arm und Rumpf, nicht an der
    # Armspanne. Die Spanne allein taugt nicht: Der Marktplatz verlangt
    # 6,22 Studs Spanne bei 5,00 Hoehe, also 1,24 x Hoehe - jede
    # zulaessige A-Pose liegt damit ueber den 0,95 x Hoehe, ab denen
    # die Spanne nach T-Pose aussieht (marketplaceTPoseSpan begruendet
    # das an drei Laeufen). Deshalb:
    #
    #   drei Silhouetten-Inseln zwischen Huefte und Schulter
    #       -> die Arme haengen frei neben dem Rumpf: A-Pose
    #   sonst breitestes Band oben und deutlich breiter als die Brust
    #       -> die Arme stehen waagerecht ab: T-Pose
    #   sonst -> die Arme liegen am Koerper: I-Pose
    # Die Neigung entscheidet, die Inseln sind nur die Bedingung dafuer,
    # dass ueberhaupt eine gemessen werden konnte: An einer echten
    # A-Pose-Figur mit weit abgespreizten Armen zerfiel die Silhouette
    # nur in 20 % der Baender in drei Stuecke - weiter oben steckt der
    # Arm in derselben Insel wie die Schulter.
    arme_frei = frei_anteil >= 0.10 and arm_neigung >= ARM_NEIGUNG
    tpose = (breitestes_anteil >= TPOSE_HOEHE and brust > 0
             and spanne >= brust * 1.3)
    if arme_frei:
        ber.messung(
            "Doku 6",
            "Das ist eine A-Pose (Arme stehen vom Koerper ab) - Doku 6 "
            "erlaubt sie.",
        )
    elif tpose:
        ber.messung("Doku 6", "Das ist eine T-Pose - Doku 6 erlaubt sie.")
    else:
        ber.an_prompt(
            "Doku 6",
            "Das sieht nach I-Pose aus: Die Arme haengen senkrecht am "
            "Koerper (Neigung %s, abgespreizt waere ab %s), und das "
            "breiteste Band liegt nicht oben auf Schulterhoehe. Doku 6: "
            "'Character bodies with I-pose may yield lower quality "
            "results.' Umformen kann das kein Skript - ins Motiv "
            "gehoert 'standing in a wide A-pose, arms held away from "
            "the body'." % (_zahl(arm_neigung), _zahl(ARM_NEIGUNG)),
        )

    # Doku 6, zweiter Punkt: nichts darf von vorn etwas anderes
    # verdecken. Gemessen mit Strahlen von vorn - vier oder mehr
    # Durchstossungen heissen, dass an dieser Stelle zwei Volumen
    # hintereinander liegen.
    start = abs(mn[1]) + abs(mx[1]) + 1.0
    obergrenze = zonen.hals_hoehe or (mn[2] + hoehe * 0.8)
    treffer, verdeckt = 0, 0
    for ix in range(40):
        x = mn[0] + (mx[0] - mn[0]) * (ix + 0.5) / 40
        for iz in range(40):
            z = mn[2] + (obergrenze - mn[2]) * (iz + 0.5) / 40
            n = durchstossungen(bvh, vz, x, z, start)
            if n >= 2:
                treffer += 1
            if n >= 4:
                verdeckt += 1
    anteil = verdeckt / treffer if treffer else 0.0
    ber.messung(
        "Doku 6",
        "Von vorn liegen auf %s %% der getroffenen Rasterpunkte "
        "unterhalb des Halses zwei Volumen hintereinander (%d von %d)."
        % ("%.0f" % (anteil * 100), verdeckt, treffer),
    )
    if anteil > 0.05:
        ber.an_prompt(
            "Doku 6",
            "Da verdeckt von vorn eine Gliedmasse eine andere. Doku 6: "
            "'Ensure that no limbs obscure or overlap each other from "
            "the front view.' Das entscheidet die Pose beim Erzeugen.",
        )


def budget_melden(sil, zonen, tris, ber, kopfteil_dreiecke):
    """Zaehlt die Dreiecke je Koerperteil und vergleicht mit Doku 4."""
    mitte_x = zonen.mitte_x
    hals = zonen.hals_hoehe
    schritt = zonen.schritt_hoehe
    grenze_kopf = hals if hals is not None else (
        sil.oben - sil.hoehe * KOPF_ANTEIL)
    grenze_bein = schritt if schritt is not None else (
        sil.unten + sil.hoehe * 0.45)

    zahl = {"Kopf": 0, "Rumpf": 0, "Arm links": 0, "Arm rechts": 0,
            "Bein links": 0, "Bein rechts": 0}
    for t in tris:
        mx_ = (t[0][0] + t[1][0] + t[2][0]) / 3
        mz = (t[0][2] + t[1][2] + t[2][2]) / 3
        if mz >= grenze_kopf:
            zahl["Kopf"] += 1
        elif mz < grenze_bein:
            zahl["Bein links" if mx_ < mitte_x else "Bein rechts"] += 1
        else:
            # Arm oder Rumpf: In welchem Silhouetten-Stueck liegt das
            # Dreieck? Das Stueck mit der Koerpermitte ist der Rumpf,
            # jedes andere ein Arm.
            i = sil.index(mz)
            rumpf = sil.insel_bei(i, mitte_x)
            eigen = sil.insel_bei(i, mx_)
            if eigen is not None and rumpf is not None and eigen != rumpf:
                zahl["Arm links" if mx_ < mitte_x else "Arm rechts"] += 1
            else:
                zahl["Rumpf"] += 1

    zahl["Kopf"] += kopfteil_dreiecke
    gesamt = sum(zahl.values())
    ber.messung(
        "Doku 4",
        "Dreiecke gesamt %d von %d erlaubten." % (gesamt, BUDGET_GESAMT),
    )
    ber.messung(
        "Doku 4",
        "Verteilung (aus der Silhouette geschaetzt, ohne Rig): Kopf %d "
        "von %d, Rumpf %d von %d, Arme %d/%d von je %d, Beine %d/%d von "
        "je %d. Die Kopfzahl enthaelt %d Dreiecke der fuenf Kopfteile."
        % (zahl["Kopf"], BUDGET_KOPF, zahl["Rumpf"], BUDGET_RUMPF,
           zahl["Arm links"], zahl["Arm rechts"], BUDGET_ARM,
           zahl["Bein links"], zahl["Bein rechts"], BUDGET_BEIN,
           kopfteil_dreiecke),
    )
    if hals is None or schritt is None:
        ber.messung(
            "Doku 4",
            "Die Grenzen sind grob: %s%s Deshalb ist die Verteilung ein "
            "Anhalt, keine Abrechnung."
            % ("kein Hals gefunden, Kopfgrenze auf das oberste Fuenftel "
               "gelegt. " if hals is None else "",
               "kein Schritt gefunden, Beingrenze auf 45 %% der Hoehe "
               "gelegt. " if schritt is None else ""),
        )
    if gesamt > BUDGET_GESAMT:
        ber.an_prompt(
            "Doku 4",
            "%d Dreiecke zu viel. Doku 4 nennt 10.742 als Obergrenze, und "
            "Auto Setup setzt beim Segmentieren noch Kappen an die "
            "Gliedmassen - wer knapp darunter liegt, faellt dort durch. "
            "Das entscheidet die Aufloesung beim Erzeugen bzw. das "
            "Dezimieren vor diesem Schritt." % (gesamt - BUDGET_GESAMT),
        )
    for name, grenze in (("Kopf", BUDGET_KOPF), ("Rumpf", BUDGET_RUMPF),
                         ("Arm links", BUDGET_ARM), ("Arm rechts", BUDGET_ARM),
                         ("Bein links", BUDGET_BEIN),
                         ("Bein rechts", BUDGET_BEIN)):
        if zahl[name] > grenze:
            ber.an_prompt(
                "Doku 4",
                "%s: %d Dreiecke, erlaubt sind %d."
                % (name, zahl[name], grenze),
            )
    return zahl


# --------------------------------------------------------------------
# Huelle: wasserdicht, Wicklung, lose Teile
# --------------------------------------------------------------------

def huelle_pruefen(objs, kopf, vz, ber, fuellen, nur_messen):
    """Doku 9: wasserdicht ueberall ausser an Augen und Mund.

    Gezaehlt werden Randkanten (Kante mit nur einer Flaeche - ein Loch)
    und nicht-mannigfaltige Kanten (mehr als zwei Flaechen). Dazu das
    Vorzeichen des Volumens: Ist es negativ, zeigen die Normalen nach
    innen, und Roblox sieht ueberall Rueckseiten - der zweite Teil von
    Doku 9 ("no back faces are exposed").
    """
    gefuellt = 0
    for obj in objs:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        doppelt = _verschweissen(bm)
        bm.edges.ensure_lookup_table()
        rand = [e for e in bm.edges if len(e.link_faces) == 1]
        wild = [e for e in bm.edges if len(e.link_faces) > 2]
        volumen = bm.calc_volume(signed=True)

        # Gemessen wird in Weltkoordinaten: Ein Netz mit noch nicht
        # eingefrorener Objektskalierung liegt lokal woanders als der
        # gemessene Kopf.
        mw = obj.matrix_world
        im_gesicht = 0
        if kopf is not None and obj.name == kopf.netz.name:
            im_gesicht = sum(
                1 for e in rand
                if _im_gesichtsfeld(
                    mw @ ((e.verts[0].co + e.verts[1].co) / 2.0), kopf, vz)
            )
        aussen = len(rand) - im_gesicht

        naht = (" %d Naht-Punkt(e) vorher verschweisst." % doppelt
                if doppelt else "")
        if rand or wild:
            ber.messung(
                "Doku 9",
                "%s: %d Randkante(n), davon %d an Augen oder Mund (dort "
                "erlaubt), %d nicht-mannigfaltige Kante(n).%s"
                % (obj.name, len(rand), im_gesicht, len(wild), naht),
            )
        else:
            ber.messung("Doku 9", "%s: wasserdicht.%s" % (obj.name, naht))

        if aussen > 0 and fuellen and not nur_messen:
            zu = [e for e in rand
                  if kopf is None or obj.name != kopf.netz.name
                  or not _im_gesichtsfeld(
                      mw @ ((e.verts[0].co + e.verts[1].co) / 2.0),
                      kopf, vz)]
            ergebnis = bmesh.ops.holes_fill(bm, edges=zu, sides=0)
            neu = len(ergebnis.get("faces", []))
            if neu:
                # Zurueckgeschrieben wird das **verschweisste** Netz -
                # ein Deckel auf einer offenen Naht waere keiner.
                bm.to_mesh(obj.data)
                obj.data.update()
                gefuellt += neu
        elif aussen > 0:
            ber.an_prompt(
                "Doku 9",
                "%s: %d Randkante(n) ausserhalb von Augen und Mund. Das "
                "sind Loecher im Netz - Doku 9 verlangt 'watertight in "
                "all regions with the exception of the eyes and mouth'. "
                "Mit --loecher-fuellen versucht das Skript sie zu "
                "schliessen; ein grosses Loch bedeutet aber fehlende "
                "Geometrie, und die kann kein Deckel ersetzen."
                % (obj.name, aussen),
            )

        if volumen < 0 and not rand and not wild:
            if nur_messen:
                ber.messung(
                    "Doku 9",
                    "%s: Das Volumen ist negativ - die Flaechen zeigen "
                    "nach innen. Nur-messen-Lauf: nicht gedreht." % obj.name,
                )
            else:
                bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
                bm.to_mesh(obj.data)
                obj.data.update()
                ber.aenderung(
                    "Doku 9",
                    "%s: Wicklung umgedreht - das Volumen war negativ, "
                    "also zeigten alle Flaechen nach innen. Roblox saehe "
                    "ueberall Rueckseiten." % obj.name,
                )
        elif volumen < 0:
            ber.messung(
                "Doku 9",
                "%s: negatives Volumen bei offenem Netz - erst die "
                "Loecher, dann die Wicklung." % obj.name,
            )
        bm.free()
    if gefuellt:
        ber.aenderung(
            "Doku 9",
            "%d Flaeche(n) eingezogen, um Loecher ausserhalb von Augen "
            "und Mund zu schliessen." % gefuellt,
        )


def _verschweissen(bm, abstand=1e-5):
    """Punkte an derselben Stelle zusammenlegen. Rueckgabe: wie viele.

    Ohne diesen Schritt zaehlt jede UV-Naht als Loch: glTF speichert
    Normalen und UVs je Punkt, deshalb zerfaellt beim Import jeder
    harte Rand in getrennte Punkte, und ein tadelloser Wuerfel kommt
    mit 24 statt 8 Punkten und lauter offenen Kanten herein. Eine Naht
    ist kein Loch - gemessen wird die Flaeche, nicht die Punktliste
    (so macht es auch mesh_check.dart in dieser App).
    """
    vorher = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=abstand)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    bm.verts.index_update()
    bm.faces.index_update()
    return vorher - len(bm.verts)


def _im_gesichtsfeld(p, kopf, vz):
    """Ob ein Punkt im Bereich von Augenhoehlen oder Mundhoehle liegt."""
    if p.z < kopf.unten:
        return False
    if front_wert(vz, p.y) < kopf.front - kopf.b * 0.5:
        return False
    r = HOEHLE_RADIUS * kopf.b * (1 + LID_BREITE)
    for ex in (kopf.mitte_x - kopf.auge_x, kopf.mitte_x + kopf.auge_x):
        if (p.x - ex) ** 2 + (p.z - kopf.auge_z) ** 2 <= r * r:
            return True
    a = MUND_HALBBREITE * kopf.b * (1 + LIPPE_BREITE)
    c = MUND_HALBHOEHE * kopf.h * (1 + LIPPE_BREITE)
    return ((p.x - kopf.mitte_x) / a) ** 2 + ((p.z - kopf.mund_z) / c) ** 2 <= 1


def lose_teile_melden(objs, kopf, ber):
    """Doku 10 und die 'Non-contiguous mesh' aus den Gegenbeispielen.

    Ob ein Buschel Geometrie Haare, ein Hut oder eine Schulter ist,
    sagt kein Netz. Was sich messen laesst: wie viele zusammenhaengende
    Stuecke der Koerper hat und wie gross sie sind. Auto Setup erwartet
    ein durchgaengiges Koerpernetz; alles, was daneben schwebt, ist ein
    Verdachtsfall.
    """
    verdacht = ("hair", "haar", "brow", "braue", "beard", "bart", "lash",
                "wimper", "hat", "hut", "glasses", "brille", "cloth",
                "shirt", "hose", "pants", "schuh", "shoe")
    for obj in objs:
        kurz = obj.name.lower()
        if any(w in kurz for w in verdacht):
            ber.an_prompt(
                "Doku 10",
                "Das Netz '%s' traegt einen Namen, der nach Accessoire "
                "klingt. Doku 10 verbietet Haare, Augenbrauen, Baerte "
                "und Wimpern im Koerpernetz; die Marktplatz-Doku sagt "
                "dasselbe fuer Kleidung ('Avatar bodies cannot include "
                "any accessories or clothing')." % obj.name,
            )
    gesamt = []
    for obj in objs:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        _verschweissen(bm)
        mw = obj.matrix_world
        gesehen = set()
        for f in bm.faces:
            if f.index in gesehen:
                continue
            stapel = [f]
            gesehen.add(f.index)
            stueck = []
            while stapel:
                akt = stapel.pop()
                stueck.append(akt)
                for e in akt.edges:
                    for nachbar in e.link_faces:
                        if nachbar.index not in gesehen:
                            gesehen.add(nachbar.index)
                            stapel.append(nachbar)
            zs = [(mw @ v.co).z for fl in stueck for v in fl.verts]
            gesamt.append((obj.name, len(stueck), min(zs), max(zs)))
        bm.free()
    if len(gesamt) <= 1:
        ber.messung(
            "Doku 10",
            "Das Koerpernetz haengt in einem Stueck zusammen - keine "
            "abgesetzten Teile, die nach Accessoire aussehen.",
        )
        return
    gesamt.sort(key=lambda e: -e[1])
    # Ein abgesetztes Stueck **im Kopfband** ist eher ein modellierter
    # Augapfel oder eine Zahnreihe - Doku 3 verlangt sogar, dass die
    # keinen Punkt mit dem Kopf teilen. Ausserhalb des Kopfes ist ein
    # abgesetztes Stueck der Verdachtsfall.
    def im_kopf(u, o):
        return kopf is not None and u >= kopf.unten
    im_gesicht = [e for e in gesamt[1:] if im_kopf(e[2], e[3])]
    daneben = [e for e in gesamt[1:] if not im_kopf(e[2], e[3])]
    ber.messung(
        "Doku 10",
        "Der Koerper besteht aus %d zusammenhaengenden Stuecken. "
        "Groesstes: %d Flaechen. Weitere: %s."
        % (len(gesamt), gesamt[0][1],
           ", ".join("%d Flaechen bei %s bis %s Studs Hoehe"
                     % (n, _zahl(u), _zahl(o))
                     for _, n, u, o in gesamt[1:6])),
    )
    if im_gesicht:
        ber.messung(
            "Doku 3",
            "%d davon liegen im Kopfband - das sind vermutlich "
            "modellierte Augaepfel oder Zahnreihen. Doku 3 verlangt "
            "genau das: 'Eyeballs, teeth, and tongue must be part of "
            "the model without sharing vertices with the body mesh.' "
            "Ob Auto Setup sie als solche erkennt, entscheidet es "
            "selbst; die fuenf Netze mit den erwarteten Namen legt "
            "dieses Skript zusaetzlich an." % len(im_gesicht),
        )
    if daneben:
        ber.an_prompt(
            "Doku 10",
            "%d Stueck(e) haengen ausserhalb des Kopfes nicht am "
            "Koerper. Auto Setup erwartet ein durchgaengiges Netz "
            "(Gegenbeispiel 'Non-contiguous mesh'), und Doku 10 "
            "verbietet Haare, Brauen, Baerte und Wimpern im Koerper. Ob "
            "es welche sind, sagt die Geometrie nicht - im Viewer "
            "nachsehen." % len(daneben),
        )


def textur_melden(ber):
    """Doku 12: mindestens eine Textur muss dabei sein."""
    bilder = [i for i in bpy.data.images if i.name != "Render Result"
              and (i.has_data or i.packed_file or i.filepath)]
    if bilder:
        ber.messung(
            "Doku 12",
            "%d Textur(en) in der Datei: %s."
            % (len(bilder), ", ".join(i.name for i in bilder[:4])),
        )
    else:
        ber.an_prompt(
            "Doku 12",
            "Keine Textur in der Datei. Doku 12: 'Models should include "
            "one or more texture maps.' Das entsteht beim Erzeugen, "
            "nicht hier.",
        )


# --------------------------------------------------------------------
# Kopf messen
# --------------------------------------------------------------------

class Kopf:
    def __init__(self, netz, b, h, unten, mitte_x, front, bvh,
                 hals_hoehe=None):
        self.netz = netz          # das Netz, in dem der Kopf steckt
        self.b = b                # Kopfbreite B
        self.h = h                # Kopfhoehe H (oberstes Fuenftel)
        self.unten = unten        # Unterkante des Kopfbands
        self.mitte_x = mitte_x
        self.front = front        # Gesichtsflaeche auf Augenhoehe
        self.bvh = bvh            # nur die Kopfdreiecke
        self.auge_z = unten + h * AUGE_HOEHE
        self.auge_x = b * AUGE_ABSTAND
        self.mund_z = unten + h * MUND_MITTE
        self.zahn_oben_z = unten + h * ZAHN_OBEN
        self.hals_hoehe = hals_hoehe


def messe_kopf(tris, vz, netze, ber, hals_hoehe=None, melden=True):
    """B, H und die Gesichtsflaeche - Masse wie in roblox_face_parts.dart.

    **Abweichung von der App, mit Grund.** Dort ist das Kopfband fest
    das oberste Fuenftel der Figur (KOPF_ANTEIL), und der Kommentar
    dort nennt das selbst grosszuegig. An einer A-Pose-Figur liegen in
    diesem Fuenftel auch Schultern und Oberarme: Gemessen wurden am
    Kastenmenschen B = 1,19 statt der 0,82, die der Kopf breit ist -
    daraus werden zu grosse, zu weit aussen sitzende Augen. Wo eine
    Halsstelle gefunden wurde, gilt deshalb sie als Unterkante des
    Kopfes; das oberste Fuenftel bleibt der Rueckfall. Beide Zahlen
    stehen im Bericht.
    """
    mn, mx = huelle(tris)
    hoehe = mx[2] - mn[2]
    fuenftel = mx[2] - hoehe * KOPF_ANTEIL
    unten = fuenftel if hals_hoehe is None else max(hals_hoehe, mn[2])
    kopf_tris = [t for t in tris if max(p[2] for p in t) >= unten]
    if not kopf_tris:
        ber.problem("Im obersten Fuenftel liegt keine Geometrie.")
        return None
    xs = [p[0] for t in kopf_tris for p in t if p[2] >= unten]
    if not xs:
        ber.problem("Im Kopfband liegen keine Punkte.")
        return None
    b = max(xs) - min(xs)
    h = mx[2] - unten
    mitte_x = (max(xs) + min(xs)) / 2

    # Das Netz, in dem der Kopf steckt: das mit dem hoechsten Punkt.
    kopfnetz = max(
        netze,
        key=lambda o: max(
            [(o.matrix_world @ v.co).z for v in o.data.vertices] or [-1e9]),
    )
    bvh = bvh_von(kopf_tris)
    start = abs(mn[1]) + abs(mx[1]) + 1.0
    auge_z = unten + h * AUGE_HOEHE
    front = strahl_vorn(bvh, vz, mitte_x, auge_z, start)
    if front is None:
        front = max(front_wert(vz, p[1]) for t in kopf_tris for p in t)
        ber.messung(
            "Doku 2",
            "Der Strahl auf die Kopfmitte traf keine Flaeche; als "
            "Gesichtsflaeche gilt die vorderste Kante des Kopfbands. Bei "
            "einer Kapuze sitzen die Teile dann zu weit vorn.",
        )
    if melden:
        ber.messung(
            "Projekt",
            "Kopf gemessen: B = %s, H = %s Studs. Unterkante des "
            "Kopfbands: %s. Alle Gesichtsmasse sind Anteile von B und H "
            "(roblox_face_parts.dart)."
            % (_zahl(b), _zahl(h),
               ("der gemessene Hals bei %s Studs statt des obersten "
                "Fuenftels bei %s" % (_zahl(unten), _zahl(fuenftel)))
               if hals_hoehe is not None else
               ("das oberste Fuenftel bei %s - kein Hals gefunden"
                % _zahl(fuenftel))),
        )
    return Kopf(kopfnetz, b, h, unten, mitte_x, front, bvh, hals_hoehe)


def hoehlen_messen(kopf, vz, tris):
    """Tiefe der Augen- und Mundhoehle und das Relief.

    Tiefe = Rand minus Mitte, der Rand als niedrigster von acht
    Strahlen auf einem Ring bei 1,3 x Radius. Der **niedrigste**, weil
    bei einer Kapuze weiter aussen liegende Strahlen auf den
    Kapuzenrand treffen und dann jedes Gesicht nach Hoehle aussaehe.

    Das Relief misst etwas anderes: ob im Gesicht ueberhaupt Geometrie
    steckt, gleich in welche Richtung. Dafuer wird die Gesichtsflaeche
    ausserhalb von Augen und Mund abgetastet, eine Quadrik
    z = a + bx + cy + dx^2 + ey^2 hineingelegt und der Rest gemessen.
    Ein glatter Kugelkopf trifft die Quadrik fast genau; ein
    modellierter Augapfel steht davor, eine Hoehle liegt dahinter. Ohne
    diese zweite Messung haelt man einen fertigen Augapfel fuer "keine
    Hoehle da" und graebt hinein - genau so ist aus einem sauberen
    Gesicht schon einmal Matsch geworden.
    """
    mn, mx = huelle(tris)
    start = abs(mn[1]) + abs(mx[1]) + 1.0
    b, h = kopf.b, kopf.h
    r = HOEHLE_RADIUS * b
    a = MUND_HALBBREITE * b
    c = MUND_HALBHOEHE * h
    augen = (kopf.mitte_x - kopf.auge_x, kopf.mitte_x + kopf.auge_x)

    def im_auge(x, z):
        return any((x - ex) ** 2 + (z - kopf.auge_z) ** 2 < r * r
                   for ex in augen)

    def im_mund(x, z):
        return ((x - kopf.mitte_x) / a) ** 2 + ((z - kopf.mund_z) / c) ** 2 < 1

    def strahl(x, z):
        return strahl_vorn(kopf.bvh, vz, x, z, start)

    def tiefe(cx, cz, rx, rz, fremd):
        mitte = strahl(cx, cz)
        if mitte is None:
            return 0.0
        rand, treffer = float("inf"), 0
        for k in range(8):
            w = k * math.pi / 4
            x, z = cx + rx * math.cos(w), cz + rz * math.sin(w)
            if fremd(x, z):
                continue
            f = strahl(x, z)
            if f is None:
                continue
            treffer += 1
            rand = min(rand, f)
        if treffer < 5:
            return 0.0
        return rand - mitte

    ring = 1.3
    links = tiefe(augen[0], kopf.auge_z, r * ring, r * ring, im_mund)
    rechts = tiefe(augen[1], kopf.auge_z, r * ring, r * ring, im_mund)
    mund = tiefe(kopf.mitte_x, kopf.mund_z, a * ring, c * ring, im_auge)

    # Quadrik durch die Gesichtsflaeche ausserhalb der Merkmale.
    xs, zs, fs = [], [], []
    halb = b * 0.42
    for i in range(11):
        x = kopf.mitte_x - halb + 2 * halb * i / 10
        for k in range(11):
            z = kopf.unten + h * (0.15 + (0.92 - 0.15) * k / 10)
            if im_auge(x, z) or im_mund(x, z):
                continue
            f = strahl(x, z)
            if f is None:
                continue
            xs.append(x - kopf.mitte_x)
            zs.append(z - kopf.auge_z)
            fs.append(f)
    auge_relief = mund_relief = 0.0
    if len(xs) >= 12:
        xa = np.array(xs)
        za = np.array(zs)
        A = np.column_stack([np.ones_like(xa), xa, za, xa * xa, za * za])
        try:
            koef, *_ = np.linalg.lstsq(A, np.array(fs), rcond=None)

            def flaeche(x, z):
                dx, dz = x - kopf.mitte_x, z - kopf.auge_z
                return float(koef @ np.array([1.0, dx, dz, dx * dx, dz * dz]))

            def rest(x, z):
                f = strahl(x, z)
                return 0.0 if f is None else f - flaeche(x, z)

            r1 = rest(augen[0], kopf.auge_z)
            r2 = rest(augen[1], kopf.auge_z)
            auge_relief = r1 if abs(r1) > abs(r2) else r2
            mund_relief = rest(kopf.mitte_x, kopf.mund_z)
        except np.linalg.LinAlgError:
            pass
    return {
        "auge_links": links,
        "auge_rechts": rechts,
        "mund": mund,
        "auge_relief": auge_relief,
        "mund_relief": mund_relief,
        "schwelle": b * HOEHLE_SCHWELLE,
    }


def hat_hoehlen(m):
    s = m["schwelle"]
    return m["auge_links"] >= s and m["auge_rechts"] >= s and m["mund"] >= s


def hat_relief(m):
    s = m["schwelle"]
    return abs(m["auge_relief"]) >= s or abs(m["mund_relief"]) >= s


# --------------------------------------------------------------------
# Hoehlen bauen
# --------------------------------------------------------------------

def _glatt(d):
    return d * d * (3 - 2 * d)


def _feld(d, tiefe, grat, breite):
    """Wie weit ein Punkt im Abstand d (1 = Rand) nach hinten wandert.

    Innerhalb der Hoehle nach hinten, im Ring darum als Grat nach vorn.
    Uebernommen aus _verschiebe in roblox_face_sculpt.dart.
    """
    if d < 1:
        return -tiefe * (1 - _glatt(d))
    if d < 1 + breite:
        return grat * math.sin(math.pi * (d - 1) / breite)
    return 0.0


def hoehlen_bauen(kopf, vz, ber):
    """Augenhoehlen und Mundhoehle ins Kopfnetz schieben.

    Zwei Schritte, beide rein geometrisch:

    1. Verfeinern, wo es noetig ist. Ein Kopf mit 1.500 Dreiecken hat
       um das Auge herum vielleicht acht; daraus wird keine Hoehle mit
       Rand. Geteilt wird nur, was groeber ist als die Zielkante, und
       nur im Gesichtsbereich.
    2. Verschieben - **nur entlang der Tiefenachse**. Die Verschiebung
       haengt allein von x und z ab, deshalb bewegen sich doppelte
       Punkte an UV-Naehten gleich weit und die Huelle bleibt
       geschlossen. Entlang der Normalen saehe eine Naht anders aus als
       ihr Gegenstueck, und genau dort risse die Huelle auf.

    Ein Lidgrat ist dabei kein Ueberhang. Ein echtes Oberlid haengt
    ueber den Augapfel; das laesst sich durch Verschieben vorhandener
    Punkte nicht bauen. Mehr geht ohne neue Topologie nicht.
    """
    obj = kopf.netz
    if not _ist_einheit(obj.matrix_world):
        ber.problem(
            "%s traegt noch eine Objekt-Transformation - die Hoehlen "
            "wuerden verrutschen. Nicht angefasst." % obj.name)
        return
    b, h = kopf.b, kopf.h
    ziel = ZIEL_KANTE * b

    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def im_gesicht(p):
        if p.z < kopf.unten:
            return False
        if front_wert(vz, p.y) < kopf.front - b * 0.5:
            return False
        r = HOEHLE_RADIUS * b * (1 + LID_BREITE)
        for ex in (kopf.mitte_x - kopf.auge_x, kopf.mitte_x + kopf.auge_x):
            if (p.x - ex) ** 2 + (p.z - kopf.auge_z) ** 2 <= r * r:
                return True
        a = MUND_HALBBREITE * b * (1 + LIPPE_BREITE)
        c = MUND_HALBHOEHE * h * (1 + LIPPE_BREITE)
        return (((p.x - kopf.mitte_x) / a) ** 2
                + ((p.z - kopf.mund_z) / c) ** 2) <= 1

    def im_gesicht_weit(p):
        """Derselbe Bereich, grosszuegiger - fuer das Verschweissen."""
        if p.z < kopf.unten - h * 0.1:
            return False
        if front_wert(vz, p.y) < kopf.front - b * 0.6:
            return False
        r = HOEHLE_RADIUS * b * (1 + LID_BREITE) * 1.5
        for ex in (kopf.mitte_x - kopf.auge_x, kopf.mitte_x + kopf.auge_x):
            if (p.x - ex) ** 2 + (p.z - kopf.auge_z) ** 2 <= r * r:
                return True
        a = MUND_HALBBREITE * b * (1 + LIPPE_BREITE) * 1.5
        c = MUND_HALBHOEHE * h * (1 + LIPPE_BREITE) * 1.5
        return (((p.x - kopf.mitte_x) / a) ** 2
                + ((p.z - kopf.mund_z) / c) ** 2) <= 1

    def dreieckszahl():
        return sum(len(f.verts) - 2 for f in bm.faces)

    # Im Gesichtsbereich die Naehte schliessen, **bevor** geteilt wird.
    # glTF speichert Normalen und UVs je Punkt, deshalb liegen an jeder
    # harten Kante zwei Punkte uebereinander und die Nachbarflaechen
    # haengen dort nicht zusammen. Wird dann nur eine Seite geteilt,
    # bleibt auf der anderen ein T-Stoss - und der reisst die Huelle
    # auf. Am Kastenmenschen waren das 111 offene Kanten in einem
    # vorher wasserdichten Netz. Verschweisst wird nur im Gesicht;
    # der Rest des Koerpers bleibt, wie er ist.
    kandidaten = [v for v in bm.verts if im_gesicht_weit(v.co)]
    verschweisst = 0
    if kandidaten:
        vor = len(bm.verts)
        bmesh.ops.remove_doubles(bm, verts=kandidaten, dist=1e-5)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        verschweisst = vor - len(bm.verts)

    vorher = dreieckszahl()
    durchgaenge = 0
    laengste = 0.0
    for _ in range(MAX_DURCHGAENGE):
        flaechen = [f for f in bm.faces if im_gesicht(f.calc_center_median())]
        if not flaechen:
            break
        kanten = {e for f in flaechen for e in f.edges}
        zu_lang = [e for e in kanten if e.calc_length() > ziel]
        laengste = max([e.calc_length() for e in kanten] or [0.0])
        if not zu_lang:
            break
        # Eine geteilte Kante bringt ungefaehr ein Dreieck dazu. Passt
        # nicht alles ins Budget, kommen die groebsten zuerst - ein
        # halber Durchgang mit den groessten Dreiecken bringt mehr als
        # gar keiner.
        platz = MAX_ZUSATZ_DREIECKE - (dreieckszahl() - vorher)
        if platz <= 0:
            ber.messung(
                "Doku 4",
                "Verfeinerung nach %d Durchgang/Durchgaengen beendet: Das "
                "Budget von %d zusaetzlichen Dreiecken ist ausgeschoepft "
                "(faceSculptTriangleBudget). Laengste Kante im Gesicht "
                "noch %s bei Ziel %s."
                % (durchgaenge, MAX_ZUSATZ_DREIECKE, _zahl(laengste, 3),
                   _zahl(ziel, 3)),
            )
            break
        if len(zu_lang) > platz:
            zu_lang.sort(key=lambda e: -e.calc_length())
            zu_lang = zu_lang[:platz]
        bmesh.ops.subdivide_edges(bm, edges=zu_lang, cuts=1,
                                  use_grid_fill=True)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        durchgaenge += 1

    r = HOEHLE_RADIUS * b
    tiefe_auge = HOEHLE_TIEFE * b
    grat_auge = LID_HOEHE * b
    a = MUND_HALBBREITE * b
    c = MUND_HALBHOEHE * h
    tiefe_mund = MUND_TIEFE * b
    grat_mund = LIPPE_HOEHE * b
    bewegt = 0
    for v in bm.verts:
        p = v.co
        if not im_gesicht(p):
            continue
        d = 0.0
        for ex in (kopf.mitte_x - kopf.auge_x, kopf.mitte_x + kopf.auge_x):
            abstand = math.hypot(p.x - ex, p.z - kopf.auge_z)
            d += _feld(abstand / r, tiefe_auge, grat_auge, LID_BREITE)
        mx_ = (p.x - kopf.mitte_x) / a
        mz = (p.z - kopf.mund_z) / c
        d += _feld(math.hypot(mx_, mz), tiefe_mund, grat_mund, LIPPE_BREITE)
        if d:
            v.co.y += vz * d
            bewegt += 1

    nachher = dreieckszahl()
    bm.to_mesh(obj.data)
    obj.data.update()
    bm.free()
    ber.aenderung(
        "Doku 2",
        "Augenhoehlen und Mundhoehle in %s gebaut: %d Naht-Punkt(e) im "
        "Gesicht verschweisst, %d Durchgang/Durchgaenge Verfeinerung "
        "(%d auf %d Dreiecke), %d Punkte verschoben. Masse aus "
        "roblox_face_sculpt.dart: Hoehlenradius %s x B, Tiefe %s x B, "
        "Mundhalbachsen %s x B und %s x H."
        % (obj.name, verschweisst, durchgaenge, vorher, nachher, bewegt,
           _zahl(HOEHLE_RADIUS, 2), _zahl(HOEHLE_TIEFE, 2),
           _zahl(MUND_HALBBREITE, 2), _zahl(MUND_HALBHOEHE, 3)),
    )


# --------------------------------------------------------------------
# Die fuenf Kopfteile
# --------------------------------------------------------------------

def _neues_netz(name, bm, verschiebung, skalierung):
    # Ein verwaister Netzblock gleichen Namens muss weg, sonst haengt
    # Blender ".001" an - und Auto Setup erkennt die Kopfteile an
    # genau diesen Namen.
    alt = bpy.data.meshes.get(name)
    if alt is not None and alt.users == 0:
        bpy.data.meshes.remove(alt)
    me = bpy.data.meshes.new(name)
    bmesh.ops.scale(bm, vec=Vector(skalierung), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(verschiebung), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    me.calc_loop_triangles()
    return obj, len(me.loop_triangles)


def kugel(name, mitte, radien, laengen=10, ringe=5):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=laengen, v_segments=ringe,
                              radius=1.0)
    # Glatt schattiert, wie die Augen der App: Bei flacher
    # Schattierung schreibt der glTF-Export je Dreieck eigene Punkte,
    # aus 42 Punkten werden 180. Die Dreiecke bleiben gleich - Roblox
    # zaehlt die -, aber die Datei waechst und die Kugel sieht
    # kantig aus. Die Zahnreihen bleiben flach; ein Quader soll
    # Kanten haben.
    for f in bm.faces:
        f.smooth = True
    return _neues_netz(name, bm, mitte, radien)


def quader(name, mitte, masse):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    return _neues_netz(name, bm, mitte, masse)


def kopfteile_bauen(kopf, vz, fehlende, ber):
    """Legt die fehlenden der fuenf Kopfteile an.

    Alle Masse sind Anteile von B und H, uebernommen aus
    FaceProportions in roblox_face_parts.dart.

    Zwei Abweichungen von der Doku, beide mit Grund:

    * Doku 2 sagt "half-sphere eyes". Gebaut wird eine **ganze** Kugel:
      Eine Halbkugel haette einen offenen Rand, und Doku 9 verlangt
      wasserdichte Netze. Die hintere Haelfte steckt in der Hoehle und
      ist nie zu sehen.
    * Doku 2 nennt fuer die Unterzaehne keine Hoehe; die App nennt
      33 % von H. Bei 36 % und 33 % mit je 3 % Hoehe stossen die
      Zahnreihen aneinander. Der geforderte Abstand von 1 % x H geht
      vor, die Unterzaehne rutschen auf 32 % - zwei Netze, die sich
      beruehren, sind die Sorte Geometrie, an der der Validator
      haengen bleibt.
    """
    b, h = kopf.b, kopf.h
    mn_start = kopf.front + b  # weit genug vor dem Gesicht
    gebaut = []

    auge_r = b * AUGE_RADIUS
    for name, x in (("LeftEye", kopf.mitte_x - kopf.auge_x),
                    ("RightEye", kopf.mitte_x + kopf.auge_x)):
        if name not in fehlende:
            continue
        # Je Auge ein eigener Strahl: Auf einem gewoelbten Gesicht liegt
        # das Augenzentrum weiter hinten als die Mitte, und ein Auge auf
        # der Tiefe der Mitte versaenke halb im Kopf. In einer Hoehle
        # trifft der Strahl deren Boden - dort gehoert der Augapfel hin.
        treffer = strahl_vorn(kopf.bvh, vz, x, kopf.auge_z, mn_start)
        if treffer is None:
            treffer = kopf.front
            ber.messung(
                "Doku 2",
                "%s: Der Strahl auf das Augenzentrum traf keine Flaeche - "
                "gesetzt wird nach der Gesichtsmitte. Im Viewer "
                "nachsehen." % name,
            )
        f = treffer - auge_r * AUGE_VERSATZ
        _, tris = kugel(name, (x, vz * f, kopf.auge_z),
                        (auge_r, auge_r, auge_r))
        gebaut.append((name, tris))

    zahn_b = b * ZAHN_BREITE
    zahn_h = h * ZAHN_HOEHE
    zahn_t = b * ZAHN_TIEFE
    mund_front = strahl_vorn(kopf.bvh, vz, kopf.mitte_x, kopf.zahn_oben_z,
                             mn_start)
    if mund_front is None:
        mund_front = kopf.front
    # Beide Zahnreihen teilen sich **einen** Strahl: Zwei Strahlen auf
    # einem schraegen Gesicht ergaeben zwei Tiefen, und die Reihen
    # stuenden versetzt.
    zahn_f = mund_front - zahn_t / 2
    oben_z = kopf.zahn_oben_z
    unten_z = min(kopf.unten + h * ZAHN_UNTEN,
                  oben_z - zahn_h - h * ZAHN_ABSTAND)
    if "UpperTeeth" in fehlende:
        _, tris = quader("UpperTeeth", (kopf.mitte_x, vz * zahn_f, oben_z),
                         (zahn_b, zahn_t, zahn_h))
        gebaut.append(("UpperTeeth", tris))
    if "LowerTeeth" in fehlende:
        _, tris = quader("LowerTeeth", (kopf.mitte_x, vz * zahn_f, unten_z),
                         (zahn_b, zahn_t, zahn_h))
        gebaut.append(("LowerTeeth", tris))
    if "Tongue" in fehlende:
        zunge_f = (zahn_f - zahn_t / 2 - b * ZUNGE_RUECKVERSATZ
                   - b * ZUNGE_TIEFE / 2)
        zunge_z = (oben_z + unten_z) / 2
        _, tris = kugel(
            "Tongue", (kopf.mitte_x, vz * zunge_f, zunge_z),
            (b * ZUNGE_BREITE / 2, b * ZUNGE_TIEFE / 2, h * ZUNGE_HOEHE / 2),
            laengen=6, ringe=4)
        gebaut.append(("Tongue", tris))

    if gebaut:
        ber.aenderung(
            "Doku 2",
            "Angelegt: %s. Zusammen %d Dreiecke, sie zaehlen zum "
            "Kopfbudget von %d."
            % (", ".join("%s (%d Dreiecke)" % g for g in gebaut),
               sum(g[1] for g in gebaut), BUDGET_KOPF),
        )
        ber.aenderung(
            "Doku 3",
            "Jedes Teil ist ein eigenes Netz und teilt keinen Punkt mit "
            "dem Kopf - genau daran trennt Auto Setup sie vom Rest.",
        )
        if abs(kopf.unten + h * ZAHN_UNTEN - unten_z) > h * 1e-6:
            ber.aenderung(
                "Projekt",
                "Die Unterzaehne sitzen bei %s %% statt %s %% von H: Bei "
                "den genannten Hoehen stiessen die Zahnreihen aneinander, "
                "und der Abstand von %s %% x H geht vor."
                % ("%.0f" % ((unten_z - kopf.unten) / h * 100),
                   "%.0f" % (ZAHN_UNTEN * 100),
                   "%.0f" % (ZAHN_ABSTAND * 100)),
            )
    return sum(g[1] for g in gebaut)


# --------------------------------------------------------------------
# Gesicht: messen, entscheiden, bauen
# --------------------------------------------------------------------

def gesicht_bearbeiten(kopf, vz, tris, ber, nur_messen, teile_neu):
    """Hoehlen und Kopfteile - in dieser Reihenfolge.

    Erst die Hoehlen, dann die Teile: Die Teile suchen die
    Gesichtsflaeche per Strahl von vorn und treffen nach dem Eingriff
    den Hoehlenboden; das Auge sitzt dann in der Hoehle, hinter dem
    Grat. Umgekehrt wuerde die Verfeinerung die Teile mit dem Kopf zu
    einem Netz verschmelzen, und Auto Setup erkennt sie gerade an ihrer
    Eigenstaendigkeit (Doku 3).
    """
    da = kopfteile_vorhanden()
    fehlende = [n for n in KOPFTEILE if n not in da]
    if da:
        ber.messung(
            "Doku 2",
            "Schon in der Datei: %s." % ", ".join(sorted(da)),
        )

    m = hoehlen_messen(kopf, vz, tris)
    ber.messung(
        "Doku 2",
        "Gesicht gemessen: Augenhoehlen links %s, rechts %s, Mundhoehle "
        "%s Studs tief (ab %s gilt es als Hoehle). Relief gegen die "
        "angepasste Gesichtsflaeche: Auge %s, Mund %s."
        % (_zahl(m["auge_links"], 3), _zahl(m["auge_rechts"], 3),
           _zahl(m["mund"], 3), _zahl(m["schwelle"], 3),
           _zahl(m["auge_relief"], 3), _zahl(m["mund_relief"], 3)),
    )

    if hat_hoehlen(m):
        ber.messung(
            "Doku 2",
            "Augenhoehlen und Mundhoehle sind da - nichts veraendert. "
            "Doku 2 verlangt 'connected eyebags' und einen 'connected "
            "mouthbag'.",
        )
    elif hat_relief(m):
        # Ein modellierter Augapfel steht **vor** der Flaeche und ergibt
        # eine negative Tiefe. Wer das als "keine Hoehle da" liest,
        # graebt in ein fertiges Gesicht hinein - bei jedem Aufruf
        # erneut, weil das Ergebnis wieder keine Hoehle ist. Genau so
        # ist aus einem sauberen Gesicht schon einmal Matsch geworden.
        if m["auge_relief"] < 0 and m["mund_relief"] < 0:
            # Vertiefungen sind da, nur flacher, als der Ringtest sie
            # sehen kann - auf einem runden Kopf liegt der Ring schon
            # durch die Woelbung hinter der Mitte. Ein zweiter Eingriff
            # wuerde die vorhandene Hoehle einfach noch einmal
            # eingraben.
            ber.messung(
                "Doku 2",
                "Augen und Mund liegen bereits hinter der "
                "Gesichtsflaeche (Relief Auge %s, Mund %s Studs) - "
                "nichts angefasst. Der Ringtest zaehlt das auf einem "
                "runden Kopf nicht als Hoehle; nachgegraben wird "
                "trotzdem nicht, das ergaebe die doppelte Tiefe."
                % (_zahl(m["auge_relief"], 3), _zahl(m["mund_relief"], 3)),
            )
        else:
            ber.messung(
                "Doku 2",
                "Im Gesicht steckt schon Geometrie (Relief Auge %s, Mund "
                "%s Studs) - nichts angefasst. Es sind aber keine "
                "Hoehlen: %sHineinzugraben macht daraus Matsch. Das "
                "gehoert ins Motiv ('two eye sockets each holding a "
                "half-sphere eye', Negativ 'bulging eyes')."
                % (_zahl(m["auge_relief"], 3), _zahl(m["mund_relief"], 3),
                   "Die Augen stehen als Kugeln vor der Flaeche. "
                   if m["auge_relief"] > 0 else ""),
            )
            ber.an_prompt(
                "Doku 2",
                "Ohne Augenhoehlen und Mundhoehle findet Auto Setup "
                "nichts zum Bewegen; die FACS-Posen brauchen eine "
                "Vertiefung hinter Lidern und Lippen.",
            )
    elif da and not teile_neu:
        ber.messung(
            "Doku 2",
            "Keine Hoehlen im Kopfnetz, aber die Kopfteile stehen schon "
            "in der Datei (%s). Nicht gegraben: Die Verfeinerung wuerde "
            "die Teile mit dem Kopf verschmelzen, und die Kugeln stuenden "
            "danach vor der Hoehle statt darin. Mit --teile-neu loescht "
            "das Skript sie, baut die Hoehlen und setzt sie danach neu."
            % ", ".join(sorted(da)),
        )
    elif da and nur_messen:
        ber.messung(
            "Doku 2",
            "Keine Hoehlen im Kopfnetz. Nur-messen-Lauf: nichts gebaut.",
        )
    elif nur_messen:
        ber.messung(
            "Doku 2",
            "Keine Hoehlen im Kopfnetz. Nur-messen-Lauf: nichts gebaut.",
        )
    else:
        if da:
            # Die Teile muessen weg, bevor verfeinert wird - sonst
            # verschmelzen sie mit dem Kopf. Gebaut werden sie
            # anschliessend neu, an derselben Stelle nach denselben
            # Anteilen; verloren geht dabei nichts, was nicht auch
            # wieder entsteht.
            for _, obj in sorted(da.items()):
                netz = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)
                # Der Netzblock muss mit weg: Bleibt er verwaist
                # liegen, heisst das neue Netz "LeftEye.001", und der
                # Name ist das Einzige, woran Auto Setup die Kopfteile
                # erkennt.
                if netz.users == 0:
                    bpy.data.meshes.remove(netz)
            ber.aenderung(
                "Doku 2",
                "%s geloescht (--teile-neu): Erst die Hoehlen, dann die "
                "Teile - die Verfeinerung haette sie sonst mit dem Kopf "
                "verschmolzen." % ", ".join(sorted(da)),
            )
            da = {}
            fehlende = list(KOPFTEILE)
        # Der Eingriff kostet Dreiecke, und die zaehlen zum Budget aus
        # Doku 4. Die App zieht den Betrag vorher ab - sie erzeugt und
        # dezimiert auf 10.742 minus 1.500 und fuellt danach auf. Wer
        # eine schon volle Figur hier hereingibt, kommt darueber.
        vorhanden = len(tris)
        if vorhanden + MAX_ZUSATZ_DREIECKE > BUDGET_GESAMT:
            ber.an_prompt(
                "Doku 4",
                "Die Figur hat schon %d Dreiecke; die Hoehlen duerfen bis "
                "zu %d hinzufuegen, und %d ist die Grenze. Vor diesem "
                "Schritt auf %d dezimieren - so macht es die App "
                "(faceSculptTriangleBudget in "
                "roblox_face_sculpt.dart)."
                % (vorhanden, MAX_ZUSATZ_DREIECKE, BUDGET_GESAMT,
                   BUDGET_GESAMT - MAX_ZUSATZ_DREIECKE),
            )
        hoehlen_bauen(kopf, vz, ber)
        neu = dreiecke(koerpernetze())
        kopf_neu = messe_kopf(neu, vz, koerpernetze(), ber, kopf.hals_hoehe,
                              melden=False)
        if kopf_neu is not None:
            n = hoehlen_messen(kopf_neu, vz, neu)
            ber.messung(
                "Doku 2",
                "Nach dem Eingriff: Ringtiefe Auge %s / %s, Mund %s "
                "(vorher %s / %s / %s); Relief Auge %s, Mund %s (vorher "
                "%s / %s)."
                % (_zahl(n["auge_links"], 3), _zahl(n["auge_rechts"], 3),
                   _zahl(n["mund"], 3), _zahl(m["auge_links"], 3),
                   _zahl(m["auge_rechts"], 3), _zahl(m["mund"], 3),
                   _zahl(n["auge_relief"], 3), _zahl(n["mund_relief"], 3),
                   _zahl(m["auge_relief"], 3), _zahl(m["mund_relief"], 3)),
            )
            # Auf einem runden Kopf ist die Ringtiefe auch mit Hoehle
            # negativ - der Ring liegt schon durch die Woelbung hinter
            # der Mitte. Ob der Eingriff gegriffen hat, sagt deshalb das
            # Relief gegen die angepasste Gesichtsflaeche: Es muss
            # negativ sein (Vertiefung) und tiefer als die Schwelle.
            tief_genug = (n["auge_relief"] <= -n["schwelle"]
                          and n["mund_relief"] <= -n["schwelle"])
            if tief_genug:
                ber.messung(
                    "Doku 2",
                    "Augen und Mund liegen jetzt hinter der "
                    "Gesichtsflaeche - das sind die 'eyebags' und der "
                    "'mouthbag' aus Doku 2.",
                )
            else:
                ber.messung(
                    "Doku 2",
                    "Die Vertiefungen sind flacher als %s Studs geblieben "
                    "- meist, weil das Netz im Gesicht zu grob ist und "
                    "das Budget von %d Dreiecken vorher aufgebraucht war. "
                    "Im Viewer nachsehen."
                    % (_zahl(n["schwelle"], 3), MAX_ZUSATZ_DREIECKE),
                )
            kopf = kopf_neu

    if not fehlende:
        ber.messung(
            "Doku 2",
            "Alle fuenf Kopfteile sind da - nichts angelegt.",
        )
        return kopf
    if nur_messen:
        ber.an_prompt(
            "Doku 2",
            "Es fehlen: %s. Doku 2 verlangt fuenf eigene Kopfteile: zwei "
            "Augen in Augenhoehlen sowie Oberzaehne, Unterzaehne und "
            "Zunge in einer Mundhoehle. Nur-messen-Lauf: nichts gebaut."
            % ", ".join(fehlende),
        )
        return kopf
    kopfteile_bauen(kopf, vz, fehlende, ber)
    if m["auge_relief"] >= m["schwelle"]:
        # Der Strahl trifft dann den modellierten Augapfel, nicht den
        # Hoehlenboden - die neue Kugel sitzt darauf. Das ist ein
        # zweites Auge auf dem ersten, und keine Zahl in diesem Skript
        # kann daraus eines machen.
        ber.an_prompt(
            "Doku 2",
            "Achtung: Am Augenzentrum steht die Flaeche %s Studs **vor** "
            "der Gesichtsflaeche - dort ist ein modellierter Augapfel, "
            "keine Hoehle. Die neu angelegte Kugel sitzt darauf. Fuer "
            "die FACS-Posen fehlt die Vertiefung; ins Motiv gehoert "
            "'two eye sockets each holding a half-sphere eye', ins "
            "Negativ 'bulging eyes'." % _zahl(m["auge_relief"], 3),
        )
    return kopf


# --------------------------------------------------------------------
# Hauptlauf
# --------------------------------------------------------------------

def main():
    ein, aus, nur_messen, fuellen, teile_neu = argumente()
    ber = Bericht()
    print("")
    print("Nachbearbeitung fuer Roblox Avatar Setup")
    print("Eingabe:", ein)
    print("Ausgabe:", aus if aus and not nur_messen else "(nur messen)")
    print("")

    if not laden(ein, ber):
        ber.drucken(ein, "")
        return
    transformationen_einfrieren(ber, nur_messen)
    if aufstellen(ber, nur_messen) is None:
        ber.drucken(ein, "")
        return

    koerper = koerpernetze()
    if not koerper:
        ber.problem("Ausser den Kopfteilen ist kein Netz in der Datei.")
        ber.drucken(ein, "")
        return
    ber.messung(
        "Doku 1",
        "%d Koerpernetz(e): %s. Doku 1 erlaubt eines oder mehrere; Auto "
        "Setup fuegt sie selbst zusammen."
        % (len(koerper), ", ".join(o.name for o in koerper)),
    )

    ohne_normalen = [
        o.name for o in koerper
        if len(o.data.polygons)
        and not o.data.has_custom_normals
        and not any(pl.use_smooth for pl in o.data.polygons)
    ]
    if ohne_normalen:
        # Ohne NORMAL-Spur schreibt glTF flache Schattierung vor, und
        # Blender exportiert dann je Dreieck eigene Punkte: aus 8.114
        # wurden an einer echten Figur 27.906. Die Dreieckszahl aendert
        # sich nicht, und nur die zaehlt Roblox - die Datei wird aber
        # dreimal so gross. Das passiert auch ohne dieses Skript, bei
        # jedem Weg durch Blender.
        ber.messung(
            "Projekt",
            "%s bringt keine Normalen mit (glTF ohne NORMAL-Spur). Beim "
            "Export schreibt Blender deshalb flache Schattierung und je "
            "Dreieck eigene Punkte; die Datei waechst, die Dreieckszahl "
            "bleibt. Wer das nicht will, gibt die Normalen schon beim "
            "Erzeugen mit." % ", ".join(ohne_normalen),
        )

    tris = dreiecke(koerper)
    vz, _ = blickrichtung(tris, ber)
    mn, mx = huelle(tris)
    sil = Silhouette(tris)
    zonen = Zonen(sil, (mn[0] + mx[0]) / 2)
    hals_melden(zonen, ber)
    pose_melden(sil, zonen, bvh_von(tris), vz, tris, ber)

    kopf = messe_kopf(tris, vz, koerper, ber, zonen.hals_hoehe)
    if kopf is not None:
        kopf = gesicht_bearbeiten(kopf, vz, tris, ber, nur_messen,
                                  teile_neu)

    # Nach den Eingriffen noch einmal alles zaehlen - der Bericht soll
    # das Ergebnis melden, nicht den Eingang.
    koerper = koerpernetze()
    teile = kopfteile_vorhanden()
    tris = dreiecke(koerper)
    for obj in teile.values():
        obj.data.calc_loop_triangles()
    kopfteil_zahl = sum(len(o.data.loop_triangles) for o in teile.values())
    sil = Silhouette(tris)
    mn, mx = huelle(tris)
    zonen = Zonen(sil, (mn[0] + mx[0]) / 2)
    budget_melden(sil, zonen, tris, ber, kopfteil_zahl)
    if len(teile) == len(KOPFTEILE):
        ber.messung(
            "Doku 2",
            "Fuenf Kopfteile in der Datei: %s."
            % ", ".join(sorted(teile)),
        )
    else:
        ber.an_prompt(
            "Doku 2",
            "Es stehen nur %d der fuenf Kopfteile in der Datei."
            % len(teile),
        )
    huelle_pruefen(koerper + list(teile.values()), kopf, vz, ber, fuellen,
                   nur_messen)
    lose_teile_melden(koerper, kopf, ber)
    textur_melden(ber)

    if not nur_messen and aus:
        bpy.ops.export_scene.gltf(
            filepath=aus,
            export_format="GLB",
            use_selection=False,
        )
        print("")
        print("Geschrieben:", aus, os.path.getsize(aus), "Bytes")
    ber.drucken(ein, aus if not nur_messen else "")


if __name__ == "__main__":
    main()
