# NRF24L01+ Time Synchronization

Technical document covering NRF24L01+ wireless modules for Pi-to-Pi time synchronization in a bimanual gripper system.

## Compilation

```bash
cd docs/time_sync
typst compile Time-Sync.typ
```

Font warnings from the `may` theme are expected and can be ignored.

## Dependencies

Typst packages (auto-downloaded on first compile):

- `may:0.1.1` — document theme
- `fletcher:0.5.8` — diagrams
- `lovelace:0.3.0` — pseudocode
- `showybox:2.0.4` — styled callout boxes
- `tiaoma:0.3.0` — QR codes
- `pinit:0.2.2` — annotations
- `wrap-it:0.1.1` — text wrapping around figures
