/// Das Roblox-Paket: die Schritte, die zwischen einem geriggten
/// Modell und einer spielbaren Figur liegen.
///
/// Zwei davon kann diese App nicht selbst erledigen, und zwar aus
/// handfesten Gründen:
///
/// * **FBX schreiben.** Mesh- und Animationsimport läuft bei Roblox
///   über `.fbx`. Ein eigener FBX-Schreiber wäre ein großes Stück
///   Arbeit, das sich hier nicht gegen Roblox testen ließe – deshalb
///   erzeugt die App stattdessen ein Blender-Skript, das die
///   Umwandlung in einem Rutsch macht.
/// * **Die Figur einsetzen.** Ein Roblox-Platz verweist auf ein
///   hochgeladenes MeshPart (`rbxassetid://…`). Das Hochladen samt
///   Moderation passiert in Studio – von außen ginge das nur mit
///   Open-Cloud-Zugangsdaten. Die App erzeugt darum ein Luau-Skript,
///   das in Studio alles Weitere übernimmt: die drei bekannten
///   Korrekturen, eine Sicherung der bisherigen Startfigur und das
///   Einsetzen als StarterCharacter.
///
/// Beide Skripte sind reiner Text und werden neben dem Modell
/// abgelegt.
library;

/// Blender-Skript: GLB laden, Transformationen einfrieren, als FBX
/// ausgeben.
///
/// Aufruf ohne Fenster:
/// `blender --background --python roblox_fbx.py`
String blenderFbxScript({
  required String glbFile,
  required String fbxFile,
}) =>
    '''
# Wandelt die geriggte GLB in ein FBX um, wie es der Roblox-Importer
# erwartet. Die Knochennamen hat die App schon auf R15 gesetzt.
#
#   blender --background --python ${_pyName(glbFile)}_blender_fbx.py
#
# Ohne Blender-Installation: blender.org, kostenlos.

import bpy
import glob
import os
import sys

# Neben dem Skript suchen, nicht im Arbeitsverzeichnis: Blender
# startet je nach Aufruf woanders. Wurden die Dateien umbenannt, wird
# die einzige .glb daneben genommen - der haeufigste Stolperstein.
HERE = os.path.dirname(os.path.abspath(__file__))
GLB = os.path.join(HERE, r"$glbFile")
if not os.path.exists(GLB):
    neben = sorted(glob.glob(os.path.join(HERE, "*.glb")))
    if len(neben) == 1:
        GLB = neben[0]
        print("Umbenannt vorgefunden, nehme:", os.path.basename(GLB))
    else:
        sys.exit("Keine .glb neben dem Skript gefunden: " + GLB)
FBX = os.path.splitext(GLB)[0] + ".fbx"

# Leere Szene - sonst landet Blenders Standardwuerfel mit im Export.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

# Der glTF-Importer legt sich eine Hilfsform fuer die Knochen an und
# sammelt sie in der Sammlung "glTF_not_exported". Ohne diese Zeilen
# landet sie im FBX - und in Roblox steht eine kleine Kugel neben der
# Figur, die niemand dort haben will.
for sammlung in list(bpy.data.collections):
    if sammlung.name.startswith("glTF_not_exported"):
        for obj in list(sammlung.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(sammlung)

# Leere Knoten ohne Inhalt (Reste der Szenenstruktur) mit hinaus.
for obj in list(bpy.data.objects):
    if obj.type == "EMPTY" and not obj.children:
        bpy.data.objects.remove(obj, do_unlink=True)

# Alles auswaehlen und die Transformationen einfrieren: Der
# Roblox-Importer verlangt Scale 1,1,1 und Rotation 0,0,0 an jedem
# Knochen. Genau hier geht das sonst kaputt.
bpy.ops.object.select_all(action="SELECT")
for obj in bpy.context.selected_objects:
    bpy.context.view_layer.objects.active = obj
    if obj.type in {"MESH", "ARMATURE"}:
        bpy.ops.object.transform_apply(
            location=False, rotation=True, scale=True
        )

# Hoechstens vier Knochen je Vertex - mehr nimmt Roblox nicht.
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.vertex_group_limit_total(limit=4)
        bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    except RuntimeError:
        # Ohne Vertexgruppen (unskinniertes Prop) gibt es nichts zu tun.
        pass

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.fbx(
    filepath=FBX,
    use_selection=False,
    apply_unit_scale=True,
    global_scale=1.0,
    apply_scale_options="FBX_SCALE_ALL",
    object_types={"ARMATURE", "MESH"},
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",
    add_leaf_bones=False,          # sonst haengen leere Endknochen dran
    primary_bone_axis="Y",
    secondary_bone_axis="X",
    bake_anim=False,               # Animationen kommen aus dem Katalog
    path_mode="COPY",
    embed_textures=True,
)

print("Fertig:", FBX)
print("Groesse:", os.path.getsize(FBX), "Bytes")
''';

