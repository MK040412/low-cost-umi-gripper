#import "@preview/may:0.1.1": *
#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#show: may

// Typography settings for technical report
#set text(size: 11pt)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")
#show figure.caption: set text(size: 10pt)
#set figure(placement: auto)
#show raw.where(block: true): set block(
  fill: luma(245), inset: 8pt, radius: 4pt
)

= Low-Cost-UMI-Report
>| A Wireless Bimanual Data Collection System for Imitation Learning

== 1. Introduction

This report presents a *low-cost wireless bimanual data collection system* designed for imitation learning on the SO-101 robot arm. Each gripper unit captures 6DoF pose via T265 VIO, fisheye observation images, and gripper aperture from the STS3215 encoder --- all logged onboard a Raspberry Pi 4B. Two grippers are synchronized via an *alternating peer-to-peer UDP protocol* over WiFi Direct, achieving zero cumulative timing error through symmetric time synchronization.

#figure(
  table(
    columns: 4,
    align: (left, center, center, center),
    table.header([*Feature*], [*UMI*], [*FastUMI*], [*Ours*]),
    table.hline(),
    [Observation], [GoPro RGB], [GoPro RGB], [T265 fisheye],
    [Pose tracking], [ORB-SLAM3], [T265 VIO], [T265 VIO],
    [Gripper width], [Vision], [ArUco], [STS3215 encoder],
    [Cameras / gripper], [1], [2], [*1*],
    [Compute], [PC offline], [Laptop + ROS], [*RPi onboard*],
    [Tethered], [No], [USB cable], [*None*],
    table.hline(),
  ),
  caption: [System comparison. Ours uses the fewest components while remaining fully wireless.],
)


== 2. System Architecture

=== 2.1 Hardware Architecture

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (16mm, 10mm),
    node-inset: 5pt,

    node((0, 0), [*T265*\ Pose 200Hz\ Fisheye 30Hz], name: <t265>,
      fill: blue.lighten(85%)),
    node((1, 0), [*RPi 4B*\ pyrealsense2\ pyserial], name: <rpi>,
      fill: green.lighten(85%)),
    node((2, 0), [*SD*\ 64GB], name: <sd>,
      fill: yellow.lighten(85%)),
    node((0, 1), [*STS3215*\ Gripper\ Encoder], name: <servo>,
      fill: orange.lighten(88%)),
    node((1, 1), [*Btn / LED*\ GPIO], name: <gpio>,
      fill: purple.lighten(90%)),
    node((2, 1), [*LiPo 7.4V*\ 1500mAh\ + UBEC], name: <pwr>,
      fill: red.lighten(92%)),

    edge(<t265>, <rpi>, "-|>", label: [USB3]),
    edge(<rpi>, <sd>, "-|>"),
    edge(<servo>, <rpi>, "-|>", label: [UART]),
    edge(<gpio>, <rpi>, "-|>"),
    edge(<pwr>, <servo>, "-|>", label: [7.4V]),
    edge(<pwr>, <rpi>, "-|>", label: [5V]),
  ),
  caption: [Single gripper unit hardware architecture. Total mass ~340g, battery life ~45 min.],
)

#figure(
  table(
    columns: 4,
    align: (left, left, left, left),
    table.header([*Connection*], [*From*], [*To*], [*Notes*]),
    table.hline(),
    [USB 3.0], [T265 Camera], [RPi USB3 (blue)], [Cable < 30cm],
    [UART TX], [RPi GPIO14], [STS3215 RX], [3.3V TTL],
    [UART RX], [RPi GPIO15], [STS3215 TX], [3.3V TTL],
    [Power 7.4V], [LiPo], [STS3215 VCC], [Direct connection],
    [Power 5V], [UBEC out], [RPi USB-C], [5V 3A rated],
    [Button], [Switch], [GPIO17], [Pull-up, active low],
    [LED], [GPIO27], [LED + resistor], [330Ω series],
    table.hline(),
  ),
  caption: [Connection details for single gripper unit.],
)

=== 2.2 Bill of Materials

