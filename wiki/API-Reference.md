# API Reference

Complete API documentation for the Low-Cost UMI Gripper software.

## Gripper Class

### Constructor

```python
Gripper(port: str = None, baudrate: int = 115200)
```

**Parameters:**
- `port`: Serial port for communication (auto-detect if None)
- `baudrate`: Communication baud rate

### Methods

#### open()
```python
gripper.open(speed: float = 1.0) -> bool
```
Opens the gripper fingers.

#### close()
```python
gripper.close(speed: float = 1.0, force: float = None) -> bool
```
Closes the gripper fingers.

#### set_position()
```python
gripper.set_position(position: float) -> bool
```
Sets the gripper to a specific position (0.0 = closed, 1.0 = open).

#### get_position()
```python
gripper.get_position() -> float
```
Returns the current gripper position.

#### get_force()
```python
gripper.get_force() -> float
```
Returns the current grip force reading.

## Sensor Classes

### ForceSensor

```python
from sensors import ForceSensor

sensor = ForceSensor(pin: int)
reading = sensor.read()
```

### Encoder

```python
from sensors import Encoder

encoder = Encoder(pin_a: int, pin_b: int)
position = encoder.read()
```

## Examples

See `software/examples/` for complete usage examples.