/// Luau-Skript für die Befehlsleiste in Roblox Studio.
///
/// [modelName] ist der Name, den das importierte Modell im Explorer
/// trägt. [asStarterCharacter] setzt es als Startfigur ein und sichert
/// die bisherige vorher nach ServerStorage.
String studioSetupLua({
  required String modelName,
  bool asStarterCharacter = true,
  double hipHeight = 2.0,
}) =>
    '''
-- In Roblox Studio einfuegen: Ansicht -> Befehlsleiste, hier
-- hineinkopieren, Enter. Vorher das FBX ueber den 3D-Importer
-- einfuegen (Import-Einstellung "R15", "Rthro" oder "Rthro Slender",
-- wenn eine Startfigur herauskommen soll; "Custom" reicht, wenn nur
-- die Katalog-Animationen laufen sollen).

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local MODEL_NAME = "$modelName"
local HIP_HEIGHT = $hipHeight

-- Der 3D-Importer benennt das Modell nach der Datei. Wurde die
-- umbenannt, heisst es hier anders - dann wird das einzige Modell mit
-- einem Mesh genommen, statt abzubrechen.
local function findeModell()
    local direkt = Workspace:FindFirstChild(MODEL_NAME)
        or StarterPlayer:FindFirstChild(MODEL_NAME)
    if direkt then return direkt end
    local treffer, anzahl = nil, 0
    for _, kind in ipairs(Workspace:GetChildren()) do
        if kind:IsA("Model")
            and kind:FindFirstChildWhichIsA("MeshPart", true) then
            treffer = kind
            anzahl += 1
        end
    end
    if anzahl == 1 then
        print("Kein Modell namens '" .. MODEL_NAME .. "' - nehme '"
            .. treffer.Name .. "'.")
        return treffer
    end
    return nil
end

local model = findeModell()
if not model then
    warn("Kein Modell gefunden. Das importierte Modell muss in "
        .. "Workspace liegen; heisst es anders als '" .. MODEL_NAME
        .. "', oben MODEL_NAME anpassen.")
    return
end

local root = model:FindFirstChild("HumanoidRootPart")
local humanoid = model:FindFirstChildOfClass("Humanoid")
if not root then
    warn("Dem Modell fehlt ein HumanoidRootPart. Beim Import "
        .. "'R15' oder 'Rthro' waehlen, nicht 'Custom'.")
    return
end

-- 1. HumanoidRootPart mit dem importierten Mesh verschweissen.
--    Ohne das faellt die Figur beim ersten Schritt auseinander.
local welded = 0
for _, part in ipairs(model:GetDescendants()) do
    if part:IsA("MeshPart") and part ~= root then
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = root
        weld.Part1 = part
        weld.Parent = root
        welded += 1

        -- 3. Kollision uebernimmt allein der HumanoidRootPart.
        --    Bleibt sie am Mesh an, haengt die Figur an Kanten fest -
        --    der Punkt, der am haeufigsten vergessen wird.
        part.CanCollide = false
        part.Anchored = false
    end
end
root.Anchored = false
model.PrimaryPart = root

-- 2. Automatische Skalierung aus, Hip Height von Hand. Sonst steht
--    die Figur im Boden oder schwebt.
if humanoid then
    humanoid.AutomaticScalingEnabled = false
    humanoid.HipHeight = HIP_HEIGHT
    humanoid.RigType = Enum.HumanoidRigType.R15
end

print(("Verschweisst: %d MeshPart(s), Kollision liegt beim "
    .. "HumanoidRootPart."):format(welded))
${asStarterCharacter ? _starterCharacterBlock : _noStarterBlock}
''';

const String _starterCharacterBlock = r'''
-- Bisherige Startfigur sichern, bevor etwas ueberschrieben wird.
local previous = StarterPlayer:FindFirstChild("StarterCharacter")
if previous then
    local backupName = "StarterCharacter_Sicherung_"
        .. os.date("%Y-%m-%d_%H-%M-%S")
    local copy = previous:Clone()
    copy.Name = backupName
    copy.Parent = ServerStorage
    previous:Destroy()
    print("Bisherige Startfigur gesichert als ServerStorage." .. backupName)
else
    print("Es gab noch keine Startfigur - nichts zu sichern.")
end

-- Einsetzen: umbenennen und nach StarterPlayer haengen.
model.Name = "StarterCharacter"
model.Parent = StarterPlayer
print("Eingesetzt. Playtest starten - du spawnst jetzt als deine Figur.")
print("Zuruecknehmen: die Sicherung aus ServerStorage zurueckholen, "
    .. "in StarterCharacter umbenennen und nach StarterPlayer ziehen.")
''';

