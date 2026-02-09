#import "@preview/may:0.1.1": *
#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge
#import "@preview/lovelace:0.3.0": *
#import "@preview/showybox:2.0.4": showybox
#import "@preview/tiaoma:0.3.0"
#import "@preview/pinit:0.2.2": *
#import "@preview/wrap-it:0.1.1": wrap-content

#show: may

// Typography settings (matching main report)
#set text(size: 11pt)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")
#show figure.caption: set text(size: 10pt)
#set figure(placement: none)
#show raw.where(block: true): set block(
  fill: luma(245), inset: 8pt, radius: 4pt
)

// Color palette (consistent with main report)
// blue = sensors, green = RPi, orange = servos/actuators
// yellow = buffers, purple = PC, red = power/sync

// Reusable callout boxes
#let info-box(title: "Info", body) = showybox(
  frame: (
    border-color: blue.darken(20%),
    title-color: blue.lighten(85%),
    body-color: blue.lighten(95%),
    thickness: 1.5pt,
    radius: 4pt,
  ),
  title-style: (
    color: blue.darken(40%),
    weight: "bold",
    sep-thickness: 0pt,
  ),
  title: title,
  body
)

#let warning-box(title: "Warning", body) = showybox(
  frame: (
    border-color: orange.darken(10%),
    title-color: orange.lighten(85%),
    body-color: orange.lighten(95%),
    thickness: 1.5pt,
    radius: 4pt,
  ),
  title-style: (
    color: orange.darken(40%),
    weight: "bold",
    sep-thickness: 0pt,
  ),
  title: title,
  body
)

#let danger-box(title: "Danger", body) = showybox(
  frame: (
    border-color: red.darken(20%),
    title-color: red.lighten(85%),
    body-color: red.lighten(92%),
    thickness: 1.5pt,
    radius: 4pt,
  ),
  title-style: (
    color: red.darken(40%),
    weight: "bold",
    sep-thickness: 0pt,
  ),
  title: title,
  body
)

= NRF24L01+ Time Synchronization for Bimanual Grippers
>| RF-Based Pi-to-Pi Clock Sync with Enhanced ShockBurst


// ════════════════════════════════════════════════════════════
// Chapter 1: Introduction
// ════════════════════════════════════════════════════════════

== Introduction

Bimanual data collection for imitation learning requires two grippers to capture synchronized frames at 30 Hz. Any timing drift between the two Raspberry Pi units causes frame misalignment that degrades policy quality. Our previous system used WiFi Direct with UDP triggers, achieving ~2 ms bounded timing error. This document presents an alternative synchronization approach using *NRF24L01+ wireless modules*, which achieves *~0.8 ms* timing error with significantly lower power consumption and simpler network setup.

The NRF24L01+ is a 2.4 GHz ISM-band transceiver with a hardware-accelerated protocol layer called *Enhanced ShockBurst* (ESB). ESB provides automatic CRC, acknowledgement, and retransmission --- features that would require significant software overhead with raw WiFi sockets. The module communicates with the RPi over SPI at up to 10 MHz, and its 32-byte maximum payload size is sufficient for our 28-byte synchronization packet with 4 bytes of headroom.

#figure(
  table(
    columns: 3,
    align: (left, center, center),
    table.header([*Property*], [*WiFi UDP*], [*NRF24L01+*]),
    table.hline(),
    [Round-trip latency], [~2 ms], [~0.8 ms],
    [Setup complexity], [WiFi Direct config], [SPI enable only],
    [Power (active)], [~300 mA], [~12 mA],
    [Power (idle)], [~100 mA], [~26 #sym.mu\A],
    [Range (indoor)], [~30 m], [~10 m (basic) / ~100 m (PA+LNA)],
    [Payload size], [~1500 B (MTU)], [32 B max],
    [Frequency band], [2.4 GHz WiFi], [2.4 GHz ISM (non-WiFi)],
    [Protocol overhead], [IP + UDP headers], [ESB (hardware)],
    table.hline(),
  ),
  caption: [WiFi UDP vs NRF24L01+ comparison for peer-to-peer synchronization.],
)