#figure(
  table(
    columns: 4,
    align: (left, center, right, left),
    table.header([*Component*], [*Qty*], [*Cost*], [*Note*]),
    table.hline(),
    [Intel RealSense T265], [#sym.times 2], [\~\$200 ea], [eBay / AliExpress],
    [Raspberry Pi 4B 4GB], [#sym.times 2], [\~\$55 ea], [],
    [MicroSD 64GB A2], [#sym.times 2], [\~\$12 ea], [High write speed],
    [Feetech STS3215], [#sym.times 2], [\~\$15 ea], [12-bit encoder],
    [7.4V 2S LiPo 1500mAh], [#sym.times 2], [\~\$15 ea], [XT30 + BMS],
    [5V 3A UBEC], [#sym.times 2], [\~\$5 ea], [],
    [Misc + 3D housing], [#sym.times 2], [\~\$20 ea], [PLA + TPU],
    table.hline(),
    [*Bimanual total*], [], [*\~\$640*], [],
    table.hline(),
  ),
  caption: [BOM for two grippers. T265 price varies \$150--250 on secondary market.],
)


=== 2.3 Per-Gripper Software Architecture

Each RPi runs a single Python process with three threads feeding a synchronized buffer at 30 Hz. The architecture ensures that pose, image, and gripper data are temporally aligned before storage.

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (14mm, 10mm),
    node-inset: 5pt,

    node((1, 0), [*Thread 1*\ T265 callback\ pose\@200Hz\ image\@30Hz], name: <t1>,
      fill: blue.lighten(88%)),
    node((0, 1), [*Thread 2*\ STS3215 UART\ poll\@100Hz], name: <t2>,
      fill: orange.lighten(88%)),
    node((2, 1), [*Thread 3*\ Disk writer\ async queue], name: <t3>,
      fill: green.lighten(88%)),
    node((1, 1), [*Sync*\ *Buffer*\ 30Hz frames], name: <buf>,
      fill: yellow.lighten(85%)),
    node((1, 2), [*GPIO ISR*\ Button\ start/stop], name: <btn>,
      fill: purple.lighten(90%)),

    edge(<t1>, <buf>, "-|>", label: [img+pose], bend: -15deg),
    edge(<t2>, <buf>, "-|>", label: [gripper], bend: 15deg),
    edge(<buf>, <t3>, "-|>", label: [frame]),
    edge(<btn>, <buf>, "-|>"),
  ),
  caption: [Per-RPi software threads. The T265 callback buffers poses at 200Hz and matches them to 30Hz fisheye frames (max error #sym.plus.minus 2.5ms).],
)

VIO drift is acceptable for our use case: at 0.3 m/s hand speed and 30 s episodes, drift stays below 5 mm. Imitation learning policies (Diffusion Policy, ACT) learn *relative* deltas --- per-step drift (~5#sym.mu\m) is negligible.


== 3. Bimanual Synchronization

=== 3.1 Problem: Independent Loops Accumulate Error

If each RPi runs `sleep(1/30)` independently, Linux scheduler jitter (~4#sym.mu\s/step) accumulates:

$ Delta t(n) = sum_(i=1)^n (T_A^i - T_B^i) approx n dot 4 mu s $ <eq:drift>

After 5 minutes (9000 steps): *36 ms drift* --- more than one full 33 ms frame.

=== 3.2 Solution: Alternating Peer-to-Peer Protocol

Unlike traditional master-slave architectures, our system uses symmetric peers that alternate trigger responsibilities. This provides balanced latency and eliminates single points of failure.

$ Delta t(n) = tau_"WiFi" approx 2 "ms" quad forall n $ <eq:bounded>

#figure(
  table(
    columns: 4,
    align: (left, right, right, center),
    table.header([*Duration*], [*Steps*], [*Indep.*], [*UDP*]),
    table.hline(),
    [3 s], [100], [0.4 ms], [~2 ms],
    [30 s], [1k], [4 ms], [~2 ms],
    [100 s], [3k], [12 ms], [~2 ms],
    [5 min], [9k], [36 ms], [~2 ms],
    table.hline(),
  ),
  caption: [Error comparison. Independent loop grows linearly; UDP trigger stays constant.],
)


=== 3.3 Bimanual System Topology

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (16mm, 10mm),
    node-inset: 6pt,

    // Peer A (Left)
    node((0, 0), [*T265\_A*], name: <tl>,
      fill: blue.lighten(88%)),
    node((0, 1), [*RPi\_A*\ (Peer A)\ WiFi], name: <rl>,
      fill: green.lighten(82%)),
    node((0, 2), [*STS\_A*], name: <sl>,
      fill: orange.lighten(88%)),

    // Peer B (Right)
    node((2, 0), [*T265\_B*], name: <tr>,
      fill: blue.lighten(88%)),
    node((2, 1), [*RPi\_B*\ (Peer B)\ WiFi], name: <rr>,
      fill: green.lighten(82%)),
    node((2, 2), [*STS\_B*], name: <sr>,
      fill: orange.lighten(88%)),

    // Sync link
    node((1, 1), [*UDP*\ 30Hz\ #sym.arrow.l.r], name: <udp>,
      fill: red.lighten(90%)),

    // PC
    node((1, 3), [*PC*\ merge + train], name: <pc>,
      fill: purple.lighten(92%)),

    edge(<tl>, <rl>, "-|>", label: [USB3]),
    edge(<rl>, <sl>, "-|>", label: [UART]),
    edge(<tr>, <rr>, "-|>", label: [USB3]),
    edge(<rr>, <sr>, "-|>", label: [UART]),
    edge(<rl>, <udp>, "<->"),
    edge(<udp>, <rr>, "<->"),
    edge(<rl>, <pc>, "-->", bend: 25deg, label: [rsync]),
    edge(<rr>, <pc>, "-->", bend: -25deg, label: [rsync]),
  ),
  caption: [Bimanual topology with symmetric peers. Both grippers communicate bidirectionally via UDP.],
)

=== 3.4 Time Synchronization Phase

Before recording begins, both peers exchange timing information to establish clock offset estimates:

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (22mm, 5mm),
    node-inset: 3pt,

    // Peer headers
    node((0, 0), [*Peer A* (RPi\_L)], name: <a>, fill: green.lighten(85%)),
    node((1, 0), [*Peer B* (RPi\_R)], name: <b>, fill: green.lighten(85%)),

    // Round 1: A -> B -> A
    node((0, 1), [$t_1$: send], name: <a1>, fill: blue.lighten(90%)),
    node((1, 2), [$t_2$: recv, $t_3$: reply], name: <b1>, fill: blue.lighten(90%)),
    node((0, 3), [$t_4$: recv], name: <a2>, fill: blue.lighten(90%)),

    edge(<a1>, <b1>, "-|>", label: [SYNC\_REQ]),
    edge(<b1>, <a2>, "-|>", label: [SYNC\_RESP]),

    // Offset A
    node((0, 4), [$theta_A = ((t_2 - t_1) + (t_3 - t_4)) / 2$], name: <oa>,
      fill: yellow.lighten(85%), stroke: 0.5pt),

    // Round 2: B -> A -> B
    node((1, 5), [$t_1$: send], name: <b3>, fill: orange.lighten(88%)),
    node((0, 6), [$t_2$: recv, $t_3$: reply], name: <a3>, fill: orange.lighten(88%)),
    node((1, 7), [$t_4$: recv], name: <b4>, fill: orange.lighten(88%)),

    edge(<b3>, <a3>, "-|>", label: [SYNC\_REQ]),
    edge(<a3>, <b4>, "-|>", label: [SYNC\_RESP]),

    // Offset B
    node((1, 8), [$theta_B = ((t_2 - t_1) + (t_3 - t_4)) / 2$], name: <ob>,
      fill: yellow.lighten(85%), stroke: 0.5pt),
  ),
  caption: [Bidirectional time synchronization. Each peer computes its clock offset using NTP-style round-trip measurement ($t_1 dots t_4$). Round 1 (blue) computes $theta_A$, Round 2 (orange) computes $theta_B$.],
)

=== 3.5 Recording Phase: Alternating Triggers

During recording, peers alternate sending step triggers, ensuring symmetric latency distribution:

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (20mm, 5mm),
    node-inset: 3pt,

    // Headers
    node((0, 0), [*Peer A*], name: <ha>, fill: green.lighten(85%)),
    node((1, 0), [*Peer B*], name: <hb>, fill: green.lighten(85%)),

    // Step 0 (even -> A triggers)
    node((0, 1), [Capture], name: <a0>, fill: blue.lighten(88%)),
    node((1, 2), [Capture], name: <b0>, fill: blue.lighten(88%)),
    edge(<a0>, <b0>, "-|>", label: [STEP \{0\}]),

    // Step 1 (odd -> B triggers)
    node((1, 3), [Capture], name: <b1>, fill: orange.lighten(88%)),
    node((0, 4), [Capture], name: <a1>, fill: orange.lighten(88%)),
    edge(<b1>, <a1>, "-|>", label: [STEP \{1\}]),

    // Step 2 (even -> A triggers)
    node((0, 5), [Capture], name: <a2>, fill: blue.lighten(88%)),
    node((1, 6), [Capture], name: <b2>, fill: blue.lighten(88%)),
    edge(<a2>, <b2>, "-|>", label: [STEP \{2\}]),

    // Continuation
    node((0.5, 7), [#sym.dots.v], name: <dots>, stroke: none),

    // Stop
    node((0, 8), [STOP], name: <sa>, fill: red.lighten(90%)),
    node((1, 8), [ACK], name: <sb>, fill: red.lighten(90%)),
    edge(<sa>, <sb>, "-|>"),
  ),
  caption: [Alternating trigger protocol. Even steps (blue): Peer A captures first and sends trigger. Odd steps (orange): Peer B captures first and sends trigger. This ensures symmetric average latency.],
)

=== 3.6 Protocol Advantages

The alternating peer-to-peer design offers several key benefits:

- *Symmetric latency:* Both peers experience identical average network delay
- *No single point of failure:* Either peer can detect and recover from the other's failure
- *Fault tolerance:* If one peer misses a trigger, the other can take over
- *Balanced load:* Network and compute overhead is evenly distributed

=== 3.7 Packet Format

Each trigger is 28 bytes, broadcast over UDP port 7265:

#figure(
  table(
    columns: 4,
    align: (left, left, right, left),
    table.header([*Field*], [*Type*], [*Size*], [*Role*]),
    table.hline(),
    [magic], [char\[2\]], [2B], ["GS" identifier],
    [msg\_type], [uint8], [1B], [SYNC_REQ/SYNC_RESP/STEP/STOP],
    [step], [uint32], [4B], [Absolute step \#],
    [episode], [uint16], [2B], [Episode index],
    [flags], [uint8], [1B], [REC / PAUSE],
    [sender\_id], [uint8], [1B], [Peer A=0, B=1],
    [timestamp], [float64], [8B], [Sender clock (s)],
    [sync\_t2], [float64], [8B], [For SYNC_RESP only],
    [checksum], [uint8], [1B], [XOR payload],
    table.hline(),
    [], [], [*28B*], [],
    table.hline(),
  ),
  caption: [UDP packet format. The absolute step number and sender\_id prevent misalignment after packet loss.],
)

=== 3.8 Timing Waveform

#figure(
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: center,
    stroke: 0.5pt + luma(180),
    table.header([], [0], [1], [2], [3], [4], [5], [6], [7]),
    table.hline(),
    [*A capture*],
    table.cell(fill: blue.lighten(85%))[#sym.checkmark],
    table.cell(fill: blue.lighten(85%))[#sym.checkmark],
    [], [],
    table.cell(fill: blue.lighten(85%))[#sym.checkmark],
    table.cell(fill: blue.lighten(85%))[#sym.checkmark],
    [], [],

    [*A#sym.arrow.r B*],
    [],
    table.cell(fill: green.lighten(82%))[#sym.arrow.r],
    table.cell(fill: green.lighten(82%))[#sym.arrow.r],
    [], [],
    table.cell(fill: green.lighten(82%))[#sym.arrow.r],
    table.cell(fill: green.lighten(82%))[#sym.arrow.r],
    [],

    [*B capture*],
    [], [],
    table.cell(fill: orange.lighten(85%))[#sym.checkmark],
    table.cell(fill: orange.lighten(85%))[#sym.checkmark],
    [],
    table.cell(fill: orange.lighten(85%))[#sym.checkmark],
    table.cell(fill: orange.lighten(85%))[#sym.checkmark],
    [],

    [*B#sym.arrow.r A*],
    [], [], [],
    table.cell(fill: green.lighten(82%))[#sym.arrow.l],
    table.cell(fill: green.lighten(82%))[#sym.arrow.l],
    [], [],
    table.cell(fill: green.lighten(82%))[#sym.arrow.l],

    table.hline(),
    [*Step*], [], table.cell(fill: blue.lighten(92%))[0], [], table.cell(fill: orange.lighten(90%))[1], [], table.cell(fill: blue.lighten(92%))[2], [], [],
    table.hline(),
  ),
  caption: [Timing diagram showing alternating triggers. Peer A captures and sends even steps (blue), Peer B captures and sends odd steps (orange). WiFi latency ~1--3ms.],
)


== 4. Data Pipeline

=== 4.1 Dataset Storage (LeRobot v3.0 format)

Each gripper produces episodes stored in LeRobot v3.0 dataset format. Multiple episodes are packed into consolidated files, reducing filesystem overhead and enabling efficient streaming. After rsync to PC, episodes from both peers are merged into a single dataset.

#figure(
  align(left,
    raw(
"dataset_name/
├── meta/
│   ├── info.json              # fps, robot_type, features, path templates
│   ├── stats.json             # global feature statistics (mean/std/min/max)
│   ├── tasks.jsonl            # task descriptions
│   └── episodes/
│       └── chunk-000/
│           └── file-000.parquet   # episode metadata (lengths, offsets)
├── data/
│   └── chunk-000/
│       └── file-000.parquet       # multi-episode frames
└── videos/
    └── observation.images.fisheye/
        └── chunk-000/
            └── file-000.mp4       # multi-episode video", block: true
    )
  ),
  caption: [LeRobot v3.0 dataset directory structure. Multiple episodes are packed into single data and video files.],
)

#figure(
  table(
    columns: 4,
    align: (left, left, left, left),
    table.header([*Column*], [*Type*], [*Shape*], [*Description*]),
    table.hline(),
    [observation.state], [float32], [(10,)], [Position (3) + quaternion (4) + gripper (1) + confidence (1) + side (1)],
    [observation.images.fisheye], [video], [(800, 848, 1)], [T265 fisheye frame (MP4)],
    [action], [float32], [(10,)], [Target state for next step],
    [timestamp], [float64], [], [Seconds from episode start],
    [episode\_index], [int64], [], [Episode identifier],
    [frame\_index], [int64], [], [Frame position within episode],
    [index], [int64], [], [Global frame index across dataset],
    [task\_index], [int64], [], [Links to tasks.jsonl],
    table.hline(),
  ),
  caption: [Parquet columns per frame. Episode boundaries are resolved via meta/episodes/ metadata, not filenames.],
)

At 30Hz with MP4-compressed fisheye video, sustained write is well within SD A2 spec.

=== 4.2 Post-Collection: Merge and Train

Since both RPis share identical absolute step numbers, merging is a trivial zip-by-step operation:

#figure(placement: none,
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (10mm, 6mm),
    node-inset: 3pt,
    node-fill: purple.lighten(92%),

    node((0, 0), [SD\_A], name: <l>),
    node((1, 0), [SD\_B], name: <r>),
    node((0.5, 1), [rsync to PC], name: <xfer>),
    node((0.5, 2), [Quality filter], name: <filter>, fill: yellow.lighten(85%)),
    node((0.5, 3), [Step\# merge], name: <merge>),
    node((0.5, 4), [LeRobot convert], name: <conv>),
    node((0.5, 5), [Train ACT/DP], name: <train>),

    edge(<l>, <xfer>, "-|>"),
    edge(<r>, <xfer>, "-|>"),
    edge(<xfer>, <filter>, "-|>"),
    edge(<filter>, <merge>, "-|>"),
    edge(<merge>, <conv>, "-|>"),
    edge(<conv>, <train>, "-|>"),
  ),
  caption: [Post-collection pipeline with quality filtering. Episodes with confidence < 2 are automatically discarded.],
)


== 5. TODO

This section lists the tasks required to build and validate the complete bimanual data collection system.

#let todo(body) = block(spacing: 6pt)[#h(0pt)#sym.square.stroked #body]

=== 5.1 Procurement and Unit Tests

*Goal:* Confirm every component works individually.

#todo[Acquire 2 T265 cameras (eBay / AliExpress). Verify firmware version 0.2.0.951.]
#todo[Flash Ubuntu 22.04 Server 64-bit on both RPi 4Bs.]
#todo[Build librealsense v2.53.1 from source with FORCE\_RSUSB\_BACKEND and Python bindings enabled.]
#todo[Add T265 USB autosuspend udev rule (disable autosuspend for vendor 8087, product 0b37).]
#todo[Enable GPIO UART on /dev/ttyAMA0. Verify STS3215 position read at 100Hz.]
#todo[Verify pyrealsense2 imports successfully and rs-pose outputs 6DoF. Verify STS3215 returns encoder values.]

=== 5.2 Single Gripper Recorder

*Goal:* Record one gripper's data (pose + fisheye + gripper width) to SD at 30Hz.

#todo[Implement T265 callback: buffer pose at 200Hz, capture fisheye at 30Hz.]
#todo[Implement STS3215 UART polling thread at 100Hz.]
#todo[Build 3-way synchronizer: on each fisheye frame, match nearest pose (#sym.plus.minus 2.5ms) and nearest gripper reading (#sym.plus.minus 5ms).]
#todo[Implement episode recorder with GPIO button (start/stop) and LED indicator.]
#todo[Save episodes to SD card. Verify sustained 30Hz write with no dropped frames.]
#todo[Build playback visualizer: fisheye + pose trajectory + gripper width overlay.]
#todo[Validate: 30-second episode records cleanly with confidence #sym.gt.eq 2 throughout.]

=== 5.3 UDP Bimanual Synchronization

*Goal:* Two grippers capture in lockstep via alternating UDP trigger.

#todo[Configure WiFi Direct connection between both RPis.]
#todo[Implement 28-byte UDP packet format (msg\_type, step, episode, flags, sender\_id, timestamp, sync\_t2, checksum).]
#todo[Implement time synchronization phase with bidirectional SYNC\_REQ / SYNC\_RESP exchange.]
#todo[Implement alternating trigger loop: even steps triggered by Peer A, odd steps by Peer B.]
#todo[Implement packet-loss detection (step gap) with empty frame insertion.]
#todo[Add periodic RTT measurement (every 300 steps) and latency logging.]
#todo[Stress test: 10-minute continuous run. Verify A/B step counts match exactly.]
#todo[Validate: average RTT < 5ms; zero step misalignment after 10 minutes.]

=== 5.4 Hardware Integration

*Goal:* Two complete wireless gripper units.

#todo[Design 3D housing in Fusion 360: T265 mount (forward-facing, TPU vibration pads), RPi slot (SD card accessible, heatsink clearance), LiPo bay (hot-swappable, XT30 connector), STS3215 parallel-jaw mechanism, ergonomic handle with trigger button.]
#todo[Print (PLA frame + TPU fingertips), assemble, and wire both units.]
#todo[Gripper calibration: STS3215 encoder count #sym.arrow mm aperture mapping.]
#todo[Battery endurance test: confirm 45+ min per charge.]

=== 5.5 Pilot Data Collection

*Goal:* 50+ bimanual demonstration episodes.

#todo[Collect tabletop pick-and-place tasks (cups, blocks, tools).]
#todo[Auto-quality filter: discard any episode where confidence drops below 2.]
#todo[Transfer data to PC via rsync. Run merge script matching step numbers.]
#todo[Verify merged dataset integrity: A/B frame counts match, no gaps.]

=== 5.6 Policy Training and Deployment

*Goal:* Close the loop from data to autonomous execution.

#todo[Convert merged episodes to LeRobot dataset format.]
#todo[Train Diffusion Policy or ACT on fisheye observation + pose state.]
#todo[Mount T265 + gripper on SO-101 follower arm wrist.]
#todo[Evaluate autonomous bimanual task execution.]


== 6. Risk Assessment

#figure(
  table(
    columns: 3,
    align: (left, center, left),
    table.header([*Risk*], [*Level*], [*Mitigation*]),
    table.hline(),
    [T265 unavailable (discontinued)], [Med], [Buy 2+ units now; fallback: OAK-D Lite + DepthAI VIO],
    [librealsense ARM64 build failure], [Med], [v2.53.1 + FORCE\_RSUSB\_BACKEND is verified on RPi4],
    [Mono fisheye hurts policy], [Med], [Add small USB RGB cam to RPi USB2 port if needed],
    [WiFi packet loss > 1%], [Low], [WiFi Direct (no router); auto-interpolation of gaps],
    [RPi thermal throttle], [Low], [Heatsink + fan; 15-min sessions with battery swap],
    [STS3215 UART unstable], [Low], [74HC126 buffer IC or USB-serial adapter fallback],
    table.hline(),
  ),
  caption: [Key risks and mitigation strategies.],
)


== 7. Conclusion

This report presented a low-cost wireless bimanual data collection system designed for imitation learning. Key contributions include:

+ *Fully wireless architecture:* Each gripper unit operates independently with onboard compute and battery, eliminating tethering constraints during data collection.

+ *Alternating peer-to-peer synchronization:* The UDP protocol ensures symmetric latency distribution and eliminates single points of failure, achieving bounded timing error regardless of recording duration.

+ *Step-based alignment:* Absolute step numbers enable trivial post-collection merging without complex timestamp alignment algorithms.

+ *Cost efficiency:* The complete bimanual system costs approximately \$640, significantly less than alternatives requiring external tracking infrastructure.

Future work includes integrating the system with the SO-101 robot arm for closed-loop policy evaluation and exploring multi-gripper configurations beyond bimanual setups.