const String _noStarterBlock = r'''
print("Als Startfigur einsetzen: Modell in 'StarterCharacter' "
    .. "umbenennen und nach StarterPlayer ziehen. Eine vorhandene "
    .. "Startfigur vorher sichern.")
''';

/// Kurzanleitung, die dem Paket beiliegt.
String robloxReadme({
  required String glbFile,
  required String fbxFile,
  required String scriptFile,
  required String luaFile,
  required List<String> missingBones,
  List<String> repairs = const [],
}) =>
    '''
Roblox-Paket
============

Diese Dateien gehoeren zusammen:

  $glbFile      Das Modell, Knochen bereits auf R15 benannt
  $scriptFile   Blender-Skript: macht daraus $fbxFile
  $luaFile      Luau-Skript fuer die Befehlsleiste in Roblox Studio

${missingBones.isEmpty ? 'Alle 15 R15-Gelenke sind vorhanden - die Figur taugt als StarterCharacter.' : 'Achtung: Diese R15-Gelenke fehlen noch:\n  ${missingBones.join(', ')}\nOhne sie laesst sich das Modell nur mit der Import-Einstellung\n"Custom" verwenden (Katalog-Animationen laufen, Startfigur nicht).'}

\${repairs.isEmpty ? '' : 'Was die App an der Datei geaendert hat\n'
    '--------------------------------------\n'
    '\${repairs.map((e) => '  * \$e').join('\n')}\n'}
Schritt 1 - FBX erzeugen
------------------------
Roblox importiert Meshes mit Rig ueber .fbx, nicht ueber .glb.

  blender --background --python $scriptFile

Oder in Blender: Datei -> Importieren -> glTF, dann Datei ->
Exportieren -> FBX. Das Skript nimmt einem dabei die drei Stellen ab,
an denen es sonst schiefgeht: Transformationen einfrieren, hoechstens
vier Knochen je Vertex, keine leeren Endknochen.

Schritt 2 - In Studio importieren
---------------------------------
Avatar -> 3D-Importer -> $fbxFile.

  "Custom"                    ergibt ein Modell auf einem einzelnen
                              Mesh, das die Katalog-R15-Animationen
                              abspielt. Laufen, Springen, Emotes
                              funktionieren, ohne eine Animation selbst
                              zu bauen.
  "R15"/"Rthro"/"Rthro Slender"  ergibt einen Humanoid-Rig, der als
                              Startfigur taugt.

Schritt 3 - Einsetzen
---------------------
Ansicht -> Befehlsleiste, den Inhalt von $luaFile hineinkopieren,
Enter. Das Skript verschweisst HumanoidRootPart und Mesh, schaltet die
automatische Skalierung ab und traegt die Hip Height ein, nimmt die
Kollision vom Mesh und legt sie auf den HumanoidRootPart, sichert eine
vorhandene Startfigur nach ServerStorage und setzt die neue ein.

Danach Playtest starten.

Schritt 4 - Mit Freunden teilen
-------------------------------
Der Platz muss dafuer bei Roblox liegen:

  Datei -> Auf Roblox veroeffentlichen (beim ersten Mal Name und
  Beschreibung vergeben).

Danach im Creator-Dashboard unter dem Erlebnis:

  Nur bestimmte Leute: Erlebnis privat lassen und die Freunde unter
  "Zugriff" als Tester hinzufuegen - sie finden es dann in ihrer
  Erlebnis-Liste.
  Fuer alle: Erlebnis auf "Oeffentlich" stellen und den Link teilen.

Gemeinsam bearbeiten geht ueber Team Create (Ansicht -> Team Create
aktivieren, dann Freunde einladen).

Wenn etwas hakt
---------------
Der Import selbst klappt meistens. Der wunde Punkt sind eigene
Animationen aus Blender - die brechen auch bei korrektem Rig oft,
waehrend die Figur an sich einwandfrei laeuft. Deshalb zuerst mit den
Katalog-Animationen testen: Laufen die, stimmen Rig und Benennung, und
eigene Bewegungen kann man danach angehen.
''';

String _pyName(String file) {
  final slash = file.lastIndexOf(RegExp(r'[/\\]'));
  final base = slash >= 0 ? file.substring(slash + 1) : file;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}
