# Verilog Golden Regression

[![CI](https://github.com/nabwei/verilog-golden-regression/actions/workflows/ci.yml/badge.svg)](https://github.com/nabwei/verilog-golden-regression/actions/workflows/ci.yml)

Kleines, unabhängig geschriebenes Simulationsbeispiel: Eine ältere und eine
refaktorierte Beschreibung erzeugen dieselben drei Grauwertbalken.
„Old“ bezeichnet hier eine eigens für dieses Beispiel geschriebene Referenz,
keine historische FPGA-Implementierung.

Mit KI-Unterstützung entwickelt, einschließlich Code, Tests und Dokumentation.

## Funktionsweise

Pro aktivem Pixeltakt wird ein Grauwert ausgegeben: `20`, `80`, `e0` (hex).
Jeder Balken dauert `BAR_WIDTH` aktive Takte. Die alte Beschreibung zählt
die gesamte Position; die neue zählt Balken und Position innerhalb des Balkens.
Synchrones Reset setzt Ausgabe und Position auf null. Ohne Enable bleiben
Ausgabe und Position stehen. Der erste aktive Takt nach Reset liefert `20`.

Die Testbench vergleicht nach der Aktualisierung der Register mit `!==`,
damit unbekannte Bits ebenfalls auffallen. Sie prüft zusätzlich einen
einfachen Sollverlauf und beendet die Simulation beim ersten Unterschied
mit Takt, Steuersignalen und Ausgaben. Reset mitten im Ablauf und Enable-Pausen
sind enthalten, einschließlich Reset bei gleichzeitig aktivem Enable in Zyklus 82.
Der Offsetzähler im neuen RTL verwendet mindestens ein Bit, sonst `$clog2(BAR_WIDTH)` Bits.

## Ausführen und Tests

Voraussetzungen: Python 3.12 und Icarus Verilog mit `iverilog` und `vvp` im PATH.
Die CI installiert Icarus und Yosys aus Ubuntu 24.04. Yosys prüft zusätzlich
die Synthesestruktur des unveränderten `pattern_new`, ohne FPGA-Timinganalyse.

```sh
python run_tests.py
```

Für Balkenbreiten 1, 4 und 7 laufen je 180 Takte ohne Mutation.
Danach müssen drei absichtliche Fehler je Breite erkannt werden:

| MUTATION | Fehler |
| --- | --- |
| 1 | Balken um einen aktiven Takt verlängert |
| 2 | mittlerer Grauwert `81` statt `80` |
| 3 | falscher Resetwert `ff` |

`MUTATION` existiert nur in der Testbench und `tb/pattern_mutant.v`, nicht im
Produktionsmodul. Der Test-Wrapper verändert Balkenbreite oder beobachtete Ausgabe.

Der Runner akzeptiert einen Mutanten nur bei fehlgeschlagener Simulation
mit `MISMATCH`-Meldung; Compilerfehler und Timeouts gelten nicht als Erkennung.
Zum direkten Untersuchen eines Fehlers:

```sh
iverilog -g2012 -s compare_patterns -Pcompare_patterns.MUTATION=2 -o build/mutant.vvp rtl/pattern_old.v rtl/pattern_new.v tb/pattern_mutant.v tb/compare_patterns.v
vvp build/mutant.vvp
```

Der zweite Befehl endet absichtlich mit Fehlerstatus. `build/` wird vom Runner angelegt.

## Limitations

- Digitale Simulation und einfacher Yosys-Strukturcheck; keine Hardwareprüfung oder Timing-Freigabe.
- Kein VGA-/Video-Protokoll, keine realen Bilddaten und keine CDC-Schaltung.
- Endliche Testfolgen sind kein formaler Äquivalenzbeweis. Gemeinsame Fehler
  in Referenz, Kandidat und Sollverlauf können unentdeckt bleiben.
- Die Mutationen demonstrieren die Empfindlichkeit für drei konkrete Fehler,
  nicht vollständige Fehlerabdeckung.
- Positive `BAR_WIDTH` wird vorausgesetzt; getestet werden 1, 4 und 7.

## English summary

An independently written old/new bar generator pair is compared cycle by cycle
with Icarus Verilog. Deterministic reset and enable stimuli cover three bar widths.
Three intentional mutations must fail with the first mismatch, rather than merely
failing to compile. Mutations stay in a test-only wrapper; the RTL counter is sized
for the configured width. Yosys checks synthesizability, not hardware timing.
Developed with AI assistance; no hardware or formal-equivalence claims.
