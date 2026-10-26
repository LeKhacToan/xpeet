# Results: speed accuracy

**Spec:** specs/speed-accuracy/spec.md

Measurements from real drives. Constants change only from what is written here (R30). Fusion is turned on only if the gate below passes (R28).

## How to record
1. Install and launch the recording build: `RECORD=1 scripts/install-device.sh`. The arguments last until Xpeet is quit; opening it again from the home screen does not record.
2. Mount the phone and drive. Cover:
   - city stop-and-go;
   - at least 3 km of steady highway (cruise control);
   - at least one tunnel or underpass.
3. Copy the drives off the phone with `scripts/pull-drives.sh` (into the gitignored `build/drives/`).
4. Run `scripts/test.sh`. `AccuracyReportTests` writes `build/drives/report.txt`. Copy the numbers below. Never copy coordinates.
5. Battery: Xcode → Debug navigator → Energy, with the phone on a cable. Compare 10 min of driving with motion on (`scripts/install-device.sh`) against motion off (`MOTION_OFF=1 scripts/install-device.sh`).

## R30 measurements
_Pending: no drives recorded yet._

| Measure | Value | Drives |
|---|---|---|
| Fix interval (median / p95) | | |
| Arrival latency (median / p95) | | |
| Fixes with speed −1 / usable for R13 | | |
| speedAccuracy (median / p95) | | |
| GPS-only σ while Live (median / p95 / weak share) | | |
| k_R (mean NIS at 1 / suggested) | | |
| τ (preliminary, magnitudes) | | |
| Tunnel behaviour (gap length, "unavailable" reported?) | | |
| Battery, motion at 50 Hz on vs off | | |

## R29 distance over time
_Pending._

## R28 accuracy gate (PR 2)
_Pending._
