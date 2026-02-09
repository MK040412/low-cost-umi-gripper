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


= Prototype Report
>| Using T265 for VIO, and 2MP USB Camera Module for RGB observation

== Introduction

The prototype report presents the design and implementation of a low-cost umi gripper using a T265 camera for visual-inertial odometry (VIO) and a 2MP USB camera module for RGB observation. It is impressed #link("https://fastumi.com/")[FastUMI] for simple setup. This report will discuss about the system components, the gripper design, and the implementation details. 

== System Components

- T265 Camera 
- #link("https://shop.wowrobo.com/products/2mp-usb-camera-module-for-so-arm100-101-30fps-3m-cable?variant=46749754523865")[2MP USB Camera Module]
- #link("https://github.com/XiujinLiu/Grip4SO101")[Grip4SO101] (3d printed)
- #link("https://shop.wowrobo.com/products/feetech-sts3215-servo-12v-30kg-high-torque-servo-for-so-arm100")[STS3215-12V 30KG Torque]
- LED
- Serial Bus Servo Driver Board 
- Rasberri Pi 4 

#pagebreak()

== Why We use Grip4SO101

#image("assets/image.png")

Grip4SO101 directly conrolled by motor, thus we can get the information of the gripper state (especially the gripper width, and power of grasping) by reading the motor gear state. Even our goal is direct plug-play style, thus it doesn't need more substantial modification to use for gripper of so101.

#pagebreak()

== Implementation Details

==== Gripper Design

The gripper use #link("https://shop.wowrobo.com/products/feetech-sts3215-servo-12v-30kg-high-torque-servo-for-so-arm100")[STS3215-12V 30KG Torque] to control the gripper. The gripper is 3d printed, and the gripper design is #link("https://github.com/XiujinLiu/Grip4SO101")[Grip4SO101]. We modify Grip4SO101 to add a LED indicator, a serial bus servo driver board, Rasberry Pi, hand held part like #link("https://umi-gripper.github.io/")[UMI] and Li-Po.

===== How to Use the Gripper

Motor of gripper is calibrated by Homing. After that, we can control the gripper by sending the command to the motor. Simply we will make open and close button on the hand held part. Before start you need to start by clicking the start button, and finish the episode by clicking the start button.\
>| There are three button : Start/Finish Button, Open Button, Close Button\




#pagebreak()

