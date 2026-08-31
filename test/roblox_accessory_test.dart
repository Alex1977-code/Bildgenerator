import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/item_prompt.dart';
import 'package:bildgenerator/services/roblox_accessory.dart';

void main() {
  group('Attachment-Namen', () {
    test('Jede AccessoryType-Art im Katalog hat einen Namen', () {
      for (final kind in itemKinds) {
        final type = kind.robloxAccessoryType;
        if (type == null) continue;
        expect(robloxAttachmentNames, contains(type), reason: kind.id);
        expect(robloxAttachmentFor(type), isNotNull, reason: kind.id);
      }
    });

    test('Die Namen stammen aus der offiziellen Tabelle', () {
      // Ein selbst ausgedachter Name führt zu keiner Fehlermeldung –
      // das Teil sitzt beim Anziehen einfach im Boden. Deshalb hier
      // festgeschrieben.
      expect(robloxAttachmentFor('Hat'), 'HatAttachment');
      expect(robloxAttachmentFor('Back'), 'BodyBackAttachment');
      expect(robloxAttachmentFor('Front'), 'BodyFrontAttachment');
      expect(robloxAttachmentFor('Neck'), 'NeckAttachment');
      expect(robloxAttachmentFor('Waist'), 'WaistCenterAttachment');
      expect(robloxAttachmentNames['Waist'],
          contains('WaistBackAttachment'));
      expect(robloxAttachmentNames['Shoulder'],
          contains('RightShoulderAttachment'));
      expect(robloxAttachmentFor(null), isNull);
      expect(robloxAttachmentFor('Gibtsnicht'), isNull);
    });
  });

  group('Größengrenzen', () {
    test('Ein Hut in der Grenze passt, ein zu großer nicht', () {
      final hut = itemKindById('hut')!;
      // Grenze für Hat: 1,87 × 2,5 × 1,87.
      final passt = accessoryFitFromSize([1.5, 2.0, 1.5], hut);
      expect(passt.ok, isTrue);
      expect(passt.text, contains('Passt'));

      final zuGross = accessoryFitFromSize([3.0, 2.0, 1.5], hut);
      expect(zuGross.ok, isFalse);
      expect(zuGross.exceeded, ['Breite']);
      expect(zuGross.text, contains('Zu groß'));
    });

    test('Der Verkleinerungsfaktor richtet sich nach der engsten Achse',
        () {
      final hut = itemKindById('hut')!;
      // Breite 2× über der Grenze, Höhe 1,2× – es zählt die Breite.
      final fit = accessoryFitFromSize([3.74, 3.0, 1.0], hut);
      expect(fit.shrinkTo, closeTo(1.87 / 3.74, 1e-6));
      expect(fit.exceeded, containsAll(['Breite', 'Höhe']));
    });

    test('Was passt, bleibt bei Faktor 1', () {
      final fit = accessoryFitFromSize([1.0, 1.0, 1.0],
          itemKindById('helm')!);
      expect(fit.shrinkTo, 1);
    });

    test('Ein Werkzeug hat keine Tabelle, aber eine Aussage', () {
      final fit =
          accessoryFitFromSize([0.3, 2.7, 0.3], itemKindById('schwert')!);
      expect(fit.limit, isNull);
      expect(fit.ok, isTrue);
      expect(fit.text, contains('keine Größentabelle'));
    });

    test('Studs werden umgerechnet', () {
      final fit = accessoryFitFromSize([1.0, 1.0, 1.0],
          itemKindById('hut')!, studsPerUnit: 5);
      expect(fit.width, 5);
      expect(fit.ok, isFalse);
    });

    test('Jede Grenze der Tabelle ist positiv', () {
      for (final entry in robloxAccessoryLimits.entries) {
        expect(entry.value.width, greaterThan(0), reason: entry.key);
        expect(entry.value.height, greaterThan(0), reason: entry.key);
        expect(entry.value.depth, greaterThan(0), reason: entry.key);
      }
      // Stichprobe gegen die offizielle Tabelle (Body Scale Normal).
      expect(robloxAccessoryLimits['Hat']!.height, 2.5);
      expect(robloxAccessoryLimits['Back']!.width, 9.86);
    });
  });

  group('Das Lua-Skript', () {
    test('Getragenes wird ein Accessory mit Handle und Attachment', () {
      final lua = robloxItemLua(itemKindById('helm')!);
      expect(lua, contains('Instance.new("Accessory")'));
      expect(lua, contains('Enum.AccessoryType.Hat'));
      expect(lua, contains('teil.Name = "Handle"'));
      expect(lua, contains('punkt.Name = "HatAttachment"'));
    });

    test('Handgehaltenes wird ein Tool mit Handle', () {
      final lua = robloxItemLua(itemKindById('schwert')!);
      expect(lua, contains('Instance.new("Tool")'));
      expect(lua, contains('teil.Name = "Handle"'));
      expect(lua, isNot(contains('Accessory')));
    });

    test('Ein Reittier bekommt einen Seat, ein Fahrzeug einen '
        'VehicleSeat', () {
      final tier = robloxItemLua(itemKindById('reitvogel')!);
      expect(tier, contains('Instance.new("Seat")'));
      expect(tier, contains('Instance.new("Model")'));
      expect(tier, isNot(contains('Accessory')));

      final wagen = robloxItemLua(itemKindById('auto')!);
      expect(wagen, contains('Instance.new("VehicleSeat")'));
    });

    test('Jedes Skript prüft erst die Auswahl', () {
      for (final kind in itemKinds) {
        final lua = robloxItemLua(kind);
        expect(lua, contains('Selection:Get()[1]'), reason: kind.id);
        expect(lua, contains('IsA("BasePart")'), reason: kind.id);
        expect(lua, isNotEmpty, reason: kind.id);
      }
    });

    test('Ein eigener Name landet im Skript', () {
      final lua =
          robloxItemLua(itemKindById('helm')!, meshName: 'Burg Helm 01');
      expect(lua, contains('"Burg Helm 01"'));
    });
  });

  group('Die Beilage', () {
    test('Nennt den Attachment-Namen und warnt vor dem falschen', () {
      final text = robloxItemReadme(itemKindById('rucksack')!);
      expect(text, contains('BodyBackAttachment'));
      expect(text, contains('keiner Fehlermeldung'));
      expect(text, contains('Accessory Fitting Tool'));
    });

    test('Beim Werkzeug steht Handle im Vordergrund', () {
      final text = robloxItemReadme(itemKindById('laterne')!);
      expect(text, contains('`Handle`'));
      expect(text, contains('Tool.Grip'));
    });

    test('Beim Reittier steht der Sitz', () {
      final text = robloxItemReadme(itemKindById('reitpferd')!);
      expect(text, contains('Sattel'));
      // Ein Boot wird auch bestiegen, hat aber kein Skelett.
      final boot = robloxItemReadme(itemKindById('boot')!);
      expect(boot, contains('Kein Accessoire'));
      expect(boot, isNot(contains('Skelett')));
      expect(text, contains('Kein Accessoire'));
    });

    test('Die Größenprüfung wird angehängt, wenn es sie gibt', () {
      final fit =
          accessoryFitFromSize([3.0, 2.0, 1.5], itemKindById('hut')!);
      final text = robloxItemReadme(itemKindById('hut')!, fit: fit);
      expect(text, contains('## Größe'));
      expect(text, contains('Zu groß'));
      expect(robloxItemReadme(itemKindById('hut')!),
          isNot(contains('## Größe')));
    });
  });
}