#showybox(
  frame: (
    border-color: blue.darken(20%),
    title-color: blue.lighten(85%),
    body-color: blue.lighten(95%),
    thickness: 1.5pt,
    radius: 4pt,
  ),
  title-style: (
    color: blue.darken(40%),
    weight: "bold",
    sep-thickness: 0pt,
  ),
  title: "Design Motivation",
  [Our 28-byte sync packet fits comfortably within the NRF24L01+ 32-byte maximum payload. The hardware ACK+payload feature allows the responder to piggyback data on the automatic acknowledgement, eliminating the need for explicit mode switching. This yields round-trip communication in a single radio transaction (~557 #sym.mu\s theoretical, ~0.8 ms measured).]
)

*Scope.* This document covers NRF24L01+ hardware setup, Enhanced ShockBurst protocol internals, the ping-pong time synchronization algorithm, dual-camera integration, error handling, complete peer implementation pseudocode, and performance analysis. It serves as a companion to the main Low-Cost-UMI technical report.


// ════════════════════════════════════════════════════════════
// Chapter 2: NRF24L01+ Hardware Overview
// ════════════════════════════════════════════════════════════
== NRF24L01+ Hardware Overview

=== Module Variants

The NRF24L01+ is available in two common form factors:

- *Basic module* (green PCB, ~\$1): On-board PCB antenna, 0 dBm TX power, ~10 m indoor range. Draws 11.3 mA at 0 dBm TX, powered directly from RPi 3.3V pin.

- *PA+LNA module* (~\$3): External antenna with power amplifier (PA) and low-noise amplifier (LNA), up to +20 dBm TX, ~100 m indoor range. Draws up to 115 mA at full power --- this *exceeds the RPi 3.3V rail capacity* (50 mA max from GPIO header).

For bimanual grippers operating within ~3 m of each other, the basic module is sufficient. If longer range is needed (e.g., remote observation stations), the PA+LNA variant requires an external 3.3V LDO regulator.

=== Pin Mapping

#figure(
  table(
    columns: 5,
    align: (left, left, left, left, left),
    table.header([*NRF24L01+ Pin*], [*Function*], [*RPi GPIO*], [*RPi Pin \#*], [*Notes*]),
    table.hline(),
    [VCC], [Power], [3.3V], [Pin 17], [Add 10#sym.mu\F + 100nF bypass],
    [GND], [Ground], [GND], [Pin 20], [],
    [CE], [Chip Enable], [GPIO22], [Pin 15], [Active high: TX/RX enable],
    [CSN], [SPI Chip Select], [GPIO8 (CE0)], [Pin 24], [Active low: SPI select],
    [SCK], [SPI Clock], [GPIO11 (SCLK)], [Pin 23], [],
    [MOSI], [SPI Data In], [GPIO10 (MOSI)], [Pin 19], [],
    [MISO], [SPI Data Out], [GPIO9 (MISO)], [Pin 21], [],
    [IRQ], [Interrupt], [GPIO25], [Pin 22], [Optional: active low],
    table.hline(),
  ),
  caption: [NRF24L01+ to Raspberry Pi 4B GPIO pin mapping. Uses SPI0 bus.],
)

=== Wiring Schematic

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (18mm, 10mm),
    node-inset: 5pt,

    // RPi
    node((0, 0), [*RPi 4B*\ SPI0 + GPIO22\ GPIO25 (IRQ)], name: <rpi>,
      fill: green.lighten(85%)),

    // NRF module
    node((2, 0), [*NRF24L01+*\ 2.4 GHz\ 2 Mbps], name: <nrf>,
      fill: blue.lighten(85%)),

    // Bypass caps
    node((2, 1), [*Bypass*\ 10#sym.mu\F + 100nF\ across VCC/GND], name: <cap>,
      fill: yellow.lighten(85%)),

    // Power source
    node((0, 1), [*3.3V Rail*\ (RPi pin 17)\ or ext. LDO], name: <pwr>,
      fill: red.lighten(92%)),

    edge(<rpi>, <nrf>, "-|>", label: [SPI + CE]),
    edge(<nrf>, <rpi>, "-|>", bend: 20deg, label: [IRQ]),
    edge(<pwr>, <cap>, "-|>"),
    edge(<cap>, <nrf>, "-|>", label: [3.3V]),
  ),
  caption: [NRF24L01+ wiring to RPi 4B. Bypass capacitors are essential for stable operation.],
)

#warning-box(title: "PA+LNA Power Warning")[
  The PA+LNA variant draws up to *115 mA at full TX power*. The RPi 3.3V GPIO pin can supply only ~50 mA. Powering a PA+LNA module directly from the RPi 3.3V rail will cause voltage drops, SPI communication failures, and unreliable radio operation. Use an *AMS1117-3.3V LDO* fed from the 5V rail (or LiPo UBEC output) with 10#sym.mu\F input and output capacitors.
]

=== SPI Configuration

Enable SPI on the Raspberry Pi:

```bash
# Method 1: raspi-config
sudo raspi-config nonint do_spi 0

# Method 2: /boot/config.txt
# Add or uncomment: dtparam=spi=on

# Verify SPI is active
ls /dev/spidev0.*
# Should show: /dev/spidev0.0  /dev/spidev0.1
```

Install the pyRF24 library:

```bash
pip install pyrf24
```

=== Updated Single-Gripper Hardware Architecture

Adding the NRF24L01+ module and a USB RGB camera to the existing gripper hardware:

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (16mm, 10mm),
    node-inset: 5pt,

    // Row 0: sensors
    node((0, 0), [*T265*\ Pose 200Hz\ Fisheye 30Hz], name: <t265>,
      fill: blue.lighten(85%)),
    node((2, 0), [*USB RGB*\ 2MP 30Hz\ (wowrobo)], name: <rgb>,
      fill: blue.lighten(85%)),

    // Row 1: compute + radio
    node((1, 0), [*RPi 4B*\ pyrealsense2\ pyserial + pyrf24], name: <rpi>,
      fill: green.lighten(85%)),
    node((2, 1), [*NRF24L01+*\ 2.4 GHz sync], name: <nrf>,
      fill: red.lighten(90%)),

    // Row 1: actuator + storage
    node((0, 1), [*STS3215*\ Gripper\ Encoder], name: <servo>,
      fill: orange.lighten(88%)),
    node((1, 1), [*SD*\ 64GB], name: <sd>,
      fill: yellow.lighten(85%)),

    // Row 2: UI + power
    node((0, 2), [*Btn / LED*\ GPIO], name: <gpio>,
      fill: purple.lighten(90%)),
    node((1, 2), [*LiPo 7.4V*\ 1500mAh\ + UBEC], name: <pwr>,
      fill: red.lighten(92%)),

    edge(<t265>, <rpi>, "-|>", label: [USB3]),
    edge(<rgb>, <rpi>, "-|>", label: [USB2]),
    edge(<rpi>, <sd>, "-|>"),
    edge(<servo>, <rpi>, "-|>", label: [UART]),
    edge(<nrf>, <rpi>, "<->", label: [SPI]),
    edge(<gpio>, <rpi>, "-|>"),
    edge(<pwr>, <servo>, "-|>", label: [7.4V]),
    edge(<pwr>, <rpi>, "-|>", label: [5V]),
  ),
  caption: [Updated single gripper hardware architecture with NRF24L01+ radio and USB RGB camera.],
)

=== Updated Bill of Materials

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
    [USB RGB Camera (wowrobo)], [#sym.times 2], [\~\$15 ea], [2MP, 30fps, 3m cable],
    [NRF24L01+ module], [#sym.times 2], [\~\$1 ea], [Basic PCB antenna],
    [7.4V 2S LiPo 1500mAh], [#sym.times 2], [\~\$15 ea], [XT30 + BMS],
    [5V 3A UBEC], [#sym.times 2], [\~\$5 ea], [],
    [Misc + 3D housing], [#sym.times 2], [\~\$20 ea], [PLA + TPU + caps],
    table.hline(),
    [*Bimanual total*], [], [*\~\$676*], [],
    table.hline(),
  ),
  caption: [Updated BOM with NRF24L01+ and dual cameras. Adds ~\$36 total over WiFi-only system.],
)


// ════════════════════════════════════════════════════════════
// Chapter 3: Enhanced ShockBurst Protocol
// ════════════════════════════════════════════════════════════
== Enhanced ShockBurst Protocol

The NRF24L01+ implements *Enhanced ShockBurst* (ESB), a hardware-accelerated packet protocol that handles preamble generation, address matching, CRC validation, automatic acknowledgement, and retransmission --- all in silicon, without CPU intervention.

=== On-Air Packet Format

Every ESB transmission follows this structure:

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 3pt,
    spacing: (2mm, 8mm),
    node-inset: 4pt,

    // Packet fields as a horizontal chain
    node((0, 0), [*Preamble*\ 1 byte], name: <pre>,
      fill: luma(230)),
    node((1, 0), [*Address*\ 3--5 bytes], name: <addr>,
      fill: green.lighten(85%)),
    node((2, 0), [*PCF*\ 9 bits], name: <pcf>,
      fill: blue.lighten(88%)),
    node((3, 0), [*Payload*\ 0--32 bytes], name: <pay>,
      fill: yellow.lighten(85%)),
    node((4, 0), [*CRC*\ 1--2 bytes], name: <crc>,
      fill: red.lighten(90%)),

    edge(<pre>, <addr>, "-"),
    edge(<addr>, <pcf>, "-"),
    edge(<pcf>, <pay>, "-"),
    edge(<pay>, <crc>, "-"),

    // Annotations
    node((0, 1), [0xAA or\ 0x55], name: <pn>, stroke: none),
    node((2, 1), [Payload len\ + PID\ + NO_ACK], name: <pcfn>, stroke: none),
    node((3, 1), [Our sync\ packet\ (32 B)], name: <payn>, stroke: none),
    node((4, 1), [CRC-16\ (2 bytes)], name: <crcn>, stroke: none),

    edge(<pre>, <pn>, "-->", stroke: luma(140)),
    edge(<pcf>, <pcfn>, "-->", stroke: luma(140)),
    edge(<pay>, <payn>, "-->", stroke: luma(140)),
    edge(<crc>, <crcn>, "-->", stroke: luma(140)),
  ),
  caption: [ESB on-air packet format. The Packet Control Field (PCF) is 9 bits packed before the payload.],
)

=== Packet Control Field (PCF) Breakdown

#figure(
  table(
    columns: 4,
    align: (left, center, left, left),
    table.header([*Field*], [*Bits*], [*Range*], [*Purpose*]),
    table.hline(),
    [Payload Length], [6], [0--32], [Dynamic payload size in bytes],
    [PID], [2], [0--3], [Packet ID for duplicate detection],
    [NO\_ACK], [1], [0/1], [Per-packet ACK disable flag],
    table.hline(),
  ),
  caption: [PCF field breakdown. PID increments per new payload to detect retransmitted duplicates.],
)

=== Auto-ACK and Retransmission

When Enhanced ShockBurst is enabled (default), the transmitter automatically:

+ Sends the packet and switches to RX mode
+ Waits for an ACK from the receiver within the *Auto Retransmit Delay* (ARD)
+ If no ACK is received, retransmits up to *ARC* times (configurable 0--15)
+ Reports success or max-retries-exceeded to the application

The receiver, upon validating address and CRC, automatically sends an ACK packet. The PID field prevents the receiver from delivering duplicate payloads caused by ACK packets lost on the return path.

=== ESB Timing

#figure(
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: center,
    stroke: 0.5pt + luma(180),
    table.header([], [PLL Lock], [TX Packet], [RX Switch], [Wait ACK], [ACK RX]),
    table.hline(),
    [*Duration*],
    table.cell(fill: blue.lighten(88%))[130 #sym.mu\s],
    table.cell(fill: green.lighten(85%))[164.5 #sym.mu\s],
    table.cell(fill: orange.lighten(88%))[~10 #sym.mu\s],
    table.cell(fill: yellow.lighten(85%))[ARD],
    table.cell(fill: blue.lighten(88%))[~30 #sym.mu\s],
    [*State*],
    table.cell(fill: blue.lighten(88%))[Standby],
    table.cell(fill: green.lighten(85%))[TX],
    table.cell(fill: orange.lighten(88%))[TX#sym.arrow RX],
    table.cell(fill: yellow.lighten(85%))[RX],
    table.cell(fill: blue.lighten(88%))[RX],
    table.hline(),
  ),
  caption: [ESB timing for a single transmission at 2 Mbps with 32-byte payload. TX packet time = (preamble + address + PCF + payload + CRC) / 2 Mbps.],
)

=== Data Rate Selection

#figure(
  table(
    columns: 4,
    align: (left, center, center, left),
    table.header([*Data Rate*], [*32B TX Time*], [*On-Air Time*], [*Use Case*]),
    table.hline(),
    [250 kbps], [~1.3 ms], [~1.5 ms], [Maximum range, lowest throughput],
    [1 Mbps], [~0.33 ms], [~0.5 ms], [Balanced],
    [*2 Mbps*], [*~0.16 ms*], [*~0.35 ms*], [*Minimum latency (our choice)*],
    table.hline(),
  ),
  caption: [Data rate comparison. We use 2 Mbps to minimize radio-on time and latency.],
)

We select *2 Mbps* because our payloads are small (32 bytes) and range requirements are modest (~3 m between grippers). The shorter on-air time also reduces collision probability in the crowded 2.4 GHz band.

=== ACK Payload Feature

A key feature for our protocol: the receiver can *pre-load a payload into the ACK packet*. When the transmitter sends a packet and the receiver auto-ACKs, the ACK carries the pre-loaded data back to the transmitter. This enables bidirectional data exchange in a single radio transaction --- critical for low-latency time synchronization.

The ACK payload must be loaded *before* the TX packet arrives. This means the responder pre-loads its response data, and when the initiator's packet triggers an auto-ACK, the responder's data rides back on the ACK. The ACK payload can be up to 32 bytes, same as a normal payload.

#info-box(title: "Channel Selection")[
  The NRF24L01+ operates on channels 0--125 (2400--2525 MHz). WiFi channels 1, 6, and 11 occupy 2401--2473 MHz. To avoid interference, we use *channel 108* (2508 MHz), which is above the WiFi band. This is especially important if the RPi's WiFi is active for other purposes (SSH, data transfer).
]


// ════════════════════════════════════════════════════════════
// Chapter 4: Ping-Pong Protocol Design
// ════════════════════════════════════════════════════════════
== Ping-Pong Protocol Design

Time synchronization requires bidirectional communication: the initiator sends a timestamp, the responder replies with its own timestamps, and the initiator computes the clock offset. The NRF24L01+ offers two approaches to achieve this.

=== Approach 1: Software Ping-Pong

In software ping-pong, each peer explicitly switches between TX and RX modes. Node A transmits, then switches to RX to listen for Node B's reply. Node B receives, switches to TX to send its reply, then switches back to RX.

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (24mm, 5mm),
    node-inset: 3pt,

    // Headers
    node((0, 0), [*Node A* (Initiator)], name: <ha>, fill: green.lighten(85%)),
    node((1, 0), [*Node B* (Responder)], name: <hb>, fill: green.lighten(85%)),

    // Step 1: A TX -> B RX
    node((0, 1), [TX mode\ send $t_1$], name: <a1>, fill: blue.lighten(88%)),
    node((1, 2), [RX mode\ recv $t_1$], name: <b1>, fill: blue.lighten(88%)),
    edge(<a1>, <b1>, "-|>", label: [SYNC packet]),

    // Step 2: A switches to RX
    node((0, 3), [Switch to RX\ (~130 #sym.mu\s)], name: <a2>, fill: orange.lighten(88%)),

    // Step 3: B TX -> A RX
    node((1, 4), [TX mode\ send $t_2, t_3$], name: <b2>, fill: blue.lighten(88%)),
    node((0, 5), [RX mode\ recv $t_2, t_3$, record $t_4$], name: <a3>, fill: blue.lighten(88%)),
    edge(<b2>, <a3>, "-|>", label: [RESP packet]),

    // Step 4: B switches back to RX
    node((1, 6), [Switch to RX\ (~130 #sym.mu\s)], name: <b3>, fill: orange.lighten(88%)),
  ),
  caption: [Software ping-pong: 4 mode switches per round trip (A: TX#sym.arrow RX, B: RX#sym.arrow TX#sym.arrow RX, A: RX#sym.arrow TX). Each switch adds ~130 #sym.mu\s PLL lock time.],
)

=== Approach 2: Hardware ACK Payload

The NRF24L01+ ACK payload feature eliminates explicit mode switching. Node B pre-loads its response data into the ACK payload buffer. When Node A transmits, the hardware automatically sends an ACK containing Node B's pre-loaded data. Node B never leaves RX mode; Node A never leaves its TX-then-auto-RX-for-ACK cycle.

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (24mm, 5mm),
    node-inset: 3pt,

    // Headers
    node((0, 0), [*Node A* (PTX)], name: <ha2>, fill: green.lighten(85%)),
    node((1, 0), [*Node B* (PRX)], name: <hb2>, fill: green.lighten(85%)),

    // Pre-load
    node((1, 1), [Pre-load ACK\ payload ($t_2', t_3'$\ from prev round)], name: <pre>, fill: yellow.lighten(85%)),

    // TX + auto ACK
    node((0, 2), [TX: send $t_1$], name: <tx>, fill: blue.lighten(88%)),
    node((1, 3), [HW auto-ACK\ with payload], name: <ack>, fill: red.lighten(90%)),
    node((0, 4), [RX: recv ACK\ + payload, record $t_4$], name: <rx>, fill: blue.lighten(88%)),

    edge(<tx>, <ack>, "-|>", label: [STEP packet]),
    edge(<ack>, <rx>, "-|>", label: [ACK + data]),

    // B updates
    node((1, 5), [Record $t_2$\ Pre-load next ACK\ ($t_2, t_3$)], name: <upd>, fill: yellow.lighten(85%)),
  ),
  caption: [Hardware ACK payload: zero explicit mode switches. Node B stays in PRX mode permanently. The ACK payload carries the previous round's timestamps.],
)

=== Approach Comparison

#figure(
  table(
    columns: 3,
    align: (left, center, center),
    table.header([*Property*], [*Software Ping-Pong*], [*HW ACK Payload*]),
    table.hline(),
    [Mode switches / round], [4], [0 (hardware)],
    [Round-trip time], [~1.5 ms], [~0.6 ms],
    [Implementation complexity], [Medium], [Low],
    [Timestamp freshness], [Current round], [Previous round],
    [Payload size each way], [32 B], [32 B],
    [Requires], [Mode switch logic], [Pre-load before RX],
    table.hline(),
  ),
  caption: [Comparison of ping-pong approaches. We use *hardware ACK payload* for lower latency, accepting one-round-old timestamps (negligible at 30 Hz: 33 ms old #sym.approx 0 drift).],
)

We choose the *hardware ACK payload* approach. The one-round timestamp staleness (33 ms at 30 Hz) introduces negligible error: at 20 ppm clock drift, 33 ms contributes only 0.66 ns of additional offset --- far below our measurement precision.

=== Pipe Configuration

The NRF24L01+ supports up to 6 receive pipes. We use pipe 1 for data and pipe 0 for auto-ACK reception:

```python
from pyrf24 import RF24, RF24_PA_LOW, RF24_2MBPS

radio = RF24(22, 0)   # CE=GPIO22, CSN=CE0
radio.begin()

# Shared addresses (5 bytes each)
ADDR_A = b"\xe7\xe7\xe7\xe7\xe7"  # Node A TX, Node B RX pipe 1
ADDR_B = b"\xc2\xc2\xc2\xc2\xc2"  # Node B TX, Node A RX pipe 1

# Node A (initiator / PTX):
radio.openWritingPipe(ADDR_A)     # TX on ADDR_A
radio.openReadingPipe(1, ADDR_B)  # RX on ADDR_B (for software mode)

# Node B (responder / PRX):
radio.openReadingPipe(1, ADDR_A)  # RX on ADDR_A
radio.openWritingPipe(ADDR_B)     # TX on ADDR_B (for ACK, auto-configured)
```

=== NRF24L01+ Packet Format

We extend the existing 28-byte UDP packet to a 32-byte NRF packet:

#figure(
  table(
    columns: 5,
    align: (left, left, right, left, left),
    table.header([*Field*], [*Type*], [*Size*], [*Offset*], [*Role*]),
    table.hline(),
    [magic], [char\[2\]], [2 B], [0], ["GS" identifier],
    [msg\_type], [uint8], [1 B], [2], [SYNC/STEP/STOP/ACK],
    [step], [uint32], [4 B], [3], [Absolute step number],
    [episode], [uint16], [2 B], [7], [Episode index],
    [flags], [uint8], [1 B], [9], [REC / PAUSE / RESYNC],
    [sender\_id], [uint8], [1 B], [10], [Peer A=0, B=1],
    [timestamp], [float64], [8 B], [11], [Sender monotonic clock (s)],
    [sync\_t2], [float64], [8 B], [19], [Responder recv timestamp],
    [seq\_num], [uint8], [1 B], [27], [Sequence counter (0--255)],
    [reserved], [uint8\[3\]], [3 B], [28], [Future use / padding],
    [checksum], [uint8], [1 B], [31], [XOR of bytes 0--30],
    table.hline(),
    [], [], [*32 B*], [], [],
    table.hline(),
  ),
  caption: [32-byte NRF packet format. Extended from the 28-byte UDP format with seq\_num for ordering and 3 reserved bytes.],
)

#info-box(title: "Payload Size Trade-Off")[
  The existing UDP protocol uses 28 bytes. Adding a sequence number (1B) and keeping 3B reserved for future extensions (e.g., battery voltage, RSSI reporting) fills the 32-byte NRF maximum exactly. Since NRF24L01+ charges the same air time for any payload up to 32 bytes when using dynamic payloads, there is no penalty for using the full capacity.
]


// ════════════════════════════════════════════════════════════
// Chapter 5: Time Synchronization Algorithm
// ════════════════════════════════════════════════════════════
== Time Synchronization Algorithm

=== NTP-Style Four-Timestamp Principle

Clock synchronization between two peers requires estimating the *offset* $theta$ between their clocks and the *one-way delay* $delta$ of message transit. Using four timestamps from a single round trip, we can compute both without knowing the exact transmission delay.

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (28mm, 5mm),
    node-inset: 3pt,

    // Headers
    node((0, 0), [*Node A* (clock $C_A$)], name: <ca>, fill: green.lighten(85%)),
    node((1, 0), [*Node B* (clock $C_B$)], name: <cb>, fill: green.lighten(85%)),

    // t1: A sends
    node((0, 1), [$t_1 = C_A ("send")$], name: <t1>, fill: blue.lighten(90%)),

    // Transit delay d_AB
    node((0.5, 2), [$d_(A arrow B)$], name: <dab>, stroke: none),

    // t2: B receives
    node((1, 3), [$t_2 = C_B ("recv")$], name: <t2>, fill: blue.lighten(90%)),

    // t3: B sends ACK
    node((1, 4), [$t_3 = C_B ("send ACK")$], name: <t3>, fill: orange.lighten(88%)),

    // Transit delay d_BA
    node((0.5, 5), [$d_(B arrow A)$], name: <dba>, stroke: none),

    // t4: A receives ACK
    node((0, 6), [$t_4 = C_A ("recv ACK")$], name: <t4>, fill: orange.lighten(88%)),

    edge(<t1>, <t2>, "-|>"),
    edge(<t3>, <t4>, "-|>"),

    // Offset result
    node((0.5, 7), [$theta = ((t_2 - t_1) + (t_3 - t_4)) / 2$], name: <off>,
      fill: yellow.lighten(85%), stroke: 0.5pt),
    node((0.5, 8), [$"RTT" = (t_4 - t_1) - (t_3 - t_2)$], name: <rtt>,
      fill: yellow.lighten(85%), stroke: 0.5pt),
  ),
  caption: [Four-timestamp exchange. $t_1, t_4$ are measured on Node A's clock; $t_2, t_3$ on Node B's clock. The offset $theta$ represents how far ahead Node B's clock is relative to Node A's.],
)

=== Mathematical Derivation

Let $theta = C_B - C_A$ be the true clock offset (B ahead of A) and assume symmetric one-way delay $d$:

$ t_2 = t_1 + d + theta quad quad t_4 = t_3 + d - theta $

Solving for $theta$:

$ theta = ((t_2 - t_1) + (t_3 - t_4)) / 2 $ <eq:offset>

The round-trip time (network delay only, excluding processing):

$ "RTT" = (t_4 - t_1) - (t_3 - t_2) $ <eq:rtt>

The one-way delay estimate:

$ d = "RTT" / 2 $ <eq:delay>

=== Multi-Round Averaging with Outlier Rejection

A single round provides one offset estimate, but Linux scheduling jitter can cause individual measurements to be noisy. We perform *10 rounds* and use median-based outlier rejection:

+ Collect 10 $(theta_i, "RTT"_i)$ pairs
+ Compute $tilde("RTT") = "median"("RTT"_1, dots, "RTT"_10)$
+ Discard any round where $"RTT"_i > 1.5 dot tilde("RTT")$ (jitter outlier)
+ Final offset $hat(theta) = "mean"(theta_i "for kept rounds")$

This rejects rounds where Linux preempted the process mid-measurement, which manifests as abnormally high RTT.

=== Synchronization Algorithm

#figure(placement: none,
  pseudocode-list(booktabs: true, numbered: true, title: smallcaps[Time Synchronization --- Initiator (Node A)])[
    + *Input:* radio (configured RF24), num\_rounds $= 10$
    + *Output:* clock offset $hat(theta)$, mean RTT
    + $"offsets" #sym.arrow.l []$, $"rtts" #sym.arrow.l []$
    + *for* $i #sym.arrow.l 1$ *to* num\_rounds *do*
      + build SYNC packet with $t_1 #sym.arrow.l "monotonic()"$
      + radio.write(packet) #h(2em) \/\/ TX + wait for ACK payload
      + $t_4 #sym.arrow.l "monotonic()"$
      + parse ACK payload: extract $t_2, t_3$
      + $theta_i #sym.arrow.l ((t_2 - t_1) + (t_3 - t_4)) / 2$
      + $"RTT"_i #sym.arrow.l (t_4 - t_1) - (t_3 - t_2)$
      + append $theta_i$ to offsets, $"RTT"_i$ to rtts
      + sleep(5 ms) #h(2em) \/\/ allow responder to pre-load next ACK
    + $tilde("RTT") #sym.arrow.l "median"("rtts")$
    + *for each* $(theta_i, "RTT"_i)$ *do*
      + *if* $"RTT"_i > 1.5 dot tilde("RTT")$ *then* discard $theta_i$
    + $hat(theta) #sym.arrow.l "mean"("kept offsets")$
    + *return* $hat(theta)$, $"mean"("kept RTTs")$
  ],
  caption: [Time synchronization algorithm. 10 rounds with median-based outlier rejection.],
)

=== Worked Numerical Example

#figure(
  table(
    columns: 6,
    align: (center, right, right, right, right, center),
    table.header([*Round*], [$t_2 - t_1$ (ms)], [$t_3 - t_4$ (ms)], [$theta_i$ (ms)], [RTT (ms)], [*Keep?*]),
    table.hline(),
    [1], [0.42], [-0.38], [0.020], [0.80], [#sym.checkmark],
    [2], [0.41], [-0.39], [0.010], [0.80], [#sym.checkmark],
    [3], [0.85], [-0.37], [0.240], [1.22], [#sym.crossmark],
    [4], [0.43], [-0.40], [0.015], [0.83], [#sym.checkmark],
    [5], [0.40], [-0.38], [0.010], [0.78], [#sym.checkmark],
    table.hline(),
    [*Result*], [], [], [*0.014*], [*0.80*], [],
    table.hline(),
  ),
  caption: [Worked example with 5 rounds. Median RTT = 0.80 ms, threshold = 1.5 #sym.times 0.80 = 1.20 ms. Round 3 (RTT = 1.22 ms > 1.20 ms) is rejected as an outlier. Final offset is the mean of the 4 kept rounds.],
)

#warning-box(title: "Use Monotonic Clock")[
  Always use #text(font: "DejaVu Sans Mono", size: 0.85em)[time.monotonic()] (Python) or #text(font: "DejaVu Sans Mono", size: 0.85em)[CLOCK\_MONOTONIC] (C). The wall clock #text(font: "DejaVu Sans Mono", size: 0.85em)[time.time()] can jump due to NTP adjustments, daylight saving, or manual changes. A jump of even 1 ms during a sync round would corrupt the offset estimate. #text(font: "DejaVu Sans Mono", size: 0.85em)[time.monotonic()] is immune to these adjustments and has nanosecond resolution on Linux.
]


// ════════════════════════════════════════════════════════════
// Chapter 6: Dual-Camera Integration
// ════════════════════════════════════════════════════════════
== Dual-Camera Integration

=== Camera Overview

Each gripper unit now carries two cameras:

- *Intel RealSense T265:* Provides 6DoF visual-inertial odometry (VIO) at 200 Hz and fisheye stereo images at 30 Hz. Connected via USB 3.0. Primary role: trajectory tracking and wide-angle observation.

- *USB RGB Camera (wowrobo):* 2MP resolution, 30 fps, connected via USB 2.0 with a 3 m cable. Designed for SO-ARM100/101 gripper integration. Primary role: close-range color observation for policy input.

=== Camera Specifications

#figure(
  table(
    columns: 5,
    align: (left, center, center, center, left),
    table.header([*Camera*], [*Resolution*], [*FPS*], [*FOV*], [*Purpose*]),
    table.hline(),
    [T265 (fisheye)], [848 #sym.times 800], [30], [163#sym.degree], [Wide-angle observation + VIO pose],
    [wowrobo RGB], [1920 #sym.times 1080], [30], [~78#sym.degree], [Close-range color observation],
    table.hline(),
  ),
  caption: [Dual camera specifications per gripper unit.],
)

The T265 uses USB 3.0 bandwidth for stereo fisheye streaming and IMU data. The wowrobo RGB camera uses USB 2.0, which provides sufficient bandwidth for 1080p\@30fps MJPEG. Since the RPi 4B has separate USB 3.0 and USB 2.0 controllers, there are no bus contention issues.

=== Updated Software Architecture

Adding the USB RGB camera and NRF24L01+ radio to the per-gripper software creates a 5-thread architecture:

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (12mm, 10mm),
    node-inset: 4pt,

    // Thread row
    node((0, 0), [*Thread 1*\ T265 callback\ pose\@200Hz\ fisheye\@30Hz], name: <t1>,
      fill: blue.lighten(88%)),
    node((1, 0), [*Thread 2*\ USB RGB\ capture\@30Hz], name: <t2>,
      fill: blue.lighten(88%)),
    node((2, 0), [*Thread 3*\ STS3215 UART\ poll\@100Hz], name: <t3>,
      fill: orange.lighten(88%)),
    node((3, 0), [*Thread 4*\ NRF24L01+\ sync\@30Hz], name: <t4>,
      fill: red.lighten(90%)),

    // Sync buffer
    node((1.5, 1), [*Sync Buffer*\ 30Hz frames], name: <buf>,
      fill: yellow.lighten(85%)),

    // Disk writer
    node((1.5, 2), [*Thread 5*\ Disk writer\ async queue], name: <t5>,
      fill: green.lighten(88%)),

    // GPIO
    node((3, 2), [*GPIO ISR*\ Button\ start/stop], name: <btn>,
      fill: purple.lighten(90%)),

    edge(<t1>, <buf>, "-|>", label: [fisheye+pose]),
    edge(<t2>, <buf>, "-|>", label: [RGB frame]),
    edge(<t3>, <buf>, "-|>", label: [gripper]),
    edge(<t4>, <buf>, "-|>", label: [sync trigger]),
    edge(<buf>, <t5>, "-|>", label: [frame bundle]),
    edge(<btn>, <buf>, "-|>"),
  ),
  caption: [Updated 5-thread software architecture. Thread 4 (NRF) provides the synchronization trigger; Thread 2 (USB RGB) adds color observation.],
)

=== Frame Synchronization Strategy

The NRF sync trigger from Thread 4 serves as the master clock for frame assembly:

+ *NRF trigger arrives* (Thread 4): Record $t_"trigger"$ using `time.monotonic()`
+ *Latch T265 pose:* Select the nearest buffered T265 pose to $t_"trigger"$ (max error #sym.plus.minus 2.5 ms at 200 Hz)
+ *Latch T265 fisheye:* Select the nearest fisheye frame (max error #sym.plus.minus 16.7 ms at 30 Hz)
+ *Latch USB RGB frame:* Select the nearest RGB frame (max error #sym.plus.minus 16.7 ms at 30 Hz)
+ *Latch STS3215 reading:* Select the nearest encoder reading (max error #sym.plus.minus 5 ms at 100 Hz)
+ *Bundle and enqueue* for disk writer

=== Updated LeRobot Dataset Columns

#figure(
  table(
    columns: 4,
    align: (left, left, left, left),
    table.header([*Column*], [*Type*], [*Shape*], [*Description*]),
    table.hline(),
    [observation.state], [float32], [(10,)], [Pos (3) + quat (4) + gripper (1) + conf (1) + side (1)],
    [observation.images.fisheye], [video], [(800, 848, 1)], [T265 fisheye frame (MP4)],
    [observation.images.rgb], [video], [(1080, 1920, 3)], [USB RGB camera frame (MP4)],
    [action], [float32], [(10,)], [Target state for next step],
    [timestamp], [float64], [], [Seconds from episode start],
    [nrf\_rtt\_ms], [float32], [], [NRF round-trip time (ms)],
    [clock\_offset\_ms], [float32], [], [Estimated clock offset (ms)],
    [episode\_index], [int64], [], [Episode identifier],
    [frame\_index], [int64], [], [Frame within episode],
    [index], [int64], [], [Global frame index],
    [task\_index], [int64], [], [Links to tasks.jsonl],
    table.hline(),
  ),
  caption: [Updated parquet columns with dual cameras and NRF sync diagnostics.],
)

#info-box(title: "USB Bandwidth Budget")[
  The RPi 4B has separate USB 3.0 (VL805) and USB 2.0 controllers. The T265 uses USB 3.0 (~200 MB/s available). The wowrobo RGB camera uses USB 2.0 (~40 MB/s available; 1080p MJPEG\@30fps needs ~15 MB/s). The NRF24L01+ uses the SPI bus (separate from USB entirely). No bandwidth conflicts exist between any of the three interfaces.
]


// ════════════════════════════════════════════════════════════
// Chapter 7: Error Handling and Drift Correction
// ════════════════════════════════════════════════════════════
== Error Handling and Drift Correction

=== Packet Loss Scenarios

The NRF24L01+ ESB protocol handles transient packet loss automatically through hardware retransmission (up to 15 retries with configurable delay). However, persistent failures --- RF interference, module reset, physical obstruction --- require software-level detection and recovery.

Three failure tiers:

+ *Transient loss:* 1--2 packets lost, ESB auto-retry succeeds. Invisible to application. Adds ~0.5 ms per retry to RTT.
+ *Burst loss:* 3+ consecutive packets lost despite 15 retries. Software timeout fires (200 ms). Insert empty frame(s) and continue.
+ *Persistent failure:* 3 consecutive software timeouts. Enter RESYNC state, re-run time synchronization, resume recording.

=== Protocol State Machine

#figure(
  diagram(
    node-stroke: 1pt,
    node-corner-radius: 4pt,
    spacing: (18mm, 14mm),
    node-inset: 5pt,

    node((0, 0), [*IDLE*\ Waiting for\ button press], name: <idle>,
      fill: luma(230)),
    node((1, 0), [*SYNC*\ Time sync\ (10 rounds)], name: <sync>,
      fill: blue.lighten(88%)),
    node((2, 0), [*RECORD*\ Alternating\ triggers 30Hz], name: <rec>,
      fill: green.lighten(85%)),
    node((2, 1), [*ERROR*\ Timeout\ counter++], name: <err>,
      fill: red.lighten(90%)),
    node((1, 1), [*RESYNC*\ Re-sync clocks\ reset offset], name: <resync>,
      fill: orange.lighten(88%)),

    edge(<idle>, <sync>, "-|>", label: [button]),
    edge(<sync>, <rec>, "-|>", label: [offset OK]),
    edge(<rec>, <err>, "-|>", label: [timeout]),
    edge(<err>, <rec>, "-|>", label: [recovered]),
    edge(<err>, <resync>, "-|>", label: [3#sym.times fail]),
    edge(<resync>, <rec>, "-|>", label: [re-synced]),
    edge(<rec>, <idle>, "-|>", bend: -40deg, label: [STOP]),
  ),
  caption: [Protocol state machine. ERROR state counts consecutive timeouts; 3 failures trigger RESYNC to re-establish clock offset.],
)

=== Retry and Timeout Configuration

#figure(
  table(
    columns: 3,
    align: (left, center, left),
    table.header([*Parameter*], [*Value*], [*Rationale*]),
    table.hline(),
    [Auto Retransmit Delay (ARD)], [500 #sym.mu\s], [Must exceed ACK payload TX time (164 #sym.mu\s at 2 Mbps)],
    [Auto Retry Count (ARC)], [15], [Maximum hardware retries before reporting failure],
    [Max HW retry time], [~8 ms], [15 #sym.times 500 #sym.mu\s + overhead],
    [Software timeout], [200 ms], [6#sym.times frame period; allows recovery within episode],
    [RESYNC threshold], [3 timeouts], [3 consecutive SW timeouts #sym.arrow re-sync],
    [Re-sync interval], [300 steps], [Periodic re-sync to correct drift (every 10 s at 30 Hz)],
    table.hline(),
  ),
  caption: [Error handling configuration. Hardware retries handle transient loss; software timeout handles persistent failure.],
)

=== Clock Drift Correction

Even after initial synchronization, crystal oscillator tolerance causes the clocks to drift apart. Typical quartz crystals have #sym.plus.minus 20 ppm tolerance:

$ Delta theta (t) = 20 "ppm" times t $

At 30 Hz, after 300 steps (10 seconds): $Delta theta = 20 times 10^(-6) times 10 = 0.2 "ms"$

This is within our #sym.plus.minus 0.4 ms sync error budget. By re-synchronizing every 300 steps, we keep accumulated drift below 0.2 ms. The re-sync is piggybacked on the normal STEP packet by setting the RESYNC flag, so no additional radio transactions are needed.

For longer recording sessions, the re-sync interval can be shortened. The drift formula gives the maximum interval for a target drift bound:

$ t_"max" = Delta theta_"max" / (20 "ppm") $

For $Delta theta_"max" = 0.1$ ms: $t_"max" = 0.1 times 10^(-3) / (20 times 10^(-6)) = 5$ s (150 steps).

=== Packet Loss Recovery

#figure(placement: none,
  pseudocode-list(booktabs: true, numbered: true, title: smallcaps[Packet Loss Recovery --- Gap Detection])[
    + *Input:* received step number $s_"new"$, expected step $s_"exp"$
    + *if* $s_"new" = s_"exp"$ *then*
      + process frame normally
      + $s_"exp" #sym.arrow.l s_"exp" + 1$ #h(2em) \/\/ or $+2$ for alternating
    + *else if* $s_"new" > s_"exp"$ *then*
      + $"gap" #sym.arrow.l s_"new" - s_"exp"$
      + *for* $j #sym.arrow.l 0$ *to* gap $- 1$ *do*
        + insert empty frame (copy previous state, mark as interpolated)
      + process $s_"new"$ normally
      + $s_"exp" #sym.arrow.l s_"new" + 1$
      + log warning: "gap of {gap} frames at step {$s_"exp"$}"
    + *else* #h(2em) \/\/ $s_"new" < s_"exp"$: duplicate or old packet
      + discard (already processed or retransmit artifact)
  ],
  caption: [Gap detection and empty frame insertion. The step number in each packet enables detection of lost frames regardless of timing.],
)

#danger-box(title: "SPI Failure Detection")[
  If the NRF24L01+ STATUS register reads *0x00* or *0xFF*, the SPI bus has failed (loose connection, power glitch, or module fault). Normal STATUS values are 0x0E (idle) or 0x2E (TX success). The software should check STATUS after every #text(font: "DejaVu Sans Mono", size: 0.85em)[radio.write()] and #text(font: "DejaVu Sans Mono", size: 0.85em)[radio.available()] call. On SPI failure: log error, attempt #text(font: "DejaVu Sans Mono", size: 0.85em)[radio.begin()] re-initialization, and if that fails, fall back to unsynchronized recording with a warning flag in the dataset.
]


// ════════════════════════════════════════════════════════════
// Chapter 8: Complete Peer Implementation
// ════════════════════════════════════════════════════════════
== Complete Peer Implementation

This chapter presents the complete pseudocode for both peers. Both share the same radio initialization; only the main loop differs between initiator and responder.

=== Radio Initialization (Shared)

#figure(placement: none,
  pseudocode-list(booktabs: true, numbered: true, title: smallcaps[Radio Initialization --- Both Peers])[
    + *Input:* is\_initiator (bool), CE\_PIN $= 22$, CSN\_PIN $= 0$
    + radio $#sym.arrow.l$ RF24(CE\_PIN, CSN\_PIN)
    + radio.begin()
    + radio.setPALevel(RF24\_PA\_LOW) #h(2em) \/\/ 0 dBm, ~10m range
    + radio.setDataRate(RF24\_2MBPS) #h(2em) \/\/ minimum latency
    + radio.setChannel(108) #h(2em) \/\/ above WiFi band
    + radio.setRetries(1, 15) #h(2em) \/\/ ARD=500#sym.mu\s, ARC=15
    + radio.setPayloadSize(32)
    + radio.enableAckPayload() #h(2em) \/\/ enable ACK payloads
    + radio.enableDynamicPayloads()
    + ADDR\_A $#sym.arrow.l$ b"\\xe7\\xe7\\xe7\\xe7\\xe7"
    + ADDR\_B $#sym.arrow.l$ b"\\xc2\\xc2\\xc2\\xc2\\xc2"
    + *if* is\_initiator *then*
      + radio.openWritingPipe(ADDR\_A)
      + radio.openReadingPipe(1, ADDR\_B)
    + *else*
      + radio.openReadingPipe(1, ADDR\_A)
      + radio.openWritingPipe(ADDR\_B)
    + radio.flush\_tx()
    + radio.flush\_rx()
    + *return* radio
  ],
  caption: [Shared radio initialization. Channel 108 avoids WiFi. ARD=500#sym.mu\s ensures ACK payload has time to transmit.],
)

=== Node A --- Initiator Main Loop

#figure(placement: none,
  pseudocode-list(booktabs: true, numbered: true, title: smallcaps[Node A --- Initiator (PTX) Main Loop])[
    + *Input:* radio, offset $hat(theta)$, fps $= 30$
    + step $#sym.arrow.l 0$, timeout\_count $#sym.arrow.l 0$
    + *Pre-recording:* run time sync (#sym.arrow Algorithm 1), get $hat(theta)$
    + *loop* (until STOP button)
      + $t_"start" #sym.arrow.l$ monotonic()
      + capture local sensors (T265 pose, fisheye, RGB, STS3215)
      + build STEP packet: step, episode, flags, $t_1 = "monotonic()"$
      + *if* step mod 300 $= 0$ *then* set RESYNC flag
      + success $#sym.arrow.l$ radio.write(packet)
      + $t_"done" #sym.arrow.l$ monotonic()
      + *if* success *and* radio.isAckPayloadAvailable() *then*
        + parse ACK payload: remote state, $t_2$, $t_3$
        + *if* RESYNC flag was set *then*
          + update $hat(theta) #sym.arrow.l ((t_2 - t_1) + (t_3 - t_"done")) / 2$
        + store frame: local sensors + remote state + sync metadata
        + timeout\_count $#sym.arrow.l 0$
      + *else*
        + timeout\_count $#sym.arrow.l$ timeout\_count $+ 1$
        + store frame with empty remote state (mark interpolated)
        + *if* timeout\_count $#sym.gt.eq 3$ *then*
          + enter RESYNC: re-run time sync, reset timeout\_count
      + step $#sym.arrow.l$ step $+ 1$
      + sleep\_until($t_"start" + 1/"fps"$)
  ],
  caption: [Node A main loop. Sends STEP packets, reads ACK payloads with remote data. Re-syncs every 300 steps or on persistent failure.],
)

=== Node B --- Responder Main Loop

#figure(placement: none,
  pseudocode-list(booktabs: true, numbered: true, title: smallcaps[Node B --- Responder (PRX) Main Loop])[
    + *Input:* radio, offset $hat(theta)$
    + radio.startListening()
    + last\_state $#sym.arrow.l$ current sensor readings
    + *Pre-load initial ACK payload:* pack(last\_state, $t_2 = 0$, $t_3 = 0$)
    + radio.writeAckPayload(1, ack\_payload) #h(1em) \/\/ pipe 1
    + *loop* (until STOP received)
      + *if* radio.available() *then*
        + $t_2 #sym.arrow.l$ monotonic() #h(2em) \/\/ receive timestamp
        + read packet from radio
        + parse: step, episode, flags, sender $t_1$
        + capture local sensors (T265 pose, fisheye, RGB, STS3215)
        + store frame: local sensors + remote $t_1$ + sync metadata
        + *if* RESYNC flag *then*
          + update $hat(theta)$ from this round's timestamps
        + $t_3 #sym.arrow.l$ monotonic() #h(2em) \/\/ pre-send timestamp
        + build ACK payload: local state, $t_2$, $t_3$
        + radio.writeAckPayload(1, ack\_payload) #h(1em) \/\/ for *next* round
      + *else*
        + sleep(100 #sym.mu\s) #h(2em) \/\/ poll interval
  ],
  caption: [Node B main loop. Stays in PRX mode permanently. Pre-loads ACK payload after each received packet for the next round.],
)

=== Packet Encoding

Python #text(font: "DejaVu Sans Mono", size: 0.85em)[struct] format for the 32-byte packet:

```python
import struct

# Format: < = little-endian
#   2s  = magic ("GS")
#   B   = msg_type (uint8)
#   I   = step (uint32)
#   H   = episode (uint16)
#   B   = flags (uint8)
#   B   = sender_id (uint8)
#   d   = timestamp (float64)
#   d   = sync_t2 (float64)
#   B   = seq_num (uint8)
#   3s  = reserved (3 bytes)
#   B   = checksum (uint8)
PACKET_FMT = "<2s B I H B B d d B 3s B"
assert struct.calcsize(PACKET_FMT) == 32

def pack_packet(msg_type, step, episode, flags, sender_id,
                timestamp, sync_t2, seq_num):
    data = struct.pack(PACKET_FMT,
        b"GS", msg_type, step, episode, flags, sender_id,
        timestamp, sync_t2, seq_num, b"\x00\x00\x00", 0)
    # Compute XOR checksum over bytes 0..30
    chk = 0
    for b in data[:31]:
        chk ^= b
    return data[:31] + bytes([chk])

def unpack_packet(data):
    fields = struct.unpack(PACKET_FMT, data)
    # Verify checksum
    chk = 0
    for b in data[:31]:
        chk ^= b
    assert chk == fields[-1], "checksum mismatch"
    return fields
```


// ════════════════════════════════════════════════════════════
// Chapter 9: Performance Analysis
// ════════════════════════════════════════════════════════════
== Performance Analysis

=== Latency Breakdown

#figure(
  table(
    columns: 4,
    align: (left, right, right, left),
    table.header([*Phase*], [*Duration*], [*Cumulative*], [*Notes*]),
    table.hline(),
    [SPI TX (32B at 8 MHz)], [~26 #sym.mu\s], [26 #sym.mu\s], [32 bytes #sym.times 8 bits / 8 MHz],
    [PLL lock], [130 #sym.mu\s], [156 #sym.mu\s], [Crystal stabilization],
    [On-air TX (2 Mbps)], [164.5 #sym.mu\s], [320.5 #sym.mu\s], [(1+5+9/8+32+2) bytes / 2 Mbps],
    [Receiver processing], [~10 #sym.mu\s], [330.5 #sym.mu\s], [Address match + CRC check],
    [ACK TX (2 Mbps, 32B)], [164.5 #sym.mu\s], [495 #sym.mu\s], [ACK with payload],
    [SPI RX (ACK payload)], [~26 #sym.mu\s], [521 #sym.mu\s], [Read ACK data from FIFO],
    [Software overhead], [~36 #sym.mu\s], [557 #sym.mu\s], [Timestamp, pack/unpack],
    table.hline(),
    [*Theoretical RTT*], [], [*~557 #sym.mu\s*], [],
    [*Measured RTT*], [], [*~800 #sym.mu\s*], [Linux scheduling adds ~243 #sym.mu\s],
    table.hline(),
  ),
  caption: [Latency breakdown for a single NRF round trip with 32-byte payload and ACK payload.],
)

=== Synchronization Error Comparison

#figure(
  table(
    columns: 4,
    align: (left, center, center, center),
    table.header([*Metric*], [*WiFi UDP*], [*NRF24L01+*], [*Improvement*]),
    table.hline(),
    [Mean RTT], [~2.0 ms], [~0.8 ms], [2.5#sym.times],
    [RTT std dev], [~0.5 ms], [~0.15 ms], [3.3#sym.times],
    [Sync error (10-round)], [~0.5 ms], [~0.2 ms], [2.5#sym.times],
    [Max sync error], [~1.5 ms], [~0.4 ms], [3.7#sym.times],
    [Drift after 300 steps], [~0.2 ms], [~0.2 ms], [Same (crystal)],
    [Error bound], [Constant], [Constant], [Both bounded],
    table.hline(),
  ),
  caption: [Sync error comparison. NRF achieves ~2.5#sym.times lower average error. Both methods bound error regardless of recording duration.],
)

=== Step Timing at 30 Hz

#figure(
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: center,
    stroke: 0.5pt + luma(180),
    table.header([], [0--0.8 ms], [0.8--1 ms], [1--5 ms], [5--32 ms], [32--33.3 ms]),
    table.hline(),
    [*NRF radio*],
    table.cell(fill: red.lighten(88%))[TX+ACK],
    table.cell(fill: red.lighten(88%))[proc],
    [], [], [],
    [*Sensors*],
    [],
    table.cell(fill: blue.lighten(88%))[latch],
    table.cell(fill: blue.lighten(88%))[T265+RGB],
    [], [],
    [*Disk*],
    [], [], [],
    table.cell(fill: green.lighten(85%))[write],
    [],
    [*Idle*],
    [], [], [], [],
    table.cell(fill: luma(240))[sleep],
    table.hline(),
    [*Duty*],
    table.cell(colspan: 2, fill: yellow.lighten(88%))[~3%],
    table.cell(fill: yellow.lighten(88%))[~12%],
    table.cell(fill: yellow.lighten(88%))[~80%],
    table.cell(fill: yellow.lighten(88%))[~5%],
    table.hline(),
  ),
  caption: [Single-step timing breakdown at 30 Hz (33.3 ms frame period). NRF radio active time is ~0.8 ms = 2.4% duty cycle. Majority of time is available for sensor capture and disk writes.],
)

=== Power Consumption

#figure(
  table(
    columns: 4,
    align: (left, center, center, left),
    table.header([*State*], [*NRF24L01+*], [*WiFi (BCM43455)*], [*Notes*]),
    table.hline(),
    [TX active], [11.3 mA], [~300 mA], [NRF at 0 dBm; WiFi at ~20 dBm],
    [RX active], [13.5 mA], [~100 mA], [Listening for packets],
    [Standby-I], [26 #sym.mu\A], [N/A], [NRF between transactions],
    [Power down], [900 nA], [N/A], [Not used during recording],
    table.hline(),
    [*Average at 30 Hz*], [*~50 #sym.mu\A*], [*~150 mA*], [NRF: 2.4% duty cycle],
    [*Daily energy (24h)*], [*~4 mWh*], [*~12 Wh*], [NRF: negligible vs RPi 4B (~10W)],
    table.hline(),
  ),
  caption: [Power comparison. The NRF24L01+ consumes ~3000#sym.times less power than WiFi. At 30 Hz with 2.4% duty cycle, its contribution to total system power is negligible.],
)

#info-box(title: "Measured vs Theoretical")[
  The ~243 #sym.mu\s gap between theoretical (557 #sym.mu\s) and measured (800 #sym.mu\s) RTT is caused by Linux scheduling latency. The RPi 4B runs a non-realtime kernel; context switches and interrupt handling add 50--200 #sym.mu\s jitter per system call. This jitter is *symmetric* (affects both peers equally on average), so it cancels in the offset calculation. The RTT measurement captures it, but the offset estimate remains accurate to within #sym.plus.minus 0.2 ms after multi-round averaging.
]


// ════════════════════════════════════════════════════════════
// Chapter 10: References and Hardware Links
// ════════════════════════════════════════════════════════════
== References and Hardware Links

=== QR Code Quick Links

#figure(placement: none,
  grid(
    columns: 3,
    gutter: 12pt,
    align(center)[
      #tiaoma.qrcode("https://www.nordicsemi.com/Products/nRF24-series", width: 2.5cm)
      \ NRF24L01+\ Datasheet
    ],
    align(center)[
      #tiaoma.qrcode("https://nrf24.github.io/RF24/", width: 2.5cm)
      \ pyRF24\ Documentation
    ],
    align(center)[
      #tiaoma.qrcode("https://pinout.xyz/", width: 2.5cm)
      \ RPi GPIO\ Pinout
    ],
    align(center)[
      #tiaoma.qrcode("https://www.intelrealsense.com/tracking-camera-t265/", width: 2.5cm)
      \ Intel T265\ Camera
    ],
    align(center)[
      #tiaoma.qrcode("https://github.com/huggingface/lerobot", width: 2.5cm)
      \ LeRobot\ Framework
    ],
    align(center)[
      #tiaoma.qrcode("https://www.youtube.com/watch?v=vJqyUTTbo6I", width: 2.5cm)
      \ UMI Gripper\ Tutorial
    ],
  ),
  caption: [QR codes for key references. Scan with any smartphone camera.],
)

=== Reference URLs

#figure(
  table(
    columns: 2,
    align: (left, left),
    table.header([*Resource*], [*URL*]),
    table.hline(),
    [NRF24L01+ Datasheet], [nordicsemi.com/Products/nRF24-series],
    [pyRF24 Library], [nrf24.github.io/RF24/],
    [RPi GPIO Pinout], [pinout.xyz],
    [Intel RealSense T265], [intelrealsense.com/tracking-camera-t265/],
    [wowrobo USB Camera], [wowrobo.com (SO-ARM100/101 compatible)],
    [LeRobot Framework], [github.com/huggingface/lerobot],
    [UMI Gripper (Stanford)], [umi-gripper.github.io],
    [Diffusion Policy], [github.com/real-stanford/diffusion\_policy],
    [ACT (Aloha)], [github.com/tonyzhaozh/act],
    table.hline(),
  ),
  caption: [Complete reference URL list.],
)
